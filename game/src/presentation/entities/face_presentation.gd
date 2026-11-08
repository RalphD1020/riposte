class_name FacePresentation
extends RefCounted

## The face shows one of the presets every character shares
## (FACE-EXPRESSION-001; the table is `character_modeling.expressions`, mirrored
## here and kept equal by a tooling test). A preset is per-side weights of the
## shared eye-assembly channels (FACE-EYE-001): blend shapes on the `Brow*`,
## `EyeLidUpper*`, `EyeLidLower*` and `EyeIris*` meshes, so brows, lids and the
## iris move as one system and the asymmetry is designed. Gaze (horizontal: +
## the character's left; vertical: + up) and the blink are the same kind of
## channel. A mesh without a channel ignores it. `dead` shows the X marks in
## place of the whole eye assembly and keeps neutral brows. A kill and a
## ring-out both show dead while that body is still on screen. A new proxy
## starts neutral, which is how a rematch gets the living face back.
##
## `bind` walks once, at proxy build. Later poses call `apply_bound` and skip
## the write while the terminal state is unchanged.
##
## See also: /docs/concepts/presentation.md

const NEUTRAL := &"neutral"
const CONFIDENT := &"confident"
const AGGRESSIVE := &"aggressive"
const ALERT := &"alert"
const DEAD := &"dead"
const EXPRESSIONS: Array[StringName] = [NEUTRAL, CONFIDENT, AGGRESSIVE, ALERT, DEAD]
## The presets that move channels.
const KEYED: Array[StringName] = [CONFIDENT, AGGRESSIVE, ALERT]
## Each keyed preset's channel weights per side and its default gaze.
const PRESETS := {
	CONFIDENT: {
		"L": {"brow_inner_down": 0.25, "brow_tension": 0.3, "brow_outer_up": 0.12, "lid_upper_close": 0.14, "lid_lower_tension": 0.3},
		"R": {"brow_inner_down": 0.3, "brow_tension": 0.35, "brow_outer_down": 0.15, "lid_upper_close": 0.18, "lid_lower_tension": 0.3},
		"gaze": Vector2(0.0, 0.0),
	},
	AGGRESSIVE: {
		"L": {"brow_inner_down": 0.9, "brow_tension": 0.8, "brow_outer_up": 0.15, "lid_upper_close": 0.3, "lid_upper_inner_down": 0.4, "lid_lower_tension": 0.45, "lid_lower_raise": 0.18},
		"R": {"brow_inner_down": 0.72, "brow_tension": 0.65, "brow_outer_up": 0.3, "lid_upper_close": 0.24, "lid_upper_inner_down": 0.3, "lid_lower_tension": 0.35, "lid_lower_raise": 0.12},
		"gaze": Vector2(0.0, -0.1),
	},
	ALERT: {
		"L": {"brow_outer_up": 0.3, "brow_inner_down": 0.05, "lid_upper_open": 0.65, "lid_upper_outer_up": 0.2, "lid_lower_relax": 0.25},
		"R": {"brow_outer_up": 0.4, "brow_inner_down": 0.05, "lid_upper_open": 0.75, "lid_upper_outer_up": 0.28, "lid_lower_relax": 0.3},
		"gaze": Vector2(0.0, 0.05),
	},
}
const GAZE_LEFT := "gaze_left"
const GAZE_RIGHT := "gaze_right"
const GAZE_UP := "gaze_up"
const GAZE_DOWN := "gaze_down"
const BLINK := "blink"


static func apply(root: Node, alive: bool) -> void:
	if root == null:
		return
	apply_bound(bind(root), alive)


static func bind(root: Node) -> Array[Node3D]:
	var parts: Array[Node3D] = []
	_collect(root, parts)
	return parts


static func apply_bound(parts: Array[Node3D], alive: bool) -> void:
	show_expression(parts, NEUTRAL if alive else DEAD)


## Shows `expression` (one of EXPRESSIONS) at `weight` with its default gaze.
static func show_expression(parts: Array[Node3D], expression: StringName, weight: float = 1.0) -> void:
	var preset: Dictionary = PRESETS.get(expression, {})
	pose(parts, expression, weight, preset.get("gaze", Vector2.ZERO), 0.0)


## The whole face: a preset at `weight`, a gaze and a blink weight.
static func pose(parts: Array[Node3D], expression: StringName, weight: float, gaze: Vector2, blink: float) -> void:
	if not EXPRESSIONS.has(expression):
		push_error("FacePresentation: unknown expression %s" % expression)
		expression = NEUTRAL
	var dead := expression == DEAD
	for node in parts:
		var part := String(node.name)
		if part.begins_with("DeadEye"):
			node.visible = dead
			continue
		node.visible = part.begins_with("Brow") or not dead
		if node is MeshInstance3D:
			_weigh(node as MeshInstance3D, channel_weights(expression, side_of(part), weight, gaze, 0.0 if dead else blink))


## The channel weights of one side: the preset's, scaled, plus the gaze and blink.
## A blink closes from the rest aperture: the preset's lid channels and the vertical
## gaze fade out as it rises (blend shapes add, so a lowered lid would otherwise close
## past the lower edge, a raised one stay open).
static func channel_weights(expression: StringName, side: String, weight: float, gaze: Vector2, blink: float) -> Dictionary:
	var out := {}
	var preset: Dictionary = PRESETS.get(expression, {})
	var channels: Dictionary = preset.get(side, {})
	var keep := 1.0 - clampf(blink, 0.0, 1.0)
	for channel: String in channels:
		var lid := channel.begins_with("lid_")
		out[channel] = float(channels[channel]) * weight * (keep if lid else 1.0)
	if expression != DEAD:
		out[GAZE_LEFT if gaze.x > 0.0 else GAZE_RIGHT] = absf(gaze.x)
		out[GAZE_UP if gaze.y > 0.0 else GAZE_DOWN] = absf(gaze.y) * keep
	out[BLINK] = blink
	return out


## "L" or "R" from a part's name (`Eye.L` in Blender, `Eye_L` once imported).
static func side_of(part: String) -> String:
	return "R" if part.contains(".R") or part.contains("_R") else "L"


static func _weigh(mesh: MeshInstance3D, weights: Dictionary) -> void:
	var source := mesh.mesh as ArrayMesh
	if source == null:
		return
	for index in mesh.get_blend_shape_count():
		mesh.set_blend_shape_value(index, float(weights.get(String(source.get_blend_shape_name(index)), 0.0)))


static func _collect(node: Node, parts: Array[Node3D]) -> void:
	if node is Node3D:
		var part := String(node.name)
		if part.begins_with("DeadEye") or part.begins_with("Eye") or part.begins_with("Brow"):
			parts.append(node as Node3D)
	for child in node.get_children():
		_collect(child, parts)
