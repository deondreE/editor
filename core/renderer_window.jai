#import "Basic";
#import "Windows";
#import "Windows_Utf8";
#import "GL";

#load "renderer_types.jai";

#program_export
init_opengl :: (r: *Renderer) -> bool {
    if !r.window.hwnd {
        log_error("init_opengl: r.window.hwnd is null!");
        return false;
    }

    r.window.hdc = GetDC(r.window.hwnd);
    if !r.window.hdc {
        log_error("GetDC failed! Error: %", GetLastError());
        return false;
    }

    pfd: PIXELFORMATDESCRIPTOR;
    pfd.nSize = size_of(PIXELFORMATDESCRIPTOR);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_SUPPORT_OPENGL | PFD_DRAW_TO_WINDOW | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    pfd.cStencilBits = 8;
    pfd.iLayerType = PFD_MAIN_PLANE;

    pixel_format := ChoosePixelFormat(r.window.hdc, *pfd);
    if pixel_format == 0 {
        log_error("ChoosePixelFormat failed! Error: %", GetLastError());
        return false;
    }

    if !SetPixelFormat(r.window.hdc, pixel_format, *pfd) {
        log_error("SetPixelFormat failed! Error: %", GetLastError());
        return false;
    }
    temp_hglrc := wglCreateContext(r.window.hdc);
    wglMakeCurrent(r.window.hdc, temp_hglrc);
    if !temp_hglrc {
        log_error("wglCreateContext failed! Error: %", GetLastError());
        return false;
    }

    wglCreateContextAttribsARB := cast(PFNWGLCREATECONTEXTATTRIBSARBPROC) wglGetProcAddress("wglCreateContextAttribsARB");
    if wglCreateContextAttribsARB {
    	attribs := s32.[
    	    WGL_CONTEXT_MINOR_VERSION_ARB, 3,
            WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
            WGL_CONTEXT_FLAGS_ARB,         WGL_CONTEXT_DEBUG_BIT_ARB,
            0 // Terminator
    	];

    	modern_context := wglCreateContextAttribsARB(r.window.hdc, null, attribs.data);
        if modern_context {
            wglMakeCurrent(null, null);
            wglDeleteContext(r.window.hglrc);
            r.window.hglrc = modern_context;
        } else {
            r.window.hglrc = temp_hglrc; // Fallback
        }
    } else {
    	r.window.hglrc = temp_hglrc; // Old GPU fallback
    }

    if !wglMakeCurrent(r.window.hdc, r.window.hglrc) {
        log_error("wglMakeCurrent failed!");
        return false;
    }

    gl_load(*r.gl, null);

    print("OpenGL Initialized Successfully!\n");
    return true;
}

#program_export
// Create the active rendering window, for the context.
create_window :: (r: *Renderer, name: string, width: s32, height: s32) -> bool
{
	wcex: WNDCLASSEXW;
	wcex.cbSize        = size_of(WNDCLASSEXW);
    wcex.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
    wcex.lpfnWndProc   = xx wnd_proc;
    wcex.hInstance     = null;
    wcex.hCursor       = LoadCursorW(null, IDC_ARROW);
    wcex.lpszClassName = utf8_to_wide("RendererWindow");

    if RegisterClassExW(*wcex) == 0 {
    	log_error("RegisterClassExW failed");
    	return false;
    }

    rc := RECT.{ 0, 0, width, height };
    AdjustWindowRect(*rc, WS_OVERLAPPEDWINDOW, BOOL.FALSE);

    hwnd := CreateWindowExW(
    	0,
    	utf8_to_wide("RendererWindow"),
    	utf8_to_wide(name),
    	WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
    	CW_USEDEFAULT, CW_USEDEFAULT,
    	rc.right - rc.left, rc.bottom - rc.top,
    	null, null, null, null
    );

    if !hwnd {
    	log_error("CreateWindowExW failed");
    	return false;
    }

    r.window.hwnd = hwnd;
    r.window.height = height;
    r.window.width = width;

    ShowWindow(hwnd, SW_SHOWDEFAULT);
    UpdateWindow(hwnd);
    return true;
}

#program_export
destroy_window :: (r: *Renderer)
{
	if r.window.hwnd {
		DestroyWindow(r.window.hwnd);
		r.window.hwnd = null;
	}
}

// Returns false when WM_QUIT is posted.
#program_export
pump_messages :: () -> bool
{
	msg: MSG;
	while PeekMessageW(*msg, null, 0, 0, PM_REMOVE) {
		if msg.message == WM_QUIT return false;
		TranslateMessage(*msg);
		DispatchMessageW(*msg);
	}
	return true; 
}


