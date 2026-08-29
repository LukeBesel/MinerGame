// Conveyor belt shader: dark rubber with moving emissive chevrons pointing +X (flow
// direction). `scroll` is accumulated on the CPU by ConveyorView (speed * dt) so speed
// changes never cause a phase jump; `active` dims chevrons on halted/ghost belts.
shader_type spatial;
render_mode cull_back;

uniform vec3 belt_color : source_color = vec3(0.078, 0.086, 0.098);
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
	ALBEDO = belt_color;
	ROUGHNESS = 0.9;
	METALLIC = 0.05;

	// Chevrons mostly on the top face; faint on the sides.
	float topness = smoothstep(0.5, 0.9, wnormal.y);
	// V shape whose tip leads in +X.
	float u = wpos.x - scroll + abs(wpos.z) * 0.85;
	float band = fract(u / chevron_spacing);
	float chev = smoothstep(0.0, chevron_sharp, band) * (1.0 - smoothstep(chevron_sharp, chevron_sharp * 2.6, band));
	EMISSION = chevron_color * chev * emission_energy * mix(0.2, 1.0, topness) * (0.15 + 0.85 * active);
}
