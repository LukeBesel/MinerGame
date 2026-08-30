## WorldLib — shared palette, layout constants, the PBR material library (CC0 texture sets
## fetched by tools/fetch_textures.py, flat-color fallback when maps are absent), and
## build-once caches of primitive meshes (no per-frame material/mesh creation, §8).
## Reference via: const WorldLib = preload("res://src/world/world_lib.gd")
extends RefCounted

# --- Palette (pinned in ARCHITECTURE.md §14) ---
const COL_BG := Color("17191D")
const COL_FLOOR := Color("23262B")
const COL_PANEL := Color("1E2126")
const COL_TEXT := Color("E8EAED")
const COL_AMBER := Color("F4B942")
const COL_GREEN := Color("3FA34D")
const COL_RED := Color("E4572E")
const COL_GREY := Color("9AA0A6")

# Supporting neutrals (visual-only constants, allowed in code).
const COL_STEEL := Color("3A3F47")
const COL_STEEL_DARK := Color("2A2E34")
const COL_TRUSS := Color("30343B")
const COL_PART := Color("B9BFC7")
const COL_SKYLIGHT := Color("AFC6E8")
const COL_WARM := Color("FFC98A")
const COL_GHOST := Color(0.55, 0.66, 0.85, 0.085)
const COL_SAFETY := Color("D9A62E")
const COL_WOOD := Color("8A6B45")
const COL_CABINET := Color("6E7681")

# Per-station accent trim colors; status semantics stay on beacons/icons only.
const STATION_ACCENTS := {
	"press": Color("F4B942"),
	"lathe": Color("7FA8D0"),
	"weld": Color("C7743F"),
	"paint": Color("4FB0A5"),
	"assembly": Color("8E9BB3"),
	"pack": Color("6FBF73"),
}

# Machine body paint per station: the accent hue pulled toward workshop-machine neutrals
# (kept deep — the desaturated paint albedo lifts whatever it is tinted with).
const STATION_PAINT := {
	"press": Color("7C6A45"),
	"lathe": Color("52687F"),
	"weld": Color("77543E"),
	"paint": Color("446E68"),
	"assembly": Color("585F70"),
	"pack": Color("4F6B54"),
}

# --- Texture sets (assets/textures/<Set>/<Set>_{Color,NormalGL,Roughness}.jpg) ---
const TEX_ROOT := "res://assets/textures"
const SET_CONCRETE := "Concrete034"
const SET_WALL := "CorrugatedSteel005"
const SET_PAINT := "PaintedMetal012"
const SET_PLATE := "MetalPlates006"
const SET_GALV := "Metal032"
const SET_RUBBER := "Rubber004"
const SET_DIAMOND := "DiamondPlate005A"

# --- Layout (stations along +X at z = 0) ---
const STATION_SPACING := 7.0
const MACHINE_HALF_W := 1.5
const BELT_TOP_Y := 0.5
const FLOOR_MIN_X := -14.0
const FLOOR_MAX_X := 50.0
const FLOOR_MIN_Z := -16.0
const FLOOR_MAX_Z := 16.0
const WALL_HEIGHT := 8.0
const WALK_MARGIN := 1.2

# Physics layers: 1 = floor (walk collision), 2 = station pick bodies.
const LAYER_FLOOR := 1
const LAYER_STATION := 2

# Render layer 2 = ceiling clutter (trusses, fans, skylight frames): the orbit camera culls
# it while looking down from above so beams never slice the management view; the walk camera
# always sees it.
const RENDER_LAYER_CEILING := 2
const CEILING_VIS_HEIGHT := 6.8


## Put every VisualInstance3D under `root` on the given render layer mask.
static func set_render_layers(root: Node, mask: int) -> void:
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers = mask
	for child in root.get_children():
		set_render_layers(child, mask)

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}


# --- Meshes (shared, scaled per node) ---

static func unit_box() -> BoxMesh:
	if not _mesh_cache.has("box"):
		var m := BoxMesh.new()
		m.size = Vector3.ONE
		_mesh_cache["box"] = m
	var out: BoxMesh = _mesh_cache["box"]
	return out


static func unit_cyl(radial: int = 20) -> CylinderMesh:
	var key := "cyl_%d" % radial
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = 0.5
		m.bottom_radius = 0.5
		m.height = 1.0
		m.radial_segments = radial
		_mesh_cache[key] = m
	var out: CylinderMesh = _mesh_cache[key]
	return out


static func unit_sphere(radial: int = 12) -> SphereMesh:
	var key := "sph_%d" % radial
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = radial
		m.rings = maxi(6, radial / 2)
		_mesh_cache[key] = m
	var out: SphereMesh = _mesh_cache[key]
	return out


