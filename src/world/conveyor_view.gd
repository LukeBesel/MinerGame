## ConveyorView3D — one belt segment of the line: emissive chevrons scrolling at a speed
## proportional to upstream throughput, plus parts riding the belt as a capped MultiMesh
## (density ∝ flow; above the cap it reads as a continuous stream, never 1:1 parts).
extends Node3D

const WorldLib = preload("res://src/world/world_lib.gd")
const BELT_SHADER: Shader = preload("res://src/world/belt_chevrons.gdshader")

const MAX_PARTS := 26
const PART_SIZE := 0.26
const PHI := 0.6180339887
const CHEV_SPACING := 0.62

var _length := 4.0
var _belt_root: Node3D = null
var _belt_mat: ShaderMaterial = null
var _ghost_mat: StandardMaterial3D = null
var _parts: MultiMeshInstance3D = null
var _part_basis: Array[Basis] = []
var _part_z: Array[float] = []

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
	var mid := _length * 0.5
	WorldLib.add_box(_belt_root, Vector3(_length, 0.12, 1.0), Vector3(mid, 0.44, 0.0), _belt_mat)

	var rail := WorldLib.mat_flat(WorldLib.COL_STEEL_DARK, 0.6, 0.4)
	WorldLib.add_box(_belt_root, Vector3(_length, 0.09, 0.07), Vector3(mid, 0.5, 0.56), rail)
	WorldLib.add_box(_belt_root, Vector3(_length, 0.09, 0.07), Vector3(mid, 0.5, -0.56), rail)
	var legs := int(floor(_length / 1.6)) + 1
	for i in range(legs):
		var lx := clampf(0.35 + float(i) * 1.6, 0.3, _length - 0.3)
		WorldLib.add_box(_belt_root, Vector3(0.09, 0.4, 0.85), Vector3(lx, 0.19, 0.0), rail)

	_parts = MultiMeshInstance3D.new()
	_parts.name = "Parts"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = WorldLib.unit_box()
	mm.instance_count = MAX_PARTS
	mm.visible_instance_count = 0
	_parts.multimesh = mm
	_parts.material_override = WorldLib.mat_part()
	_parts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_parts)
	# Precompute per-slot jitter (deterministic, cosmetic).
	for i in range(MAX_PARTS):
		var yaw := fmod(float(i) * 2.39996, TAU) * 0.12
		_part_basis.append(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(PART_SIZE, PART_SIZE, PART_SIZE)))
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
	_parts.visible = not g


func _process(delta: float) -> void:
	if _belt_mat == null:
		return
	_speed = lerpf(_speed, _target_speed, minf(1.0, delta * 3.0))
	var count := clampi(int(round(_density * _length)), 0, MAX_PARTS)
	if count != _shown:
		_shown = count
		_parts.multimesh.visible_instance_count = count
		_update_parts()
	if _speed <= 0.005:
		return
	var d := _speed * delta
	_scroll_chev = fposmod(_scroll_chev + d, CHEV_SPACING)
	_scroll_parts = fposmod(_scroll_parts + d, _length)
	_belt_mat.set_shader_parameter("scroll", _scroll_chev)
	if count > 0:
		_update_parts()


func _update_parts() -> void:
	var mm := _parts.multimesh
	var y := WorldLib.BELT_TOP_Y + PART_SIZE * 0.5
	for i in range(_shown):
		var x := fposmod(float(i) * PHI * _length + _scroll_parts, _length)
		mm.set_instance_transform(i, Transform3D(_part_basis[i], Vector3(x, y, _part_z[i])))