#program_export
init_render_batch :: (r: *Renderer, batch: *Render_Batch) {
	gl := *r.gl;
	batch.max_vertices = MAX_BATCH_VERTICES;
	array_reserve(*batch.vertices, MAX_BATCH_VERTICES);

	gl.glGenVertexArrays(1, *batch.vao);
	gl.glGenBuffers(1, *batch.vbo);

	gl.glBindVertexArray(batch.vao);
	gl.glBindBuffer(GL_ARRAY_BUFFER, batch.vbo);

	gl.glBufferData(GL_ARRAY_BUFFER, batch.max_vertices *size_of(Vertex), null, GL_DYNAMIC_DRAW);

	gl.glEnableVertexAttribArray(0);
	gl.glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, size_of(Vertex), xx 0);

	gl.glEnableVertexAttribArray(1);
	gl.glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, size_of(Vertex), cast(*void) size_of(Vector2));

	gl.glEnableVertexAttribArray(2);
	gl.glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, size_of(Vertex), xx cast(*void) (size_of(Vector2) * 2));

 	gl.glBindVertexArray(0);
}

#program_export
push_quad :: (batch: *Render_Batch, x: float, y: float, w: float, h: float, color: Vector4, uv_min := Vector2.{0,0}, uv_max := Vector2.{1,1}) {
	v1 := Vertex.{.{x, y}, .{uv_min.x, uv_min.y}, color};
	v2 := Vertex.{.{x+w, y}, .{uv_max.x, uv_min.y}, color};
	v3 := Vertex.{.{x+w, y+h}, .{uv_max.x, uv_max.y}, color};
	v4 := Vertex.{.{x, y+h}, .{uv_min.x, uv_max.y}, color};

	// Append both triangles of the quad to the vertices array.
	array_add(*batch.vertices, v1);
	array_add(*batch.vertices, v2);
	array_add(*batch.vertices, v3);

	array_add(*batch.vertices, v1);
	array_add(*batch.vertices, v4);
	array_add(*batch.vertices, v3);
}

#program_export
flush_batch :: (r: *Renderer, batch: *Render_Batch) {
	if batch.vertices.count == 0 return;

	gl := *r.gl;
	gl.glBindBuffer(GL_ARRAY_BUFFER, batch.vbo);

	// Update gpu buffer with our vertex data.
	gl.glBufferData(GL_ARRAY_BUFFER, batch.max_vertices * size_of(Vertex), null, GL_DYNAMIC_DRAW);
	gl.glBufferSubData(GL_ARRAY_BUFFER, 0, batch.vertices.count * size_of(Vertex), batch.vertices.data);

	gl.glBindVertexArray(batch.vao);
	gl.glDrawArrays(GL_TRIANGLES, 0, xx batch.vertices.count);

	batch.vertices.count = 0 ;
}

#program_export 
create_shader_program :: (r: *Renderer, vertex_src: string, fragment_src: string) -> u32 {
	gl := *r.gl;
	using gl;

	compile_shader :: (gl: *GL_Procedures, source: string, type: u32) -> u32 {
		using gl;
		shader := glCreateShader(type);
		c_str := source.data;
		length := cast(s32) source.count;
		glShaderSource(shader, 1, *c_str, *length);
		glCompileShader(shader);

		success : s32;
		glGetShaderiv(shader, GL_COMPILE_STATUS, *success);
		if !success {
			info_log: [512]u8;
			glGetShaderInfoLog(shader, 512, null, info_log.data);
			print("Shader Error: %\n", to_string(info_log.data));
		}

		return shader;
	}


	vs := compile_shader(gl, vertex_src, GL_VERTEX_SHADER);
	fs := compile_shader(gl, fragment_src, GL_FRAGMENT_SHADER);

	program := glCreateProgram();
	glAttachShader(program, vs);
	glAttachShader(program, fs);
	glLinkProgram(program);

	glDeleteShader(vs);
	glDeleteShader(fs);

	return program;
}

#scope_file

PFNWGLCREATECONTEXTATTRIBSARBPROC :: #type (hdc: HDC, hShareContext: HGLRC, attribList: *s32) -> HGLRC #c_call;

wnd_proc :: (hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT #c_call {
	if msg == WM_DESTROY {
		PostQuitMessage(0);
		return 0;
	}

	if msg == WM_SIZE {
		width := cast(s32) (lp & 0xFFFF);
		height := cast(s32) (lp >> 16);
		gl.glViewport(0, 0, xx width, xx height);
		return 0;
	}

	return DefWindowProcW(hwnd, msg, wp, lp);
}