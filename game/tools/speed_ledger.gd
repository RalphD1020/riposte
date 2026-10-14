extends SceneTree

## Print the Combat Speed Ledger for the shipped rules, or rewrite its page.
##
## Run: godot --headless --path game --script res://tools/speed_ledger.gd [-- --write]
##
## See also: /docs/reference/combat-speed-ledger.md


func _initialize() -> void:
	var rules := StandardDuelRules.create()
	if OS.get_cmdline_user_args().has("--write"):
		var path := ProjectSettings.globalize_path("res://").path_join(SpeedLedger.DOC)
		var page := SpeedLedger.rewritten(rules)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("speed ledger: cannot write %s" % path)
			quit(1)
			return
		file.store_string(page)
		file.close()
		print("speed ledger: wrote %s" % path)
	else:
		print(SpeedLedger.table(rules))
	quit()
