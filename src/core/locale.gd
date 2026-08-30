## L — minimal localization table. All user-facing strings go through L.t("key") or
## L.tf("key", [args]). English-only at launch; table lives at src/data/locale/en.json.
## Missing keys return the key itself so untranslated strings are visible, never crashes.
extends Node

const LOCALE_PATH := "res://src/data/locale/en.json"

var _table: Dictionary = {}

func _ready() -> void:
	reload()

func reload() -> void:
	_table = {}
	if not FileAccess.file_exists(LOCALE_PATH):
		push_warning("L: locale file missing at %s" % LOCALE_PATH)
		return
	var f := FileAccess.open(LOCALE_PATH, FileAccess.READ)
	if f == null:
		push_error("L: cannot open locale file")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_table = parsed
	else:
		push_error("L: locale file is not a JSON object")

func t(key: String) -> String:
	return str(_table.get(key, key))

func tf(key: String, args: Array) -> String:
	var s := t(key)
	for i in args.size():
		s = s.replace("{%d}" % i, str(args[i]))
	return s

func has_key(key: String) -> bool:
	return _table.has(key)
