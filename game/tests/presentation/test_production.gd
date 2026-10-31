extends TestCase

## PRES-PRODUCTION: the production body candidate survives the real import path
## and articulates on WolfRig as one coherent body. The candidate is not the
## shipping fighter; this suite is the evidence its acceptance is judged on,
## beside a person's review of the captures.
##
## Skinning is read from the imported asset: its vertices, its four-influence
## bone/weight arrays and its skin's bind poses, blended on the skeleton's
## actual poses (linear blend skinning, the formula Godot's skinning runs). In
## the real-stack test those poses come live from the real modifier stack —
## clip → CombatPoseModifier3D (with clavicle participation) → TwoBoneIK3D —
## inside `skeleton_updated`. (`MeshInstance3D.bake_mesh_from_current_skeleton_pose`
## refuses an imported skin under the headless runner in 4.7.2, so the blend is
## done here on the imported data rather than read back from the renderer.)
##
## Contracts (each test names the one it holds):
## - PRES-PRODUCTION-IMPORT: one skinned body, WolfRig, the rig contract, the
##   1.80 m height, a four-influence stride, normalized weights, Wolf's clips.
## - PRES-PRODUCTION-CLIPS: clips deform without tearing or collapsing joints.
## - PRES-PRODUCTION-GIRDLE: the shoulder articulates as one girdle — the
##   socket rises with the arm when the clavicle participates, the surface does
##   not fold, the arm stays clear of the neck — and the gate catches the two
##   defects it exists for (a static chest shell; a girdle that sinks).
## - PRES-PRODUCTION-HIP: the pelvis opening and thigh top bend as one band
##   through the legs' combat range, and the gate catches a static pelvis shell.
## - PRES-PRODUCTION-STACK: under the real combat stack the hands stay on the
##   grip, the girdle neither folds nor meets the neck, and the clavicle lifts.
##
## Implements: /spec/invariants.md#physique-001, /spec/invariants.md#pres-clavicle-001
## See also: /docs/concepts/character-modeling.md, /docs/reference/assets.md
## Source: tools/character_modeling/character_modeling/production.py

const CANDIDATE_GLB := "res://assets/generated/fighters/wolf_production.glb"
const WRAPPER := "res://assets/presentation/fighters/duelist/wolf_production_wrapper.tscn"
const WOLF_GLB := "res://assets/generated/fighters/wolf.glb"
const RIG_CONTRACT := "res://content/characters/wolf.rig-contract.json"
## Blender is Z-up, -Y forward; the glTF exporter turns that into Godot's
## Y-up, +Z forward (docs/reference/assets.md). A contract head (bx,by,bz)
## imports at Godot (bx, bz, -by).
const CONTRACT_EPSILON := 1e-4
const BODY := "Body"
## Compatibility's skinning limit, set explicitly at export.
const INFLUENCES := 4
## Clips that stress the joints the body's loops are for.
const CLIPS: Array[StringName] = [&"idle", &"walk_forward", &"charge_support", &"swing_support", &"overswing", &"dash_forward", &"hurt_heavy", &"death"]
const FRACTIONS: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
## Joint rings: the vertices split evenly between the two bones of a joint.
const JOINTS := {"elbow.L": ["UpperArm.L", "Forearm.L"], "elbow.R": ["UpperArm.R", "Forearm.R"], "knee.L": ["UpperLeg.L", "LowerLeg.L"], "knee.R": ["UpperLeg.R", "LowerLeg.R"]}
## A joint ring may thin as it bends (linear blend skinning pinches the inside
## of a fold) but must keep this share of its rest radius.
const RING_FLOOR := 0.6
const SKIN_EPSILON := 1e-4
## The shoulder range (abduction / flexion / extension, degrees, twist).
## Release range: every pose combat reaches. 120° and 150° and extension are
## diagnostic: measured, compared with and without the clavicle, not gated.
const RELEASE_RANGE := [["abduct", 45.0, 0.0], ["abduct", 90.0, 0.0], ["flex", 90.0, 0.0], ["abduct", 90.0, 45.0]]
const DIAGNOSTIC_RANGE := [["abduct", 120.0, 0.0], ["abduct", 150.0, 0.0], ["flex", 150.0, 0.0]]
## Calibrated (not invented) against the measured body, the clavicle-at-rest
## variant and the static-chest-shell fixture on this asset:
## - girdle triangles folded over (normal reversed in their own bone frame):
##   0 at 45° and in rotation, one sliver at the socket's top-front corner at
##   90°; the release budget is that one per girdle.
const FOLD_BUDGET := 1
## - follow: how far the girdle above the socket rises, as a share of the
##   deltoid's rise, from 90° up. The body measures 0.11 (abduction 90°) to
##   0.24 (flexion 90°); with the clavicle at rest an abducted girdle sinks
##   (-0.07 at 90°); the static chest shell is exactly 0.
const FOLLOW_FLOOR := 0.05
## - an upper-arm vertex in the neck band stays this far from the neck's axis
##   (the neck's half-width is 7.4 cm; the body measures ≥ 14 cm).
const NECK_CLEAR_M := 0.12
const NECK_BAND := Vector2(1.40, 1.75)
## The legs' combat range (direction of the thigh from rest, degrees): the
## lunge's lead flexion, the trailing leg's extension, the side step.
const HIP_RANGE := [["flex", 45.0], ["extend", 30.0], ["abduct", 30.0]]
## Wolf's combat clips swing a thigh at most 30° from rest (dash_forward);
## only death reaches 70°, which stays a capture review, not this gate.
## - stretch: worst posed/rest band edge. The body measures 1.56–2.01x; the
##   bound is a tear guard, not the shell's discriminator (the shell measures
##   1.59–2.78x, overlapping).
const HIP_STRETCH_MAX := 2.5
## - follow: mean move of the blended opening as a share of the thigh top's
##   move. The body measures 0.26–0.27 on both legs in every row; the static
##   pelvis shell is exactly 0.
const HIP_FOLLOW_FLOOR := 0.15
## Hands on the grip in the real stack (block hands are ~7 cm; PRES-RIG).
const GRIP_TOLERANCE := 0.035


