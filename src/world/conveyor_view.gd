## ConveyorView3D — one belt segment of the line: textured rubber belt with emissive
## chevrons scrolling at a speed proportional to upstream throughput, galvanized C-channel
## side rails, rotating end rollers, H-frame leg stands, and parts riding the belt as three
## capped MultiMesh shape variants (density ∝ flow; above the cap it reads as a continuous
## stream, never 1:1 parts).
extends Node3D

const WorldLib = preload("res://src/world/world_lib.gd")
const BELT_SHADER: Shader = preload("res://src/world/belt_chevrons.gdshader")

const MAX_PARTS := 26
const VARIANTS := 3
const PART_SIZE := 0.26
const PHI := 0.6180339887
const CHEV_SPACING := 0.62

var _length := 4.0
var _belt_root: Node3D = null
var _belt_mat: ShaderMaterial = null
var _ghost_mat: StandardMaterial3D = null
var _parts_root: Node3D = null
var _part_mms: Array = []
var _part_basis: Array[Basis] = []
var _part_y: Array[float] = []
var _part_z: Array[float] = []
var _rollers: Array = []

var _scroll_chev := 0.0
var _scroll_parts := 0.0
var _speed := 0.0
var _target_speed := 0.0
var _density := 0.0
var _shown := -1
var _active := false
var _ghosted := false


## Build a belt spanning local x in [0, length] at z = 0.
func setup(length: float) -> void:
	_length = maxf(1.0, length)
	_ghost_mat = WorldLib.mat_ghost_unique()
	_belt_root = Node3D.new()
	_belt_root.name = "Belt"
	add_child(_belt_root)

	_belt_mat = ShaderMaterial.new()
	_belt_mat.shader = BELT_SHADER
	_belt_mat.set_shader_parameter("chevron_spacing", CHEV_SPACING)
	_belt_mat.set_shader_parameter("albedo_tex", WorldLib.set_tex(WorldLib.SET_RUBBER, "Color"))
	_belt_mat.set_shader_parameter("normal_tex", WorldLib.set_tex(WorldLib.SET_RUBBER, "NormalGL"))
	_belt_mat.set_shader_parameter("rough_tex", WorldLib.set_tex(WorldLib.SET_RUBBER, "Roughness"))
	var mid := _length * 0.5
	WorldLib.add_box(_belt_root, Vector3(_length, 0.12, 1.0), Vector3(mid, 0.44, 0.0), _belt_mat)

	# C-channel side rails with a return lip.
	var rail := WorldLib.mat_galv()
	var rail_dark := WorldLib.mat_galv_dark()
	WorldLib.add_box(_belt_root, Vector3(_length, 0.16, 0.06), Vector3(mid, 0.46, 0.56), rail)
	WorldLib.add_box(_belt_root, Vector3(_length, 0.16, 0.06), Vector3(mid, 0.46, -0.56), rail)
	WorldLib.add_box(_belt_root, Vector3(_length, 0.035, 0.1), Vector3(mid, 0.55, 0.54), rail_dark, false)
	WorldLib.add_box(_belt_root, Vector3(_length, 0.035, 0.1), Vector3(mid, 0.55, -0.54), rail_dark, false)

	# Rotating end rollers (visible drum + offset collar so the spin reads).
	for ex in [minf(0.16, _length * 0.5), _length - minf(0.16, _length * 0.5)]:
		var spin := Node3D.new()
		spin.position = Vector3(ex, 0.43, 0.0)
		_belt_root.add_child(spin)
		var drum := WorldLib.add_cyl(spin, 0.1, 1.06, Vector3.ZERO, rail_dark, 12, false)
		drum.rotation.x = PI * 0.5
		var collar := MeshInstance3D.new()
		collar.mesh = WorldLib.washer_mesh()
		collar.scale = Vector3(0.115, 0.115, 0.115)
		collar.position = Vector3(0.0, 0.0, 0.36)
		collar.rotation.x = PI * 0.5
		collar.material_override = rail
		collar.set_meta("base_mat", rail)
		collar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spin.add_child(collar)
		_rollers.append(spin)

	# H-frame leg stands with feet (one MultiMesh).
	var leg_tfs: Array = []
	var legs := int(floor(_length / 1.7)) + 1
	for i in range(legs):
		var lx := clampf(0.4 + float(i) * 1.7, 0.35, _length - 0.35)
		for lz in [-0.42, 0.42]:
			leg_tfs.append(Transform3D(Basis.from_scale(Vector3(0.07, 0.4, 0.07)), Vector3(lx, 0.19, lz)))
			leg_tfs.append(Transform3D(Basis.from_scale(Vector3(0.16, 0.03, 0.16)), Vector3(lx, 0.015, lz)))
		leg_tfs.append(Transform3D(Basis.from_scale(Vector3(0.06, 0.05, 0.86)), Vector3(lx, 0.22, 0.0)))
	WorldLib.add_multimesh(_belt_root, WorldLib.unit_box(), rail_dark, leg_tfs)

	# Parts: three stamped-shape variants sharing the MAX_PARTS budget.
	_parts_root = Node3D.new()
	_parts_root.name = "Parts"
	add_child(_parts_root)
	var meshes: Array = [WorldLib.unit_box(), WorldLib.unit_cyl(12), WorldLib.washer_mesh()]
	for v in range(VARIANTS):
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[v]
		mm.instance_count = (MAX_PARTS + VARIANTS - 1 - v) / VARIANTS
		mm.visible_instance_count = 0
		mmi.multimesh = mm
		mmi.material_override = WorldLib.mat_part()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_parts_root.add_child(mmi)
		_part_mms.append(mmi)
	# Precompute per-slot jitter + per-variant footprint (deterministic, cosmetic).
	for i in range(MAX_PARTS):
		var yaw := fmod(float(i) * 2.39996, TAU) * 0.12
		var b := Basis(Vector3.UP, yaw)
		match i % VARIANTS:
			0:	# stamped plate
				_part_basis.append(b * Basis.from_scale(Vector3(0.3, 0.09, 0.3)))
				_part_y.append(0.045)
			1:	# turned puck
				_part_basis.append(b * Basis.from_scale(Vector3(0.24, 0.12, 0.24)))
				_part_y.append(0.06)
			_:	# stamped ring
				_part_basis.append(b * Basis.from_scale(Vector3(0.15, 0.15, 0.15)))
				_part_y.append(0.036)
		_part_z.append(fmod(float(i) * 0.7548776, 1.0) * 0.24 - 0.12)
	_shown = 0


