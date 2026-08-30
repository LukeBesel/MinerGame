## StationView3D — one machine on the line: a distinct multi-part industrial assembly per
## pinned station id (textured PBR, pipe runs, control cabinet, guard rails, hazard curbs),
## status beacon + colorblind-safe icon, WIP pile, scrap bin, and cycle animation driven by
## the sim_stats station view dict. Locked stations render as ghost outlines with a price tag.
extends Node3D

const WorldLib = preload("res://src/world/world_lib.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")

const WIP_MAX := 12

# Shared particle resources (built once for all stations).
static var _spark_process: ParticleProcessMaterial = null
static var _spark_mesh: QuadMesh = null
static var _mist_process: ParticleProcessMaterial = null
static var _mist_mesh: QuadMesh = null

var station_index: int = -1
var station_id := ""

var _body: Node3D = null
var _unlocked := true
var _status: int = SimTypes.STATUS_IDLE
var _is_bottleneck := false
var _hovered := false
var _throughput := 0.0
var _cycle_rate := 0.0
var _phase := 0.0
var _anim_t := 0.0
var _top_y := 3.2

var _ghost_mat: StandardMaterial3D = null
var _beacon_mat: StandardMaterial3D = null
var _accent_mat: StandardMaterial3D = null
var _screen_mat: StandardMaterial3D = null
var _accent_color := WorldLib.COL_AMBER
var _accent_energy := 0.5

var _icon_label: Label3D = null
var _price_label: Label3D = null
var _name_label: Label3D = null
var _beacon_root: Node3D = null
var _wip: MultiMeshInstance3D = null
var _wip_shown := -1
var _bin_root: Node3D = null
var _scrap_fill: MeshInstance3D = null
var _scrap_frac := 0.0
var _scrap_target := 0.0
var _pop_tween: Tween = null

# Animated silhouette parts (set by the relevant builder only).
var _ram: MeshInstance3D = null
var _spindle: Node3D = null
var _arm_a: Node3D = null
var _arm_b: Node3D = null
var _arm_c: Node3D = null
var _arm_d: Node3D = null
var _scan_bar: MeshInstance3D = null
var _particles: GPUParticles3D = null


func setup(index: int, view: Dictionary) -> void:
	station_index = index
	station_id = str(view.get("id", ""))
	name = "Station_%d_%s" % [index, station_id]
	_accent_color = WorldLib.STATION_ACCENTS.get(station_id, WorldLib.COL_AMBER)
	_ghost_mat = WorldLib.mat_ghost_unique()
	_anim_t = float(index) * 1.37	# desync idle animations between stations
	_build_common(str(view.get("name", "")))
	_build_machine()
	_build_cell_dressing()
	_build_collider()
	# Force the first apply_view() to run the unlock/lock path.
	_unlocked = true
	_status = -1
	apply_view(view)


## Called at 10 Hz with this station's view dict from EventBus.sim_stats.
func apply_view(view: Dictionary) -> void:
	var unlocked := bool(view.get("unlocked", false))
	if unlocked != _unlocked:
		_set_unlocked(unlocked)
	if not _unlocked:
		var cost: Variant = view.get("unlock_cost")
		if cost is Object and cost.has_method("format"):
			var fmt := str(WorldLib.setting("number_format", "suffix"))
			_price_label.text = "$ %s" % str(cost.format(fmt))
		return
	var status := int(view.get("status", SimTypes.STATUS_IDLE))
	if status != _status:
		_set_status(status)
	_throughput = maxf(0.0, float(view.get("throughput", 0.0)))
	var stats: Dictionary = view.get("stats", {})
	var capacity := maxf(1.0, float(stats.get("capacity", 1)))
	_cycle_rate = clampf(_throughput / capacity, 0.0, 3.0)
	# Resync the animation phase with the sim's cycle progress when drifted.
	var progress := clampf(float(view.get("progress", 0.0)), 0.0, 1.0)
	var drift := fposmod(progress - _phase + 0.5, 1.0) - 0.5
	if absf(drift) > 0.2:
		_phase = progress
	var bneck := bool(view.get("is_bottleneck", false))
	if bneck != _is_bottleneck:
		_is_bottleneck = bneck
		_refresh_accent()
	# WIP pile in front of the input side.
	var wip_frac := 0.0
	var cap := float(view.get("buffer_in_cap", 0.0))
	if cap > 0.0:
		wip_frac = clampf(float(view.get("buffer_in", 0.0)) / cap, 0.0, 1.0)
	var shown := int(ceil(wip_frac * float(WIP_MAX)))
	if station_index == 0:
		shown = 3	# station 0 draws from infinite raw stock: steady small pile
	if shown != _wip_shown:
		_wip_shown = shown
		_wip.multimesh.visible_instance_count = shown
	# Scrap bin fill ~ share of production lost to quality.
	var scrap := maxf(0.0, float(view.get("scrap_rate", 0.0)))
	var frac := scrap / maxf(scrap + _throughput, 0.001)
	_scrap_target = pow(clampf(frac, 0.0, 1.0), 0.6)


## World-space anchor above the machine for the bottleneck marker / celebration burst.
func marker_height() -> float:
	return _top_y + 0.9


func set_hovered(h: bool) -> void:
	if h == _hovered:
		return
	_hovered = h
	_accent_mat.emission_energy_multiplier = _accent_energy * (2.0 if h else 1.0)
	var ga := 0.2 if h else WorldLib.COL_GHOST.a
	_ghost_mat.albedo_color = Color(WorldLib.COL_GHOST.r, WorldLib.COL_GHOST.g, WorldLib.COL_GHOST.b, ga)