func _init() -> void:
	suite_name = "PRES-PRODUCTION"


class Skinned:
	var root: Node
	var skeleton: Skeleton3D
	var body: MeshInstance3D
	var vertices: PackedVector3Array
	var indices: PackedInt32Array
	var bones: PackedInt32Array
	var weights: PackedFloat32Array
	var stride: int
	## Skin bind index -> skeleton bone index, and each bind's pose.
	var bind_bone: PackedInt32Array
	var bind_pose: Array[Transform3D] = []

	func read(scene_root: Node, skel: Skeleton3D) -> void:
		root = scene_root
		skeleton = skel
		body = scene_root.find_child("Body", true, false) as MeshInstance3D
		var arrays := body.mesh.surface_get_arrays(0)
		vertices = arrays[Mesh.ARRAY_VERTEX]
		indices = arrays[Mesh.ARRAY_INDEX]
		bones = arrays[Mesh.ARRAY_BONES]
		weights = arrays[Mesh.ARRAY_WEIGHTS]
		stride = roundi(float(bones.size()) / float(vertices.size()))
		for bind in body.skin.get_bind_count():
			var bone := body.skin.get_bind_bone(bind)
			bind_bone.append(bone if bone >= 0 else skeleton.find_bone(body.skin.get_bind_name(bind)))
			bind_pose.append(body.skin.get_bind_pose(bind))

	## Each bind's skinning transform for skeleton-space bone poses `globals`.
	func joints(globals: Array[Transform3D]) -> Array[Transform3D]:
		var out: Array[Transform3D] = []
		for bind in bind_bone.size():
			out.append(globals[bind_bone[bind]] * bind_pose[bind])
		return out

	## Linear blend skinning of every vertex, with `blend` weights (default:
	## the imported ones).
	func skin(globals: Array[Transform3D], blend: PackedFloat32Array = PackedFloat32Array(), slots: PackedInt32Array = PackedInt32Array()) -> PackedVector3Array:
		var w := weights if blend.is_empty() else blend
		var b := bones if slots.is_empty() else slots
		var joint := joints(globals)
		var out := PackedVector3Array()
		out.resize(vertices.size())
		for index in vertices.size():
			var sum := Vector3.ZERO
			for slot in stride:
				var weight := w[index * stride + slot]
				if weight > 0.0:
					sum += joint[b[index * stride + slot]] * vertices[index] * weight
			out[index] = sum
		return out

	## The skeleton bones a vertex rides, with their weights.
	func influences(index: int) -> Dictionary:
		var named := {}
		for slot in stride:
			var weight := weights[index * stride + slot]
			if weight > 0.0:
				named[bind_bone[bones[index * stride + slot]]] = weight
		return named

	func dominant(index: int) -> int:
		var best := -1
		var most := 0.0
		for slot in stride:
			if weights[index * stride + slot] > most:
				most = weights[index * stride + slot]
				best = slot
		return bones[index * stride + best]


## The candidate under the gate. A suite for another candidate on WolfRig
## (PRES-MALE-BASE) overrides these two and inherits every case unchanged.
func _candidate_glb() -> String:
	return CANDIDATE_GLB


func _wrapper() -> String:
	return WRAPPER


func _candidate() -> Skinned:
	var found := Skinned.new()
	var root := (load(_candidate_glb()) as PackedScene).instantiate()
	found.read(root, root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D)
	return found


static func _ring(found: Skinned, pair: Array) -> PackedInt32Array:
	var wanted := [found.skeleton.find_bone(pair[0]), found.skeleton.find_bone(pair[1])]
	var ring := PackedInt32Array()
	for index in found.vertices.size():
		var named := found.influences(index)
		if named.size() == 2 and named.has(wanted[0]) and named.has(wanted[1]) and absf(float(named[wanted[0]]) - 0.5) < 0.01:
			ring.append(index)
	return ring


static func _mean_radius(points: PackedVector3Array, ring: PackedInt32Array) -> float:
	var centre := Vector3.ZERO
	for index in ring:
		centre += points[index]
	centre /= float(ring.size())
	var total := 0.0
	for index in ring:
		total += points[index].distance_to(centre)
	return total / float(ring.size())


## The girdle: triangles touching a vertex that rides `clavicle` (a bone index).
static func _girdle(found: Skinned, clavicle: int) -> PackedInt32Array:
	var tris := PackedInt32Array()
	for t in range(0, found.indices.size(), 3):
		for corner in 3:
			if found.influences(found.indices[t + corner]).has(clavicle):
				tris.append(t)
				break
	return tris


