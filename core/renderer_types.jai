#import "Windows";
#import "GL";
#import "Math";

W32Handle :: struct {
 	sdl_window: *SDL_Window;
    gl_context: SDL_GLContext;
    width:  s32;
    height: s32;
}

Renderer :: struct {
	window: W32Handle;
	gl: GL_Procedures;
}

Vertex :: struct {
	position: Vector2;
	uv: Vector2;
	color: Vector4;
}

MAX_BATCH_VERTICES : s32 : 10000;
Render_Batch :: struct {
	vertices: [..]Vertex;
	vbo: u32;
	vao: u32;
	max_vertices: s32;
}
