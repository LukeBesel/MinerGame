// Volumetric-look skylight shaft: additive, unshaded cone that fades toward the floor and
// at its silhouette edges. Pure raster trick — survives gl_compatibility (web) unchanged.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.62, 0.72, 0.92);
uniform float strength = 0.09;

varying float vy;

void vertex() {
	vy = VERTEX.y + 0.5; // unit cylinder: 0 at floor end, 1 at skylight end
}

void fragment() {
	float h = clamp(vy, 0.0, 1.0);
	float a = pow(h, 1.35);
	// Fade the silhouette so the cone has no hard polygon edge.
	float rim = abs(dot(normalize(VIEW), normalize(NORMAL)));
	a *= smoothstep(0.06, 0.6, rim);
	ALBEDO = tint * a * strength;
}