## Girdle triangles folded over: the posed normal faces against the rest normal
## carried by the triangle's own dominant bone (so a turned body is not a fold).
static func _folds(found: Skinned, tris: PackedInt32Array, posed: PackedVector3Array, globals: Array[Transform3D]) -> int:
	return _folded(found, tris, posed, globals).size()


## The folded triangles themselves (their first index), for messages.
static func _folded(found: Skinned, tris: PackedInt32Array, posed: PackedVector3Array, globals: Array[Transform3D]) -> PackedInt32Array:
	var joint := found.joints(globals)
	var folded := PackedInt32Array()
	for t in tris:
		var a := found.indices[t]
		var rest_n := (found.vertices[found.indices[t + 1]] - found.vertices[a]).cross(found.vertices[found.indices[t + 2]] - found.vertices[a])
		var posed_n := (posed[found.indices[t + 1]] - posed[a]).cross(posed[found.indices[t + 2]] - posed[a])
		if rest_n.length_squared() < 1e-12:
			continue
		if posed_n.dot(joint[found.dominant(a)].basis * rest_n) < 0.0:
			folded.append(t)
	return folded


## Where folded triangles sit at rest (their mean first vertex), for messages.
static func _where(found: Skinned, folded: PackedInt32Array) -> Vector3:
	var sum := Vector3.ZERO
	for t in folded:
		sum += found.vertices[found.indices[t]]
	return (sum / float(maxi(1, folded.size()))).snappedf(0.01)


## Mean rise of the girdle above the socket (vertices riding chest, clavicle
## and arm, above `above_y`) as a share of the deltoid cap's mean rise.
static func _follow(found: Skinned, rest: PackedVector3Array, posed: PackedVector3Array, side: String, above_y: float) -> float:
	var chest := found.skeleton.find_bone("Chest")
	var clavicle := found.skeleton.find_bone("Shoulder." + side)
	var upper := found.skeleton.find_bone("UpperArm." + side)
	var girdle := 0.0
	var girdle_count := 0
	var cap := 0.0
	var cap_count := 0
	for index in found.vertices.size():
		var named := found.influences(index)
		if named.has(chest) and named.has(clavicle) and named.has(upper) and rest[index].y > above_y:
			girdle += posed[index].y - rest[index].y
			girdle_count += 1
		elif named.size() == 2 and named.has(clavicle) and named.has(upper):
			cap += posed[index].y - rest[index].y
			cap_count += 1
	if girdle_count == 0 or cap_count == 0 or absf(cap) < 1e-9:
		return NAN
	return (girdle / float(girdle_count)) / (cap / float(cap_count))


## Nearest horizontal approach of an upper-arm-dominant vertex in the neck band
## to the neck's axis (Neck head -> Head head).
static func _neck_clearance(found: Skinned, posed: PackedVector3Array, globals: Array[Transform3D]) -> float:
	var base := globals[found.skeleton.find_bone("Neck")].origin
	var top := globals[found.skeleton.find_bone("Head")].origin
	var axis := (top - base).normalized()
	var arms := [found.skeleton.find_bone("UpperArm.L"), found.skeleton.find_bone("UpperArm.R")]
	var nearest := INF
	for index in posed.size():
		var point := posed[index]
		if point.y < NECK_BAND.x or point.y > NECK_BAND.y or not arms.has(found.bind_bone[found.dominant(index)]):
			continue
		var offset := point - base
		nearest = minf(nearest, (offset - axis * offset.dot(axis)).length())
	return nearest


static func _direction(motion: String, degrees: float, lateral: float) -> Vector3:
	var a := deg_to_rad(degrees)
	match motion:
		"flex":
			return Vector3(0.0, -cos(a), sin(a))
		"extend":
			return Vector3(0.0, -cos(a), -sin(a))
		_:
			return Vector3(lateral * sin(a), -cos(a), 0.0)


## Pose the left arm through `row`, the clavicle raised by `response` (or not),
## re-aimed after it as the IK would reach its target, then twisted.
static func _shoulder_pose(skeleton: Skeleton3D, row: Array, response: ClavicleResponse) -> void:
	skeleton.reset_bone_poses()
	var direction := _direction(row[0], row[1], 1.0)
	ClipPose.aim_arm(skeleton, "L", direction)
	if response != null:
		ClipPose.raise_clavicles(skeleton, response)
		ClipPose.aim_arm(skeleton, "L", direction)
	if not is_zero_approx(float(row[2])):
		ClipPose.twist(skeleton, "UpperArm.L", float(row[2]))


func _clavicle_response() -> ClavicleResponse:
	var wrapper := (load(_wrapper()) as PackedScene).instantiate() as SwordRig3D
	var response := wrapper.clavicle_response
	wrapper.free()
	return response


