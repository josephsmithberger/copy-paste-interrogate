// Godot 4 Shader for a vertical blur falloff effect.
// Date: 2024-05-23
//
// This shader blurs the background behind it with a vertical gradient falloff.
// It's ideal for creating "frosted glass" UI elements or atmospheric effects.

shader_type canvas_item;

// The render_mode is simplified. `blend_mix` is sufficient.
render_mode blend_mix;

// --- Blur & Falloff Controls ---
uniform float blur_strength : hint_range(0.0, 10.0, 0.1) = 4.0;
uniform float falloff_size : hint_range(0.01, 1.0, 0.01) = 0.5;
uniform float falloff_offset : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform float falloff_curve : hint_range(0.1, 5.0, 0.1) = 1.0;

// --- Gradient Color Controls ---
uniform vec4 gradient_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float gradient_strength : hint_range(0.0, 1.0, 0.01) = 0.5;

// The SCREEN_TEXTURE uniform captures what's rendered behind the object.
// `filter_linear` gives a slightly smoother result when sampling.
// `mipmaps_anisotropic` can improve quality at sharp angles but is less critical in 2D.
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

void fragment() {
    // --- 1. Calculate Falloff Factor ---
    // This determines the strength of the blur at the current pixel.
    // It calculates a 0.0 to 1.0 value based on the vertical position (UV.y).
    
    // Calculate falloff from the top
    float top_falloff = (UV.y - falloff_offset) / falloff_size;
    top_falloff = clamp(1.0 - top_falloff, 0.0, 1.0);
    
    // Calculate falloff from the bottom
    float bottom_falloff = ((1.0 - UV.y) - falloff_offset) / falloff_size;
    bottom_falloff = clamp(1.0 - bottom_falloff, 0.0, 1.0);
    
    // The final factor is the stronger of the two falloffs
    float falloff_factor = max(top_falloff, bottom_falloff);
    
    // Apply the curve to control the transition's sharpness.
    falloff_factor = pow(falloff_factor, falloff_curve);

    // --- 2. Perform the Blur ---
    // Only perform the expensive blur if the effect is active.
    vec3 blurred_color;
    if (falloff_factor > 0.001) {
        // A higher-quality 5x5 Gaussian blur.
        vec3 sum = vec3(0.0);
        float total_weight = 0.0;
        float current_blur = blur_strength * falloff_factor;

        for (int x = -2; x <= 2; x++) {
            for (int y = -2; y <= 2; y++) {
                // Calculate the weight for this sample based on its distance from the center.
                // This creates the smooth falloff characteristic of a Gaussian blur.
                float weight = exp(-0.5 * (float(x * x + y * y)) / 2.0);
                
                vec2 offset = vec2(float(x), float(y)) * SCREEN_PIXEL_SIZE * current_blur;
                sum += texture(SCREEN_TEXTURE, SCREEN_UV + offset).rgb * weight;
                total_weight += weight;
            }
        }
        blurred_color = sum / total_weight;
    }

    // --- 3. Combine and Output ---
    // Get the original, un-blurred color from the background.
    vec3 original_color = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
    
    // If the falloff is active, mix the original color with the blurred color.
    // If not, we just use the original color. This prevents a hard edge at the
    // start of the gradient where falloff_factor is exactly 0.
    vec3 final_rgb = mix(original_color, blurred_color, falloff_factor);
    
    // Now, mix the gradient color over the result.
    // The strength of the gradient is also controlled by the falloff factor.
    final_rgb = mix(final_rgb, gradient_color.rgb, falloff_factor * gradient_strength);
    
    // **KEY FIX**: The final alpha should be 1.0 so the object is opaque
    // and correctly shows the blurred background.
    // Your old code (`final_color.a *= intensity`) was making the object itself
    // transparent, which is why you only saw a gradient.
    COLOR = vec4(final_rgb, 1.0);
}

