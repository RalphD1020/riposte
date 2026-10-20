extends SceneTree

## Plays Wolf's victory stand-in on the machine's audio device and quits when
## the player finishes. The headless driver does not reach `finished`.
##
##   godot --path game --script res://tools/smoke_victory_sting.gd
##
## See also: /docs/reference/testing.md


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var stream := load(RiposteKits.VICTORY_STING_STAND_IN) as AudioStream
	var player := AudioStreamPlayer.new()
	player.stream = stream
	root.add_child(player)
	player.play()
	print("RIPOSTE_STING_SMOKE driver", AudioServer.get_driver_name(), "length", stream.get_length())
	for frame in 300:
		await process_frame
		if not player.playing:
			print("RIPOSTE_STING_SMOKE finished_frame", frame)
			quit()
			return
	print("RIPOSTE_STING_SMOKE still_playing position", player.get_playback_position())
	quit(1)
