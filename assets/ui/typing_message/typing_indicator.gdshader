shader_type canvas_item;
render_mode unshaded;

uniform vec4 gradient_color : source_color = vec4(0.0, 0.5, 1.0, 1.0);
uniform vec4 background_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);

uniform float speed : hint_range(0.0, 10.0) = 2.0;
uniform float width : hint_range(0.0, 1.0) = 0.15;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.02;

void fragment() {
    // sample the sprite texture and clip where fully transparent
    vec4 tex = texture(TEXTURE, UV);
    if (tex.a < 0.01) {
        discard;
    }

    // triangle/bounce wave: 0 -> 1 -> 0
    float t = TIME * speed;
    float pos = abs(fract(t) * 2.0 - 1.0);

    // distance from current pixel to the moving position
    float dist = abs(UV.x - pos);

    // moving band intensity
    float band = 1.0 - smoothstep(width, width + edge_softness, dist);

    // mix between background and gradient colors
    vec4 final_color = mix(background_color, gradient_color, band);

    // apply sprite alpha
    final_color.a *= tex.a;

    COLOR = final_color;
}
