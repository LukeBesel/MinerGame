## Headless test runner. Usage (from repo root):
##   /home/user/godot/godot --headless --path . -s res://tests/run_tests.gd
## Discovers tests/test_*.gd, runs every test_* method on a fresh instance, exits 1 on failure.
## Filter with env BNK_TEST_FILTER=<substring of file name>.
extends SceneTree


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var total_pass := 0
	var total_fail := 0
	var total_asserts := 0
	var files: Array[String] = []
	var dir := DirAccess.open("res://tests")
	if dir == null:
		print("FATAL: cannot open res://tests")
		quit(1)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.begins_with("test_") and fname.ends_with(".gd") and fname != "test_framework.gd":
			files.append(fname)
		fname = dir.get_next()
	files.sort()
	var filter := OS.get_environment("BNK_TEST_FILTER")
	for file in files:
		if filter != "" and not file.contains(filter):
			continue
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			print("FAIL %s : could not load/compile (see errors above)" % file)
			total_fail += 1
			continue
		var probe: Variant = script.new()
		var methods: Array[String] = []
		for m: Dictionary in probe.get_method_list():
			var method_name: String = m["name"]
			if method_name.begins_with("test_"):
				methods.append(method_name)
		methods.sort()
		for method in methods:
			var case: Variant = script.new()
			case.call(method)
			total_asserts += case._assert_count
			if case._assert_count == 0:
				case._failures.append("no assertions executed (aborted by a script error?)")
			if case._failures.is_empty():
				total_pass += 1
				print("PASS %s.%s" % [file, method])
			else:
				total_fail += 1
				for f: String in case._failures:
					print("FAIL %s.%s : %s" % [file, method, f])
	var elapsed := Time.get_ticks_msec() - started
	print("=== TESTS passed=%d failed=%d asserts=%d in %dms ===" % [total_pass, total_fail, total_asserts, elapsed])
	quit(1 if total_fail > 0 else 0)
