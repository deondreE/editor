#import "Basic";
#import "SDL";
#import "GL";

#load "renderer_types.jai";

#program_export
create_window :: (r: *Renderer, name: string, width: s32, height: s32) -> bool {
    if SDL_Init(SDL_INIT_VIDEO) < 0 {
        log_error("SDL_Init failed: %", to_string(SDL_GetError()));
        return false;
    }

    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, xx SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS, xx SDL_GL_CONTEXT_DEBUG_FLAG);

    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE,   24);
    SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);

    r.window.sdl_window = SDL_CreateWindow(
        temp_c_string(name),
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        width, height,
        SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE
    );

    if !r.window.sdl_window {
        log_error("SDL_CreateWindow failed: %", to_string(SDL_GetError()));
        return false;
    }

    r.window.width  = width;
    r.window.height = height;
    return true;
}

#program_export
init_opengl :: (r: *Renderer) -> bool {
    if !r.window.sdl_window {
        log_error("init_opengl: sdl_window is null — call create_window first");
        return false;
    }

    r.window.gl_context = SDL_GL_CreateContext(r.window.sdl_window);
    if !r.window.gl_context {
        log_error("SDL_GL_CreateContext failed: %", to_string(SDL_GetError()));
        return false;
    }

    if SDL_GL_MakeCurrent(r.window.sdl_window, r.window.gl_context) < 0 {
        log_error("SDL_GL_MakeCurrent failed: %", to_string(SDL_GetError()));
        return false;
    }

    // Adaptive vsync, fall back to regular vsync
    if SDL_GL_SetSwapInterval(-1) < 0  SDL_GL_SetSwapInterval(1);

    gl_load(*r.gl, (name: *u8) -> *void #c_call {
        return SDL_GL_GetProcAddress(name);
    });

    print("OpenGL initialized via SDL\n");
    return true;
}

#program_export
destroy_window :: (r: *Renderer) {
    if r.window.gl_context {
        SDL_GL_DeleteContext(r.window.gl_context);
        r.window.gl_context = null;
    }
    if r.window.sdl_window {
        SDL_DestroyWindow(r.window.sdl_window);
        r.window.sdl_window = null;
    }
    SDL_Quit();
}

#program_export
pump_messages :: (r: *Renderer) -> bool {
    event: SDL_Event;
    while SDL_PollEvent(*event) {
        if event.type == {
            case SDL_QUIT;
                return false;

            case SDL_WINDOWEVENT;
                if event.window.event == SDL_WINDOWEVENT_RESIZED {
                    r.window.width  = event.window.data1;
                    r.window.height = event.window.data2;
                    r.gl.glViewport(0, 0, xx r.window.width, xx r.window.height);
                }
        }
    }
    return true;
}

#program_export
swap_buffers :: (r: *Renderer) {
    SDL_GL_SwapWindow(r.window.sdl_window);
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

    gl.glBufferData(GL_ARRAY_BUFFER, batch.max_vertices * size_of(Vertex), null, GL_DYNAMIC_DRAW);

    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, size_of(Vertex), xx 0);

    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, size_of(Vertex), cast(*void) size_of(Vector2));

    gl.glEnableVertexAttribArray(2);
    gl.glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, size_of(Vertex), cast(*void) (size_of(Vector2) * 2));

    gl.glBindVertexArray(0);
}

#program_export
push_quad :: (batch: *Render_Batch, x: float, y: float, w: float, h: float, color: Vector4, uv_min := Vector2.{0,0}, uv_max := Vector2.{1,1}) {
    v1 := Vertex.{.{x,   y},   .{uv_min.x, uv_min.y}, color};
    v2 := Vertex.{.{x+w, y},   .{uv_max.x, uv_min.y}, color};
    v3 := Vertex.{.{x+w, y+h}, .{uv_max.x, uv_max.y}, color};
    v4 := Vertex.{.{x,   y+h}, .{uv_min.x, uv_max.y}, color};

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
    gl.glBufferData(GL_ARRAY_BUFFER, batch.max_vertices * size_of(Vertex), null, GL_DYNAMIC_DRAW);
    gl.glBufferSubData(GL_ARRAY_BUFFER, 0, batch.vertices.count * size_of(Vertex), batch.vertices.data);
    gl.glBindVertexArray(batch.vao);
    gl.glDrawArrays(GL_TRIANGLES, 0, xx batch.vertices.count);
    batch.vertices.count = 0;
}

#program_export
create_shader_program :: (r: *Renderer, vertex_src: string, fragment_src: string) -> u32 {
    gl := *r.gl;
    using gl;

    compile_shader :: (gl: *GL_Procedures, source: string, type: u32) -> u32 {
        using gl;
        shader := glCreateShader(type);
        c_str  := source.data;
        length := cast(s32) source.count;
        glShaderSource(shader, 1, *c_str, *length);
        glCompileShader(shader);

        success: s32;
        glGetShaderiv(shader, GL_COMPILE_STATUS, *success);
        if !success {
            info_log: [512]u8;
            glGetShaderInfoLog(shader, 512, null, info_log.data);
            print("Shader compile error: %\n", to_string(info_log.data));
        }
        return shader;
    }

    vs := compile_shader(gl, vertex_src, GL_VERTEX_SHADER);
    fs := compile_shader(gl, fragment_src, GL_FRAGMENT_SHADER);

    program := glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, fs);
    glLinkProgram(program);

    success: s32;
    glGetProgramiv(program, GL_LINK_STATUS, *success);
    if !success {
        info: [512]u8;
        glGetProgramInfoLog(program, 512, null, info.data);
        print("Shader link error: %\n", to_string(info.data));
    }

    glDeleteShader(vs);
    glDeleteShader(fs);
    return program;
}
