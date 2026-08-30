// Floor shader: real worn-concrete PBR maps (world-space UVs, detail normal) layered with
// seam grid, traffic wear, dashed amber aisle strips marking the line path, and a green
// radial pulse wave (driven by FactoryWorld on EventBus.bottleneck_cleared — wave_radius < 0
// means off). Texture uniforms default safe, so the shader still renders if maps are absent.
shader_type spatial;
render_mode cull_back;

uniform vec3 base_color : source_color = vec3(0.195, 0.205, 0.225);
uniform vec3 seam_color : source_color = vec3(0.05, 0.055, 0.065);
uniform float seam_period = 4.6;
uniform float seam_width = 0.04;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap;
uniform float uv_scale = 0.16;
uniform float detail_uv_scale = 0.83;
uniform float normal_strength = 0.55;

uniform vec3 strip_color : source_color = vec3(0.956, 0.725, 0.259);
uniform float strip_emission = 0.5;
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
	// Two concrete samples at different scales kill visible tiling on the big slab.
	vec3 tex_a = texture(albedo_tex, p * uv_scale).rgb;
	vec3 tex_b = texture(albedo_tex, p * detail_uv_scale + vec2(0.37, 0.11)).rgb;
	vec3 conc = tex_a * mix(vec3(1.0), tex_b * 1.9, 0.35);
	float wear = vnoise(p * 0.33) * 0.7 + vnoise(p * 1.31) * 0.3;
	vec3 col = base_color * conc * (0.8 + 0.34 * wear);

	// Concrete pour-seam grid.
	vec2 g = abs(fract(p / seam_period - 0.5) - 0.5) * seam_period;
	float seam = 1.0 - smoothstep(0.0, seam_width, min(g.x, g.y));
	col = mix(col, seam_color, seam * 0.5);

	// Traffic wear/polish along the production aisle (z near 0).
	float aisle = 1.0 - smoothstep(0.8, 3.4, abs(p.y));
	col *= 1.0 - 0.13 * aisle;

	// Sparse dark scuffs.
	float scuff = smoothstep(0.78, 1.0, vnoise(p * 2.7 + 13.7));
	col = mix(col, col * 0.65, scuff * 0.55);

	ALBEDO = col;
	METALLIC = 0.0;
	float r = texture(rough_tex, p * uv_scale).r;
	ROUGHNESS = clamp(r * (1.02 - 0.2 * wear) - 0.14 * aisle, 0.35, 1.0);
	NORMAL_MAP = texture(normal_tex, p * detail_uv_scale).rgb;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - seam);

	// Dashed amber strips marking the line path.
	float in_x = step(strip_min_x, p.x) * step(p.x, strip_max_x);
	float strip = (1.0 - smoothstep(strip_half_width * 0.55, strip_half_width, abs(abs(p.y) - strip_z))) * in_x;
	strip *= step(0.3, fract(p.x * 0.5));
	// Painted stripe: worn paint albedo + faint emission so it reads at night.
	col = mix(col, strip_color * (0.55 + 0.3 * wear), strip * 0.85);
	ALBEDO = col;
	vec3 emis = strip_color * strip * strip_emission;

	// Green pulse wave (the signature bottleneck-cleared moment).
	float dist = distance(p, wave_origin);
	float ring = 1.0 - smoothstep(0.0, wave_width, abs(dist - wave_radius));
	emis += wave_color * ring * ring * wave_strength;

	EMISSION = emis;
}
