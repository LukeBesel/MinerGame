// Floor shader: worn dark concrete with seam grid, traffic wear, dashed amber aisle strips
// marking the line path, and a green radial pulse wave (driven by FactoryWorld on
// EventBus.bottleneck_cleared — wave_radius < 0 means off).
shader_type spatial;
render_mode cull_back;

uniform vec3 base_color : source_color = vec3(0.137, 0.149, 0.169);
uniform vec3 seam_color : source_color = vec3(0.072, 0.079, 0.091);
uniform float seam_period = 2.0;
uniform float seam_width = 0.05;

uniform vec3 strip_color : source_color = vec3(0.956, 0.725, 0.259);
uniform float strip_emission = 0.55;
uniform float strip_z = 2.45;
uniform float strip_half_width = 0.075;
uniform float strip_min_x = -6.0;
uniform float strip_max_x = 41.0;

uniform vec2 wave_origin = vec2(0.0, 0.0);
uniform float wave_radius = -100.0;
uniform float wave_width = 2.4;
uniform float wave_strength = 0.0;
uniform vec3 wave_color : source_color = vec3(0.247, 0.639, 0.302);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 p = wpos.xz;
	float wear = vnoise(p * 0.33) * 0.7 + vnoise(p * 1.31) * 0.3;
	vec3 col = base_color * (0.82 + 0.34 * wear);

	// Concrete seam grid.
	vec2 g = abs(fract(p / seam_period - 0.5) - 0.5) * seam_period;
	float seam = 1.0 - smoothstep(0.0, seam_width, min(g.x, g.y));
	col = mix(col, seam_color, seam * 0.85);

	// Traffic wear along the production aisle (z near 0).
	col *= 1.0 - 0.10 * (1.0 - smoothstep(0.8, 3.2, abs(p.y)));

	// Sparse dark scuffs.
	float scuff = smoothstep(0.78, 1.0, vnoise(p * 2.7 + 13.7));
	col = mix(col, col * 0.7, scuff * 0.5);

	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = 0.93 - 0.18 * wear;

	// Dashed amber strips marking the line path.
	float in_x = step(strip_min_x, p.x) * step(p.x, strip_max_x);
	float strip = (1.0 - smoothstep(strip_half_width * 0.55, strip_half_width, abs(abs(p.y) - strip_z))) * in_x;
	strip *= step(0.3, fract(p.x * 0.5));
	vec3 emis = strip_color * strip * strip_emission;

	// Green pulse wave (the signature bottleneck-cleared moment).
	float dist = distance(p, wave_origin);
	float ring = 1.0 - smoothstep(0.0, wave_width, abs(dist - wave_radius));
	emis += wave_color * ring * ring * wave_strength;

	EMISSION = emis;
}
