## FactoryWorld — root of the 3D factory. Builds the whole scene in code: an art-directed
## industrial hall (AgX tonemap, cool skylight shafts vs warm high-bays, textured PBR shell,
## worked-in prop dressing), the station line + conveyors from EventBus.sim_stats, the
## traveling bottleneck marker, the green bottleneck-cleared pulse, cameras, ambient life.
extends Node3D

const WorldLib = preload("res://src/world/world_lib.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")
const StationView = preload("res://src/world/station_view.gd")
const ConveyorView = preload("res://src/world/conveyor_view.gd")
const CameraRig = preload("res://src/world/camera_rig.gd")
const FLOOR_SHADER: Shader = preload("res://src/world/floor_grid.gdshader")
const SHAFT_SHADER: Shader = preload("res://src/world/light_shaft.gdshader")

const WAVE_SPEED := 15.0
const WAVE_DURATION := 2.4
const MARKER_Y := 4.15

var _line_root: Node3D = null
var _station_views: Array = []
var _conveyors: Array = []
var _station_sig := "?"
var _rig: Node3D = null
var _floor_mat: ShaderMaterial = null
var _reduce_motion := false

# Bottleneck marker (single traveling beacon — slides between stations, never teleports).
var _marker: Node3D = null
var _marker_rotor: Node3D = null
var _marker_core_mat: StandardMaterial3D = null
var _marker_rotor_mat: StandardMaterial3D = null
var _marker_light: OmniLight3D = null
var _marker_label: Label3D = null
var _marker_tween: Tween = null
var _bottleneck_idx := -1
var _flash_t := 0.0

# Bottleneck-cleared pulse.
var _wave_t := -1.0
var _wave_origin := Vector2.ZERO
var _pulse_ring: MeshInstance3D = null
var _pulse_ring_mat: StandardMaterial3D = null
var _burst: GPUParticles3D = null

# Selection + hover.
var _selection_ring: MeshInstance3D = null
var _hover_idx := -1

# Ambient life.
var _fan_blades: Array = []
var _forklift: Node3D = null
var _forklift_dir := 1.0
var _forklift_pause := 0.0
var _flicker_light: OmniLight3D = null
var _flicker_next := 4.0
var _flicker_burst := 0.0


func _ready() -> void:
	_reduce_motion = WorldLib.reduce_motion()
	_build_environment()
	_build_lights()
	_build_shell()
	_build_shafts()
	_build_dressing()
	_build_props()
	_build_signage()
	_build_mezzanine()
	_build_decals()
	_build_ambient_life()
	_build_marker()
	_build_pulse_fx()
	_build_selection_ring()
	_line_root = Node3D.new()
	_line_root.name = "Line"
	add_child(_line_root)
	_rig = CameraRig.new()
	add_child(_rig)
	_rig.hover_changed.connect(_on_hover_changed)

	EventBus.sim_stats.connect(_on_sim_stats)
	EventBus.game_reset.connect(_rebuild_line)
	EventBus.load_completed.connect(_rebuild_line)
	EventBus.bottleneck_changed.connect(_on_bottleneck_changed)
	EventBus.bottleneck_cleared.connect(_on_bottleneck_cleared)
	EventBus.station_upgraded.connect(_on_station_upgraded)
	EventBus.station_unlocked.connect(_on_station_unlocked)
	EventBus.station_selected.connect(_on_station_selected)
	EventBus.settings_changed.connect(_on_settings_changed)
	_rebuild_line()


# ------------------------------------------------------------------ environment & shell

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("101318")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("353D4C")
	env.ambient_light_energy = 0.85
	# AgX + a saturation/contrast lift underneath: filmic-neutral highlights without the
	# washed-out mids the default settings give.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.4
	env.tonemap_white = 8.0
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_strength = 1.02
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.08
	# SSAO/fog are Forward+ features; they degrade silently on gl_compatibility (web).
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.6
	env.ssao_power = 1.7
	env.fog_enabled = true
	env.fog_light_color = Color("1C2230")
	env.fog_density = 0.0075
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.09
	env.adjustment_saturation = 1.2
	var we := WorldEnvironment.new()
	we.name = "WorldEnv"
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	# Cool daylight through the skylights — the key light, shadowed.
	var sun := DirectionalLight3D.new()
	sun.name = "Skylight"
	sun.light_color = Color("CFE0F5")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.shadow_bias = 0.06
	sun.directional_shadow_max_distance = 90.0
	sun.rotation_degrees = Vector3(-56.0, -28.0, 0.0)
	add_child(sun)
	# Two soft cool pools where the biggest shafts land (spot budget is separate from omni
	# on gl_compatibility; shadows off — cheap).
	for i in range(2):
		var spot := SpotLight3D.new()
		spot.light_color = Color("BBD1EE")
		spot.light_energy = 2.1
		spot.spot_range = 11.0
		spot.spot_angle = 34.0
		spot.spot_angle_attenuation = 1.4
		spot.position = Vector3(3.5 + float(i) * 21.0, 7.6, 2.0)
		spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		add_child(spot)


