extends SceneTree

## Loads every project script (typecheck gate). Not a linter and not --import.
## Warnings are errors (project.godot), so any warning fails the load.
##
## See also: /docs/reference/testing.md
## See also: /docs/reference/godot.md

const SCAN_ROOTS: PackedStringArray = ["res://src", "res://content", "res://tests", "res://tools"]


func _initialize() -> void:
	var discovered := 0
	var failed := 0
	for scan_root in SCAN_ROOTS:
		var counts := _scan(scan_root)
		discovered += counts.x
		failed += counts.y
	print("SCRIPT-CHECK discovered=%d failed=%d" % [discovered, failed])
	print(
		"RIPOSTE_RESULT %s"
		% JSON.stringify({"kind": "gdscript-check", "files": discovered, "failed": failed, "passed": discovered - failed})
	)
	quit(1 if failed > 0 or discovered == 0 else 0)


func _scan(path: String) -> Vector2i:
	var discovered := 0
	var failed := 0
	var dir := DirAccess.open(path)
	if dir == null:
		print("FAIL  missing %s" % path)
		return Vector2i(0, 1)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var child := path.path_join(entry)
			if dir.current_is_dir():
				var nested := _scan(child)
				discovered += nested.x
				failed += nested.y
			elif entry.ends_with(".gd"):
				discovered += 1
				var script := load(child) as GDScript
				if script == null or not script.can_instantiate():
					print("FAIL  load %s" % child)
					failed += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return Vector2i(discovered, failed)