## PRES-PRODUCTION-IMPORT
func test_the_candidate_imports_as_one_skinned_body_on_wolfrig() -> void:
	## ARRANGE
	var found := _candidate()
	var wolf := (load(WOLF_GLB) as PackedScene).instantiate()
	var wolf_skeleton := wolf.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	## ASSERT: the same skeleton, bone for bone, rest for rest.
	assert_true(found.body != null and found.body.skin != null, "one body with a skin")
	assert_eq(found.skeleton.get_bone_count(), wolf_skeleton.get_bone_count(), "WolfRig's bone count")
	for bone in wolf_skeleton.get_bone_count():
		var bone_name := wolf_skeleton.get_bone_name(bone)
		var mine := found.skeleton.find_bone(bone_name)
		assert_true(mine >= 0, "bone %s is present" % bone_name)
		if mine >= 0:
			assert_true(found.skeleton.get_bone_global_rest(mine).origin.distance_to(wolf_skeleton.get_bone_global_rest(bone).origin) < SKIN_EPSILON, "bone %s rests where Wolf's does" % bone_name)
	## Four influences survive import: the stride is four, no 8-weight flag.
	assert_eq(found.stride, INFLUENCES, "four bone slots per vertex after import")
	assert_eq(found.body.mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS, 0, "never the eight-weight layout")
	var unweighted := 0
	var blended := 0
	for index in found.vertices.size():
		var total := 0.0
		for slot in found.stride:
			total += found.weights[index * found.stride + slot]
		if absf(total - 1.0) > 1e-3:
			unweighted += 1
		if found.influences(index).size() > 2:
			blended += 1
	assert_eq(unweighted, 0, "every vertex is fully weighted")
	assert_true(blended > 0, "the shoulder and groin blend more than two bones (%d vertices)" % blended)
	## Wolf's clips ride along, by name.
	var mine_player := found.root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var wolf_player := wolf.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_true(mine_player != null, "the candidate carries an AnimationPlayer")
	if mine_player != null:
		for clip_name: StringName in wolf_player.get_animation_list():
			assert_true(mine_player.has_animation(clip_name), "the candidate carries Wolf's %s" % clip_name)
	var low := INF
	var high := -INF
	for vertex in found.vertices:
		low = minf(low, vertex.y)
		high = maxf(high, vertex.y)
	assert_true(low >= -0.005 and low < 0.03, "the soles stand on the floor (%.4f)" % low)
	assert_near(high, PhysicalBaseline.FIGHTER_HEIGHT_M, 0.005, "the crown is Wolf's 1.80 m")
	wolf.free()
	found.root.free()


## PRES-PRODUCTION-IMPORT (Gate 3): names, parents and rest heads against
## wolf.rig-contract.json through the Blender->Godot axis change.
func test_the_import_honours_the_rig_contract_and_the_height_invariant() -> void:
	## ARRANGE
	var found := _candidate()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RIG_CONTRACT))
	assert_true(parsed is Dictionary, "fixture: the rig contract parses")
	var contract_bones: Array = parsed["bones"]
	assert_eq(found.skeleton.get_bone_count(), contract_bones.size(), "every contract bone is imported, and no more")
	## ASSERT
	var drift := 0.0
	for entry: Dictionary in contract_bones:
		var bone_name: String = entry["name"]
		var bone := found.skeleton.find_bone(bone_name)
		assert_true(bone >= 0, "bone %s is present" % bone_name)
		if bone < 0:
			continue
		var parent := found.skeleton.get_bone_parent(bone)
		var parent_name := found.skeleton.get_bone_name(parent) if parent >= 0 else ""
		assert_eq(parent_name, str(entry["parent"]) if entry["parent"] != null else "", "%s keeps its parent" % bone_name)
		var head: Array = entry["head"]
		drift = maxf(drift, ClipPose.global_poses(found.skeleton)[bone].origin.distance_to(Vector3(head[0], head[2], -head[1])))
	assert_true(drift < CONTRACT_EPSILON, "every rest head matches the contract through the axis change (worst %.6f m)" % drift)
	var high := -INF
	for vertex in found.vertices:
		high = maxf(high, vertex.y)
	assert_near(high, PhysicalBaseline.FIGHTER_HEIGHT_M, 0.01, "Wolf's crown stands 1.80 m above the floor in Godot")
	found.root.free()


## PRES-PRODUCTION-IMPORT: binds are the inverse rests.
func test_the_skin_is_the_identity_at_rest() -> void:
	## ARRANGE
	var found := _candidate()
	found.skeleton.reset_bone_poses()
	## ACT
	var rest := found.skin(ClipPose.global_poses(found.skeleton))
	## ASSERT
	var worst := 0.0
	for index in found.vertices.size():
		worst = maxf(worst, rest[index].distance_to(found.vertices[index]))
	assert_true(worst < SKIN_EPSILON, "rest skinning reproduces the mesh (worst %.6f m)" % worst)
	found.root.free()