## Upstream throughput drives belt speed and part density. `flowing` is false while either
## end of this segment is still locked.
func set_flow(throughput: float, flowing: bool) -> void:
	if flowing != _active:
		_active = flowing
		_belt_mat.set_shader_parameter("active", 1.0 if flowing else 0.0)
	if not flowing:
		_target_speed = 0.0
		_density = 0.0
		return
	_target_speed = clampf(0.55 + throughput * 0.38, 0.55, 4.2)
	_density = clampf(throughput / _target_speed, 0.0, float(MAX_PARTS) / _length)


func set_ghost(g: bool) -> void:
	if g == _ghosted:
		return
	_ghosted = g
	WorldLib.apply_ghost(_belt_root, g, _ghost_mat)
	_parts_root.visible = not g


func _process(delta: float) -> void:
	if _belt_mat == null:
		return
	_speed = lerpf(_speed, _target_speed, minf(1.0, delta * 3.0))
	var count := clampi(int(round(_density * _length)), 0, MAX_PARTS)
	if count != _shown:
		_shown = count
		for v in range(VARIANTS):
			var mmi: MultiMeshInstance3D = _part_mms[v]
			mmi.multimesh.visible_instance_count = (count + VARIANTS - 1 - v) / VARIANTS
		_update_parts()
	if _speed <= 0.005:
		return
	var d := _speed * delta
	_scroll_chev = fposmod(_scroll_chev + d, CHEV_SPACING)
	_scroll_parts = fposmod(_scroll_parts + d, _length)
	_belt_mat.set_shader_parameter("scroll", _scroll_chev)
	for spin in _rollers:
		var s := spin as Node3D
		s.rotation.z -= d * 10.0
	if count > 0:
		_update_parts()


func _update_parts() -> void:
	var y0 := WorldLib.BELT_TOP_Y
	for i in range(_shown):
		var x := fposmod(float(i) * PHI * _length + _scroll_parts, _length)
		var mmi: MultiMeshInstance3D = _part_mms[i % VARIANTS]
		mmi.multimesh.set_instance_transform(i / VARIANTS, Transform3D(_part_basis[i], Vector3(x, y0 + _part_y[i], _part_z[i])))