func _build_shell() -> void:
	var min_x := WorldLib.FLOOR_MIN_X
	var max_x := WorldLib.FLOOR_MAX_X
	var min_z := WorldLib.FLOOR_MIN_Z
	var max_z := WorldLib.FLOOR_MAX_Z
	var len_x := max_x - min_x
	var len_z := max_z - min_z
	var cx := (min_x + max_x) * 0.5
	var wall_h := WorldLib.WALL_HEIGHT

	# Floor with the worn-concrete shader (also carries the green pulse wave).
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = FLOOR_SHADER
	_floor_mat.set_shader_parameter("albedo_tex", WorldLib.set_tex(WorldLib.SET_CONCRETE, "Color"))
	_floor_mat.set_shader_parameter("normal_tex", WorldLib.set_tex(WorldLib.SET_CONCRETE, "NormalGL"))
	_floor_mat.set_shader_parameter("rough_tex", WorldLib.set_tex(WorldLib.SET_CONCRETE, "Roughness"))
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	floor_mesh.mesh = WorldLib.unit_box()
	floor_mesh.scale = Vector3(len_x, 0.5, len_z)
	floor_mesh.position = Vector3(cx, -0.25, 0.0)
	floor_mesh.material_override = _floor_mat
	add_child(floor_mesh)
	# Floor collider so the Gemba Walk body has ground.
	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorBody"
	floor_body.collision_layer = WorldLib.LAYER_FLOOR
	floor_body.collision_mask = 0
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(len_x, 1.0, len_z)
	fshape.shape = fbox
	fshape.position = Vector3(cx, -0.5, 0.0)
	floor_body.add_child(fshape)
	add_child(floor_body)

	# Perimeter: corrugated-steel walls over a scuffed concrete dado, steel columns.
	var wall_mat := WorldLib.mat_wall()
	var dado_mat := WorldLib.mat_wall_dado()
	WorldLib.add_box(self, Vector3(len_x, wall_h, 0.4), Vector3(cx, wall_h * 0.5, min_z - 0.2), wall_mat)
	WorldLib.add_box(self, Vector3(len_x, wall_h, 0.4), Vector3(cx, wall_h * 0.5, max_z + 0.2), wall_mat)
	WorldLib.add_box(self, Vector3(0.4, wall_h, len_z + 0.8), Vector3(min_x - 0.2, wall_h * 0.5, 0.0), wall_mat)
	WorldLib.add_box(self, Vector3(0.4, wall_h, len_z + 0.8), Vector3(max_x + 0.2, wall_h * 0.5, 0.0), wall_mat)
	WorldLib.add_box(self, Vector3(len_x, 1.35, 0.46), Vector3(cx, 0.67, min_z - 0.18), dado_mat)
	WorldLib.add_box(self, Vector3(len_x, 1.35, 0.46), Vector3(cx, 0.67, max_z + 0.18), dado_mat)
	WorldLib.add_box(self, Vector3(0.46, 1.35, len_z + 0.8), Vector3(min_x + 0.18, 0.67, 0.0), dado_mat)
	WorldLib.add_box(self, Vector3(0.46, 1.35, len_z + 0.8), Vector3(max_x - 0.18, 0.67, 0.0), dado_mat)

	# Structural wall columns (one MultiMesh) give the long walls rhythm.
	var col_tfs: Array = []
	var colx := min_x + 3.0
	while colx < max_x - 1.0:
		col_tfs.append(Transform3D(Basis.from_scale(Vector3(0.34, wall_h, 0.3)), Vector3(colx, wall_h * 0.5, min_z + 0.22)))
		col_tfs.append(Transform3D(Basis.from_scale(Vector3(0.34, wall_h, 0.3)), Vector3(colx, wall_h * 0.5, max_z - 0.22)))
		colx += 8.0
	WorldLib.add_multimesh(self, WorldLib.unit_box(), WorldLib.mat_steel_plate_dark(), col_tfs)

	# High windows: cool glazed bands on both long walls (dimmer than before — daylight now
	# comes from the roof).
	var glass_mat := WorldLib.mat_emissive(WorldLib.COL_SKYLIGHT, 0.5, 0.42)
	var frame_tfs: Array = []
	var glass_tfs: Array = []
	for i in range(6):
		var sx := min_x + 7.0 + float(i) * 9.0
		glass_tfs.append(Transform3D(Basis.from_scale(Vector3(3.4, 1.0, 0.1)), Vector3(sx, 6.5, min_z + 0.12)))
		glass_tfs.append(Transform3D(Basis.from_scale(Vector3(3.4, 1.0, 0.1)), Vector3(sx, 6.5, max_z - 0.12)))
		frame_tfs.append(Transform3D(Basis.from_scale(Vector3(3.6, 0.1, 0.16)), Vector3(sx, 7.05, min_z + 0.12)))
		frame_tfs.append(Transform3D(Basis.from_scale(Vector3(3.6, 0.1, 0.16)), Vector3(sx, 5.95, min_z + 0.12)))
		frame_tfs.append(Transform3D(Basis.from_scale(Vector3(3.6, 0.1, 0.16)), Vector3(sx, 7.05, max_z - 0.12)))
		frame_tfs.append(Transform3D(Basis.from_scale(Vector3(3.6, 0.1, 0.16)), Vector3(sx, 5.95, max_z - 0.12)))
	WorldLib.add_multimesh(self, WorldLib.unit_box(), glass_mat, glass_tfs, false)
	WorldLib.add_multimesh(self, WorldLib.unit_box(), WorldLib.mat_galv_dark(), frame_tfs, false)

	# Roof trusses as one MultiMesh (silhouette depth against the dark void above).
	var truss := MultiMeshInstance3D.new()
	truss.name = "Trusses"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = WorldLib.unit_box()
	var transforms: Array[Transform3D] = []
	var tx := min_x + 3.5
	while tx < max_x - 1.0:
		transforms.append(Transform3D(Basis.from_scale(Vector3(0.16, 0.16, len_z - 1.0)), Vector3(tx, 7.25, 0.0)))
		transforms.append(Transform3D(Basis.from_scale(Vector3(0.16, 0.16, len_z - 1.0)), Vector3(tx, 8.1, 0.0)))
		for j in range(8):
			var dz := -14.0 + float(j) * 4.0
			var rot := 0.46 if j % 2 == 0 else -0.46
			var diag := Basis.from_euler(Vector3(rot, 0.0, 0.0)) * Basis.from_scale(Vector3(0.09, 0.09, 2.05))
			transforms.append(Transform3D(diag, Vector3(tx, 7.67, dz + 2.0)))
		tx += 7.0
	transforms.append(Transform3D(Basis.from_scale(Vector3(len_x, 0.13, 0.13)), Vector3(cx, 8.05, -8.0)))
	transforms.append(Transform3D(Basis.from_scale(Vector3(len_x, 0.13, 0.13)), Vector3(cx, 8.05, 8.0)))
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	truss.multimesh = mm
	truss.material_override = WorldLib.mat_flat(WorldLib.COL_TRUSS, 0.8, 0.2)
	truss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	truss.layers = 1 << (WorldLib.RENDER_LAYER_CEILING - 1)
	add_child(truss)

	# Skylight panels in the roof plane (ceiling layer, culled from the top-down view):
	# bright cool glass in galvanized frames — the visible source of the light shafts.
	var sky_glass: Array = []
	var sky_frame: Array = []
	for p in _skylight_positions():
		sky_glass.append(Transform3D(Basis.from_scale(Vector3(2.6, 0.08, 2.0)), Vector3(p.x, 8.28, p.z)))
		sky_frame.append(Transform3D(Basis.from_scale(Vector3(2.9, 0.14, 0.18)), Vector3(p.x, 8.26, p.z - 1.05)))
		sky_frame.append(Transform3D(Basis.from_scale(Vector3(2.9, 0.14, 0.18)), Vector3(p.x, 8.26, p.z + 1.05)))
		sky_frame.append(Transform3D(Basis.from_scale(Vector3(0.18, 0.14, 2.2)), Vector3(p.x - 1.4, 8.26, p.z)))
		sky_frame.append(Transform3D(Basis.from_scale(Vector3(0.18, 0.14, 2.2)), Vector3(p.x + 1.4, 8.26, p.z)))
	var glass := WorldLib.add_multimesh(self, WorldLib.unit_box(), WorldLib.mat_emissive(Color("D7E6FA"), 2.6, 0.55), sky_glass, false)
	glass.layers = 1 << (WorldLib.RENDER_LAYER_CEILING - 1)
	var frames := WorldLib.add_multimesh(self, WorldLib.unit_box(), WorldLib.mat_galv_dark(), sky_frame, false)
	frames.layers = 1 << (WorldLib.RENDER_LAYER_CEILING - 1)


func _skylight_positions() -> Array:
	# Two over the line (between stations), two over the back aisle, two over the south
	# staging floor — no shaft sits in front of the wall signage or on a station itself.
	return [
		Vector3(3.5, 0.0, 2.6), Vector3(24.5, 0.0, 2.6), Vector3(13.5, 0.0, -9.5),
		Vector3(34.5, 0.0, -9.5), Vector3(9.0, 0.0, 8.5), Vector3(29.0, 0.0, 8.5),
	]


