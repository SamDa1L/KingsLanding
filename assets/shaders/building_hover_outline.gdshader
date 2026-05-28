shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec4 outline_color : source_color = vec4(1.0, 0.88, 0.24, 1.0);
uniform int outline_width_px = 2;
uniform float alpha_threshold = 0.05;

void fragment() {
	float base_alpha = textureLod(screen_texture, SCREEN_UV, 0.0).a;
	float nearby_alpha = 0.0;
	int width = clamp(outline_width_px, 1, 8);
	for (int x = -8; x <= 8; x++) {
		for (int y = -8; y <= 8; y++) {
			if (abs(x) > width || abs(y) > width) {
				continue;
			}
			if (x == 0 && y == 0) {
				continue;
			}
			vec2 offset_uv = SCREEN_UV + vec2(float(x), float(y)) * SCREEN_PIXEL_SIZE;
			nearby_alpha = max(nearby_alpha, textureLod(screen_texture, offset_uv, 0.0).a);
		}
	}

	if (base_alpha <= alpha_threshold && nearby_alpha > alpha_threshold) {
		COLOR = outline_color;
	} else {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	}
}
