extends Node
## Headless test runner. Run with:
##   godot --headless --path <ROOT> res://tests/test_runner.tscn [-- --kd-test=<substring>[,<substring>...]]
## Discovers tests/unit/test_*.gd and tests/integration/test_*.gd, runs every test_* method,
## prints a summary, writes tests/output/results.txt and exits with code 1 on any failure.

const TEST_DIRS := ["res://tests/unit", "res://tests/integration"]


func _ready() -> void:
	# let autoloads finish _ready before running
	await get_tree().process_frame
	var args := BootArgs.parse()
	# one piece of a file name, or several separated by commas (any of them selects the file): used to run a
	# test after the ones that may disturb it, in the same process, as the full suite does
	var filters := String(args.get("test", "")).split(",", false)
	var total_tests := 0
	var total_assertions := 0
	var failed: PackedStringArray = []
	var skipped_all: PackedStringArray = []
	var report: PackedStringArray = []
	var t_start := Time.get_ticks_msec()

	if not Defs.errors.is_empty():
		for e in Defs.errors:
			failed.append("Defs: %s" % e)

	for dir_path in TEST_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		var files := dir.get_files()
		files.sort()
		for file in files:
			if not (file.begins_with("test_") and file.ends_with(".gd")):
				continue
			if not filters.is_empty() and not Array(filters).any(func(f: String) -> bool: return file.find(f) >= 0):
				continue
			var script: GDScript = load("%s/%s" % [dir_path, file])
			if script == null or not script.can_instantiate():
				failed.append("%s: failed to load (parse error?)" % file)
				continue
			var instance: Variant = script.new()
			if not (instance is KDTestCase):
				failed.append("%s: does not extend KDTestCase" % file)
				continue
			var tc: KDTestCase = instance
			for m in script.get_script_method_list():
				var method_name: String = m["name"]
				if not method_name.begins_with("test_"):
					continue
				tc.current_test = "%s::%s" % [file.get_basename(), method_name]
				var before := tc.failures.size()
				var skipped_before := tc.skipped.size()
				var t0 := Time.get_ticks_msec()
				tc.before_each()
				var ret: Variant = tc.call(method_name)
				if ret is Object and (ret as Object).get_class() == "GDScriptFunctionState":
					await ret
				tc.after_each()
				total_tests += 1
				var status := "ok" if tc.failures.size() == before else "FAIL"
				if status == "ok" and tc.skipped.size() > skipped_before:
					status = "SKIP"
				report.append("[%s] %s (%d ms)" % [status, tc.current_test, Time.get_ticks_msec() - t0])
			total_assertions += tc.assertions
			for f in tc.failures:
				failed.append(f)
			for sk in tc.skipped:
				skipped_all.append(sk)

	var elapsed := Time.get_ticks_msec() - t_start
	for line in report:
		print(line)
	print("----")
	for f in failed:
		print("FAILURE: %s" % f)
	for sk in skipped_all:
		print("SKIPPED: %s" % sk)
	var summary := "TESTS: %d run, %d assertions, %d failures, %d skipped, %d ms" % [total_tests, total_assertions,
		failed.size(), skipped_all.size(), elapsed]
	print(summary)

	var out_dir := ProjectSettings.globalize_path("res://tests/output")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f := FileAccess.open(out_dir.path_join("results.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(report) + "\n----\n" + "\n".join(failed) + "\n" + summary + "\n")
		f.close()
	get_tree().quit(0 if failed.is_empty() and total_tests > 0 else 1)