## Additive cone "god rays" under the skylights (layer 1 — visible from the management view
## even while the roof itself is culled; reads as atmosphere from every angle).
func _build_shafts() -> void:
	var root := Node3D.new()
	root.name = "LightShafts"
	add_child(root)
	var mat := ShaderMaterial.new()
	mat.shader = SHAFT_SHADER
	var positions: Array = _skylight_positions()
	# Cones only under the line/back-aisle skylights — the south pair would haze the
	# management camera's foreground from above.
	for i in range(mini(4, positions.size())):
		var p: Vector3 = positions[i]
		var mi := MeshInstance3D.new()
		mi.mesh = WorldLib.cone_mesh(0.155, 0.28, 18)
		mi.scale = Vector3(7.4, 7.9, 7.4)
		mi.position = Vector3(p.x + 0.9, 4.15, p.z + 0.55)
		mi.rotation_degrees = Vector3(4.0, 0.0, -7.0)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## Warm high-bay fixtures over the line + the cable tray feeding the machines (rebuilt with
## the station count; omni lights only at every 2nd station to stay well inside the
## gl_compatibility per-mesh light limit).
func _build_fixtures(n_stations: int) -> void:
	var old := get_node_or_null("Fixtures")
	if old != null:
		old.name = "FixturesOld"
		old.queue_free()
	var root := Node3D.new()
	root.name = "Fixtures"
	add_child(root)
	var shade_mat := WorldLib.mat_galv_dark()
	var bulb_mat := WorldLib.mat_emissive(WorldLib.COL_WARM, 2.6, 0.5)
	var count := maxi(n_stations, 3)
	for i in range(count):
		var x := float(i) * WorldLib.STATION_SPACING
		# Conduit stem + bell shade + bright disc.
		WorldLib.add_cyl(root, 0.03, 1.7, Vector3(x, 6.6, 0.0), shade_mat, 8, false)
		var bell := MeshInstance3D.new()
		bell.mesh = WorldLib.cone_mesh(0.12, 0.5, 18)
		bell.scale = Vector3(1.0, 0.42, 1.0)
		bell.position = Vector3(x, 5.72, 0.0)
		bell.material_override = shade_mat
		bell.set_meta("base_mat", shade_mat)
		root.add_child(bell)
		WorldLib.add_cyl(root, 0.36, 0.05, Vector3(x, 5.53, 0.0), bulb_mat, 16, false)
		if i % 2 == 0:
			var light := OmniLight3D.new()
			light.light_color = WorldLib.COL_WARM
			light.light_energy = 3.6
			light.omni_range = 12.5
			light.omni_attenuation = 1.5
			light.position = Vector3(x, 5.1, 0.0)
			root.add_child(light)
	# Cable tray behind the line with drop conduits into each cell.
	var tray_len := float(count - 1) * WorldLib.STATION_SPACING + 4.0
	var tray_cx := float(count - 1) * WorldLib.STATION_SPACING * 0.5
	WorldLib.add_box(root, Vector3(tray_len, 0.07, 0.42), Vector3(tray_cx, 4.72, -1.7), shade_mat, false)
	WorldLib.add_box(root, Vector3(tray_len, 0.09, 0.045), Vector3(tray_cx, 4.8, -1.9), shade_mat, false)
	WorldLib.add_box(root, Vector3(tray_len, 0.09, 0.045), Vector3(tray_cx, 4.8, -1.5), shade_mat, false)
	var hanger_tfs: Array = []
	var drop_tfs: Array = []
	for i in range(count):
		var x := float(i) * WorldLib.STATION_SPACING
		hanger_tfs.append(Transform3D(Basis.from_scale(Vector3(0.05, 2.6, 0.05)), Vector3(x + 2.6, 6.1, -1.7)))
		drop_tfs.append(Transform3D(Basis.from_scale(Vector3(0.055, 2.5, 0.055)), Vector3(x - 0.9, 3.5, -1.68)))
	WorldLib.add_multimesh(root, WorldLib.unit_box(), shade_mat, hanger_tfs, false)
	WorldLib.add_multimesh(root, WorldLib.unit_cyl(8), WorldLib.mat_flat(Color("22242A"), 0.7, 0.1), drop_tfs, false)


func _build_dressing() -> void:
	var galv := WorldLib.mat_galv()
	var dark := WorldLib.mat_galv_dark()
	# Raw-stock infeed at the head of the line.
	var infeed := Node3D.new()
	infeed.name = "Infeed"
	infeed.position = Vector3(-6.4, 0.0, 0.0)
	add_child(infeed)
	WorldLib.add_box(infeed, Vector3(0.18, 1.9, 1.2), Vector3(-0.5, 0.95, 0.0), galv)
	WorldLib.add_box(infeed, Vector3(0.18, 1.9, 1.2), Vector3(0.5, 0.95, 0.0), galv)
	var chute := WorldLib.add_box(infeed, Vector3(1.4, 0.14, 1.1), Vector3(0.15, 1.55, 0.0), dark)
	chute.rotation.z = -0.5
	for i in range(3):
		var billet := WorldLib.add_cyl(infeed, 0.14, 1.15, Vector3(-0.15 + float(i) * 0.3, 0.14, 0.0), WorldLib.mat_part(), 10)
		billet.rotation.z = PI * 0.5
	# Shipping dock at the tail (green chevrons pointing out).
	var dock := Node3D.new()
	dock.name = "Dock"
	dock.position = Vector3(41.5, 0.0, 0.0)
	add_child(dock)
	WorldLib.add_box(dock, Vector3(3.6, 0.1, 3.8), Vector3(0.0, 0.05, 0.0), WorldLib.mat_diamond())
	WorldLib.add_box(dock, Vector3(0.3, 2.6, 0.3), Vector3(0.6, 1.3, -1.6), galv)
	WorldLib.add_box(dock, Vector3(0.3, 2.6, 0.3), Vector3(0.6, 1.3, 1.6), galv)
	WorldLib.add_box(dock, Vector3(0.34, 0.3, 3.5), Vector3(0.6, 2.7, 0.0), galv)
	WorldLib.add_box(dock, Vector3(0.1, 0.08, 3.3), Vector3(0.6, 2.52, 0.0), WorldLib.mat_emissive(WorldLib.COL_GREEN, 1.6, 0.3), false)
	var chev_mat := WorldLib.mat_emissive(WorldLib.COL_GREEN, 1.1, 0.3)
	for i in range(3):
		var c := WorldLib.add_box(dock, Vector3(0.5, 0.04, 0.14), Vector3(-1.1 + float(i) * 0.55, 0.11, 0.35), chev_mat, false)
		c.rotation.y = 0.6
		var c2 := WorldLib.add_box(dock, Vector3(0.5, 0.04, 0.14), Vector3(-1.1 + float(i) * 0.55, 0.11, -0.35), chev_mat, false)
		c2.rotation.y = -0.6


# ------------------------------------------------------------------ worked-in prop dressing