static func unit_torus() -> TorusMesh:
	if not _mesh_cache.has("torus"):
		var m := TorusMesh.new()
		m.inner_radius = 0.94
		m.outer_radius = 1.0
		m.rings = 48
		m.ring_segments = 10
		_mesh_cache["torus"] = m
	var out: TorusMesh = _mesh_cache["torus"]
	return out


## Chunky small torus (washer/ring stamped part, roller collar...).
static func washer_mesh() -> TorusMesh:
	if not _mesh_cache.has("washer"):
		var m := TorusMesh.new()
		m.inner_radius = 0.55
		m.outer_radius = 1.0
		m.rings = 20
		m.ring_segments = 8
		_mesh_cache["washer"] = m
	var out: TorusMesh = _mesh_cache["washer"]
	return out


static func quad(size: float) -> QuadMesh:
	var key := "quad_%.3f" % size
	if not _mesh_cache.has(key):
		var m := QuadMesh.new()
		m.size = Vector2(size, size)
		_mesh_cache[key] = m
	var out: QuadMesh = _mesh_cache[key]
	return out


## Cone (bell shade / light shaft): unit height, given top/bottom radii at scale 1.
static func cone_mesh(top_r: float, bottom_r: float, radial: int = 16) -> CylinderMesh:
	var key := "cone_%.2f_%.2f_%d" % [top_r, bottom_r, radial]
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top_r
		m.bottom_radius = bottom_r
		m.height = 1.0
		m.radial_segments = radial
		m.cap_top = false
		m.cap_bottom = false
		_mesh_cache[key] = m
	var out: CylinderMesh = _mesh_cache[key]
	return out


# --- Texture loading (parallel/headless-safe: missing maps degrade to flat materials) ---

static func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		var cached: Variant = _tex_cache[path]
		return cached as Texture2D
	var t: Texture2D = null
	if ResourceLoader.exists(path, "Texture2D"):
		var res: Variant = load(path)
		t = res as Texture2D
	_tex_cache[path] = t
	return t


static func set_tex(set_name: String, map_name: String) -> Texture2D:
	return tex("%s/%s/%s_%s.jpg" % [TEX_ROOT, set_name, set_name, map_name])


# --- Materials (cached by parameters; do not mutate cached instances at runtime) ---