## Quick visible acknowledgement that an upgrade landed on this station.
func flash_upgrade() -> void:
	_accent_mat.emission_energy_multiplier = _accent_energy * 3.2
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	_pop_tween = create_tween()
	if not WorldLib.reduce_motion():
		_body.scale = Vector3.ONE * 1.055
		_pop_tween.tween_property(_body, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.parallel().tween_property(_accent_mat, "emission_energy_multiplier", _accent_energy, 0.45)


func _process(delta: float) -> void:
	if _body == null or not _unlocked:
		return
	var running := _status == SimTypes.STATUS_RUNNING
	if running:
		_anim_t += delta * clampf(0.6 + _throughput * 0.5, 0.6, 2.6)
		_phase = fposmod(_phase + _cycle_rate * delta, 1.0)
	# Smooth scrap-fill growth.
	if absf(_scrap_frac - _scrap_target) > 0.004:
		_scrap_frac = lerpf(_scrap_frac, _scrap_target, minf(1.0, delta * 2.0))
		var h := maxf(0.02, _scrap_frac * 0.42)
		_scrap_fill.scale.y = h
		_scrap_fill.position.y = 0.1 + h * 0.5
	match station_id:
		"press":
			_animate_press()
		"lathe":
			if running:
				_spindle.rotate_x(delta * clampf(4.0 + _throughput * 2.0, 4.0, 11.0))
		"weld":
			if running:
				_arm_a.rotation.y = sin(_anim_t * 1.6) * 0.5
				_arm_b.rotation.z = -0.55 + sin(_anim_t * 3.1) * 0.16
		"paint":
			if running:
				_arm_a.position.x = sin(_anim_t * 1.9) * 0.55
		"assembly":
			if running:
				_arm_a.rotation.z = -0.4 + sin(_anim_t * 2.7) * 0.3
				_arm_b.rotation.z = 0.5 + sin(_anim_t * 2.7) * 0.22
				_arm_c.rotation.z = 0.4 + sin(_anim_t * 2.7 + PI) * 0.3
				_arm_d.rotation.z = -0.5 + sin(_anim_t * 2.7 + PI) * 0.22
		"pack":
			if running:
				_scan_bar.position.y = 1.45 + sin(_anim_t * 2.6) * 0.5
			else:
				_scan_bar.position.y = lerpf(_scan_bar.position.y, 0.95, minf(1.0, delta * 4.0))
		_:
			if running and _spindle != null:
				_spindle.rotate_y(delta * 2.0)


# ------------------------------------------------------------------ build: shared furniture

func _build_common(display_name: String) -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	# Base plinth: dark plate skirt + diamond-plate working surface.
	WorldLib.add_box(_body, Vector3(2.9, 0.2, 2.3), Vector3(0.0, 0.1, 0.0), WorldLib.mat_steel_plate_dark())
	WorldLib.add_box(_body, Vector3(2.74, 0.05, 2.14), Vector3(0.0, 0.225, 0.0), WorldLib.mat_diamond())
	# Corner bolts (one MultiMesh).
	var bolt_tfs: Array = []
	for cx in [-1.28, 1.28]:
		for cz in [-1.0, 1.0]:
			bolt_tfs.append(Transform3D(Basis.from_scale(Vector3(0.09, 0.05, 0.09)), Vector3(cx, 0.24, cz)))
			bolt_tfs.append(Transform3D(Basis.from_scale(Vector3(0.05, 0.03, 0.05)), Vector3(cx * 0.82, 0.24, cz * 0.82)))
	WorldLib.add_multimesh(_body, WorldLib.unit_cyl(8), WorldLib.mat_galv(), bolt_tfs, false)
	# Accent trim strip along the plinth front (hover highlight + bottleneck tint).
	_accent_mat = WorldLib.mat_emissive_unique(_accent_color, _accent_energy, 0.22)
	WorldLib.add_box(_body, Vector3(2.9, 0.06, 0.05), Vector3(0.0, 0.25, 1.17), _accent_mat, false)

	# Status beacon on a corner post (outside _body so it never ghosts).
	_beacon_root = Node3D.new()
	_beacon_root.name = "Beacon"
	add_child(_beacon_root)
	var post := WorldLib.mat_galv_dark()
	WorldLib.add_box(_beacon_root, Vector3(0.07, 2.15, 0.07), Vector3(-1.28, 1.08, -1.0), post, false)
	WorldLib.add_box(_beacon_root, Vector3(0.16, 0.05, 0.16), Vector3(-1.28, 2.12, -1.0), post, false)
	_beacon_mat = WorldLib.mat_emissive_unique(WorldLib.COL_GREY, 0.8, 0.25)
	WorldLib.add_cyl(_beacon_root, 0.1, 0.2, Vector3(-1.28, 2.25, -1.0), _beacon_mat, 14, false)
	WorldLib.add_cyl(_beacon_root, 0.115, 0.03, Vector3(-1.28, 2.38, -1.0), post, 14, false)
	_icon_label = WorldLib.make_label("", WorldLib.COL_GREY, 56, 0.012)
	_icon_label.position = Vector3(-1.28, 2.65, -1.0)
	_beacon_root.add_child(_icon_label)

	# Nameplate near the aisle.
	_name_label = WorldLib.make_label(display_name, Color(WorldLib.COL_TEXT, 0.75), 30, 0.0072)
	_name_label.position = Vector3(0.0, 0.44, 1.95)
	add_child(_name_label)

	# Unlock price tag (locked/ghost state only).
	_price_label = WorldLib.make_label("", WorldLib.COL_AMBER, 44, 0.0095)
	_price_label.position = Vector3(0.0, 2.55, 0.0)
	_price_label.visible = false
	add_child(_price_label)

	_build_wip_pile()
	_build_scrap_bin()
	_build_cabinet()


## Control cabinet with a station-tinted screen, LEDs, vents, and conduit up to the cable
## tray drop behind the cell.
func _build_cabinet() -> void:
	var cab := Node3D.new()
	cab.name = "Cabinet"
	cab.position = Vector3(-1.95, 0.0, -1.3)
	cab.rotation.y = 0.22
	_body.add_child(cab)
	var shell := WorldLib.mat_paint(WorldLib.COL_CABINET)
	var dark := WorldLib.mat_galv_dark()
	WorldLib.add_box(cab, Vector3(0.56, 0.1, 0.5), Vector3(0.0, 0.05, 0.0), dark)
	WorldLib.add_box(cab, Vector3(0.52, 1.35, 0.44), Vector3(0.0, 0.78, 0.0), shell)
	# Door seam + hinges + handle.
	WorldLib.add_box(cab, Vector3(0.015, 1.2, 0.02), Vector3(0.12, 0.78, 0.225), dark, false)
	WorldLib.add_box(cab, Vector3(0.02, 0.16, 0.03), Vector3(-0.24, 0.7, 0.225), dark, false)
	# Vent fins low on the door.
	for i in range(3):
		WorldLib.add_box(cab, Vector3(0.3, 0.022, 0.02), Vector3(-0.03, 0.3 + float(i) * 0.07, 0.227), dark, false)
	# Station-tinted screen (the little HMI glow) + two pilot LEDs.
	_screen_mat = WorldLib.mat_emissive_unique(_accent_color, 1.0, 0.28)
	WorldLib.add_box(cab, Vector3(0.3, 0.22, 0.02), Vector3(-0.02, 1.22, 0.228), _screen_mat, false)
	WorldLib.add_box(cab, Vector3(0.05, 0.05, 0.02), Vector3(0.16, 0.98, 0.228), WorldLib.mat_emissive(WorldLib.COL_GREEN, 0.9, 0.3), false)
	WorldLib.add_box(cab, Vector3(0.05, 0.05, 0.02), Vector3(0.05, 0.98, 0.228), WorldLib.mat_emissive(WorldLib.COL_AMBER, 0.7, 0.3), false)
	# Conduit from the cabinet roof to the tray drop behind the cell.
	WorldLib.add_pipe(_body, [Vector3(-1.95, 1.48, -1.3), Vector3(-1.95, 2.3, -1.45), Vector3(-0.95, 2.3, -1.62)], 0.035, dark)


## Guard rails on the back of the cell + hazard curb around the work envelope + painted
## station number on the slab.
func _build_cell_dressing() -> void:
	var dress := Node3D.new()
	dress.name = "CellDressing"
	add_child(dress)
	var safety := WorldLib.mat_safety()
	var post_tfs: Array = []
	for px in [-2.45, -1.25, 1.25, 2.45]:
		post_tfs.append(Transform3D(Basis.from_scale(Vector3(0.09, 0.95, 0.09)), Vector3(px, 0.48, -1.95)))
	post_tfs.append(Transform3D(Basis.from_scale(Vector3(0.09, 0.95, 0.09)), Vector3(-2.45, 0.48, -1.15)))
	post_tfs.append(Transform3D(Basis.from_scale(Vector3(0.09, 0.95, 0.09)), Vector3(2.45, 0.48, -1.15)))
	WorldLib.add_multimesh(dress, WorldLib.unit_box(), safety, post_tfs)
	WorldLib.add_box(dress, Vector3(5.0, 0.07, 0.07), Vector3(0.0, 0.88, -1.95), safety, false)
	WorldLib.add_box(dress, Vector3(5.0, 0.05, 0.05), Vector3(0.0, 0.5, -1.95), safety, false)
	WorldLib.add_box(dress, Vector3(0.07, 0.07, 0.85), Vector3(-2.45, 0.88, -1.55), safety, false)
	WorldLib.add_box(dress, Vector3(0.07, 0.07, 0.85), Vector3(2.45, 0.88, -1.55), safety, false)
	# Hazard curb marking the cell floor envelope (thin, sits on the slab).
	var hz := WorldLib.mat_hazard()
	WorldLib.add_box(dress, Vector3(5.2, 0.035, 0.14), Vector3(0.0, 0.018, 2.15), hz, false)
	WorldLib.add_box(dress, Vector3(0.14, 0.035, 4.3), Vector3(-2.6, 0.018, 0.0), hz, false)
	WorldLib.add_box(dress, Vector3(0.14, 0.035, 4.3), Vector3(2.6, 0.018, 0.0), hz, false)
	# Painted station number on the slab, aisle side.
	var num := WorldLib.make_sign("%02d" % (station_index + 1), Color(0.58, 0.59, 0.61), 120, 0.0085)
	num.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	num.position = Vector3(-1.95, 0.03, 1.62)
	dress.add_child(num)


func _build_wip_pile() -> void:
	_wip = MultiMeshInstance3D.new()
	_wip.name = "WipPile"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = WorldLib.unit_box()
	mm.instance_count = WIP_MAX
	mm.visible_instance_count = 0
	for i in range(WIP_MAX):
		var col := i % 2
		var row := (i / 2) % 2
		var layer := i / 4
		var jx := fmod(float(i) * 0.6180339, 1.0) * 0.07 - 0.035
		var jz := fmod(float(i) * 0.7548776, 1.0) * 0.07 - 0.035
		var jr := fmod(float(i) * 0.3819661, 1.0) * 0.5 - 0.25
		var pos := Vector3(-2.15 + float(col) * 0.36 + jx, 0.16 + float(layer) * 0.31, 0.85 + float(row) * 0.36 + jz)
		var basis := Basis(Vector3.UP, jr) * Basis.from_scale(Vector3(0.3, 0.3, 0.3))
		mm.set_instance_transform(i, Transform3D(basis, pos))
	_wip.multimesh = mm
	_wip.material_override = WorldLib.mat_part()
	add_child(_wip)


func _build_scrap_bin() -> void:
	_bin_root = Node3D.new()
	_bin_root.name = "ScrapBin"
	_bin_root.position = Vector3(1.3, 0.0, 1.55)
	_bin_root.scale = Vector3(0.85, 0.85, 0.85)
	add_child(_bin_root)
	var bin_mat := WorldLib.mat_pbr(WorldLib.SET_PLATE, Color(0.42, 0.27, 0.22), 0.9, 1.0, 0.3, 0.85)
	var rim_mat := WorldLib.mat_emissive(WorldLib.COL_RED, 0.22, 0.24)
	# Bin shell: floor + 4 thin walls + emissive rim.
	WorldLib.add_box(_bin_root, Vector3(0.86, 0.06, 0.62), Vector3(0.0, 0.05, 0.0), bin_mat)
	WorldLib.add_box(_bin_root, Vector3(0.86, 0.5, 0.05), Vector3(0.0, 0.31, 0.3), bin_mat)
	WorldLib.add_box(_bin_root, Vector3(0.86, 0.5, 0.05), Vector3(0.0, 0.31, -0.3), bin_mat)
	WorldLib.add_box(_bin_root, Vector3(0.05, 0.5, 0.62), Vector3(0.42, 0.31, 0.0), bin_mat)
	WorldLib.add_box(_bin_root, Vector3(0.05, 0.5, 0.62), Vector3(-0.42, 0.31, 0.0), bin_mat)
	WorldLib.add_box(_bin_root, Vector3(0.9, 0.045, 0.66), Vector3(0.0, 0.575, 0.0), rim_mat, false)
	# Fork pockets so it reads as a tippable skip.
	WorldLib.add_box(_bin_root, Vector3(0.2, 0.09, 0.64), Vector3(-0.22, -0.005, 0.0), WorldLib.mat_galv_dark(), false)
	WorldLib.add_box(_bin_root, Vector3(0.2, 0.09, 0.64), Vector3(0.22, -0.005, 0.0), WorldLib.mat_galv_dark(), false)
	# Fill block that rises with scrap rate.
	var fill_mat := WorldLib.mat_emissive(WorldLib.COL_RED, 0.2, 0.22)
	_scrap_fill = WorldLib.add_box(_bin_root, Vector3(0.74, 1.0, 0.5), Vector3(0.0, 0.11, 0.0), fill_mat, false)
	_scrap_fill.scale.y = 0.02


func _build_collider() -> void:
	var body := StaticBody3D.new()
	body.name = "Pick"
	body.collision_layer = WorldLib.LAYER_STATION
	body.collision_mask = 0
	body.set_meta("station_index", station_index)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.1, 3.6, 2.6)
	shape.shape = box
	shape.position = Vector3(0.0, 1.8, 0.0)
	body.add_child(shape)
	add_child(body)


