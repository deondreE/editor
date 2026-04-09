#load "engine_api.jai";

vertex_shader_source := #string GLSL
#version 330 core
layout (location = 0) in vec2 aPos;
layout (location = 1) in vec2 aTexCoord;
layout (location = 2) in vec4 aColor;
out vec2 TexCoord;
out vec4 OurColor;
uniform mat4 projection;
void main() {
    gl_Position = projection * vec4(aPos, 0.0, 1.0);
    TexCoord = aTexCoord;
    OurColor = aColor;
}
GLSL

fragment_shader_source := #string GLSL
#version 330 core
out vec4 FragColor;
in vec2 TexCoord;
in vec4 OurColor;
uniform sampler2D textTexture;
uniform bool useTexture;
void main() {
    if (useTexture) {
        float alpha = texture(textTexture, TexCoord).r;
        FragColor = vec4(OurColor.rgb, OurColor.a * alpha);
    } else {
        FragColor = OurColor;
    }
}
GLSL

main :: () {
    r: Renderer;
    cur_batch: Render_Batch;

    if !create_window(*r, "Test Window", 1280, 720) {
        print("Failed to create window\n");
        return;
    }

    if !init_opengl(*r) {
        print("Failed to init OpenGL\n");
        return;
    }

    gl := *r.gl;

    gl.glViewport(0, 0, xx r.window.width, xx r.window.height);
    init_render_batch(*r, *cur_batch);
    shader_id := create_shader_program(*r, vertex_shader_source, fragment_shader_source);

    print("Engine running\n");
    while pump_messages(*r) {
        gl.glClearColor(0.05, 0.05, 0.05, 1.0);
        gl.glClear(GL_COLOR_BUFFER_BIT);
        gl.glUseProgram(shader_id);

        projection := orthographic_projection_matrix(0, xx r.window.width, xx r.window.height, 0, -1, 1);
        proj_loc := gl.glGetUniformLocation(shader_id, "projection");
        gl.glUniformMatrix4fv(proj_loc, 1, GL_TRUE, *projection._11);

        text_use_loc := gl.glGetUniformLocation(shader_id, "useTexture");
        gl.glUniform1i(text_use_loc, 0);

        push_quad(*cur_batch, 100, 100, 50, 80, .{1, 0.8, 0, 1});
        flush_batch(*r, *cur_batch);
        swap_buffers(*r);
    }

    destroy_window(*r);
}