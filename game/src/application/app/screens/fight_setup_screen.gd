class_name FightSetupScreen
extends ScreenBase

## Quick Play's match card. One screen: who fights, which palette, which
## difficulty, which stage. Start Match launches the selected stage.
##
## See also: /docs/concepts/ux.md

var _player_palette: int = 0
var _cpu_palette: int = 1
var _stage_index: int = 0
var _stages: Array[StageDefinition] = []
var _blurb: Label


func build() -> void:
	UiKit.heading(lead, AppCopy.FIGHT_SETUP)
	UiKit.caption(lead, AppCopy.PLAYER)
	UiKit.body(lead, "Wolf")
	UiKit.segmented(lead, PackedStringArray([AppCopy.PALETTE_MAIN, AppCopy.PALETTE_ALTERNATE]), _player_palette, _choose_player, AppCopy.PALETTE)
	UiKit.caption(body, AppCopy.OPPONENT)
	UiKit.body(body, "Wolf")
	UiKit.segmented(body, PackedStringArray([AppCopy.PALETTE_MAIN, AppCopy.PALETTE_ALTERNATE]), _cpu_palette, _choose_cpu, AppCopy.PALETTE)
	UiKit.caption(body, AppCopy.DIFFICULTY)
	UiKit.segmented(body, AppCopy.difficulty_labels(), app.settings.difficulty, app.set_difficulty, AppCopy.DIFFICULTY)
	_stages = StageCatalog.playable()
	var labels := PackedStringArray()
	for stage: StageDefinition in _stages:
		labels.append(stage.display_name)
	UiKit.caption(body, AppCopy.STAGE)
	UiKit.segmented(body, labels, _stage_index, _choose_stage, AppCopy.STAGE)
	_blurb = UiKit.body(body, _stages[_stage_index].blurb)
	set_primary(UiKit.button(body, AppCopy.START_MATCH, _start, &"PrimaryButton"))
	UiKit.button(body, AppCopy.BACK, back)


func back() -> void:
	app.go_to(AppScreen.Id.MAIN_MENU)


func _choose_player(index: int) -> void:
	_player_palette = index


func _choose_cpu(index: int) -> void:
	_cpu_palette = index


func _choose_stage(index: int) -> void:
	_stage_index = index
	if _blurb != null and index >= 0 and index < _stages.size():
		_blurb.text = _stages[index].blurb


func _start() -> void:
	var stage_id := ContentIds.ARENA_STANDARD
	if _stage_index >= 0 and _stage_index < _stages.size():
		stage_id = _stages[_stage_index].stage_id
	app.start_arena(PackedInt32Array([_player_palette, _cpu_palette]), stage_id)