## A pallet's 8 boards, appended into a shared transform list (one MultiMesh for every
## board in the hall = one draw call).
func _pallet_into(tfs: Array, pos: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	for i in range(5):
		var off := b * Vector3(-0.44 + float(i) * 0.22, 0.12, 0.0)
		tfs.append(Transform3D(b * Basis.from_scale(Vector3(0.16, 0.045, 1.05)), pos + off))
	for i in range(3):
		var off2 := b * Vector3(0.0, 0.05, -0.44 + float(i) * 0.44)
		tfs.append(Transform3D(b * Basis.from_scale(Vector3(1.05, 0.09, 0.12)), pos + off2))


func _build_props() -> void:
	var root := Node3D.new()
	root.name = "Props"
	add_child(root)

	# --- Pallets (stacks near infeed, loaded singles near the dock) ---
	var pallet_tfs: Array = []
	for s in range(5):
		_pallet_into(pallet_tfs, Vector3(-10.6, 0.02 + float(s) * 0.17, -4.4), 0.06)
	for s in range(3):
		_pallet_into(pallet_tfs, Vector3(-9.2, 0.02 + float(s) * 0.17, -6.1), -0.12)
	_pallet_into(pallet_tfs, Vector3(-10.0, 0.02, 5.2), 0.35)
	_pallet_into(pallet_tfs, Vector3(43.6, 0.02, 4.6), -0.18)
	_pallet_into(pallet_tfs, Vector3(45.2, 0.02, -3.4), 0.52)
	_pallet_into(pallet_tfs, Vector3(24.0, 0.02, 10.8), 1.2)
	# Staging area on the south aisle (fills the management-camera foreground).
	_pallet_into(pallet_tfs, Vector3(6.4, 0.02, 9.6), 0.18)
	_pallet_into(pallet_tfs, Vector3(7.9, 0.02, 10.3), -0.28)
	_pallet_into(pallet_tfs, Vector3(14.2, 0.02, 11.0), 0.75)
	for s in range(3):
		_pallet_into(pallet_tfs, Vector3(33.5, 0.02 + float(s) * 0.17, 10.2), 0.1 * float(s))
	WorldLib.add_multimesh(root, WorldLib.unit_box(), WorldLib.mat_wood(), pallet_tfs)

	# --- Strapped crate piles (instance colors vary the cardboard/steel tones) ---
	var crate_tfs: Array = []
	var crate_cols: Array = []
	var strap_tfs: Array = []
	var crate_data := [
		[Vector3(-10.0, 0.5, 5.2), 0.35, Vector3(0.9, 0.62, 0.9), Color(0.62, 0.5, 0.36)],
		[Vector3(43.6, 0.45, 4.6), -0.18, Vector3(0.85, 0.55, 0.85), Color(0.66, 0.55, 0.4)],
		[Vector3(43.6, 0.95, 4.72), 0.1, Vector3(0.7, 0.45, 0.7), Color(0.58, 0.47, 0.34)],
		[Vector3(45.2, 0.42, -3.4), 0.52, Vector3(0.8, 0.5, 0.8), Color(0.52, 0.52, 0.54)],
		[Vector3(24.0, 0.42, 10.8), 1.2, Vector3(0.8, 0.5, 0.8), Color(0.6, 0.5, 0.38)],
		[Vector3(24.9, 0.38, 11.4), 0.9, Vector3(0.62, 0.42, 0.62), Color(0.55, 0.55, 0.5)],
		[Vector3(37.2, 0.4, -11.6), 0.2, Vector3(0.85, 0.55, 0.85), Color(0.64, 0.52, 0.38)],
		[Vector3(38.2, 0.36, -12.4), -0.4, Vector3(0.66, 0.46, 0.66), Color(0.57, 0.5, 0.42)],
		[Vector3(6.4, 0.44, 9.6), 0.18, Vector3(0.88, 0.56, 0.88), Color(0.63, 0.51, 0.37)],
		[Vector3(7.9, 0.4, 10.3), -0.28, Vector3(0.78, 0.48, 0.78), Color(0.55, 0.54, 0.5)],
		[Vector3(6.4, 0.98, 9.7), 0.4, Vector3(0.62, 0.42, 0.62), Color(0.6, 0.48, 0.35)],
		[Vector3(14.2, 0.4, 11.0), 0.75, Vector3(0.8, 0.5, 0.8), Color(0.58, 0.5, 0.4)],
	]
	for cd in crate_data:
		var pos: Vector3 = cd[0]
		var yaw: float = cd[1]
		var size: Vector3 = cd[2]
		var b := Basis(Vector3.UP, yaw)
		crate_tfs.append(Transform3D(b * Basis.from_scale(size), pos))
		crate_cols.append(cd[3])
		strap_tfs.append(Transform3D(b * Basis.from_scale(Vector3(size.x + 0.02, size.y + 0.02, 0.06)), pos))
		strap_tfs.append(Transform3D(b * Basis.from_scale(Vector3(0.06, size.y + 0.02, size.z + 0.02)), pos))
	var crate_mat := WorldLib.mat_pbr(WorldLib.SET_PAINT, Color(1, 1, 1), 0.75, 1.0, 0.0, 0.85, true)
	var crate_mm := WorldLib.add_multimesh(root, WorldLib.unit_box(), crate_mat, crate_tfs, true, crate_cols)
	crate_mm.name = "Crates"
	WorldLib.add_multimesh(root, WorldLib.unit_box(), WorldLib.mat_flat(Color("23262C"), 0.6, 0.2), strap_tfs, false)

	# --- Steel drums (weld/paint supply corner + under the mezzanine) ---
	var drum_tfs: Array = []
	var drum_cols: Array = []
	var drum_spots := [
		Vector3(15.4, 0.44, -8.2), Vector3(16.2, 0.44, -8.9), Vector3(15.0, 0.44, -9.3),
		Vector3(16.4, 0.44, -7.6), Vector3(22.6, 0.44, -12.6), Vector3(23.5, 0.44, -12.2),
		Vector3(6.5, 0.44, -12.5), Vector3(7.3, 0.44, -13.1), Vector3(46.0, 0.44, 8.6),
		Vector3(45.3, 0.44, 9.4),
	]
	var drum_palette := [Color(0.32, 0.42, 0.58), Color(0.5, 0.32, 0.24), Color(0.36, 0.38, 0.4), Color(0.5, 0.47, 0.3)]
	for i in range(drum_spots.size()):
		drum_tfs.append(Transform3D(Basis(Vector3.UP, float(i) * 1.1) * Basis.from_scale(Vector3(0.62, 0.88, 0.62)), drum_spots[i]))
		drum_cols.append(drum_palette[i % drum_palette.size()])
	var drum_mat := WorldLib.mat_pbr(WorldLib.SET_PAINT, Color(1, 1, 1), 0.8, 1.0, 0.25, 0.7, true)
	WorldLib.add_multimesh(root, WorldLib.unit_cyl(14), drum_mat, drum_tfs, true, drum_cols)
	var rim_tfs: Array = []
	for i in range(drum_spots.size()):
		rim_tfs.append(Transform3D(Basis.from_scale(Vector3(0.3, 0.06, 0.3)), drum_spots[i] + Vector3(0.0, 0.44, 0.0)))
	WorldLib.add_multimesh(root, WorldLib.unit_torus(), WorldLib.mat_galv_dark(), rim_tfs, false)

	# --- Cantilever stock shelving by the far wall, loaded with bar stock ---
	var shelf_tfs: Array = []
	var shelf_x := 36.5
	for c in range(3):
		var x := shelf_x + float(c) * 1.7
		shelf_tfs.append(Transform3D(Basis.from_scale(Vector3(0.16, 3.1, 0.16)), Vector3(x, 1.55, -14.6)))
		shelf_tfs.append(Transform3D(Basis.from_scale(Vector3(0.16, 0.1, 1.15)), Vector3(x, 0.06, -14.1)))
		for lvl in range(3):
			shelf_tfs.append(Transform3D(Basis.from_scale(Vector3(0.12, 0.09, 0.95)), Vector3(x, 1.0 + float(lvl) * 0.85, -14.05)))
	WorldLib.add_multimesh(root, WorldLib.unit_box(), WorldLib.mat_paint(Color(0.64, 0.4, 0.2)), shelf_tfs)
	var stock_tfs: Array = []
	for lvl in range(3):
		for s in range(2):
			var rot := Basis.from_euler(Vector3(0.0, 0.0, PI * 0.5))
			stock_tfs.append(Transform3D(Basis(rot) * Basis.from_scale(Vector3(0.11 + float(s) * 0.05, 4.1, 0.11 + float(s) * 0.05)), Vector3(shelf_x + 1.7, 1.12 + float(lvl) * 0.85, -13.95 + float(s) * 0.3)))
	WorldLib.add_multimesh(root, WorldLib.unit_cyl(10), WorldLib.mat_part(), stock_tfs)

	# --- Fire extinguisher points on the wall columns (columns sit at x = 5/21/37) ---
	var ext_tfs: Array = []
	var sign_tfs: Array = []
	for x in [5.0, 21.0, 37.0]:
		ext_tfs.append(Transform3D(Basis.from_scale(Vector3(0.17, 0.46, 0.17)), Vector3(x, 0.62, -15.54)))
		sign_tfs.append(Transform3D(Basis.from_scale(Vector3(0.3, 0.3, 0.04)), Vector3(x, 1.55, -15.6)))
	WorldLib.add_multimesh(root, WorldLib.unit_cyl(10), WorldLib.mat_paint(Color(0.72, 0.16, 0.12)), ext_tfs)
	WorldLib.add_multimesh(root, WorldLib.unit_box(), WorldLib.mat_emissive(Color(0.75, 0.2, 0.15), 0.55, 0.55), sign_tfs, false)


func _build_signage() -> void:
	var root := Node3D.new()
	root.name = "Signage"
	add_child(root)
	# Big line designation on the back wall (wall inner face sits at z = -16.0), lifted
	# above the mezzanine handrail.
	var line_sign := WorldLib.make_sign("LINE 1", Color(WorldLib.COL_AMBER, 0.92), 170, 0.012)
	line_sign.position = Vector3(17.0, 5.35, -15.94)
	root.add_child(line_sign)
	# Safety scoreboard near the infeed end.
	WorldLib.add_box(root, Vector3(3.3, 1.5, 0.08), Vector3(-6.5, 4.85, -15.88), WorldLib.mat_pbr(WorldLib.SET_PAINT, Color(0.16, 0.3, 0.2), 0.6, 1.0, 0.1, 0.7))
	WorldLib.add_box(root, Vector3(3.42, 1.62, 0.05), Vector3(-6.5, 4.85, -15.93), WorldLib.mat_galv_dark(), false)
	var s1 := WorldLib.make_sign("SAFETY FIRST", Color(0.92, 0.94, 0.9), 62, 0.0105)
	s1.position = Vector3(-6.5, 5.14, -15.82)
	root.add_child(s1)
	var s2 := WorldLib.make_sign("312 DAYS SINCE LAST INCIDENT", Color(0.72, 0.86, 0.68), 30, 0.0075)
	s2.position = Vector3(-6.5, 4.68, -15.82)
	root.add_child(s2)
	# Shipping stencil over the dock end wall (inner face x = 50.0).
	var ship := WorldLib.make_sign("SHIPPING →", Color(0.62, 0.78, 0.62), 96, 0.014)
	ship.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	ship.position = Vector3(49.94, 3.6, 0.0)
	root.add_child(ship)
	# Receiving stencil on the infeed end wall (inner face x = -14.0).
	var recv := WorldLib.make_sign("RECEIVING", Color(0.75, 0.72, 0.6), 84, 0.013)
	recv.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	recv.position = Vector3(-13.94, 3.6, 0.0)
	root.add_child(recv)


## Mezzanine walkway with railing along the back wall + access stairs.
func _build_mezzanine() -> void:
	var root := Node3D.new()
	root.name = "Mezzanine"
	add_child(root)
	var deck_y := 3.35
	var z_mid := -14.3
	var x0 := 2.0
	var x1 := 30.0
	var cx := (x0 + x1) * 0.5
	var len := x1 - x0
	WorldLib.add_box(root, Vector3(len, 0.12, 2.6), Vector3(cx, deck_y, z_mid), WorldLib.mat_diamond())
	WorldLib.add_box(root, Vector3(len, 0.3, 0.08), Vector3(cx, deck_y - 0.16, z_mid + 1.3), WorldLib.mat_steel_plate_dark(), false)
	# Support columns + railing posts (MultiMeshes) — structure stays steel, only the
	# handrails carry safety yellow so the mezzanine doesn't shout.
	var col_tfs: Array = []
	var post_tfs: Array = []
	var px := x0 + 0.6
	while px < x1:
		col_tfs.append(Transform3D(Basis.from_scale(Vector3(0.22, deck_y, 0.22)), Vector3(px, deck_y * 0.5 - 0.06, z_mid + 1.1)))
		px += 5.6
	var rx := x0 + 0.3
	while rx < x1 + 0.3:
		post_tfs.append(Transform3D(Basis.from_scale(Vector3(0.06, 1.05, 0.06)), Vector3(rx, deck_y + 0.58, z_mid + 1.25)))
		rx += 2.0
	WorldLib.add_multimesh(root, WorldLib.unit_box(), WorldLib.mat_steel_plate_dark(), col_tfs)
	WorldLib.add_multimesh(root, WorldLib.unit_box(), WorldLib.mat_galv_dark(), post_tfs, false)
	WorldLib.add_box(root, Vector3(len + 0.6, 0.06, 0.06), Vector3(cx, deck_y + 1.1, z_mid + 1.25), WorldLib.mat_safety(), false)
	WorldLib.add_box(root, Vector3(len + 0.6, 0.04, 0.04), Vector3(cx, deck_y + 0.62, z_mid + 1.25), WorldLib.mat_galv_dark(), false)
	# Stairs down at the east end (stringers descend with the steps).
	var step_tfs: Array = []
	for i in range(9):
		var t := float(i) / 8.0
		step_tfs.append(Transform3D(Basis.from_scale(Vector3(0.34, 0.06, 1.1)), Vector3(x1 + 0.4 + t * 3.2, deck_y - 0.12 - t * (deck_y - 0.35), z_mid)))
	WorldLib.add_multimesh(root, WorldLib.unit_box(), WorldLib.mat_diamond(), step_tfs)
	var stringer := WorldLib.add_box(root, Vector3(4.5, 0.12, 0.06), Vector3(x1 + 2.0, deck_y - 1.6, z_mid - 0.56), WorldLib.mat_steel_plate_dark(), false)
	stringer.rotation.z = -0.72
	var stringer2 := WorldLib.add_box(root, Vector3(4.5, 0.12, 0.06), Vector3(x1 + 2.0, deck_y - 1.6, z_mid + 0.56), WorldLib.mat_steel_plate_dark(), false)
	stringer2.rotation.z = -0.72
	# A bit of stored stock up top.
	WorldLib.add_box(root, Vector3(0.8, 0.55, 0.8), Vector3(x0 + 3.0, deck_y + 0.34, z_mid - 0.4), WorldLib.mat_pbr(WorldLib.SET_PAINT, Color(0.6, 0.5, 0.38), 0.75, 1.0, 0.0, 0.85))
	WorldLib.add_box(root, Vector3(0.66, 0.44, 0.66), Vector3(x0 + 6.4, deck_y + 0.28, z_mid - 0.2), WorldLib.mat_pbr(WorldLib.SET_PAINT, Color(0.5, 0.52, 0.55), 0.75, 1.0, 0.0, 0.85))


## Oil stains and tire skids: alpha decal quads floating just above the slab (heights are
## staggered so transparent quads never z-fight each other).
func _build_decals() -> void:
	var oil := WorldLib.mat_decal("oil_stain.png")
	var skid := WorldLib.mat_decal("skid_marks.png")
	if oil == null and skid == null:
		return
	var root := Node3D.new()
	root.name = "Decals"
	add_child(root)
	var oil_spots := [
		[Vector3(3.4, 0.0, 1.9), 2.6, 0.9], [Vector3(10.2, 0.0, -2.3), 3.4, 2.2],
		[Vector3(17.6, 0.0, 2.4), 2.2, 4.1], [Vector3(24.5, 0.0, -1.9), 3.0, 0.4],
		[Vector3(-8.6, 0.0, -1.2), 3.8, 5.2], [Vector3(31.4, 0.0, 2.1), 2.4, 2.9],
		[Vector3(15.6, 0.0, -7.4), 3.1, 1.4], [Vector3(30.2, 0.0, 6.3), 2.7, 3.6],
	]
	var i := 0
	if oil != null:
		for sp in oil_spots:
			var q := MeshInstance3D.new()
			q.mesh = WorldLib.quad(1.0)
			q.material_override = oil
			q.rotation_degrees = Vector3(-90.0, float(sp[2]) * 57.3, 0.0)
			q.position = Vector3(float(sp[0].x), 0.008 + float(i % 3) * 0.004, float(sp[0].z))
			q.scale = Vector3(float(sp[1]), float(sp[1]), 1.0)
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(q)
			i += 1
	var skid_spots := [
		[Vector3(-2.4, 0.0, -6.8), 4.2, 0.25], [Vector3(12.5, 0.0, -10.8), 5.0, 1.62],
		[Vector3(27.0, 0.0, 7.6), 4.4, -0.5], [Vector3(38.5, 0.0, -6.2), 4.8, 2.3],
		[Vector3(16.5, 0.0, 5.6), 4.6, 1.52],
	]
	if skid != null:
		for sp in skid_spots:
			var q := MeshInstance3D.new()
			q.mesh = WorldLib.quad(1.0)
			q.material_override = skid
			q.rotation_degrees = Vector3(-90.0, float(sp[2]) * 57.3, 0.0)
			q.position = Vector3(float(sp[0].x), 0.02 + float(i % 3) * 0.004, float(sp[0].z))
			q.scale = Vector3(float(sp[1]) * 0.5, float(sp[1]), 1.0)
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(q)
			i += 1


func _build_ambient_life() -> void:
	# 1) Slow ceiling fans.
	for fi in range(2):
		var base := Vector3(7.0, 7.0, -6.0) if fi == 0 else Vector3(28.0, 7.0, 6.0)
		var fan := Node3D.new()
		fan.name = "Fan_%d" % fi
		fan.position = base
		add_child(fan)
		WorldLib.add_box(fan, Vector3(0.07, 0.7, 0.07), Vector3(0.0, 0.55, 0.0), WorldLib.mat_galv_dark(), false)
		var hub := Node3D.new()
		fan.add_child(hub)
		WorldLib.add_cyl(hub, 0.12, 0.1, Vector3.ZERO, WorldLib.mat_galv_dark(), 10, false)
		for bi in range(3):
			var blade := WorldLib.add_box(hub, Vector3(1.5, 0.03, 0.22), Vector3.ZERO, WorldLib.mat_flat(WorldLib.COL_TRUSS, 0.7, 0.2), false)
			blade.rotation.y = float(bi) * TAU / 3.0
			blade.position = Basis(Vector3.UP, blade.rotation.y) * Vector3(0.75, -0.02, 0.0)
		WorldLib.set_render_layers(fan, 1 << (WorldLib.RENDER_LAYER_CEILING - 1))
		_fan_blades.append(hub)
	# 2) Forklift drifting the back aisle.
	_forklift = Node3D.new()
	_forklift.name = "Forklift"
	_forklift.position = Vector3(-8.0, 0.0, -11.5)
	add_child(_forklift)
	var body_mat := WorldLib.mat_paint(Color("B08A2E"))
	var dark := WorldLib.mat_galv_dark()
	WorldLib.add_box(_forklift, Vector3(1.5, 0.75, 1.0), Vector3(-0.1, 0.63, 0.0), body_mat)
	WorldLib.add_box(_forklift, Vector3(0.8, 0.85, 0.9), Vector3(-0.45, 1.43, 0.0), body_mat)
	WorldLib.add_box(_forklift, Vector3(0.09, 1.9, 0.12), Vector3(0.75, 0.95, 0.3), dark)
	WorldLib.add_box(_forklift, Vector3(0.09, 1.9, 0.12), Vector3(0.75, 0.95, -0.3), dark)
	WorldLib.add_box(_forklift, Vector3(0.7, 0.05, 0.22), Vector3(1.15, 0.14, 0.28), dark)
	WorldLib.add_box(_forklift, Vector3(0.7, 0.05, 0.22), Vector3(1.15, 0.14, -0.28), dark)
	WorldLib.add_box(_forklift, Vector3(0.75, 0.09, 0.85), Vector3(-0.32, 2.02, 0.0), dark, false)
	for wi in range(4):
		var wx := 0.42 if wi % 2 == 0 else -0.62
		var wz := 0.52 if wi < 2 else -0.52
		var wheel := WorldLib.add_cyl(_forklift, 0.26, 0.16, Vector3(wx, 0.26, wz), WorldLib.mat_flat(Color("101216"), 0.9, 0.0), 12, false)
		wheel.rotation.x = PI * 0.5
	WorldLib.add_box(_forklift, Vector3(0.06, 0.1, 0.18), Vector3(-0.86, 1.0, 0.0), WorldLib.mat_emissive(WorldLib.COL_AMBER, 1.8, 0.3), false)
	# 3) One slightly faulty fixture over the back aisle.
	var fix := Node3D.new()
	fix.name = "FlickerFixture"
	fix.position = Vector3(12.0, 6.6, -11.0)
	add_child(fix)
	WorldLib.add_cyl(fix, 0.4, 0.14, Vector3.ZERO, WorldLib.mat_galv_dark(), 12, false)
	WorldLib.add_cyl(fix, 0.24, 0.07, Vector3(0.0, -0.08, 0.0), WorldLib.mat_emissive(WorldLib.COL_WARM, 1.6, 0.5), 10, false)
	_flicker_light = OmniLight3D.new()
	_flicker_light.light_color = WorldLib.COL_WARM
	_flicker_light.light_energy = 1.1
	_flicker_light.omni_range = 8.0
	_flicker_light.position = Vector3(0.0, -0.3, 0.0)
	fix.add_child(_flicker_light)
	# Dust motes drifting through the light (near-static ambience).
	var dust := GPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 26
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.position = Vector3(17.0, 4.0, 0.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26.0, 3.0, 10.0)
	pm.gravity = Vector3(0.0, -0.015, 0.0)
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.09
	pm.direction = Vector3(1.0, 0.0, 0.0)
	pm.spread = 180.0
	dust.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.78, 0.85, 1.0, 0.06)
	quad.material = dm
	dust.draw_pass_1 = quad
	add_child(dust)