# ------------------------------------------------------------------ build: silhouettes

func _build_machine() -> void:
	match station_id:
		"press":
			_build_press()
		"lathe":
			_build_lathe()
		"weld":
			_build_weld()
		"paint":
			_build_paint()
		"assembly":
			_build_assembly()
		"pack":
			_build_pack()
		_:
			_build_generic()


func _build_press() -> void:
	_top_y = 3.75
	var paint := WorldLib.mat_machine(station_id)
	var plate := WorldLib.mat_steel_plate()
	var dark := WorldLib.mat_steel_plate_dark()
	var galv := WorldLib.mat_galv()
	# Bed + bolster.
	WorldLib.add_box(_body, Vector3(1.9, 0.75, 1.55), Vector3(0.0, 0.6, 0.0), dark)
	WorldLib.add_edge_trim(_body, Vector3(1.9, 0.75, 1.55), Vector3(0.0, 0.6, 0.0), galv)
	WorldLib.add_box(_body, Vector3(1.0, 0.18, 0.9), Vector3(0.0, 1.06, 0.0), plate)
	# C-frame uprights with guide rods.
	WorldLib.add_box(_body, Vector3(0.42, 2.5, 0.62), Vector3(-0.88, 2.2, 0.0), paint)
	WorldLib.add_box(_body, Vector3(0.42, 2.5, 0.62), Vector3(0.88, 2.2, 0.0), paint)
	WorldLib.add_cyl(_body, 0.055, 2.2, Vector3(-0.55, 2.3, 0.28), galv, 10, false)
	WorldLib.add_cyl(_body, 0.055, 2.2, Vector3(0.55, 2.3, 0.28), galv, 10, false)
	WorldLib.add_cyl(_body, 0.055, 2.2, Vector3(-0.55, 2.3, -0.28), galv, 10, false)
	WorldLib.add_cyl(_body, 0.055, 2.2, Vector3(0.55, 2.3, -0.28), galv, 10, false)
	# Crown with hydraulic hat + hoses down the back.
	WorldLib.add_box(_body, Vector3(2.3, 0.68, 1.2), Vector3(0.0, 3.42, 0.0), paint)
	WorldLib.add_edge_trim(_body, Vector3(2.3, 0.68, 1.2), Vector3(0.0, 3.42, 0.0), galv)
	WorldLib.add_box(_body, Vector3(1.1, 0.34, 0.8), Vector3(0.0, 3.93, 0.0), dark)
	WorldLib.add_cyl(_body, 0.16, 0.4, Vector3(-0.35, 4.28, 0.0), galv, 12, false)
	WorldLib.add_cyl(_body, 0.16, 0.4, Vector3(0.35, 4.28, 0.0), galv, 12, false)
	WorldLib.add_pipe(_body, [Vector3(0.85, 3.6, -0.55), Vector3(1.15, 3.2, -0.85), Vector3(1.15, 1.2, -0.85), Vector3(0.9, 0.7, -0.6)], 0.045, WorldLib.mat_flat(Color("1E2126"), 0.55, 0.1))
	# Motor + belt guard on the left upright.
	WorldLib.add_box(_body, Vector3(0.5, 0.55, 0.5), Vector3(-1.3, 3.1, -0.15), dark)
	WorldLib.add_cyl(_body, 0.3, 0.14, Vector3(-1.32, 2.5, 0.1), galv, 14, false)
	# Accent + warning chevron strip on the crown.
	WorldLib.add_box(_body, Vector3(2.3, 0.07, 0.06), Vector3(0.0, 3.42, 0.63), _accent_mat, false)
	WorldLib.add_box(_body, Vector3(1.35, 0.12, 0.045), Vector3(0.0, 3.06, 0.6), WorldLib.mat_hazard(), false)
	# The ram (animated: slides on the guide rods).
	_ram = WorldLib.add_box(_body, Vector3(1.14, 0.85, 0.92), Vector3(0.0, 2.55, 0.0), plate)
	var die := WorldLib.add_box(_ram, Vector3(0.62, 0.28, 0.6), Vector3(0.0, -0.55, 0.0), dark)
	die.set_meta("base_mat", dark)