## PRES-PRODUCTION-CLIPS
func test_the_candidates_clips_deform_it_without_tearing_or_collapse() -> void:
	## ARRANGE
	var found := _candidate()
	var player := found.root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_true(player != null, "fixture: the candidate's clips")
	found.skeleton.reset_bone_poses()
	var rest_globals := ClipPose.global_poses(found.skeleton)
	var rest := found.skin(rest_globals)
	var rings := {}
	for joint: String in JOINTS:
		rings[joint] = _ring(found, JOINTS[joint])
		assert_true(rings[joint].size() >= 8, "fixture: %s has a joint loop (%d vertices)" % [joint, rings[joint].size()])
	var rigid := PackedInt32Array()
	var rigid_bone := PackedInt32Array()
	for index in found.vertices.size():
		var named := found.influences(index)
		if named.size() == 1:
			rigid.append(index)
			rigid_bone.append(int(named.keys()[0]))
	## The tear check samples the vertices that ride one bone alone; the
	## blended joints (shoulder girdle, five-ring hip) are held by their own
	## cases. A third of the body is a sample, not a majority claim.
	assert_true(rigid.size() * 3 > found.vertices.size(), "fixture: a third of the vertices follow one bone (%d of %d)" % [rigid.size(), found.vertices.size()])
	var rest_reach := PackedFloat32Array()
	for i in rigid.size():
		rest_reach.append(rest[rigid[i]].distance_to(rest_globals[rigid_bone[i]].origin))
	## PERTURB check: a clip must actually move the body.
	var death := player.get_animation(&"death")
	ClipPose.apply(found.skeleton, death, death.length)
	var fallen := found.skin(ClipPose.global_poses(found.skeleton))
	var moved := 0.0
	for index in fallen.size():
		moved = maxf(moved, fallen[index].distance_to(rest[index]))
	assert_true(moved > 0.3, "fixture: the death clip poses the candidate (%.3f m)" % moved)
	var thinnest := {}
	for clip_name: StringName in CLIPS:
		var clip := player.get_animation(clip_name)
		assert_true(clip != null, "fixture: the candidate has %s" % clip_name)
		if clip == null:
			continue
		for fraction: float in FRACTIONS:
			## ACT
			ClipPose.apply(found.skeleton, clip, clip.length * fraction)
			var globals := ClipPose.global_poses(found.skeleton)
			var posed := found.skin(globals)
			## ASSERT
			var torn := 0
			for i in rigid.size():
				var reach := posed[rigid[i]].distance_to(globals[rigid_bone[i]].origin)
				if not is_finite(reach) or absf(reach - rest_reach[i]) > SKIN_EPSILON:
					torn += 1
			assert_eq(torn, 0, "%s @%.2f: single-bone vertices keep their distance to the bone" % [clip_name, fraction])
			for joint: String in JOINTS:
				var ratio := _mean_radius(posed, rings[joint]) / _mean_radius(rest, rings[joint])
				thinnest[joint] = minf(float(thinnest.get(joint, INF)), ratio)
				assert_true(ratio >= RING_FLOOR, "%s @%.2f: the %s keeps %.0f%% of its radius (has %.2f)" % [clip_name, fraction, joint, RING_FLOOR * 100.0, ratio])
	assert_true(float(thinnest["knee.L"]) < 0.99, "fixture: the clips bend the knees (%.3f)" % float(thinnest["knee.L"]))
	found.root.free()


## PRES-PRODUCTION-CLIPS: the clips never key the arms (IK bends the elbows),
## so the elbow loops are bent directly through the guard's range.
func test_an_elbow_bent_like_the_guard_keeps_its_loop() -> void:
	## ARRANGE
	var found := _candidate()
	found.skeleton.reset_bone_poses()
	var rest := found.skin(ClipPose.global_poses(found.skeleton))
	for side: String in ["L", "R"]:
		var joint := "elbow." + side
		var ring := _ring(found, JOINTS[joint])
		assert_true(ring.size() >= 8, "fixture: %s has a loop" % joint)
		for degrees: float in [90.0, 130.0]:
			## PERTURB
			found.skeleton.reset_bone_poses()
			ClipPose.bend(found.skeleton, "Forearm." + side, Vector3.RIGHT, degrees)
			## ACT
			var bent := found.skin(ClipPose.global_poses(found.skeleton))
			## ASSERT
			var ratio := _mean_radius(bent, ring) / _mean_radius(rest, ring)
			assert_true(ratio < 0.999, "fixture: %s actually bent at %d degrees (%.3f)" % [joint, int(degrees), ratio])
			assert_true(ratio >= RING_FLOOR, "%s bent %d degrees keeps %.0f%% of its radius (has %.3f)" % [joint, int(degrees), RING_FLOOR * 100.0, ratio])
	found.root.free()


