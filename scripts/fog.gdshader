shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled;
// Fog of war: a full-screen quad that rebuilds the world position of every pixel from the depth
// buffer and darkens it by the player's visibility map (scripts/main.gd, _update_fog).
// fog_tex: 1 = visible now, ~0.43 = explored earlier, 0 = never seen.

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec2 fog_size = vec2(400.0, 300.0);  // world units covered by fog_tex
uniform float explored_dark = 0.5;
uniform float hidden_dark = 0.86;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);  // 1x1 quad stretched over the whole screen
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	world.xyz /= world.w;
	vec2 uv = world.xz / fog_size;
	float v = texture(fog_tex, clamp(uv, vec2(0.0), vec2(1.0))).r;
	float outside = step(1.0, max(max(-uv.x, uv.x - 1.0), max(-uv.y, uv.y - 1.0)) + 1.0);
	float seen = smoothstep(0.0, 0.43, v);
	float now = smoothstep(0.43, 1.0, v);
	float dark = mix(hidden_dark, explored_dark, seen);
	dark = mix(dark, 0.0, now);
	ALBEDO = vec3(0.01, 0.015, 0.03);
	ALPHA = mix(dark, hidden_dark, outside);
}
