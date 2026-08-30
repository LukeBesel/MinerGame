## InputSetup — registers gameplay input actions in code (rebindable later, and avoids
## hand-editing project.godot's brittle input serialization). Called once by Main at boot.
## Action names are pinned in docs/ARCHITECTURE.md §8.
extends RefCounted

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"toggle_walk": [KEY_TAB],
	"interact": [KEY_E],
	"pause_menu": [KEY_ESCAPE],
}


static func register_actions() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in ACTIONS[action]:
			if _has_key_event(action, key):
				continue
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)


static func _has_key_event(action: String, key: int) -> bool:
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == key:
			return true
	return false