## PRES-PRODUCTION-GIRDLE: the shoulder articulates as one girdle through the
## release range, with the clavicle participating as the candidate scene
## configures it; and the gate catches a static chest shell (the socket weighted
## to the chest alone: the arm swings out of a fixed torso) and a girdle with
## the clavicle held at rest (the shoulder top sinks as the arm rises).
func test_the_shoulder_articulates_as_one_connected_girdle() -> void:
	## ARRANGE
	var found := _candidate()
	var response := _clavicle_response()
	assert_true(response != null, "fixture: the candidate scene names a clavicle response")
	var clavicle := found.skeleton.find_bone("Shoulder.L")
	var chest := found.skeleton.find_bone("Chest")
	var upper := found.skeleton.find_bone("UpperArm.L")
	var girdle := _girdle(found, clavicle)
	assert_true(girdle.size() > 20, "fixture: the girdle rides the clavicle (%d triangles)" % girdle.size())
	found.skeleton.reset_bone_poses()
	var rest := found.skin(ClipPose.global_poses(found.skeleton))
	var socket_top := -INF
	for index in found.vertices.size():
		if found.influences(index).has(clavicle) and found.influences(index).has(upper) and found.influences(index).has(chest):
			socket_top = maxf(socket_top, rest[index].y)
	var above := socket_top - 0.01
	## The static-chest-shell fixture: the socket's chest/clavicle/arm vertices
	## re-weighted to the chest alone.
	var shell := found.weights.duplicate()
	var shell_slots := found.bones.duplicate()
	var chest_bind := found.bind_bone.find(chest)
	var reweighted := 0
	for index in found.vertices.size():
		var named := found.influences(index)
		if named.has(chest) and named.has(clavicle) and named.has(upper):
			reweighted += 1
			for slot in found.stride:
				shell[index * found.stride + slot] = 1.0 if slot == 0 else 0.0
				shell_slots[index * found.stride + slot] = chest_bind if slot == 0 else 0
	assert_true(reweighted >= 5, "fixture: the shell re-weights the socket (%d vertices)" % reweighted)
	for row: Array in RELEASE_RANGE:
		var label := "%s %d° twist %d°" % [row[0], int(row[1]), int(row[2])]
		## ACT
		_shoulder_pose(found.skeleton, row, response)
		var globals := ClipPose.global_poses(found.skeleton)
		var posed := found.skin(globals)
		## ASSERT
		assert_true(_folds(found, girdle, posed, globals) <= FOLD_BUDGET, "%s: the girdle does not fold (%d folded)" % [label, _folds(found, girdle, posed, globals)])
		assert_true(_neck_clearance(found, posed, globals) >= NECK_CLEAR_M, "%s: the arm stays clear of the neck (%.3f m)" % [label, _neck_clearance(found, posed, globals)])
		if float(row[1]) >= 90.0 and is_zero_approx(float(row[2])):
			var follow := _follow(found, rest, posed, "L", above)
			assert_true(follow >= FOLLOW_FLOOR, "%s: the girdle rises with the arm (follow %.2f)" % [label, follow])
			## PERTURB: the same pose on the static chest shell, and with the
			## clavicle at rest. The gate must refuse both.
			var flat := found.skin(globals, shell, shell_slots)
			assert_true(_follow(found, rest, flat, "L", above) < FOLLOW_FLOOR, "%s: a static chest shell is caught (follow %.2f)" % [label, _follow(found, rest, flat, "L", above)])
			## Without the clavicle an abducted arm's socket top sinks (measured
			## -0.14 at 90°); in flexion the socket's own arm share lifts it a
			## little, so that negative is abduction's.
			if row[0] == "abduct":
				_shoulder_pose(found.skeleton, row, null)
				var sunk := found.skin(ClipPose.global_poses(found.skeleton))
				assert_true(_follow(found, rest, sunk, "L", above) < FOLLOW_FLOOR, "%s: a girdle that sinks without the clavicle is caught (follow %.2f)" % [label, _follow(found, rest, sunk, "L", above)])
	## Diagnostic range: not release, but the clavicle must help, never hurt.
	for row: Array in DIAGNOSTIC_RANGE:
		_shoulder_pose(found.skeleton, row, response)
		var globals := ClipPose.global_poses(found.skeleton)
		var with_clavicle := found.skin(globals)
		var folds_with := _folds(found, girdle, with_clavicle, globals)
		var follow_with := _follow(found, rest, with_clavicle, "L", above)
		assert_true(_neck_clearance(found, with_clavicle, globals) >= NECK_CLEAR_M, "%s %d° (diagnostic): the arm stays clear of the neck" % [row[0], int(row[1])])
		_shoulder_pose(found.skeleton, row, null)
		var bare_globals := ClipPose.global_poses(found.skeleton)
		var bare := found.skin(bare_globals)
		assert_true(folds_with <= _folds(found, girdle, bare, bare_globals) + 2, "%s %d° (diagnostic): the clavicle does not add folds (%d vs %d)" % [row[0], int(row[1]), folds_with, _folds(found, girdle, bare, bare_globals)])
		assert_true(follow_with > _follow(found, rest, bare, "L", above), "%s %d° (diagnostic): the clavicle lifts the girdle (%.2f)" % [row[0], int(row[1]), follow_with])
	found.root.free()


## PRES-PRODUCTION-HIP: the pelvis opening and the thigh top bend as one band
## through the legs' combat range (lunge flexion, the trailing leg's
## extension, the side step's abduction), and the gate catches a static pelvis
## shell (the opening weighted to the hips alone: the leg swings out of a
## fixed box).
func test_the_hip_bends_as_one_band_with_the_seat_and_the_groin() -> void:
	## ARRANGE
	var found := _candidate()
	var hips := found.skeleton.find_bone("Hips")
	found.skeleton.reset_bone_poses()
	var rest := found.skin(ClipPose.global_poses(found.skeleton))
	for side: String in ["L", "R"]:
		var thigh := found.skeleton.find_bone("UpperLeg." + side)
		var band := _hip_band(found, hips, thigh)
		assert_true(band.size() > 20, "fixture: the %s hip band blends pelvis and thigh (%d triangles)" % [side, band.size()])
		var shell := found.weights.duplicate()
		var shell_slots := found.bones.duplicate()
		var hips_bind := found.bind_bone.find(hips)
		var reweighted := 0
		for index in found.vertices.size():
			var named := found.influences(index)
			## The band `_hip_follow` measures, not the thigh it measures against.
			if named.has(hips) and named.has(thigh) and float(named[thigh]) < 0.9:
				reweighted += 1
				for slot in found.stride:
					shell[index * found.stride + slot] = 1.0 if slot == 0 else 0.0
					shell_slots[index * found.stride + slot] = hips_bind if slot == 0 else 0
		assert_true(reweighted >= 8, "fixture: the shell re-weights the %s opening (%d vertices)" % [side, reweighted])
		for row: Array in HIP_RANGE:
			var label := "%s hip %s %d°" % [side, row[0], int(row[1])]
			## ACT
			found.skeleton.reset_bone_poses()
			ClipPose.aim(found.skeleton, "UpperLeg." + side, _direction(row[0], row[1], 1.0 if side == "L" else -1.0))
			var globals := ClipPose.global_poses(found.skeleton)
			var posed := found.skin(globals)
			## ASSERT
			var stretch := _stretch(found, band, rest, posed)
			var follow := _hip_follow(found, hips, thigh, rest, posed)
			assert_true(_folds(found, band, posed, globals) <= FOLD_BUDGET, "%s: the hip band does not fold (%d folded)" % [label, _folds(found, band, posed, globals)])
			assert_true(stretch <= HIP_STRETCH_MAX, "%s: no band edge stretches past %.1fx (has %.2fx)" % [label, HIP_STRETCH_MAX, stretch])
			assert_true(follow >= HIP_FOLLOW_FLOOR, "%s: the opening moves with the thigh (follow %.2f)" % [label, follow])
			## PERTURB: the same pose on the static pelvis shell. The gate must refuse it.
			var flat := found.skin(globals, shell, shell_slots)
			assert_true(_hip_follow(found, hips, thigh, rest, flat) < HIP_FOLLOW_FLOOR, "%s: a static pelvis shell is caught (follow %.2f)" % [label, _hip_follow(found, hips, thigh, rest, flat)])
	found.root.free()