func _animate_press() -> void:
	var p := _phase
	var y := 2.55
	if p < 0.55:
		y = 2.55 - 0.14 * (p / 0.55)
	elif p < 0.68:
		var t := (p - 0.55) / 0.13
		y = lerpf(2.41, 1.62, t * t)
	elif p < 0.78:
		y = 1.62
	else:
		var t2 := (p - 0.78) / 0.22
		y = lerpf(1.62, 2.55, t2)
	_ram.position.y = y


func _build_lathe() -> void:
	_top_y = 2.5
	var paint := WorldLib.mat_machine(station_id)
	var plate := WorldLib.mat_steel_plate()
	var dark := WorldLib.mat_steel_plate_dark()
	var galv := WorldLib.mat_galv()
	# Feet + bed casting + ways.
	WorldLib.add_box(_body, Vector3(0.55, 0.55, 0.95), Vector3(-1.0, 0.5, 0.0), dark)
	WorldLib.add_box(_body, Vector3(0.55, 0.55, 0.95), Vector3(1.0, 0.5, 0.0), dark)
	WorldLib.add_box(_body, Vector3(2.8, 0.38, 1.1), Vector3(0.0, 0.96, 0.0), paint)
	WorldLib.add_edge_trim(_body, Vector3(2.8, 0.38, 1.1), Vector3(0.0, 0.96, 0.0), galv)
	WorldLib.add_box(_body, Vector3(2.6, 0.06, 0.16), Vector3(0.0, 1.18, 0.3), galv, false)
	WorldLib.add_box(_body, Vector3(2.6, 0.06, 0.16), Vector3(0.0, 1.18, -0.3), galv, false)
	# Chip tray under the bed.
	WorldLib.add_box(_body, Vector3(2.5, 0.07, 0.9), Vector3(0.0, 0.28, 0.35), dark)
	# Headstock with chuck + gearbox detail.
	WorldLib.add_box(_body, Vector3(0.9, 1.2, 1.1), Vector3(-1.0, 1.75, 0.0), paint)
	WorldLib.add_edge_trim(_body, Vector3(0.9, 1.2, 1.1), Vector3(-1.0, 1.75, 0.0), galv)
	WorldLib.add_box(_body, Vector3(0.92, 0.3, 0.5), Vector3(-1.0, 1.35, 0.35), dark)
	WorldLib.add_box(_body, Vector3(0.85, 0.07, 0.06), Vector3(-1.0, 2.38, 0.56), _accent_mat, false)
	# Splash guard behind the work.
	WorldLib.add_box(_body, Vector3(2.1, 1.15, 0.06), Vector3(0.35, 1.85, -0.52), plate)
	# Tailstock + carriage.
	WorldLib.add_box(_body, Vector3(0.45, 0.66, 0.78), Vector3(1.08, 1.47, 0.0), paint)
	WorldLib.add_cyl(_body, 0.07, 0.5, Vector3(0.78, 1.75, 0.0), galv, 10).rotation.z = PI * 0.5
	WorldLib.add_box(_body, Vector3(0.38, 0.34, 0.55), Vector3(0.28, 1.3, 0.55), dark)
	WorldLib.add_box(_body, Vector3(0.2, 0.24, 0.2), Vector3(0.28, 1.6, 0.55), galv)
	# Spindle assembly (animated: rotates about X).
	_spindle = Node3D.new()
	_spindle.name = "Spindle"
	_spindle.position = Vector3(-0.45, 1.75, 0.0)
	_body.add_child(_spindle)
	var chuck := WorldLib.add_cyl(_spindle, 0.32, 0.22, Vector3(0.12, 0.0, 0.0), plate, 16)
	chuck.rotation.z = PI * 0.5
	var work := WorldLib.add_cyl(_spindle, 0.11, 1.35, Vector3(0.85, 0.0, 0.0), WorldLib.mat_part(), 12)
	work.rotation.z = PI * 0.5
	# Jaw nubs so the spin reads at a glance.
	WorldLib.add_box(_spindle, Vector3(0.1, 0.6, 0.1), Vector3(0.12, 0.0, 0.0), WorldLib.mat_galv_dark())
	WorldLib.add_box(_spindle, Vector3(0.1, 0.1, 0.6), Vector3(0.12, 0.0, 0.0), WorldLib.mat_galv_dark())
	# Coolant line arcing over the chuck.
	WorldLib.add_pipe(_body, [Vector3(-1.35, 2.35, 0.3), Vector3(-0.85, 2.6, 0.25), Vector3(-0.45, 2.25, 0.2)], 0.03, galv)


