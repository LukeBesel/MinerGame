## FactoryWorld — root of the 3D factory. Builds the whole scene in code: moody industrial
## environment, the station line + conveyors from EventBus.sim_stats, the traveling bottleneck
## marker, the green bottleneck-cleared pulse, cameras, and a little ambient factory life.
extends Node3D

const WorldLib = preload("res://src/world/world_lib.gd")
const SimTypes = preload("res://src/sim/sim_types.gd")
const StationView = preload("res://src/world/station_view.gd")
const ConveyorView = preload("res://src/world/conveyor_view.gd")
const CameraRig = preload("res://src/world/camera_rig.gd")
const FLOOR_SHADER: Shader = preload("res://src/world/floor_grid.gdshader")

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
	_build_dressing()
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
	env.background_color = WorldLib.COL_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("2E3542")
	env.ambient_light_energy = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	# SSAO/fog are Forward+ features; they degrade silently on gl_compatibility (web).
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 2.2
	env.fog_enabled = true
	env.fog_light_color = Color("161A21")
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.03
	var we := WorldEnvironment.new()
	we.name = "WorldEnv"
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Skylight"
	sun.light_color = Color("C7D6EE")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	add_child(sun)


func _build_shell() -> void:
	var min_x := WorldLib.FLOOR_MIN_X
	var max_x := WorldLib.FLOOR_MAX_X
	var min_z := WorldLib.FLOOR_MIN_Z
	var max_z := WorldLib.FLOOR_MAX_Z
	var len_x := max_x - min_x
	var len_z := max_z - min_z
	var cx := (min_x + max_x) * 0.5
	var wall_h := WorldLib.WALL_HEIGHT

	# Floor with the worn-grid shader (also carries the green pulse wave).
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = FLOOR_SHADER
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

	# Perimeter walls with emissive skylight strips.
	var wall_mat := WorldLib.mat_flat(WorldLib.COL_PANEL, 0.85, 0.05)
	var band_mat := WorldLib.mat_flat(Color("191C21"), 0.85, 0.05)
	var strip_mat := WorldLib.mat_emissive(WorldLib.COL_SKYLIGHT, 1.35, 0.4)
	WorldLib.add_box(self, Vector3(len_x, wall_h, 0.4), Vector3(cx, wall_h * 0.5, min_z - 0.2), wall_mat)
	WorldLib.add_box(self, Vector3(len_x, wall_h, 0.4), Vector3(cx, wall_h * 0.5, max_z + 0.2), wall_mat)
	WorldLib.add_box(self, Vector3(0.4, wall_h, len_z + 0.8), Vector3(min_x - 0.2, wall_h * 0.5, 0.0), wall_mat)
	WorldLib.add_box(self, Vector3(0.4, wall_h, len_z + 0.8), Vector3(max_x + 0.2, wall_h * 0.5, 0.0), wall_mat)
	WorldLib.add_box(self, Vector3(len_x, 1.3, 0.46), Vector3(cx, 0.65, min_z - 0.18), band_mat)
	WorldLib.add_box(self, Vector3(len_x, 1.3, 0.46), Vector3(cx, 0.65, max_z + 0.18), band_mat)
	for i in range(6):
		var sx := min_x + 7.0 + float(i) * 9.0
		WorldLib.add_box(self, Vector3(3.4, 1.0, 0.14), Vector3(sx, 6.6, min_z + 0.1), strip_mat, false)
		WorldLib.add_box(self, Vector3(3.4, 1.0, 0.14), Vector3(sx, 6.6, max_z - 0.1), strip_mat, false)
	for i in range(3):
		var sz := -10.0 + float(i) * 10.0
		WorldLib.add_box(self, Vector3(0.14, 1.0, 3.4), Vector3(min_x + 0.1, 6.6, sz), strip_mat, false)
		WorldLib.add_box(self, Vector3(0.14, 1.0, 3.4), Vector3(max_x - 0.1, 6.6, sz), strip_mat, false)

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


## Warm ceiling fixtures over the line (emissive bulbs at every station, real omni light
## pools at every other one to stay within gl_compatibility per-mesh light limits).
func _build_fixtures(n_stations: int) -> void:
	var old := get_node_or_null("Fixtures")
	if old != null:
		old.name = "FixturesOld"
		old.queue_free()
	var root := Node3D.new()
	root.name = "Fixtures"
	add_child(root)
	var shade_mat := WorldLib.mat_flat(WorldLib.COL_STEEL_DARK, 0.6, 0.3)
	var bulb_mat := WorldLib.mat_emissive(WorldLib.COL_WARM, 2.2, 0.5)
	var count := maxi(n_stations, 3)
	for i in range(count):
		var x := float(i) * WorldLib.STATION_SPACING
		WorldLib.add_box(root, Vector3(0.05, 1.8, 0.05), Vector3(x, 6.55, 0.0), shade_mat, false)
		WorldLib.add_cyl(root, 0.5, 0.16, Vector3(x, 5.68, 0.0), shade_mat, 14, false)
		WorldLib.add_cyl(root, 0.3, 0.08, Vector3(x, 5.6, 0.0), bulb_mat, 12, false)
		if i % 2 == 0:
			var light := OmniLight3D.new()
			light.light_color = WorldLib.COL_WARM
			light.light_energy = 3.4
			light.omni_range = 13.0
			light.omni_attenuation = 1.5
			light.position = Vector3(x, 5.2, 0.0)
			root.add_child(light)


