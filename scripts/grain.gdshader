shader_type canvas_item;
// Silent Hill screen treatment: moving film grain and a dark vignette over the 3D view.

uniform float grain = 0.035;
uniform float vignette = 0.55;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float n = hash(floor(FRAGCOORD.xy / 2.0) + floor(TIME * 24.0) * 1.37) - 0.5;
	float v = smoothstep(0.35, 0.95, length(uv - 0.5) * 1.35);
	COLOR = vec4(vec3(0.5 + n), abs(n) * grain * 2.0);
	COLOR = mix(COLOR, vec4(0.02, 0.02, 0.02, 1.0), v * vignette);
}