func _build_weld() -> void:
	_top_y = 2.6
	var paint := WorldLib.mat_machine(station_id)
	var plate := WorldLib.mat_steel_plate()
	var dark := WorldLib.mat_steel_plate_dark()
	var galv := WorldLib.mat_galv()
	# Robot pedestal + slewing ring.
	WorldLib.add_cyl(_body, 0.5, 0.5, Vector3(-0.55, 0.47, -0.3), dark, 18)
	WorldLib.add_cyl(_body, 0.42, 0.1, Vector3(-0.55, 0.76, -0.3), galv, 18, false)
	# Positioner table with clamps + workpiece.
	WorldLib.add_box(_body, Vector3(1.5, 0.42, 1.15), Vector3(0.6, 0.43, 0.25), paint)
	WorldLib.add_edge_trim(_body, Vector3(1.5, 0.42, 1.15), Vector3(0.6, 0.43, 0.25), galv)
	WorldLib.add_box(_body, Vector3(0.9, 0.28, 0.7), Vector3(0.6, 0.78, 0.25), WorldLib.mat_part())
	WorldLib.add_box(_body, Vector3(0.12, 0.4, 0.12), Vector3(0.25, 0.9, 0.0), dark)
	WorldLib.add_box(_body, Vector3(0.12, 0.4, 0.12), Vector3(0.95, 0.9, 0.5), dark)
	# Wire feeder + gas bottle behind the robot.
	WorldLib.add_box(_body, Vector3(0.45, 0.4, 0.35), Vector3(-1.15, 0.45, -0.85), paint)
	WorldLib.add_cyl(_body, 0.16, 1.05, Vector3(-1.28, 0.55, -0.35), WorldLib.mat_paint(Color(0.35, 0.5, 0.4)), 12)
	WorldLib.add_cyl(_body, 0.07, 0.14, Vector3(-1.28, 1.13, -0.35), galv, 8, false)
	# Articulated arm: base yaw node -> tilted lower arm -> elbow node -> upper arm + torch.
	_arm_a = Node3D.new()
	_arm_a.name = "ArmBase"
	_arm_a.position = Vector3(-0.55, 0.82, -0.3)
	_body.add_child(_arm_a)
	WorldLib.add_box(_arm_a, Vector3(0.4, 0.34, 0.4), Vector3(0.0, 0.1, 0.0), paint)
	var lower := Node3D.new()
	lower.rotation.z = -0.62
	_arm_a.add_child(lower)
	WorldLib.add_box(lower, Vector3(0.26, 1.15, 0.26), Vector3(0.0, 0.55, 0.0), paint)
	WorldLib.add_cyl(lower, 0.17, 0.34, Vector3(0.0, 0.02, 0.0), dark, 12).rotation.x = PI * 0.5
	_arm_b = Node3D.new()
	_arm_b.name = "ArmElbow"
	_arm_b.position = Vector3(0.0, 1.12, 0.0)
	_arm_b.rotation.z = -0.55
	lower.add_child(_arm_b)
	WorldLib.add_cyl(_arm_b, 0.15, 0.3, Vector3(0.0, 0.0, 0.0), dark, 12).rotation.x = PI * 0.5
	WorldLib.add_box(_arm_b, Vector3(0.2, 0.95, 0.2), Vector3(0.0, 0.42, 0.0), paint)
	WorldLib.add_box(_arm_b, Vector3(0.14, 0.3, 0.14), Vector3(0.0, 0.9, 0.0), dark)
	WorldLib.add_cyl(_arm_b, 0.06, 0.3, Vector3(0.0, 1.05, 0.0), WorldLib.mat_emissive(Color("FFB36B"), 1.6, 0.3), 10, false)
	# Dress pack cable along the arm.
	WorldLib.add_pipe(_arm_b, [Vector3(-0.12, 0.1, 0.0), Vector3(-0.16, 0.6, 0.05), Vector3(-0.08, 0.95, 0.0)], 0.035, WorldLib.mat_flat(Color("1E2126"), 0.55, 0.1))
	_particles = _make_sparks()
	_particles.position = Vector3(0.0, 1.15, 0.0)
	_arm_b.add_child(_particles)
	# Smoked amber weld screen on the aisle side only (keeps the robot silhouette readable).
	var screen := StandardMaterial3D.new()
	screen.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	screen.albedo_color = Color(0.4, 0.19, 0.07, 0.3)
	screen.roughness = 0.35
	screen.cull_mode = BaseMaterial3D.CULL_DISABLED
	var s1 := WorldLib.add_box(_body, Vector3(1.05, 0.8, 0.035), Vector3(-0.95, 0.64, 1.08), screen, false)
	s1.set_meta("base_mat", screen)
	WorldLib.add_box(_body, Vector3(1.11, 0.05, 0.05), Vector3(-0.95, 1.06, 1.08), galv, false)
	WorldLib.add_box(_body, Vector3(0.05, 0.85, 0.05), Vector3(-1.48, 0.64, 1.08), galv, false)
	WorldLib.add_box(_body, Vector3(0.05, 0.85, 0.05), Vector3(-0.42, 0.64, 1.08), galv, false)
	WorldLib.add_box(_body, Vector3(0.07, 0.07, 0.05), Vector3(-0.55, 1.0, 0.3), _accent_mat, false)


