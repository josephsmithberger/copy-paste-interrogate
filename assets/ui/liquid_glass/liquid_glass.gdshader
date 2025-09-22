shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest_mipmap;

// Pass the control size in pixels from script
uniform vec2 rect_size = vec2(100.0, 100.0);

// visual tuning
uniform float blur_amount : hint_range(0.0, 1.0) = 0.3;
uniform float corner_power : hint_range(1.0, 32.0) = 8.0; // squircle sharpness
uniform float edge_falloff : hint_range(0.0, 20.0) = 8.0; // how quickly rounded edge falls off

void fragment() {
    vec2 local_uv  = UV;       // 0..1 within this control
    vec2 screen_uv = SCREEN_UV; // 0..1 on screen

    // --- normalize UV into square space so aspect doesn't change the corner roundness ---
    float aspect = max(rect_size.x, 1.0) / max(rect_size.y, 1.0); // avoid div-by-zero
    // center coordinates in [-1..1]
    vec2 norm = (local_uv - vec2(0.5)) * 2.0;
    // compress X by aspect so a wide rect maps into square coords
    norm.x /= aspect;

    // squircle / circle decision: use circle when roughly square
    float shape;
    if (abs(aspect - 1.0) < 0.01) {
        shape = pow(length(norm), corner_power);
    } else {
        shape = pow(abs(norm.x), corner_power) + pow(abs(norm.y), corner_power);
    }

    // edge masks (tune edge_falloff to taste)
    float edge = clamp((1.0 - shape * edge_falloff), 0.0, 1.0);
    float edge2 = clamp((0.95 - shape * (edge_falloff * 0.95)) * 2.0, 0.0, 1.0);
    float transition = smoothstep(0.0, 1.0, edge + edge2);

    if (transition > 0.0) {
        // lens mapping inside the shape (keeps lens based on normalized shape)
        vec2 lens = ((local_uv - 0.5) * (1.0 - shape * 2.0) + 0.5);

        // convert node pixel size into screen_uv-size
        vec2 control_size_in_suv = rect_size * SCREEN_PIXEL_SIZE;
        // top-left of this control in SCREEN_UV: SCREEN_UV - local_uv * control_size
        vec2 control_origin_suv = screen_uv - local_uv * control_size_in_suv;
        vec2 final_sample_uv = control_origin_suv + lens * control_size_in_suv;

        // blur sampling
        vec4 final_color = vec4(0.0);
        float total = 0.0;
        for (float x = -4.0; x <= 4.0; x++) {
            for (float y = -4.0; y <= 4.0; y++) {
                vec2 offset = vec2(x, y) * SCREEN_PIXEL_SIZE * blur_amount;
                final_color += textureLod(screen_texture, final_sample_uv + offset, 0.0);
                total += 1.0;
            }
        }
        final_color /= total;

        // a little lighting/gradient to sell depth (kept simple)
        float gradient = clamp((clamp(norm.y, -1.0, 1.0) + 1.0) * 0.5, 0.0, 1.0);
        vec4 lighting = clamp(final_color + vec4(edge) * (gradient * 0.3 + edge2 * 0.2), 0.0, 1.0);

        COLOR = mix(textureLod(screen_texture, screen_uv, 0.0), lighting, transition);
    } else {
        COLOR = textureLod(screen_texture, screen_uv, 0.0);
    }
}
