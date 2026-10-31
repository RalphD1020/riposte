extends SceneTree

## Dev capture for the production-body review (the Phase gate a person signs):
## the imported candidate on WolfRig in every review pose, from the same six
## framings each time, saved to .reports/production/<pose>_<view>.png. Clips
## are the candidate's own (Wolf's, by name); the shoulder range, wrist, hip
## and turn poses are posed directly, because in a match the arms belong to the
## runtime IK. Clavicle participation is the candidate scene's
## `ClavicleResponse`, applied the way `CombatPoseModifier3D` applies it; the
## `_no_clavicle` rows hold the girdle at rest for comparison. The real combat
## stack (clips, combat pose, clavicle, IK, sword) is
## tools/capture_production_match.gd. A green PRES-PRODUCTION is evidence;
## these pictures are what the body is accepted on.
##
##   godot --path game --rendering-method gl_compatibility --resolution 900x900 -s res://tools/capture_production.gd [-- --out=<dir>]

const CANDIDATE_GLB := "res://assets/generated/fighters/wolf_production.glb"
const WRAPPER := "res://assets/presentation/fighters/duelist/wolf_production_wrapper.tscn"
## The modeling pose's arm drop below horizontal (character_modeling.pose).
const A_POSE_DROP_DEG := 35.0
## The shipped gameplay camera (RiposteKits.camera_profile): pitch and nearest distance.
const GAMEPLAY_PITCH_DEG := 48.0
const GAMEPLAY_DISTANCE := 14.0
const GAMEPLAY_FOV_DEG := 40.0
const LOOK_AT := Vector3(0.0, 0.95, 0.0)
## Each clip at the frame that shows what it is for.
const CLIP_POSES := [
	["idle_guard", &"idle", 0.5],
	["walk", &"walk_forward", 0.5],
	["commitment_load", &"charge_support", 1.0],
	["cut", &"swing_support", 0.5],
	["overswing", &"overswing", 0.5],
	["lunge", &"dash_forward", 0.5],
	["hit_heavy", &"hurt_heavy", 0.5],
	["death", &"death", 1.0],
	["victory_flourish", &"victory_combo", 0.5],
	["victory_idle", &"victory_idle", 0.5],
]
## Direct bends from rest: bone, local axis, degrees.
const BEND_POSES := [
	["elbow_flexion", [["Forearm.L", Vector3.RIGHT, 120.0], ["Forearm.R", Vector3.RIGHT, 120.0]]],
	["wrist_grip", [["Hand.L", Vector3.RIGHT, 40.0], ["Hand.R", Vector3.RIGHT, -40.0]]],
	["hip_rotation", [["UpperLeg.L", Vector3.UP, 40.0], ["UpperLeg.R", Vector3.UP, -40.0]]],
	["knee_flexion", [["LowerLeg.L", Vector3.RIGHT, 100.0], ["LowerLeg.R", Vector3.RIGHT, 100.0]]],
	["torso_turn", [["Spine", Vector3.UP, 30.0], ["Chest", Vector3.UP, 15.0]]],
	["neck_turn", [["Neck", Vector3.UP, 45.0]]],
]
## The shoulder range: name, motion, degrees, twist, and whether a
## `_no_clavicle` comparison is also shot. 150° is diagnostic, not release.
const SHOULDER_RANGE := [
	["abduction_45", "abduct", 45.0, 0.0, false],
	["abduction_90", "abduct", 90.0, 0.0, true],
	["abduction_120", "abduct", 120.0, 0.0, false],
	["abduction_150", "abduct", 150.0, 0.0, true],
	["flexion_90", "flex", 90.0, 0.0, false],
	["flexion_150", "flex", 150.0, 0.0, true],
	["extension_40", "extend", 40.0, 0.0, false],
	["rotation_90_out", "abduct", 90.0, 45.0, false],
]

var _out := ""
var _skeleton: Skeleton3D
var _camera: Camera3D
var _clavicle: ClavicleResponse


func _init() -> void:
	_out = ProjectSettings.globalize_path("res://../.reports/production")
	var candidate_glb := CANDIDATE_GLB
	var alive := true
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--candidate="):
			candidate_glb = argument.trim_prefix("--candidate=")
		elif argument == "--dead":
			alive = false
	DirAccess.make_dir_recursive_absolute(_out)
	var wrapper := (load(WRAPPER) as PackedScene).instantiate() as SwordRig3D
	_clavicle = wrapper.clavicle_response
	wrapper.free()
	var world := Node3D.new()
	root.add_child(world)
	_stage(world)
	var candidate := (load(candidate_glb) as PackedScene).instantiate()
	world.add_child(candidate)
	## The face shows what the game shows: living eyes, or the X once dead.
	FacePresentation.apply(candidate, alive)
	_skeleton = candidate.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_camera = Camera3D.new()
	world.add_child(_camera)
	_camera.make_current()
	_run.call_deferred(candidate)