# ------------------------------------------------------------------ marker / pulse / selection

func _build_marker() -> void:
	_marker = Node3D.new()
	_marker.name = "BottleneckMarker"
	_marker.visible = false
	add_child(_marker)
	_marker_core_mat = WorldLib.mat_emissive_unique(WorldLib.COL_RED, 2.6, 0.3)
	_marker_rotor_mat = WorldLib.mat_emissive_unique(WorldLib.COL_RED, 3.0, 0.3)
	WorldLib.add_cyl(_marker, 0.17, 0.07, Vector3(0.0, -0.16, 0.0), WorldLib.mat_galv_dark(), 12, false)
	WorldLib.add_cyl(_marker, 0.1, 0.26, Vector3.ZERO, _marker_core_mat, 12, false)
	_marker_rotor = Node3D.new()
	_marker.add_child(_marker_rotor)
	WorldLib.add_box(_marker_rotor, Vector3(0.62, 0.09, 0.13), Vector3(0.17, 0.0, 0.0), _marker_rotor_mat, false)
	_marker_light = OmniLight3D.new()
	_marker_light.light_color = WorldLib.COL_RED
	_marker_light.light_energy = 2.4
	_marker_light.omni_range = 8.5
	_marker.add_child(_marker_light)
	_marker_label = WorldLib.make_label("!", WorldLib.COL_RED, 116, 0.014)
	_marker_label.position = Vector3(0.0, 0.68, 0.0)
	_marker.add_child(_marker_label)