## The hip band: triangles touching a vertex that rides both the hips and `thigh`.
static func _hip_band(found: Skinned, hips: int, thigh: int) -> PackedInt32Array:
	var tris := PackedInt32Array()
	for t in range(0, found.indices.size(), 3):
		for corner in 3:
			var named := found.influences(found.indices[t + corner])
			if named.has(hips) and named.has(thigh):
				tris.append(t)
				break
	return tris


## Mean move of the vertices blending the hips and `thigh` (the thigh short of
## 90 %), as a share of the mean move of the upper thigh's own vertices (the
## thigh at 90 % or more, within 30 cm of the hip joint).
static func _hip_follow(found: Skinned, hips: int, thigh: int, rest: PackedVector3Array, posed: PackedVector3Array) -> float:
	var hip_y := found.skeleton.get_bone_global_rest(thigh).origin.y
	var band := 0.0
	var band_count := 0
	var top := 0.0
	var top_count := 0
	for index in found.vertices.size():
		var named := found.influences(index)
		var moved := posed[index].distance_to(rest[index])
		var share := float(named.get(thigh, 0.0))
		if named.has(hips) and share > 0.0 and share < 0.9:
			band += moved
			band_count += 1
		elif share >= 0.9 and rest[index].y > hip_y - 0.3:
			top += moved
			top_count += 1
	if band_count == 0 or top_count == 0 or top < 1e-9:
		return NAN
	return (band / float(band_count)) / (top / float(top_count))


## The worst edge-length ratio (posed / rest) over `tris`.
static func _stretch(found: Skinned, tris: PackedInt32Array, rest: PackedVector3Array, posed: PackedVector3Array) -> float:
	var worst := 1.0
	for t in tris:
		for corner in 3:
			var a := found.indices[t + corner]
			var b := found.indices[t + (corner + 1) % 3]
			var length := rest[a].distance_to(rest[b])
			if length > 1e-6:
				worst = maxf(worst, posed[a].distance_to(posed[b]) / length)
	return worst


## PRES-PRODUCTION-GIRDLE: the neck check is real — a deltoid pushed into the
## neck (the rejected body's medial socket, rebuilt as a perturbation) fails it.
func test_an_arm_pushed_into_the_neck_is_caught() -> void:
	## ARRANGE
	var found := _candidate()
	found.skeleton.reset_bone_poses()
	var globals := ClipPose.global_poses(found.skeleton)
	var posed := found.skin(globals)
	assert_true(_neck_clearance(found, posed, globals) >= NECK_CLEAR_M, "fixture: the body at rest is clear")
	## PERTURB: carry the upper-arm vertices of the shoulder band beside the neck.
	var upper := found.skeleton.find_bone("UpperArm.L")
	var pushed := 0
	for index in posed.size():
		if found.bind_bone[found.dominant(index)] == upper and posed[index].y > 1.30:
			posed[index] = Vector3(0.09, 1.48, posed[index].z)
			pushed += 1
	assert_true(pushed > 0, "fixture: vertices were moved")
	## ACT / ASSERT
	assert_true(_neck_clearance(found, posed, globals) < NECK_CLEAR_M, "an arm root beside the neck fails the clearance (%.3f m)" % _neck_clearance(found, posed, globals))
	found.root.free()


