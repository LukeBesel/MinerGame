## Main — boot orchestrator. Registers input actions, loads the newest valid save (or starts
## a new game), then instances the 3D factory world and the HUD. Also drives the headless
## smoke run used by CI (set env BNK_SMOKE=1 to boot, simulate ~4 s, print a marker and quit).
extends Node

const InputSetup = preload("res://src/core/input_setup.gd")

const WORLD_SCENE := "res://src/world/factory_world.tscn"
const HUD_SCENE := "res://src/ui/hud.tscn"


func _ready() -> void:
	InputSetup.register_actions()
	_boot_game()
	_instance_layers()
	EventBus.load_completed.emit()
	_maybe_run_smoke()


func _boot_game() -> void:
	if SaveManager.has_method("boot_load"):
		SaveManager.boot_load()
	elif Game.has_method("new_game"):
		Game.new_game()


func _instance_layers() -> void:
	if ResourceLoader.exists(WORLD_SCENE):
		add_child((load(WORLD_SCENE) as PackedScene).instantiate())
	else:
		push_warning("Main: world scene missing (%s)" % WORLD_SCENE)
	if ResourceLoader.exists(HUD_SCENE):
		add_child((load(HUD_SCENE) as PackedScene).instantiate())
	else:
		push_warning("Main: HUD scene missing (%s)" % HUD_SCENE)


func _maybe_run_smoke() -> void:
	if OS.get_environment("BNK_SMOKE") == "":
		return
	get_tree().create_timer(4.0).timeout.connect(_finish_smoke)


func _finish_smoke() -> void:
	var stats: Dictionary = {}
	if Game.has_method("get_stats_snapshot"):
		stats = Game.get_stats_snapshot()
	var money_text := "n/a"
	var money: Variant = stats.get("money")
	if money is Object and money.has_method("format"):
		money_text = money.format()
	print("BNK_SMOKE_OK pps=%s money=%s" % [str(stats.get("pps", 0.0)), money_text])
	get_tree().quit(0)