func _build_pulse_fx() -> void:
	_pulse_ring = MeshInstance3D.new()
	_pulse_ring.name = "PulseRing"
	_pulse_ring.mesh = WorldLib.unit_torus()
	_pulse_ring_mat = WorldLib.mat_emissive_unique(WorldLib.COL_GREEN, 3.0, 0.2)
	_pulse_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pulse_ring.material_override = _pulse_ring_mat
	_pulse_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pulse_ring.visible = false
	add_child(_pulse_ring)

	_burst = GPUParticles3D.new()
	_burst.name = "ClearBurst"
	_burst.amount = 30
	_burst.lifetime = 0.8
	_burst.one_shot = true
	_burst.explosiveness = 1.0
	_burst.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 180.0
	pm.initial_velocity_min = 2.2
	pm.initial_velocity_max = 4.6
	pm.gravity = Vector3(0.0, -5.0, 0.0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color = WorldLib.COL_GREEN
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	_burst.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	dm.emission_enabled = true
	dm.emission = WorldLib.COL_GREEN
	dm.emission_energy_multiplier = 3.0
	quad.material = dm
	_burst.draw_pass_1 = quad
	add_child(_burst)


func _build_selection_ring() -> void:
	_selection_ring = MeshInstance3D.new()
	_selection_ring.name = "SelectionRing"
	_selection_ring.mesh = WorldLib.unit_torus()
	var m := WorldLib.mat_emissive_unique(WorldLib.COL_AMBER, 1.5, 0.25)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(WorldLib.COL_AMBER, 0.5)
	_selection_ring.material_override = m
	_selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_ring.scale = Vector3(2.45, 1.0, 2.45)
	_selection_ring.visible = false
	add_child(_selection_ring)


# ------------------------------------------------------------------ line rebuild + snapshot

func _snapshot() -> Dictionary:
	if Game.get("sim") == null:
		return {}
	if not Game.has_method("get_stats_snapshot"):
		return {}
	var s: Variant = Game.get_stats_snapshot()
	if s is Dictionary:
		return s
	return {}


func _rebuild_line() -> void:
	_rebuild_from(_snapshot())


func _rebuild_from(snap: Dictionary) -> void:
	var stations: Array = snap.get("stations", [])
	for child in _line_root.get_children():
		child.queue_free()
	_station_views.clear()
	_conveyors.clear()
	_bottleneck_idx = -1
	_marker.visible = false
	_selection_ring.visible = false
	_hover_idx = -1
	var n := stations.size()
	_build_fixtures(maxi(n, 6))
	if n == 0:
		# Sim/data not ready: attractive empty factory, framed on the future line area.
		if _rig != null:
			_rig.frame_line(-4.0, 18.0)
		return
	var ids := PackedStringArray()
	for i in range(n):
		var view: Dictionary = stations[i]
		ids.append(str(view.get("id", i)))
		var sv: Node3D = StationView.new()
		sv.position = Vector3(float(i) * WorldLib.STATION_SPACING, 0.0, 0.0)
		_line_root.add_child(sv)
		sv.setup(i, view)
		_station_views.append(sv)
	_station_sig = ",".join(ids)
	# Conveyor segments: infeed + between stations + outfeed.
	var half := WorldLib.MACHINE_HALF_W
	for c in range(n + 1):
		var cv: Node3D = ConveyorView.new()
		var start_x := 0.0
		var length := 4.0
		if c == 0:
			start_x = -5.4
			length = 5.4 - half
		elif c == n:
			start_x = float(n - 1) * WorldLib.STATION_SPACING + half
			length = 3.9
		else:
			start_x = float(c - 1) * WorldLib.STATION_SPACING + half
			length = WorldLib.STATION_SPACING - half * 2.0
		cv.position = Vector3(start_x, 0.0, 0.0)
		_line_root.add_child(cv)
		cv.setup(length)
		_conveyors.append(cv)
	_floor_mat.set_shader_parameter("strip_min_x", -6.5)
	_floor_mat.set_shader_parameter("strip_max_x", float(n - 1) * WorldLib.STATION_SPACING + 6.5)
	_apply_stats(snap)
	_frame_unlocked(stations)
	var bn := int(snap.get("bottleneck", -1))
	if bn >= 0:
		_move_marker(bn, false)


func _frame_unlocked(stations: Array) -> void:
	if _rig == null:
		return
	var max_i := 0
	for i in range(stations.size()):
		var view: Dictionary = stations[i]
		if bool(view.get("unlocked", false)):
			max_i = i
	_rig.frame_line(-4.5, float(max_i) * WorldLib.STATION_SPACING + 4.5)


func _on_sim_stats(stats: Dictionary) -> void:
	var stations: Array = stats.get("stations", [])
	if stations.size() != _station_views.size():
		_rebuild_from(stats)
		return
	_apply_stats(stats)


func _apply_stats(stats: Dictionary) -> void:
	var stations: Array = stats.get("stations", [])
	var n := stations.size()
	if n == 0 or _station_views.size() != n:
		return
	for i in range(n):
		var view: Dictionary = stations[i]
		var sv: Node3D = _station_views[i]
		sv.apply_view(view)
	# Conveyor flow follows the upstream station.
	for c in range(_conveyors.size()):
		var up: int = clampi(maxi(c - 1, 0), 0, n - 1)
		var up_view: Dictionary = stations[up]
		var down: int = clampi(c, 0, n - 1)
		var down_view: Dictionary = stations[down]
		var flowing := bool(up_view.get("unlocked", false)) and bool(down_view.get("unlocked", false))
		var cv: Node3D = _conveyors[c]
		cv.set_ghost(not flowing)
		cv.set_flow(maxf(0.0, float(up_view.get("throughput", 0.0))), flowing)
	# Safety net: keep the marker honest even if a transition signal was missed.
	var bn := int(stats.get("bottleneck", -1))
	if bn != _bottleneck_idx and (_marker_tween == null or not _marker_tween.is_running()):
		_move_marker(bn, true)


# ------------------------------------------------------------------ bottleneck marker

func _marker_pos_for(idx: int) -> Vector3:
	var y := MARKER_Y
	if idx >= 0 and idx < _station_views.size():
		var sv: Node3D = _station_views[idx]
		var h: Variant = sv.call("marker_height")
		y = float(h)
	return Vector3(float(idx) * WorldLib.STATION_SPACING, y, 0.0)


func _move_marker(idx: int, animated: bool) -> void:
	_bottleneck_idx = idx
	if _marker_tween != null and _marker_tween.is_valid():
		_marker_tween.kill()
		_marker_tween = null
	if idx < 0 or idx >= _station_views.size():
		_marker.visible = false
		return
	var dest := _marker_pos_for(idx)
	if not animated or _reduce_motion or not _marker.visible:
		_marker.visible = true
		_marker.position = dest
		return
	_marker_tween = create_tween()
	_marker_tween.tween_property(_marker, "position", dest, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _on_bottleneck_changed(new_index: int, _old_index: int) -> void:
	if _flash_t > 0.0:
		# Let the green celebration finish, then slide (handled in _process).
		_bottleneck_idx = new_index
		return
	_move_marker(new_index, true)


func _on_bottleneck_cleared(station: int) -> void:
	# THE signature moment: the old red beacon pops green with a burst, and a green energy
	# wave sweeps down the line from the cleared station. (Juice owns slow-mo + chime.)
	var pos := _marker_pos_for(station)
	_burst.position = pos
	_burst.restart()
	_burst.emitting = true
	_set_marker_color(WorldLib.COL_GREEN)
	_flash_t = 0.55
	if _reduce_motion:
		return
	_wave_t = 0.0
	_wave_origin = Vector2(pos.x, 0.0)
	_floor_mat.set_shader_parameter("wave_origin", _wave_origin)
	_pulse_ring.position = Vector3(pos.x, 0.12, 0.0)
	_pulse_ring.scale = Vector3(0.5, 1.0, 0.5)
	_pulse_ring.visible = true


func _set_marker_color(c: Color) -> void:
	_marker_core_mat.emission = c
	_marker_core_mat.albedo_color = Color(c.r * 0.3, c.g * 0.3, c.b * 0.3)
	_marker_rotor_mat.emission = c
	_marker_rotor_mat.albedo_color = Color(c.r * 0.3, c.g * 0.3, c.b * 0.3)
	_marker_light.light_color = c
	_marker_label.modulate = c


# ------------------------------------------------------------------ other events

func _on_station_upgraded(station: int, _upgrade_id: String, _levels: int, _new_level: int) -> void:
	if station >= 0 and station < _station_views.size():
		var sv: Node3D = _station_views[station]
		sv.call("flash_upgrade")


func _on_station_unlocked(station: int) -> void:
	if station >= 0 and station < _station_views.size():
		var sv: Node3D = _station_views[station]
		sv.call("flash_upgrade")
		_rig.frame_line(-4.5, float(station) * WorldLib.STATION_SPACING + 4.5)


func _on_station_selected(station: int) -> void:
	if station < 0 or station >= _station_views.size():
		_selection_ring.visible = false
		return
	_selection_ring.position = Vector3(float(station) * WorldLib.STATION_SPACING, 0.09, 0.0)
	_selection_ring.visible = true


func _on_hover_changed(idx: int) -> void:
	if _hover_idx >= 0 and _hover_idx < _station_views.size():
		var old: Node3D = _station_views[_hover_idx]
		old.call("set_hovered", false)
	_hover_idx = idx
	if idx >= 0 and idx < _station_views.size():
		var sv: Node3D = _station_views[idx]
		sv.call("set_hovered", true)


func _on_settings_changed(key: String, _value: Variant) -> void:
	if key == "reduce_motion" or key == "":
		_reduce_motion = WorldLib.reduce_motion()


# ------------------------------------------------------------------ per-frame ambience

func _process(delta: float) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	# Bottleneck marker: rotate + pulse (steady under reduce_motion).
	if _marker.visible:
		if not _reduce_motion:
			_marker_rotor.rotation.y += delta * 3.4
			var pulse := 2.4 + sin(t * 6.0) * 0.9
			_marker_light.light_energy = pulse
		else:
			_marker_light.light_energy = 2.4
		if _flash_t > 0.0:
			_flash_t -= delta
			if _flash_t <= 0.0:
				_set_marker_color(WorldLib.COL_RED)
				if _bottleneck_idx != _marker_hover_index():
					_move_marker(_bottleneck_idx, true)
	# Green pulse wave sweeping the floor + expanding ring.
	if _wave_t >= 0.0:
		_wave_t += delta
		var k := _wave_t / WAVE_DURATION
		if k >= 1.0:
			_wave_t = -1.0
			_floor_mat.set_shader_parameter("wave_radius", -100.0)
			_floor_mat.set_shader_parameter("wave_strength", 0.0)
			_pulse_ring.visible = false
		else:
			var radius := _wave_t * WAVE_SPEED
			var strength := 2.2 * (1.0 - k) * minf(1.0, _wave_t * 6.0)
			_floor_mat.set_shader_parameter("wave_radius", radius)
			_floor_mat.set_shader_parameter("wave_strength", strength)
			_pulse_ring.scale = Vector3(maxf(0.5, radius), 1.0, maxf(0.5, radius))
			_pulse_ring_mat.albedo_color = Color(0.06, 0.25, 0.09, maxf(0.0, 1.0 - k))
	# Selection ring idle spin.
	if _selection_ring.visible and not _reduce_motion:
		_selection_ring.rotation.y += delta * 0.7
	# Fans.
	var fan_speed := 0.3 if _reduce_motion else 0.9
	for hub in _fan_blades:
		var h := hub as Node3D
		h.rotation.y += delta * fan_speed
	# Forklift drifting the back aisle.
	if _forklift != null:
		if _reduce_motion:
			pass	# parked
		elif _forklift_pause > 0.0:
			_forklift_pause -= delta
		else:
			_forklift.position.x += _forklift_dir * 1.35 * delta
			if _forklift.position.x > 42.0:
				_forklift_dir = -1.0
				_forklift.rotation.y = PI
				_forklift_pause = 2.5
			elif _forklift.position.x < -8.0:
				_forklift_dir = 1.0
				_forklift.rotation.y = 0.0
				_forklift_pause = 2.5
	# Faulty fixture flicker (skipped under reduce_motion).
	if _flicker_light != null and not _reduce_motion:
		if _flicker_burst > 0.0:
			_flicker_burst -= delta
			_flicker_light.light_energy = 0.25 + absf(sin(t * 47.0)) * 0.9
			if _flicker_burst <= 0.0:
				_flicker_light.light_energy = 1.1
		else:
			_flicker_next -= delta
			if _flicker_next <= 0.0:
				_flicker_burst = randf_range(0.1, 0.3)
				_flicker_next = randf_range(4.0, 11.0)


func _marker_hover_index() -> int:
	# Which station the marker currently sits over (x / spacing, rounded).
	return int(round(_marker.position.x / WorldLib.STATION_SPACING))
