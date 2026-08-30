// Conveyor belt shader: real rubber PBR maps scrolling with the belt, plus moving emissive
// chevrons pointing +X (flow direction). `scroll` is accumulated on the CPU by ConveyorView
// (speed * dt, wrapped at chevron_spacing) so speed changes never cause a phase jump; the
// rubber UV tiles at exactly 1 tile per chevron_spacing so the wrap is invisible. `active`
// dims chevrons on halted/ghost belts. Texture uniforms default safe if maps are absent.
shader_type spatial;
render_mode cull_back;

uniform vec3 belt_color : source_color = vec3(0.30, 0.30, 0.32);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap;
uniform vec3 chevron_color : source_color = vec3(0.956, 0.725, 0.259);
uniform float chevron_spacing = 0.62;
uniform float chevron_sharp = 0.1;
uniform float scroll = 0.0;
uniform float emission_energy = 0.85;
uniform float active = 1.0;

varying vec3 wpos;
varying vec3 wnormal;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float u = wpos.x - scroll;
	// 1 rubber tile per chevron_spacing => the CPU-side wrap at chevron_spacing is seamless.
	vec2 belt_uv = vec2(u / chevron_spacing * 0.5, wpos.z * 0.8 + wpos.y * 0.8);
	vec3 rub = texture(albedo_tex, belt_uv).rgb;
	ALBEDO = belt_color * rub;
	ROUGHNESS = texture(rough_tex, belt_uv).r * 0.95;
	METALLIC = 0.02;
	NORMAL_MAP = texture(normal_tex, belt_uv).rgb;
	NORMAL_MAP_DEPTH = 0.8;

	// Chevrons mostly on the top face; faint on the sides.
	float topness = smoothstep(0.5, 0.9, wnormal.y);
	// V shape whose tip leads in +X.
	float band = fract((u + abs(wpos.z) * 0.85) / chevron_spacing);
	float chev = smoothstep(0.0, chevron_sharp, band) * (1.0 - smoothstep(chevron_sharp, chevron_sharp * 2.6, band));
	EMISSION = chevron_color * chev * emission_energy * mix(0.2, 1.0, topness) * (0.15 + 0.85 * active);
}
