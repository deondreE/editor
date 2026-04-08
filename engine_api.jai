#import "Basic";
#import "String";
#import "File";
#import "File_Utilities";
#import "Windows";
#import "Math";
#import "GL";

Engine :: #library,no_static_library "engine";

Vertex :: struct {}

Renderer :: struct {
	window: W32Handle;
	gl: GL_Procedures; 
}

W32Handle :: struct {
	hdc: HDC;
	width: s32;
	hwnd: HWND;
	height: s32; 
}

Render_Batch :: struct {
	vertices: [..]Vertex;
	vbo: u32;
	vao: u32;	
	max_vertices: s32;
}


pump_messages :: () -> bool #elsewhere Engine;

create_window :: (r: *Renderer, name: string, width: s32, height: s32) -> bool #elsewhere Engine;
destroy_window :: (r: *Renderer) #elsewhere Engine;
init_opengl :: (r: *Renderer) -> bool #elsewhere Engine;
push_quad :: (batch: *Render_Batch, x: float, y: float, w: float, h: float, color: Vector4, uv_min := Vector2.{0,0}, uv_max := Vector2.{1,1}) #elsewhere Engine;
init_render_batch :: (r: *Renderer, batch: *Render_Batch) #elsewhere Engine;
flush_batch :: (r: *Renderer, batch: *Render_Batch) #elsewhere Engine;
create_shader_program :: (r: *Renderer, vertex_src: string, fragment_src: string) -> u32 #elsewhere Engine;