extends SceneTree

## Dev capture for the stance and grip review (PRES-GRIP-001,
## PRES-LONGPOINT-001): a real fighter proxy, posed by the real stack (clip →
## CombatPoseModifier3D → TwoBoneIK3D → GripHandsModifier3D) at the plane's
## landmarks, with the skeleton, the sword's frame and both hands' axes drawn
## over it. Saved to .reports/grip/<body>/<pose>_<view>.png.
##
## Overlay colours: white bones and joints; sword frame from the pommel — blue
## the handle/blade (toward the point), red the crossguard bar (the edges lie
## along it), green the flat's normal; each hand from its palm — yellow wrist →
## palm, magenta its knuckle line (`hand_span_axes`). The pictures are what a
## person accepts; PRES-RIG's grip checks are evidence.
##
##   godot --path game --rendering-method gl_compatibility --resolution 900x900 -s res://tools/capture_grip.gd [-- --body=production|blockout --out=<dir>]

const WRAPPERS := {
	"production": "res://assets/presentation/fighters/duelist/wolf_production_wrapper.tscn",
	"blockout": "res://assets/presentation/fighters/duelist/wolf_wrapper.tscn",
}
const FRAME := 1.0 / 60.0
const SETTLE_FRAMES := 4
const AXIS_LENGTH := 0.12
const SWORD_AXIS_LENGTH := 0.3
const BONE_PAIRS := [
	["Hips", "Spine"], ["Spine", "Chest"], ["Chest", "Neck"], ["Neck", "Head"],
	["Chest", "Shoulder.R"], ["Shoulder.R", "UpperArm.R"], ["UpperArm.R", "Forearm.R"], ["Forearm.R", "Hand.R"],
	["Chest", "Shoulder.L"], ["Shoulder.L", "UpperArm.L"], ["UpperArm.L", "Forearm.L"], ["Forearm.L", "Hand.L"],
	["Hips", "UpperLeg.R"], ["UpperLeg.R", "LowerLeg.R"], ["LowerLeg.R", "Foot.R"],
	["Hips", "UpperLeg.L"], ["UpperLeg.L", "LowerLeg.L"], ["LowerLeg.L", "Foot.L"],
]
## name, degrees, phase, charge.
const POSES := [
	["right_load_charged", -135.0, CombatPhase.Id.CHARGING, 1.0],
	["right_wound", -135.0, CombatPhase.Id.NEUTRAL, 0.0],
	["right_90", -90.0, CombatPhase.Id.NEUTRAL, 0.0],
	["right_ready_45", -45.0, CombatPhase.Id.NEUTRAL, 0.0],
	["right_15", -15.0, CombatPhase.Id.NEUTRAL, 0.0],
	["long_guard", 0.0, CombatPhase.Id.NEUTRAL, 0.0],
	["left_15", 15.0, CombatPhase.Id.NEUTRAL, 0.0],
	["left_ready_45", 45.0, CombatPhase.Id.NEUTRAL, 0.0],
	["left_90", 90.0, CombatPhase.Id.NEUTRAL, 0.0],
	["left_wound", 135.0, CombatPhase.Id.NEUTRAL, 0.0],
	["left_load_charged", 135.0, CombatPhase.Id.CHARGING, 1.0],
]
## Views in the combat frame (+X the fighter's left, +Y up, +Z forward):
## camera position, look-at, fov.
const VIEWS := [
	["front", Vector3(0.0, 1.35, 2.7), Vector3(0.0, 1.15, 0.35), 45.0],
	["side", Vector3(-2.7, 1.35, 0.5), Vector3(0.0, 1.15, 0.5), 45.0],
	["three_quarter", Vector3(-1.7, 1.6, 2.1), Vector3(0.0, 1.15, 0.4), 45.0],
]
## The hands close-up: framed on the two grips, from in front, above and to
## the fighter's right, wherever the sword is.
const HANDS_OFFSET := Vector3(-0.32, 0.26, 0.42)
const HANDS_FOV := 34.0

var _out := ""
var _body := "production"
var _proxy: FighterPresentation3D
var _rig: SwordRig3D
var _skeleton: Skeleton3D
var _camera: Camera3D
var _lines: ImmediateMesh