func _build_dressing() -> void:
	var dark := WorldLib.mat_flat(WorldLib.COL_STEEL_DARK, 0.7, 0.3)
	var steel := WorldLib.mat_flat(WorldLib.COL_STEEL, 0.55, 0.35)
	# Raw-stock infeed at the head of the line.
	var infeed := Node3D.new()
	infeed.name = "Infeed"
	infeed.position = Vector3(-6.4, 0.0, 0.0)
	add_child(infeed)
	WorldLib.add_box(infeed, Vector3(0.18, 1.9, 1.2), Vector3(-0.5, 0.95, 0.0), steel)
	WorldLib.add_box(infeed, Vector3(0.18, 1.9, 1.2), Vector3(0.5, 0.95, 0.0), steel)
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
	WorldLib.add_box(dock, Vector3(3.6, 0.1, 3.8), Vector3(0.0, 0.05, 0.0), WorldLib.mat_flat(Color("1B1E23"), 0.9, 0.0))
	WorldLib.add_box(dock, Vector3(0.3, 2.6, 0.3), Vector3(0.6, 1.3, -1.6), steel)
	WorldLib.add_box(dock, Vector3(0.3, 2.6, 0.3), Vector3(0.6, 1.3, 1.6), steel)
	WorldLib.add_box(dock, Vector3(0.34, 0.3, 3.5), Vector3(0.6, 2.7, 0.0), steel)
	WorldLib.add_box(dock, Vector3(0.1, 0.08, 3.3), Vector3(0.6, 2.52, 0.0), WorldLib.mat_emissive(WorldLib.COL_GREEN, 1.6, 0.3), false)
	var chev_mat := WorldLib.mat_emissive(WorldLib.COL_GREEN, 1.1, 0.3)
	for i in range(3):
		var c := WorldLib.add_box(dock, Vector3(0.5, 0.04, 0.14), Vector3(-1.1 + float(i) * 0.55, 0.11, 0.35), chev_mat, false)
		c.rotation.y = 0.6
		var c2 := WorldLib.add_box(dock, Vector3(0.5, 0.04, 0.14), Vector3(-1.1 + float(i) * 0.55, 0.11, -0.35), chev_mat, false)
		c2.rotation.y = -0.6


func _build_ambient_life() -> void:
	# 1) Slow ceiling fans.
	for fi in range(2):
		var base := Vector3(7.0, 7.0, -6.0) if fi == 0 else Vector3(28.0, 7.0, 6.0)
		var fan := Node3D.new()
		fan.name = "Fan_%d" % fi
		fan.position = base
		add_child(fan)
		WorldLib.add_box(fan, Vector3(0.07, 0.7, 0.07), Vector3(0.0, 0.55, 0.0), WorldLib.mat_flat(WorldLib.COL_STEEL_DARK, 0.6, 0.3), false)
		var hub := Node3D.new()
		fan.add_child(hub)
		WorldLib.add_cyl(hub, 0.12, 0.1, Vector3.ZERO, WorldLib.mat_flat(WorldLib.COL_STEEL_DARK, 0.6, 0.3), 10, false)
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
	var body_mat := WorldLib.mat_flat(Color("8A6B2C"), 0.6, 0.2)
	var dark := WorldLib.mat_flat(WorldLib.COL_STEEL_DARK, 0.7, 0.3)
	WorldLib.add_box(_forklift, Vector3(1.5, 0.75, 1.0), Vector3(-0.1, 0.63, 0.0), body_mat)
	WorldLib.add_box(_forklift, Vector3(0.8, 0.85, 0.9), Vector3(-0.45, 1.43, 0.0), body_mat)
	WorldLib.add_box(_forklift, Vector3(0.09, 1.9, 0.12), Vector3(0.75, 0.95, 0.3), dark)
	WorldLib.add_box(_forklift, Vector3(0.09, 1.9, 0.12), Vector3(0.75, 0.95, -0.3), dark)
	WorldLib.add_box(_forklift, Vector3(0.7, 0.05, 0.22), Vector3(1.15, 0.14, 0.28), dark)
	WorldLib.add_box(_forklift, Vector3(0.7, 0.05, 0.22), Vector3(1.15, 0.14, -0.28), dark)
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
	WorldLib.add_cyl(fix, 0.4, 0.14, Vector3.ZERO, WorldLib.mat_flat(WorldLib.COL_STEEL_DARK, 0.6, 0.3), 12, false)
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
	WorldLib.add_cyl(_marker, 0.17, 0.07, Vector3(0.0, -0.16, 0.0), WorldLib.mat_flat(WorldLib.COL_STEEL_DARK, 0.6, 0.4), 12, false)
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