func _build_paint() -> void:
	_top_y = 3.15
	var shell := WorldLib.mat_machine(station_id)
	var plate := WorldLib.mat_steel_plate()
	var dark := WorldLib.mat_steel_plate_dark()
	var galv := WorldLib.mat_galv()
	# Booth shell with a window band and roof plenum.
	WorldLib.add_box(_body, Vector3(2.5, 2.55, 0.16), Vector3(0.0, 1.5, -0.62), shell)
	WorldLib.add_box(_body, Vector3(0.16, 2.55, 1.4), Vector3(-1.17, 1.5, 0.0), shell)
	WorldLib.add_box(_body, Vector3(0.16, 2.55, 1.4), Vector3(1.17, 1.5, 0.0), shell)
	WorldLib.add_box(_body, Vector3(2.5, 0.16, 1.4), Vector3(0.0, 2.82, 0.0), shell)
	WorldLib.add_edge_trim(_body, Vector3(2.5, 0.16, 1.4), Vector3(0.0, 2.82, 0.0), galv)
	# Roof plenum + exhaust stack with cap.
	WorldLib.add_box(_body, Vector3(1.5, 0.4, 1.0), Vector3(0.0, 3.1, 0.0), galv)
	WorldLib.add_cyl(_body, 0.22, 0.85, Vector3(0.55, 3.7, -0.15), galv, 12)
	WorldLib.add_cyl(_body, 0.3, 0.1, Vector3(0.55, 4.16, -0.15), dark, 12, false)
	# Observation windows in the side walls (soft interior glow).
	var win := WorldLib.mat_emissive_unique(Color(0.55, 0.85, 0.8), 0.55, 0.4)
	WorldLib.add_box(_body, Vector3(0.04, 0.5, 0.75), Vector3(-1.26, 1.7, 0.0), win, false)
	WorldLib.add_box(_body, Vector3(0.04, 0.5, 0.75), Vector3(1.26, 1.7, 0.0), win, false)
	# Filter grid on the back wall interior.
	for i in range(3):
		WorldLib.add_box(_body, Vector3(0.6, 0.7, 0.03), Vector3(-0.7 + float(i) * 0.7, 1.35, -0.51), plate, false)
	# Floor grating.
	WorldLib.add_box(_body, Vector3(2.2, 0.08, 1.1), Vector3(0.0, 0.28, 0.0), WorldLib.mat_diamond())
	# Emissive edge trim on the booth mouth.
	WorldLib.add_box(_body, Vector3(0.07, 2.55, 0.07), Vector3(-1.17, 1.5, 0.68), _accent_mat, false)
	WorldLib.add_box(_body, Vector3(0.07, 2.55, 0.07), Vector3(1.17, 1.5, 0.68), _accent_mat, false)
	# Workpiece pedestal.
	WorldLib.add_cyl(_body, 0.28, 0.5, Vector3(0.0, 0.5, 0.0), dark, 14)
	WorldLib.add_box(_body, Vector3(0.6, 0.5, 0.5), Vector3(0.0, 1.0, 0.0), WorldLib.mat_part())
	# Paint feed lines up the outside of the booth.
	WorldLib.add_pipe(_body, [Vector3(1.28, 0.4, -0.5), Vector3(1.28, 2.5, -0.5), Vector3(0.7, 2.95, -0.3)], 0.04, galv)
	# Sliding nozzle bar under the roof (animated on X).
	_arm_a = Node3D.new()
	_arm_a.name = "NozzleBar"
	_arm_a.position = Vector3(0.0, 2.6, 0.0)
	_body.add_child(_arm_a)
	WorldLib.add_box(_arm_a, Vector3(0.18, 0.3, 1.0), Vector3.ZERO, dark)
	WorldLib.add_cyl(_arm_a, 0.05, 0.25, Vector3(0.0, -0.25, 0.0), WorldLib.mat_galv(), 8)
	_particles = _make_mist(_accent_color)
	_particles.position = Vector3(0.0, 2.2, 0.0)
	_body.add_child(_particles)


