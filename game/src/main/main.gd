class_name RiposteMain
extends Node

## Scene entry: hands the world mount, camera rig, and UI root from
## main.tscn to the RiposteApp composition root.
##
## See also: /docs/concepts/ux.md

## Overridable before entering the tree (APP-E2E uses a scratch file).
var settings_path: String = PlayerSettings.PATH
var seed_override: int = 0
var _app: RiposteApp


func _ready() -> void:
	_app = RiposteApp.new()
	_app.name = "RiposteApp"
	_app.settings_path = settings_path
	_app.seed_override = seed_override
	_app.attach($WorldRoot/PresentationMount as Node3D, $WorldRoot/CameraRig as DuelCameraRig, $UiRoot as Control)
	add_child(_app)


func app() -> RiposteApp:
	return _app
