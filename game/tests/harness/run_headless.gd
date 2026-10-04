extends Node


func _ready() -> void:
	print("Running headless test harness...")
	# Test harness placeholder
	print("RIPOSTE_RESULT {\"kind\":\"test\",\"suites\":0,\"passed\":0,\"failed\":0}")
	get_tree().quit(0)