func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--body="):
			_body = argument.trim_prefix("--body=")
		elif argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("res://../.reports/grip").path_join(_body)
	DirAccess.make_dir_recursive_absolute(_out)
	var rules := StandardDuelRules.create()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	var skin := FighterSkinKit.new()
	skin.skin_id = &"capture.grip"
	skin.scene = load(WRAPPERS[_body]) as PackedScene
	kits.combatant(0).fighter_skin = skin
	var world := Node3D.new()
	root.add_child(world)
	_stage(world)
	_proxy = FighterPresentation3D.create(0, DuelSide.Id.LIGHT_SOUTH, kits.combatant(0), rules.combatant(0).fighter.push_radius, rules.combatant(0))
	world.add_child(_proxy)
	_rig = _proxy.rig()
	_skeleton = _rig.skeleton()
	_lines = ImmediateMesh.new()
	var overlay := MeshInstance3D.new()
	overlay.mesh = _lines
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	overlay.material_override = material
	world.add_child(overlay)
	_skeleton.skeleton_updated.connect(_draw_overlay)
	_camera = Camera3D.new()
	world.add_child(_camera)
	_camera.make_current()
	_run.call_deferred()


func _run() -> void:
	for pose: Array in POSES:
		var row := PresentationFighter.new()
		row.health = 100.0
		row.weapon_angle = deg_to_rad(float(pose[1]))
		row.phase = pose[2]
		row.swing_progress = 1.0
		row.charge = float(pose[3])
		row.target_bearing = PI * 0.5
		for view: Array in VIEWS + [["hands"]]:
			for _i in SETTLE_FRAMES:
				_proxy.apply_pose(Vector3.ZERO, PI * 0.5, row.weapon_angle, row, FRAME)
				await process_frame
			var frame := (_rig.get_parent() as Node3D).global_transform
			if view[0] == "hands":
				var grips := (_rig.grip_target(0).global_position + _rig.grip_target(1).global_position) * 0.5
				_camera.fov = HANDS_FOV
				_camera.look_at_from_position(grips + frame.basis * HANDS_OFFSET, grips, Vector3.UP)
			else:
				_camera.fov = view[3]
				_camera.look_at_from_position(frame * (view[1] as Vector3), frame * (view[2] as Vector3), Vector3.UP)
			for _i in 2:
				_proxy.apply_pose(Vector3.ZERO, PI * 0.5, row.weapon_angle, row, FRAME)
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_out.path_join("%s_%s.png" % [pose[0], view[0]]))
	print("RIPOSTE_CAPTURE grip %s -> %s" % [_body, _out])
	quit()


## Rebuilt inside `skeleton_updated`, while the modifier stack's output is live.
func _draw_overlay() -> void:
	var into_world := _skeleton.global_transform
	_lines.clear_surfaces()
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for pair: Array in BONE_PAIRS:
		_line(into_world * _skeleton.get_bone_global_pose(_skeleton.find_bone(pair[0])).origin, into_world * _skeleton.get_bone_global_pose(_skeleton.find_bone(pair[1])).origin, Color.WHITE)
	var sword := (_rig.grip_target(0).get_parent() as Node3D).global_transform
	_axis(sword.origin, sword.basis.z, SWORD_AXIS_LENGTH, Color(0.2, 0.45, 1.0))
	_axis(sword.origin, sword.basis.x, SWORD_AXIS_LENGTH, Color(1.0, 0.2, 0.2))
	_axis(sword.origin, sword.basis.y, SWORD_AXIS_LENGTH, Color(0.2, 1.0, 0.3))
	for index in 2:
		var hand := into_world * _skeleton.get_bone_global_pose(_skeleton.find_bone("Hand.R" if index == 0 else "Hand.L"))
		var palm := hand.origin + hand.basis.y.normalized() * SwordRig3D.HAND_LENGTH
		_line(hand.origin, palm, Color(1.0, 0.9, 0.1))
		_axis(palm, hand.basis * _rig.hand_span_axes[index], AXIS_LENGTH, Color(1.0, 0.2, 1.0))
	_lines.surface_end()


func _axis(from: Vector3, direction: Vector3, length: float, color: Color) -> void:
	_line(from, from + direction.normalized() * length, color)


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(a)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(b)


func _stage(world: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.30, 0.28)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.52, 0.58)
	environment.ambient_light_energy = 0.6
	var holder := WorldEnvironment.new()
	holder.environment = environment
	world.add_child(holder)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.92, 0.82)
	key.light_energy = 1.2
	key.shadow_enabled = true
	world.add_child(key)
	key.look_at_from_position(Vector3(3.0, 5.0, 4.0), Vector3.ZERO, Vector3.UP)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6.0, 6.0)
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)