static func mat_flat(c: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var key := "f|%s|%.2f|%.2f" % [c.to_html(), rough, metal]
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mat_cache[key] = m
	var out: StandardMaterial3D = _mat_cache[key]
	return out


## Textured PBR material with world-space triplanar mapping (hides seams on scaled
## primitives). Falls back to a flat material when the texture set is missing on disk.
static func mat_pbr(set_name: String, tint: Color, tile: float, rough: float = 1.0, metal: float = 0.0, fallback_rough: float = 0.8, vcol: bool = false) -> StandardMaterial3D:
	var key := "p|%s|%s|%.2f|%.2f|%.2f|%s" % [set_name, tint.to_html(), tile, rough, metal, str(vcol)]
	if not _mat_cache.has(key):
		var color := set_tex(set_name, "Color")
		if color == null:
			var flat := StandardMaterial3D.new()
			flat.albedo_color = tint
			flat.roughness = fallback_rough
			flat.metallic = metal
			flat.vertex_color_use_as_albedo = vcol
			_mat_cache[key] = flat
		else:
			var m := StandardMaterial3D.new()
			m.albedo_texture = color
			m.albedo_color = tint
			m.metallic = metal
			m.roughness = rough
			var r := set_tex(set_name, "Roughness")
			if r != null:
				m.roughness_texture = r
				m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			var n := set_tex(set_name, "NormalGL")
			if n != null:
				m.normal_enabled = true
				m.normal_texture = n
				m.normal_scale = 1.0
			m.uv1_scale = Vector3(tile, tile, tile)
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_triplanar_sharpness = 6.0
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			m.vertex_color_use_as_albedo = vcol
			_mat_cache[key] = m
	var out: StandardMaterial3D = _mat_cache[key]
	return out


# The named library (all cached; call freely).

static func mat_machine(station_id: String) -> StandardMaterial3D:
	var paint: Color = STATION_PAINT.get(station_id, Color("6E7276"))
	return mat_pbr(SET_PAINT, paint, 0.55, 1.0, 0.12, 0.62)


static func mat_paint(tint: Color) -> StandardMaterial3D:
	return mat_pbr(SET_PAINT, tint, 0.55, 1.0, 0.12, 0.62)


static func mat_steel_plate() -> StandardMaterial3D:
	return mat_pbr(SET_PLATE, Color(0.62, 0.64, 0.67), 0.85, 1.0, 0.55, 0.5)


static func mat_steel_plate_dark() -> StandardMaterial3D:
	return mat_pbr(SET_PLATE, Color(0.36, 0.38, 0.41), 0.85, 1.0, 0.5, 0.55)


static func mat_galv() -> StandardMaterial3D:
	return mat_pbr(SET_GALV, Color(0.68, 0.71, 0.74), 0.9, 1.0, 0.72, 0.42)


static func mat_galv_dark() -> StandardMaterial3D:
	return mat_pbr(SET_GALV, Color(0.4, 0.42, 0.45), 0.9, 1.0, 0.6, 0.5)


static func mat_wall() -> StandardMaterial3D:
	return mat_pbr(SET_WALL, Color(0.4, 0.42, 0.46), 0.35, 1.0, 0.35, 0.8)


static func mat_wall_dado() -> StandardMaterial3D:
	return mat_pbr(SET_CONCRETE, Color(0.34, 0.36, 0.39), 0.5, 1.0, 0.0, 0.85)


static func mat_concrete_prop() -> StandardMaterial3D:
	return mat_pbr(SET_CONCRETE, Color(0.5, 0.51, 0.53), 0.5, 1.0, 0.0, 0.85)


static func mat_diamond() -> StandardMaterial3D:
	return mat_pbr(SET_DIAMOND, Color(0.58, 0.6, 0.63), 1.5, 1.0, 0.6, 0.45)


static func mat_rubber() -> StandardMaterial3D:
	return mat_pbr(SET_RUBBER, Color(0.5, 0.5, 0.52), 0.8, 1.0, 0.0, 0.9)


static func mat_safety() -> StandardMaterial3D:
	return mat_pbr(SET_PAINT, COL_SAFETY, 0.8, 1.0, 0.1, 0.6)


static func mat_wood() -> StandardMaterial3D:
	return mat_pbr(SET_CONCRETE, COL_WOOD, 1.1, 1.0, 0.0, 0.9)


## Hazard-stripe curb material (generated texture, world triplanar so stripes stay diagonal).
static func mat_hazard() -> StandardMaterial3D:
	if not _mat_cache.has("hazard"):
		var t := tex(TEX_ROOT + "/generated/hazard_stripes.jpg")
		if t == null:
			_mat_cache["hazard"] = mat_flat(COL_SAFETY, 0.8, 0.0)
		else:
			var m := StandardMaterial3D.new()
			m.albedo_texture = t
			m.albedo_color = Color(0.92, 0.92, 0.92)
			m.roughness = 0.85
			m.uv1_scale = Vector3(1.6, 1.6, 1.6)
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			_mat_cache["hazard"] = m
	var out: StandardMaterial3D = _mat_cache["hazard"]
	return out


## Floor decal (oil stain / skid marks): alpha-blended quad, no shadows, draws just above
## the slab. Returns null when the texture is missing (caller skips the decal).
static func mat_decal(file: String) -> StandardMaterial3D:
	var key := "d|" + file
	if not _mat_cache.has(key):
		var t := tex(TEX_ROOT + "/generated/" + file)
		if t == null:
			_mat_cache[key] = null
		else:
			var m := StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_texture = t
			m.albedo_color = Color(1, 1, 1, 0.85)
			m.roughness = 0.5
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			m.disable_receive_shadows = true
			m.no_depth_test = false
			_mat_cache[key] = m
	var out: StandardMaterial3D = _mat_cache[key]
	return out


static func mat_emissive(c: Color, energy: float = 2.0, albedo_scale: float = 0.22) -> StandardMaterial3D:
	var key := "e|%s|%.2f|%.2f" % [c.to_html(), energy, albedo_scale]
	if not _mat_cache.has(key):
		_mat_cache[key] = _make_emissive(c, energy, albedo_scale)
	var out: StandardMaterial3D = _mat_cache[key]
	return out


## Fresh (uncached) emissive material — for anything whose color/energy changes at runtime
## (status beacons, hover accents, the bottleneck marker). Built once per owner at setup.
static func mat_emissive_unique(c: Color, energy: float = 2.0, albedo_scale: float = 0.22) -> StandardMaterial3D:
	return _make_emissive(c, energy, albedo_scale)


static func _make_emissive(c: Color, energy: float, albedo_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r * albedo_scale, c.g * albedo_scale, c.b * albedo_scale)
	m.roughness = 0.6
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


static func mat_part() -> StandardMaterial3D:
	if not _mat_cache.has("part"):
		var m := StandardMaterial3D.new()
		m.albedo_color = COL_PART
		m.metallic = 0.55
		m.roughness = 0.38
		var r := set_tex(SET_GALV, "Roughness")
		if r != null:
			m.roughness = 0.85
			m.roughness_texture = r
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.emission_enabled = true
		m.emission = COL_AMBER
		m.emission_energy_multiplier = 0.07
		_mat_cache["part"] = m
	var out: StandardMaterial3D = _mat_cache["part"]
	return out


static func mat_ghost_unique() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = COL_GHOST
	m.emission_enabled = true
	m.emission = Color(0.5, 0.62, 0.85)
	m.emission_energy_multiplier = 0.22
	m.disable_receive_shadows = true
	return m


# --- Node helpers ---

static func add_box(parent: Node, size: Vector3, pos: Vector3, mat: Material, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = unit_box()
	mi.scale = size
	mi.position = pos
	mi.material_override = mat
	mi.set_meta("base_mat", mat)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func add_cyl(parent: Node, radius: float, height: float, pos: Vector3, mat: Material, radial: int = 20, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = unit_cyl(radial)
	mi.scale = Vector3(radius * 2.0, height, radius * 2.0)
	mi.position = pos
	mi.material_override = mat
	mi.set_meta("base_mat", mat)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func add_sphere(parent: Node, radius: float, pos: Vector3, mat: Material, radial: int = 12, shadow: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = unit_sphere(radial)
	mi.scale = Vector3.ONE * radius * 2.0
	mi.position = pos
	mi.material_override = mat
	mi.set_meta("base_mat", mat)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## One draw call for many copies of a mesh: MultiMesh from an array of Transform3D.
static func add_multimesh(parent: Node, mesh: Mesh, mat: Material, transforms: Array, shadow: bool = true, colors: Array = []) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		if i < colors.size():
			mm.set_instance_color(i, colors[i])
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.set_meta("base_mat", mat)
	if not shadow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


## Pipe run: cylinders through the waypoints with sphere elbows at interior joints.
static func add_pipe(parent: Node, points: Array, radius: float, mat: Material) -> void:
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var mid := (a + b) * 0.5
		var seg := b - a
		var mi := MeshInstance3D.new()
		mi.mesh = unit_cyl(10)
		mi.scale = Vector3(radius * 2.0, seg.length(), radius * 2.0)
		mi.position = mid
		if seg.normalized().abs().dot(Vector3.UP) < 0.999:
			mi.rotation = Quaternion(Vector3.UP, seg.normalized()).get_euler()
		mi.material_override = mat
		mi.set_meta("base_mat", mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		if i > 0:
			add_sphere(parent, radius * 1.18, a, mat, 10)


## Thin lighter trim strips laid along the top edges of a box footprint — reads as a
## chamfered/welded edge from a distance and breaks up big flat faces.
static func add_edge_trim(parent: Node, size: Vector3, pos: Vector3, mat: Material, t: float = 0.045) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y := pos.y + size.y * 0.5
	add_box(parent, Vector3(size.x + t, t, t), Vector3(pos.x, y, pos.z + hz), mat, false)
	add_box(parent, Vector3(size.x + t, t, t), Vector3(pos.x, y, pos.z - hz), mat, false)
	add_box(parent, Vector3(t, t, size.z + t), Vector3(pos.x + hx, y, pos.z), mat, false)
	add_box(parent, Vector3(t, t, size.z + t), Vector3(pos.x - hx, y, pos.z), mat, false)


static func make_label(text: String, color: Color, font_size: int = 48, pixel_size: float = 0.012) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = pixel_size
	l.modulate = color
	l.outline_size = maxi(6, font_size / 4)
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return l


## Flat wall/floor signage text: not billboarded, no outline halo, subtle emissive so it
## stays readable in the dark hall without glowing like UI.
static func make_sign(text: String, color: Color, font_size: int = 64, pixel_size: float = 0.02) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = pixel_size
	l.modulate = color
	l.outline_size = 0
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	return l


## Swap every MeshInstance3D / MultiMeshInstance3D under `root` to/from the given ghost
## material. Base materials are restored from the "base_mat" meta stored by the helpers.
static func apply_ghost(root: Node, ghost: bool, ghost_mat: Material) -> void:
	if root is MeshInstance3D or root is MultiMeshInstance3D:
		var gi := root as GeometryInstance3D
		if ghost:
			gi.material_override = ghost_mat
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			var base: Material = gi.get_meta("base_mat", null)
			gi.material_override = base
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in root.get_children():
		apply_ghost(child, ghost, ghost_mat)


# --- Settings access (parallel-safe: SettingsService may still be a stub) ---

static func setting(key: String, fallback: Variant) -> Variant:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return fallback
	var root := (loop as SceneTree).root
	if root == null:
		return fallback
	var svc := root.get_node_or_null("SettingsService")
	if svc == null:
		return fallback
	var v: Variant = svc.get(key)
	if v == null:
		return fallback
	return v


static func reduce_motion() -> bool:
	return setting("reduce_motion", false) == true


static func cam_sensitivity() -> float:
	var v: Variant = setting("camera_sensitivity", 1.0)
	if v is float or v is int:
		return clampf(float(v), 0.1, 4.0)
	return 1.0