## PRES-PRODUCTION-STACK: the candidate on a real proxy, posed by the real
## stack, at guard across the sword's arc (where parries are met), the full
## shoulder load, a loaded cut in flight, and the overswing.
func test_the_real_combat_stack_keeps_the_hands_on_the_grip_and_the_girdle_whole() -> void:
	## ARRANGE
	var rules := StandardDuelRules.create()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	var skin := FighterSkinKit.new()
	skin.skin_id = &"test.wolf_production"
	skin.scene = load(_wrapper()) as PackedScene
	kits.combatant(0).fighter_skin = skin
	var proxy := FighterPresentation3D.create(0, DuelSide.Id.LIGHT_SOUTH, kits.combatant(0), rules.combatant(0).fighter.push_radius, rules.combatant(0))
	(Engine.get_main_loop() as SceneTree).root.add_child(proxy)
	var rig := proxy.rig()
	assert_true(rig != null and rig.clavicle_response != null and rig.combat_pose().clavicle != null, "fixture: the candidate's stack carries clavicle participation")
	var skeleton := rig.skeleton()
	var found := Skinned.new()
	found.read(proxy, skeleton)
	var girdle_l := _girdle(found, skeleton.find_bone("Shoulder.L"))
	var girdle_r := _girdle(found, skeleton.find_bone("Shoulder.R"))
	var clavicle_r := skeleton.find_bone("Shoulder.R")
	var rows := []
	for degrees: float in [-135.0, -90.0, -45.0, 0.0, 45.0, 90.0, 135.0]:
		rows.append(["guard %d°" % int(degrees), _row(deg_to_rad(degrees))])
	rows.append(["full load", _row(deg_to_rad(-135.0), CombatPhase.Id.CHARGING, 1.0, 1.0, 0.0)])
	rows.append(["loaded cut", _row(deg_to_rad(-45.0), CombatPhase.Id.ACTIVE_THREAT, 0.3, 0.0, 1.0)])
	rows.append(["overswing", _row(deg_to_rad(50.0), CombatPhase.Id.OVERSWING, 1.0, 0.0, 1.0)])
	var load_lift := 0.0
	for entry: Array in rows:
		var label: String = entry[0]
		var row: PresentationFighter = entry[1]
		var measured := {}
		## ACT: settle the real stack; measure while its output is live.
		var measure := func() -> void:
			var globals: Array[Transform3D] = []
			for bone in skeleton.get_bone_count():
				globals.append(skeleton.get_bone_global_pose(bone))
			var posed := found.skin(globals)
			var folded := _folded(found, girdle_l, posed, globals)
			folded.append_array(_folded(found, girdle_r, posed, globals))
			measured["folds"] = folded.size()
			measured["where"] = _where(found, folded)
			var corners := []
			for t in folded:
				corners.append([found.vertices[found.indices[t]].snappedf(0.001), found.vertices[found.indices[t + 1]].snappedf(0.001), found.vertices[found.indices[t + 2]].snappedf(0.001)])
			measured["corners"] = corners
			measured["neck"] = _neck_clearance(found, posed, globals)
			measured["lift"] = skeleton.get_bone_pose_rotation(clavicle_r).angle_to(skeleton.get_bone_rest(clavicle_r).basis.get_rotation_quaternion())
			for index in 2:
				var hand := skeleton.find_bone("Hand.R" if index == 0 else "Hand.L")
				var pose := skeleton.global_transform * skeleton.get_bone_global_pose(hand)
				var palm := pose.origin + pose.basis.y.normalized() * SwordRig3D.HAND_LENGTH
				measured["grip%d" % index] = palm.distance_to(rig.grip_target(index).global_position)
		await _settle(proxy, row, measure)
		## ASSERT
		assert_true(measured.has("folds"), "fixture: %s was measured inside the stack's update" % label)
		if not measured.has("folds"):
			continue
		assert_true(float(measured["grip0"]) <= GRIP_TOLERANCE and float(measured["grip1"]) <= GRIP_TOLERANCE, "%s: both hands stay on the grip (%.3f, %.3f m)" % [label, float(measured["grip0"]), float(measured["grip1"])])
		assert_true(int(measured["folds"]) <= FOLD_BUDGET * 2, "%s: neither girdle folds (%d folded near %s: %s)" % [label, int(measured["folds"]), measured["where"], str(measured["corners"])])
		assert_true(float(measured["neck"]) >= NECK_CLEAR_M, "%s: the arms stay clear of the neck (%.3f m)" % [label, float(measured["neck"])])
		if label == "full load":
			load_lift = float(measured["lift"])
	assert_true(rad_to_deg(load_lift) > 2.0, "the full load lifts the dominant clavicle (%.1f°)" % rad_to_deg(load_lift))
	proxy.queue_free()
	await await_frames(1)


static func _row(angle: float, phase: CombatPhase.Id = CombatPhase.Id.NEUTRAL, progress: float = 1.0, charge: float = 0.0, swing_charge: float = 0.0) -> PresentationFighter:
	var row := PresentationFighter.new()
	row.health = 100.0
	row.weapon_angle = angle
	row.phase = phase
	row.swing_progress = progress
	row.charge = charge
	row.swing_charge = swing_charge
	row.target_bearing = PI * 0.5
	return row


## Pose the proxy and run its skeleton's modifier stack once, calling `during`
## inside `skeleton_updated`, while the modifier output is live (PRES-RIG's
## `_settle`).
func _settle(proxy: FighterPresentation3D, row: PresentationFighter, during: Callable) -> void:
	proxy.apply_pose(Vector3.ZERO, PI * 0.5, row.weapon_angle, row, 1.0)
	proxy.apply_pose(Vector3.ZERO, PI * 0.5, row.weapon_angle, row, 1.0 / 60.0)
	var skeleton := proxy.rig().skeleton()
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	skeleton.skeleton_updated.connect(during)
	skeleton.advance(1.0 / 60.0)
	await await_frames(1)
	skeleton.skeleton_updated.disconnect(during)