func _run(candidate: Node) -> void:
	var player := candidate.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton.reset_bone_poses()
	_a_pose()
	await _shoot("a_pose")
	_skeleton.reset_bone_poses()
	await _shoot("rest_guard")
	for row: Array in CLIP_POSES:
		var clip := player.get_animation(row[1])
		ClipPose.apply(_skeleton, clip, clip.length * float(row[2]))
		ClipPose.raise_clavicles(_skeleton, _clavicle)
		await _shoot(row[0])
	for row: Array in BEND_POSES:
		_skeleton.reset_bone_poses()
		for bend: Array in row[1]:
			ClipPose.bend(_skeleton, bend[0], bend[1], bend[2])
		await _shoot(row[0])
	for row: Array in SHOULDER_RANGE:
		_shoulder_pose(row, true)
		await _shoot(row[0])
		if row[4]:
			_shoulder_pose(row, false)
			await _shoot(row[0] + "_no_clavicle")
	print("RIPOSTE_CAPTURE production -> %s" % _out)
	quit()


## Both arms through one shoulder motion, straight, the clavicle raised by the
## response and the arm re-aimed after it (as IK would reach its target).
func _shoulder_pose(row: Array, clavicle: bool) -> void:
	_skeleton.reset_bone_poses()
	for side: String in ["L", "R"]:
		_aim_arm(side, row)
	if clavicle:
		ClipPose.raise_clavicles(_skeleton, _clavicle)
		for side: String in ["L", "R"]:
			_aim_arm(side, row)
	if not is_zero_approx(float(row[3])):
		ClipPose.twist(_skeleton, "UpperArm.L", float(row[3]))
		ClipPose.twist(_skeleton, "UpperArm.R", -float(row[3]))


func _aim_arm(side: String, row: Array) -> void:
	ClipPose.aim_arm(_skeleton, side, shoulder_direction(row[1], row[2], 1.0 if side == "L" else -1.0))


## Skeleton-space arm direction (Godot: +Y up, the fighter faces +Z, the left
## arm is +X): abduction in the frontal plane, flexion forward, extension back.
static func shoulder_direction(motion: String, degrees: float, lateral: float) -> Vector3:
	var a := deg_to_rad(degrees)
	match motion:
		"flex":
			return Vector3(0.0, -cos(a), sin(a))
		"extend":
			return Vector3(0.0, -cos(a), -sin(a))
		_:
			return Vector3(lateral * sin(a), -cos(a), 0.0)


## Aim each arm chain straight down-and-out at the modeling pose's drop.
func _a_pose() -> void:
	for side: String in ["L", "R"]:
		var lateral := 1.0 if side == "L" else -1.0
		var drop := deg_to_rad(A_POSE_DROP_DEG)
		ClipPose.aim_arm(_skeleton, side, Vector3(lateral * cos(drop), -sin(drop), 0.0))


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
	## A rim from behind, so the rear views show form rather than a silhouette.
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.6
	world.add_child(rim)
	rim.look_at_from_position(Vector3(-3.0, 4.0, -4.0), Vector3.ZERO, Vector3.UP)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6.0, 6.0)
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)


## Body framings from every side (front, both sides, rear, both obliques, top,
## the gameplay camera) and the left shoulder close from in front and behind:
## a shoulder judged from the front alone hid an arm leaving the back.
func _shoot(pose_name: String) -> void:
	var gameplay_dir := Vector3(1.0, 0.0, 0.35).normalized()
	var pitch := deg_to_rad(GAMEPLAY_PITCH_DEG)
	var views := [
		["front", Vector3(0.0, 1.0, 3.4), LOOK_AT, 50.0],
		["side", Vector3(3.4, 1.0, 0.0), LOOK_AT, 50.0],
		["side_right", Vector3(-3.4, 1.0, 0.0), LOOK_AT, 50.0],
		["rear", Vector3(0.0, 1.0, -3.4), LOOK_AT, 50.0],
		["three_quarter", Vector3(2.4, 1.7, 2.6), LOOK_AT, 50.0],
		["rear_three_quarter", Vector3(-2.4, 1.7, -2.6), LOOK_AT, 50.0],
		["top", Vector3(0.0, 4.2, 0.3), Vector3(0.0, 1.2, 0.0), 40.0],
		["rear_closeup", Vector3(-0.95, 1.8, -1.15), Vector3(-0.18, 1.4, 0.0), 45.0],
		["gameplay", LOOK_AT + gameplay_dir * GAMEPLAY_DISTANCE * cos(pitch) + Vector3.UP * GAMEPLAY_DISTANCE * sin(pitch), LOOK_AT, GAMEPLAY_FOV_DEG],
		["closeup", Vector3(0.95, 1.8, 1.15), Vector3(0.18, 1.4, 0.0), 45.0],
	]
	for view: Array in views:
		_camera.fov = view[3]
		_camera.look_at_from_position(view[1], view[2], Vector3.UP)
		for _i in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out.path_join("%s_%s.png" % [pose_name, view[0]]))
