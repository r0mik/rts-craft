shader_type canvas_item;
// Hologram overlay for the unit portrait: thin scanlines, a slow bright sweep and a dark vignette.

void fragment() {
	float lines = step(0.5, fract(UV.y * 70.0)) * 0.10;
	float sweep = smoothstep(0.06, 0.0, abs(fract(TIME * 0.25) - UV.y)) * 0.18;
	vec2 c = UV - 0.5;
	float vignette = smoothstep(0.25, 0.75, length(c * vec2(1.0, 0.9)));
	COLOR = vec4(0.3, 0.85, 1.0, lines + sweep) + vec4(0.0, 0.0, 0.0, vignette * 0.55);
	COLOR.rgb = mix(COLOR.rgb, vec3(0.0), vignette * 0.9);
}
