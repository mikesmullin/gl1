//! Fullscreen diamond wipe shader (Game9 `diamond.glsl` / DDRKirby-style).
//! Hand-authored for GLCORE (Linux). Per-pixel pattern, progress + color uniforms.

const sg = @import("sokol").gfx;

pub const ATTR_position = 0;
pub const UB_fs_params = 0;

/// STD140-friendly pack: two float4s.
/// [0] = progress, res_x, res_y, _pad
/// [1] = color rgba
pub const FsParams = extern struct {
    progress: f32 align(16) = 0,
    res_x: f32 = 0,
    res_y: f32 = 0,
    _pad: f32 = 0,
    color: [4]f32 align(16) = .{ 0.1, 0.1, 0.1, 1 },
};

const vs_glsl410 =
    \\#version 410
    \\
    \\layout(location = 0) in vec2 position;
    \\
    \\void main()
    \\{
    \\    gl_Position = vec4(position, 0.0, 1.0);
    \\}
    \\
;

const fs_glsl410 =
    \\#version 410
    \\
    \\// progress, res_x, res_y, pad | color.rgba  (matches FsParams layout)
    \\uniform vec4 fs_params[2];
    \\layout(location = 0) out vec4 FragColor;
    \\
    \\void main()
    \\{
    \\    float progress = fs_params[0].x;
    \\    vec2 resolution = fs_params[0].yz;
    \\    vec4 color = fs_params[1];
    \\    // Game9: float diamondSize = 4*3*4.0f; // 48 px
    \\    float diamondSize = 48.0;
    \\    float xFraction = fract(gl_FragCoord.x / diamondSize);
    \\    float yFraction = fract(gl_FragCoord.y / diamondSize);
    \\    float xDistance = abs(xFraction - 0.5);
    \\    float yDistance = abs(yFraction - 0.5);
    \\    vec2 UV = gl_FragCoord.xy / max(resolution, vec2(1.0));
    \\    if (xDistance + yDistance + UV.x + UV.y > progress * 4.0) {
    \\        discard;
    \\    }
    \\    FragColor = color;
    \\}
    \\
;

pub fn shaderDesc(backend: sg.Backend) sg.ShaderDesc {
    var desc: sg.ShaderDesc = .{};
    desc.label = "diamond_shader";
    switch (backend) {
        .GLCORE => {
            desc.vertex_func.source = vs_glsl410;
            desc.vertex_func.entry = "main";
            desc.fragment_func.source = fs_glsl410;
            desc.fragment_func.entry = "main";
            desc.attrs[0].base_type = .FLOAT;
            desc.attrs[0].glsl_name = "position";
            desc.uniform_blocks[0].stage = .FRAGMENT;
            desc.uniform_blocks[0].layout = .STD140;
            desc.uniform_blocks[0].size = 32;
            desc.uniform_blocks[0].glsl_uniforms[0].type = .FLOAT4;
            desc.uniform_blocks[0].glsl_uniforms[0].array_count = 2;
            desc.uniform_blocks[0].glsl_uniforms[0].glsl_name = "fs_params";
        },
        else => {
            // Fallback: empty desc — caller should use sgl tile path if shader invalid.
            desc.label = "diamond_shader_unsupported";
        },
    }
    return desc;
}