func _build_assembly() -> void:
	_top_y = 2.75
	var paint := WorldLib.mat_machine(station_id)
	var plate := WorldLib.mat_steel_plate()
	var dark := WorldLib.mat_steel_plate_dark()
	var galv := WorldLib.mat_galv()
	# Bench with diamond top + gantry frame over it.
	WorldLib.add_box(_body, Vector3(2.5, 0.72, 1.25), Vector3(0.0, 0.6, 0.1), paint)
	WorldLib.add_edge_trim(_body, Vector3(2.5, 0.72, 1.25), Vector3(0.0, 0.6, 0.1), galv)
	WorldLib.add_box(_body, Vector3(2.5, 0.06, 1.25), Vector3(0.0, 0.99, 0.1), WorldLib.mat_diamond())
	WorldLib.add_box(_body, Vector3(2.5, 0.06, 0.05), Vector3(0.0, 1.04, 0.74), _accent_mat, false)
	WorldLib.add_box(_body, Vector3(0.55, 0.3, 0.45), Vector3(0.0, 1.18, 0.1), WorldLib.mat_part())
	# Gantry uprights + beam + trolley.
	WorldLib.add_box(_body, Vector3(0.14, 1.75, 0.14), Vector3(-1.15, 1.85, 0.1), galv)
	WorldLib.add_box(_body, Vector3(0.14, 1.75, 0.14), Vector3(1.15, 1.85, 0.1), galv)
	WorldLib.add_box(_body, Vector3(2.45, 0.16, 0.16), Vector3(0.0, 2.68, 0.1), galv)
	WorldLib.add_box(_body, Vector3(0.3, 0.14, 0.22), Vector3(0.35, 2.53, 0.1), dark)
	WorldLib.add_pipe(_body, [Vector3(0.35, 2.5, 0.1), Vector3(0.35, 2.1, 0.35), Vector3(0.0, 1.6, 0.3)], 0.03, WorldLib.mat_flat(Color("1E2126"), 0.55, 0.1))
	# Parts rack behind the bench, with tinted small-part bins.
	WorldLib.add_box(_body, Vector3(0.1, 1.9, 0.1), Vector3(-1.05, 0.95, -0.95), galv)
	WorldLib.add_box(_body, Vector3(0.1, 1.9, 0.1), Vector3(1.05, 0.95, -0.95), galv)
	WorldLib.add_box(_body, Vector3(2.25, 0.07, 0.5), Vector3(0.0, 1.32, -0.95), plate)
	WorldLib.add_box(_body, Vector3(2.25, 0.07, 0.5), Vector3(0.0, 1.86, -0.95), plate)
	var bin_cols := [Color(0.55, 0.6, 0.7), Color(0.72, 0.55, 0.35), Color(0.5, 0.65, 0.52), Color(0.66, 0.62, 0.45)]
	var bin_tfs: Array = []
	var bin_colors: Array = []
	for i in range(4):
		bin_tfs.append(Transform3D(Basis.from_scale(Vector3(0.42, 0.26, 0.36)), Vector3(-0.78 + float(i) * 0.52, 1.5, -0.95)))
		bin_colors.append(bin_cols[i % bin_cols.size()])
	for i in range(3):
		bin_tfs.append(Transform3D(Basis.from_scale(Vector3(0.42, 0.26, 0.36)), Vector3(-0.52 + float(i) * 0.52, 2.04, -0.95)))
		bin_colors.append(bin_cols[(i + 2) % bin_cols.size()])
	WorldLib.add_multimesh(_body, WorldLib.unit_box(), WorldLib.mat_pbr(WorldLib.SET_PAINT, Color(1, 1, 1), 0.75, 1.0, 0.0, 0.8, true), bin_tfs, true, bin_colors)
	# Two small pick arms working over the bench, mirrored.
	_arm_a = _make_mini_arm(Vector3(-0.75, 1.02, 0.1), paint)
	var elbow_a: Node3D = _arm_a.get_meta("elbow")
	_arm_b = elbow_a
	_arm_c = _make_mini_arm(Vector3(0.75, 1.02, 0.1), paint)
	var elbow_c: Node3D = _arm_c.get_meta("elbow")
	_arm_d = elbow_c
	_arm_c.rotation.y = PI


func _make_mini_arm(pos: Vector3, paint: StandardMaterial3D) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	_body.add_child(root)
	WorldLib.add_cyl(root, 0.16, 0.2, Vector3(0.0, 0.1, 0.0), WorldLib.mat_steel_plate_dark(), 12)
	WorldLib.add_box(root, Vector3(0.16, 0.72, 0.16), Vector3(0.0, 0.5, 0.0), paint)
	var elbow := Node3D.new()
	elbow.position = Vector3(0.0, 0.84, 0.0)
	elbow.rotation.z = 0.5
	root.add_child(elbow)
	WorldLib.add_cyl(elbow, 0.1, 0.2, Vector3.ZERO, WorldLib.mat_steel_plate_dark(), 10).rotation.x = PI * 0.5
	WorldLib.add_box(elbow, Vector3(0.12, 0.6, 0.12), Vector3(0.0, 0.26, 0.0), paint)
	WorldLib.add_box(elbow, Vector3(0.09, 0.14, 0.16), Vector3(0.0, 0.6, 0.0), WorldLib.mat_galv())
	root.set_meta("elbow", elbow)
	return root


func _build_pack() -> void:
	_top_y = 2.7
	var paint := WorldLib.mat_machine(station_id)
	var plate := WorldLib.mat_steel_plate()
	var dark := WorldLib.mat_steel_plate_dark()
	var galv := WorldLib.mat_galv()
	# Pass-through roller bed with visible rollers.
	WorldLib.add_box(_body, Vector3(2.7, 0.42, 1.0), Vector3(0.0, 0.42, 0.0), paint)
	WorldLib.add_edge_trim(_body, Vector3(2.7, 0.42, 1.0), Vector3(0.0, 0.42, 0.0), galv)
	var roller_tfs: Array = []
	for i in range(6):
		var rx := -1.1 + float(i) * 0.44
		roller_tfs.append(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)) * Basis.from_scale(Vector3(0.09, 0.88, 0.09)), Vector3(rx, 0.68, 0.0)))
	WorldLib.add_multimesh(_body, WorldLib.unit_cyl(10), galv, roller_tfs, false)
	# Scanner arch across the bed.
	WorldLib.add_box(_body, Vector3(0.3, 2.0, 0.34), Vector3(0.0, 1.66, -0.78), paint)
	WorldLib.add_box(_body, Vector3(0.3, 2.0, 0.34), Vector3(0.0, 1.66, 0.78), paint)
	WorldLib.add_box(_body, Vector3(0.34, 0.32, 1.9), Vector3(0.0, 2.58, 0.0), paint)
	WorldLib.add_edge_trim(_body, Vector3(0.34, 0.32, 1.9), Vector3(0.0, 2.58, 0.0), galv)
	WorldLib.add_box(_body, Vector3(0.06, 0.06, 1.85), Vector3(0.0, 2.4, 0.0), _accent_mat, false)
	# Camera pods looking into the arch.
	WorldLib.add_box(_body, Vector3(0.16, 0.14, 0.2), Vector3(0.0, 2.32, -0.6), dark, false)
	WorldLib.add_box(_body, Vector3(0.16, 0.14, 0.2), Vector3(0.0, 2.32, 0.6), dark, false)
	# Sweeping scanner bar (emissive green line inside the arch).
	_scan_bar = WorldLib.add_box(_body, Vector3(0.06, 0.055, 1.45), Vector3(0.0, 0.95, 0.0), WorldLib.mat_emissive(WorldLib.COL_GREEN, 2.6, 0.25), false)
	# Label printer + monitor on the outfeed side.
	WorldLib.add_box(_body, Vector3(0.5, 0.45, 0.45), Vector3(1.1, 1.1, -0.85), paint)
	WorldLib.add_box(_body, Vector3(0.34, 0.05, 0.02), Vector3(1.1, 1.05, -0.61), WorldLib.mat_emissive(Color(0.9, 0.92, 0.95), 0.7, 0.4), false)
	WorldLib.add_box(_body, Vector3(0.05, 0.7, 0.05), Vector3(1.1, 1.65, -0.85), galv, false)
	WorldLib.add_box(_body, Vector3(0.4, 0.28, 0.05), Vector3(1.1, 2.1, -0.85), dark, false)
	WorldLib.add_box(_body, Vector3(0.34, 0.22, 0.02), Vector3(1.1, 2.1, -0.81), _accent_mat, false)
	# Finished goods on a pallet at the output side (stretch-wrapped).
	WorldLib.add_box(_body, Vector3(0.85, 0.1, 0.85), Vector3(0.95, 0.05, 0.95), WorldLib.mat_wood())
	WorldLib.add_box(_body, Vector3(0.36, 0.36, 0.36), Vector3(0.78, 0.28, 0.85), WorldLib.mat_part())
	WorldLib.add_box(_body, Vector3(0.36, 0.36, 0.36), Vector3(1.14, 0.28, 1.05), WorldLib.mat_part())
	WorldLib.add_box(_body, Vector3(0.36, 0.36, 0.36), Vector3(0.95, 0.64, 0.95), WorldLib.mat_part())
	var wrap := StandardMaterial3D.new()
	wrap.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wrap.albedo_color = Color(0.75, 0.8, 0.9, 0.16)
	wrap.roughness = 0.25
	var w := WorldLib.add_box(_body, Vector3(0.78, 0.72, 0.78), Vector3(0.95, 0.47, 0.95), wrap, false)
	w.set_meta("base_mat", wrap)


