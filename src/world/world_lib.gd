## WorldLib — shared palette, layout constants, and build-once caches of primitive meshes and
## StandardMaterial3D instances for the 3D factory (no per-frame material/mesh creation, §8).
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
const COL_GHOST := Color(0.55, 0.66, 0.85, 0.06)

# Per-station accent trim colors; status semantics stay on beacons/icons only.
const STATION_ACCENTS := {
	"press": Color("F4B942"),
	"lathe": Color("7FA8D0"),
	"weld": Color("C7743F"),
	"paint": Color("4FB0A5"),
	"assembly": Color("8E9BB3"),
	"pack": Color("6FBF73"),
}

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

# Render layer 2 = ceiling clutter (trusses, fans): the orbit camera culls it while looking
# down from above so beams never slice the management view; the walk camera always sees it.
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


static func quad(size: float) -> QuadMesh:
	var key := "quad_%.3f" % size
	if not _mesh_cache.has(key):
		var m := QuadMesh.new()
		m.size = Vector2(size, size)
		_mesh_cache[key] = m
	var out: QuadMesh = _mesh_cache[key]
	return out


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


## Swap every MeshInstance3D under `root` to/from the given ghost material.
## Base materials are restored from the "base_mat" meta stored by add_box/add_cyl.
static func apply_ghost(root: Node, ghost: bool, ghost_mat: Material) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if ghost:
			mi.material_override = ghost_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			var base: Material = mi.get_meta("base_mat", null)
			mi.material_override = base
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