func _build_generic() -> void:
	_top_y = 2.6
	var paint := WorldLib.mat_machine(station_id)
	var galv := WorldLib.mat_galv()
	WorldLib.add_box(_body, Vector3(1.9, 1.7, 1.4), Vector3(0.0, 1.07, 0.0), paint)
	WorldLib.add_edge_trim(_body, Vector3(1.9, 1.7, 1.4), Vector3(0.0, 1.07, 0.0), galv)
	WorldLib.add_box(_body, Vector3(1.9, 0.07, 0.06), Vector3(0.0, 1.95, 0.71), _accent_mat, false)
	_spindle = Node3D.new()
	_spindle.position = Vector3(0.0, 2.15, 0.0)
	_body.add_child(_spindle)
	WorldLib.add_box(_spindle, Vector3(0.9, 0.18, 0.18), Vector3.ZERO, WorldLib.mat_steel_plate_dark())


# ------------------------------------------------------------------ particles

func _make_sparks() -> GPUParticles3D:
	if _spark_process == null:
		_spark_process = ParticleProcessMaterial.new()
		_spark_process.direction = Vector3(0.0, -0.5, 0.5)
		_spark_process.spread = 42.0
		_spark_process.initial_velocity_min = 1.6
		_spark_process.initial_velocity_max = 3.2
		_spark_process.gravity = Vector3(0.0, -9.0, 0.0)
		_spark_process.scale_min = 0.5
		_spark_process.scale_max = 1.0
		_spark_process.color = Color("FFB36B")
		_spark_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_spark_process.emission_sphere_radius = 0.05
		_spark_mesh = QuadMesh.new()
		_spark_mesh.size = Vector2(0.05, 0.05)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.emission_enabled = true
		m.emission = Color("FF8A3D")
		m.emission_energy_multiplier = 3.4
		_spark_mesh.material = m
	var p := GPUParticles3D.new()
	p.name = "Sparks"
	p.amount = 22
	p.lifetime = 0.55
	p.process_material = _spark_process
	p.draw_pass_1 = _spark_mesh
	p.emitting = false
	return p


func _make_mist(tint: Color) -> GPUParticles3D:
	if _mist_process == null:
		_mist_process = ParticleProcessMaterial.new()
		_mist_process.direction = Vector3(0.0, -1.0, 0.0)
		_mist_process.spread = 25.0
		_mist_process.initial_velocity_min = 0.35
		_mist_process.initial_velocity_max = 0.7
		_mist_process.gravity = Vector3.ZERO
		_mist_process.damping_min = 0.4
		_mist_process.damping_max = 0.7
		_mist_process.scale_min = 3.0
		_mist_process.scale_max = 6.5
		_mist_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		_mist_process.emission_box_extents = Vector3(0.7, 0.15, 0.4)
		_mist_mesh = QuadMesh.new()
		_mist_mesh.size = Vector2(0.16, 0.16)
	var p := GPUParticles3D.new()
	p.name = "Mist"
	p.amount = 14
	p.lifetime = 1.3
	p.process_material = _mist_process
	var mesh := _mist_mesh.duplicate() as QuadMesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(tint.r, tint.g, tint.b, 0.14)
	m.emission_enabled = true
	m.emission = tint
	m.emission_energy_multiplier = 0.5
	mesh.material = m
	p.draw_pass_1 = mesh
	p.emitting = false
	return p


# ------------------------------------------------------------------ state changes

func _set_unlocked(u: bool) -> void:
	_unlocked = u
	WorldLib.apply_ghost(_body, not u, _ghost_mat)
	_beacon_root.visible = u
	_wip.visible = u
	_bin_root.visible = u
	_name_label.visible = u
	_price_label.visible = not u
	var dress := get_node_or_null("CellDressing")
	if dress != null:
		dress.visible = u
	if _particles != null:
		_particles.emitting = false
	if u:
		_set_status(SimTypes.STATUS_IDLE)
		_refresh_accent()


func _set_status(status: int) -> void:
	_status = status
	var color := WorldLib.COL_GREY
	var energy := 1.5
	var icon := ""
	match status:
		SimTypes.STATUS_RUNNING:
			color = WorldLib.COL_GREEN
			energy = 2.4
		SimTypes.STATUS_STARVED:
			color = WorldLib.COL_GREY
			energy = 1.5
			icon = "Zz"
		SimTypes.STATUS_BLOCKED:
			color = WorldLib.COL_AMBER
			energy = 2.2
			icon = "■"
		_:
			color = Color("6B7076")
			energy = 0.8
	_beacon_mat.emission = color
	_beacon_mat.albedo_color = Color(color.r * 0.3, color.g * 0.3, color.b * 0.3)
	_beacon_mat.emission_energy_multiplier = energy
	_icon_label.text = icon
	_icon_label.modulate = color
	# Cabinet HMI wakes with the machine.
	if _screen_mat != null:
		_screen_mat.emission_energy_multiplier = 1.35 if status == SimTypes.STATUS_RUNNING else 0.55
	if _particles != null:
		_particles.emitting = _unlocked and status == SimTypes.STATUS_RUNNING


## Accent trim leans red-orange while this station is the bottleneck (the traveling
## marker owned by FactoryWorld carries the "!" and the pulsing glow).
func _refresh_accent() -> void:
	var c := WorldLib.COL_RED if _is_bottleneck else _accent_color
	_accent_energy = 1.35 if _is_bottleneck else 0.5
	_accent_mat.emission = c
	_accent_mat.albedo_color = Color(c.r * 0.22, c.g * 0.22, c.b * 0.22)
	_accent_mat.emission_energy_multiplier = _accent_energy * (2.0 if _hovered else 1.0)
