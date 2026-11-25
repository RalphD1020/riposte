class_name SkeletonCapture
extends RefCounted

## SKELETON-CAPTURE-001 in Godot: save a viewport's image and, when its world shows a skeleton,
## the skeleton sidecar beside it (`<png>.skeleton.json`, schema `riposte.skeleton_capture`, the
## same as Blender's `tools/blender/inspect/skeleton_capture.py`). The sidecar holds the camera,
## every visible Skeleton3D's final posed bones (after the modifier stack: world position and
## rotation, the image pixel each joint lands on, in front of the camera / inside the frame) and
## the arm readings of `tools/blender/skeleton_capture_core.py` (elbow flexion, upper-arm
## elevation, forearm pitch, elbow above shoulder / wrist). Tools only — never the game.
##
## Godot rolls a skeleton back to its pre-modifier pose after each update, so the drawn (final)
## pose is only readable inside `skeleton_updated`. `watch(tree)` records every skeleton's final
## pose there (start of a capture tool, before the first shot); `save` also starts watching, and a
## skeleton not yet recorded is written from its animation pose with `pose_source` saying so.

const SCHEMA := "riposte.skeleton_capture"
const VERSION := 1
const SIDECAR_SUFFIX := ".skeleton.json"
const ARM_BONES := {"R": ["UpperArm.R", "Forearm.R", "Hand.R"], "L": ["UpperArm.L", "Forearm.L", "Hand.L"]}
## Arm validation (skeleton_capture_core.HEURISTICS): `hard` failures make a pose invalid, `warning`s
## are provisional quality signals (never approvals); a level forearm is tolerated.
const ELBOW_BELOW_SHOULDER_M := -0.05
const ELBOW_ABOVE_WRIST_MAX_M := 0.05
const SEGMENT_LENGTH_TOLERANCE := 0.02
const UPPER_ELEVATION_MAX_DEG := 90.0
const ELBOW_FLEX_MIN_DEG := 15.0
const ELBOW_FLEX_MAX_DEG := 140.0


const POSE_META := &"skeleton_capture_pose"
const FRAME_META := &"skeleton_capture_frame"
const WATCH_META := &"skeleton_capture_watch"


## Record the final pose of every Skeleton3D in `tree`, now and as they are added.
static func watch(tree: SceneTree) -> void:
	if tree.has_meta(WATCH_META):
		return
	tree.set_meta(WATCH_META, true)
	tree.node_added.connect(_on_node_added)
	for node in tree.root.find_children("*", "Skeleton3D", true, false):
		_track(node as Skeleton3D)


static func _on_node_added(node: Node) -> void:
	if node is Skeleton3D:
		_track(node as Skeleton3D)


static func _track(skeleton: Skeleton3D) -> void:
	if skeleton == null or skeleton.has_meta(WATCH_META):
		return
	skeleton.set_meta(WATCH_META, true)
	skeleton.skeleton_updated.connect(_remember.bind(skeleton))


static func _remember(skeleton: Skeleton3D) -> void:
	var poses: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_global_pose(bone))
	skeleton.set_meta(POSE_META, poses)
	skeleton.set_meta(FRAME_META, Engine.get_process_frames())


## Save `viewport`'s current image to `png_path` and its sidecar; returns the image save error.
static func save(viewport: Viewport, png_path: String, tool: String, extra: Dictionary = {}) -> Error:
	if viewport.is_inside_tree():
		watch(viewport.get_tree())
	var image := viewport.get_texture().get_image()
	var error := image.save_png(png_path)
	if error == OK:
		write(viewport, png_path, image.get_size(), tool, extra)
	return error


## Write the sidecar for an image of `size` already saved from `viewport`; "" when the world shows
## no skeleton or no camera. An image cut from the viewport's texture at `crop_origin` (texture
## pixels) and resized by `resample` maps its joints the same way.
static func write(viewport: Viewport, png_path: String, size: Vector2i, tool: String, extra: Dictionary = {}, crop_origin := Vector2.ZERO, resample := 1.0) -> String:
	var camera := viewport.get_camera_3d()
	if camera == null:
		return ""
	var skeletons: Array[Dictionary] = []
	var texture_scale := Vector2(viewport.get_texture().get_size()) / viewport.get_visible_rect().size
	var mapping := Transform2D(0.0, texture_scale * resample, 0.0, -crop_origin * resample)
	for node in viewport.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		if skeleton == null or not skeleton.is_visible_in_tree():
			continue
		skeletons.append(_skeleton(skeleton, camera, mapping, size))
	if skeletons.is_empty():
		return ""
	## The image's subject: the skeleton with the most joints inside the frame.
	var primary := 0
	var best := -1
	for index in skeletons.size():
		var seen := 0
		for bone: Dictionary in skeletons[index]["bones"]:
			seen += 1 if bone["in_frame"] else 0
		if seen > best:
			best = seen
			primary = index
	var orthographic := camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	var lens := {"projection": "orthographic" if orthographic else "perspective", "position": _vector(camera.global_position),
		"rotation_xyzw": _quaternion(camera.global_basis.get_rotation_quaternion())}
	if orthographic:
		lens["ortho_size"] = camera.size
	else:
		lens["fov_deg"] = camera.fov
	var sidecar := {
		"schema": SCHEMA, "version": VERSION, "engine": "godot", "tool": tool, "up": [0.0, 1.0, 0.0], "units": "m",
		"image": {"file": png_path.get_file(), "width": size.x, "height": size.y},
		"frame": Engine.get_process_frames(),
		"camera": lens,
		"skeletons": skeletons,
		"primary": primary,
		"arms": skeletons[primary]["arms"],
		"heuristics": skeletons[primary]["heuristics"],
		"extra": extra,
	}
	var path := sidecar_path(png_path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SkeletonCapture: cannot write %s" % path)
		return ""
	file.store_string(JSON.stringify(sidecar, " "))
	file.close()
	return path


## A sidecar's skeletons mapped into a board cell (skeleton_capture_core.board_cell): every pixel
## scaled by `scale` and offset by the cell's `origin` in board pixels; world data unchanged.
static func board_cell(sidecar: Dictionary, origin: Vector2, scale: float) -> Dictionary:
	var cell := {"image": sidecar.get("image", {}), "camera": sidecar.get("camera", {}), "arms": sidecar.get("arms", {}), "heuristics": sidecar.get("heuristics", {}), "extra": sidecar.get("extra", {}), "skeletons": []}
	for skeleton: Dictionary in sidecar.get("skeletons", []):
		var bones: Array = []
		for bone: Dictionary in skeleton.get("bones", []):
			var mapped := bone.duplicate()
			if bone.get("pixel") != null:
				mapped["pixel"] = [snappedf(origin.x + float(bone["pixel"][0]) * scale, 0.01), snappedf(origin.y + float(bone["pixel"][1]) * scale, 0.01)]
			bones.append(mapped)
		var entry := skeleton.duplicate()
		entry["bones"] = bones
		(cell["skeletons"] as Array).append(entry)
	return cell


static func sidecar_path(png_path: String) -> String:
	return (png_path.get_basename() if png_path.get_extension().to_lower() == "png" else png_path) + SIDECAR_SUFFIX


static func _skeleton(skeleton: Skeleton3D, camera: Camera3D, mapping: Transform2D, size: Vector2i) -> Dictionary:
	var bones: Array[Dictionary] = []
	var positions := {}
	var final: Array = skeleton.get_meta(POSE_META, [])
	var recorded := final.size() == skeleton.get_bone_count()
	for bone in skeleton.get_bone_count():
		var pose := skeleton.get_bone_global_pose(bone)
		if recorded:
			pose = final[bone]
		var world := skeleton.global_transform * pose
		var in_front := not camera.is_position_behind(world.origin)
		var pixel := mapping * camera.unproject_position(world.origin)
		var parent := skeleton.get_bone_parent(bone)
		var parent_name: Variant = null
		if parent >= 0:
			parent_name = skeleton.get_bone_name(parent)
		var image_pixel: Variant = null
		if in_front:
			image_pixel = [snappedf(pixel.x, 0.01), snappedf(pixel.y, 0.01)]
		bones.append({
			"name": skeleton.get_bone_name(bone), "parent": parent_name,
			"position": _vector(world.origin), "rotation_xyzw": _quaternion(world.basis.get_rotation_quaternion()),
			"pixel": image_pixel,
			"in_front": in_front, "in_frame": in_front and pixel.x >= 0.0 and pixel.y >= 0.0 and pixel.x <= size.x and pixel.y <= size.y,
		})
		positions[skeleton.get_bone_name(bone)] = world.origin
	var arms := arm_readings(positions, Vector3.UP)
	return {"name": String(skeleton.get_path()), "pose_source": "final (after the modifier stack, frame %d)" % int(skeleton.get_meta(FRAME_META, -1)) if recorded else "animation (before modifiers: call SkeletonCapture.watch before the first shot)",
		"arms": arms, "heuristics": heuristics(arms, segment_lengths(skeleton, positions)), "bones": bones}


## Per side the posed and rest upper-arm / forearm lengths (joint to joint) for the hard check.
static func segment_lengths(skeleton: Skeleton3D, positions: Dictionary) -> Dictionary:
	var out := {}
	for side: String in ARM_BONES:
		var names: Array = ARM_BONES[side]
		var ids := [skeleton.find_bone(names[0]), skeleton.find_bone(names[1]), skeleton.find_bone(names[2])]
		if ids.has(-1) or not (positions.has(names[0]) and positions.has(names[1]) and positions.has(names[2])):
			continue
		var rest: Array[Vector3] = []
		for id: int in ids:
			rest.append(skeleton.global_transform * skeleton.get_bone_global_rest(id).origin)
		out[side] = {
			"upper": (positions[names[0]] as Vector3).distance_to(positions[names[1]]), "fore": (positions[names[1]] as Vector3).distance_to(positions[names[2]]),
			"upper_rest": rest[0].distance_to(rest[1]), "fore_rest": rest[1].distance_to(rest[2]),
		}
	return out


## Per arm the checks over `arm_readings` (skeleton_capture_core.heuristics): each {value, limit, pass,
## severity}, the arm's `verdict` ("pass" / "warning" / "fail") and `pass` (no hard failure).
static func heuristics(arms: Dictionary, lengths: Dictionary = {}) -> Dictionary:
	var out := {}
	for side: String in arms:
		var r: Dictionary = arms[side]
		var flex: float = r["elbow_flex_deg"]
		var checks := {
			"elbow_below_shoulder": _check(r["elbow_above_shoulder_m"], ELBOW_BELOW_SHOULDER_M, r["elbow_above_shoulder_m"] <= ELBOW_BELOW_SHOULDER_M, "warning"),
			"elbow_not_above_wrist": _check(r["elbow_above_wrist_m"], ELBOW_ABOVE_WRIST_MAX_M, r["elbow_above_wrist_m"] <= ELBOW_ABOVE_WRIST_MAX_M, "warning"),
			"upper_arm_not_above_horizontal": _check(r["upper_elevation_deg"], UPPER_ELEVATION_MAX_DEG, r["upper_elevation_deg"] <= UPPER_ELEVATION_MAX_DEG, "warning"),
			"elbow_bent_not_folded": _check(flex, [ELBOW_FLEX_MIN_DEG, ELBOW_FLEX_MAX_DEG], flex >= ELBOW_FLEX_MIN_DEG and flex <= ELBOW_FLEX_MAX_DEG, "warning"),
		}
		if lengths.has(side) and float(lengths[side]["upper_rest"]) > 0.0 and float(lengths[side]["fore_rest"]) > 0.0:
			var seg: Dictionary = lengths[side]
			var worst := maxf(absf(float(seg["upper"]) / float(seg["upper_rest"]) - 1.0), absf(float(seg["fore"]) / float(seg["fore_rest"]) - 1.0))
			checks["joint_lengths_preserved"] = _check(snappedf(worst, 0.00001), SEGMENT_LENGTH_TOLERANCE, worst <= SEGMENT_LENGTH_TOLERANCE, "hard")
		var hard := false
		var warn := false
		for name: String in checks:
			if not checks[name]["pass"]:
				hard = hard or checks[name]["severity"] == "hard"
				warn = warn or checks[name]["severity"] == "warning"
		checks["verdict"] = "fail" if hard else ("warning" if warn else "pass")
		checks["pass"] = not hard
		out[side] = checks
	return out


static func _check(value: Variant, limit: Variant, ok: bool, severity: String) -> Dictionary:
	return {"value": value, "limit": limit, "pass": ok, "severity": severity}


## The shared arm readings (skeleton_capture_core.arm_readings), per side present.
static func arm_readings(positions: Dictionary, up: Vector3) -> Dictionary:
	var out := {}
	for side: String in ARM_BONES:
		var names: Array = ARM_BONES[side]
		if not (positions.has(names[0]) and positions.has(names[1]) and positions.has(names[2])):
			continue
		var s: Vector3 = positions[names[0]]
		var e: Vector3 = positions[names[1]]
		var w: Vector3 = positions[names[2]]
		var fore := w - e
		out[side] = {
			"elbow_flex_deg": snappedf(180.0 - rad_to_deg((s - e).angle_to(w - e)), 0.01),
			"upper_elevation_deg": snappedf(rad_to_deg((e - s).angle_to(-up)), 0.01),
			"forearm_pitch_deg": snappedf(rad_to_deg(asin(clampf(fore.normalized().dot(up), -1.0, 1.0))) if fore.length() > 1e-9 else 0.0, 0.01),
			"elbow_above_shoulder_m": snappedf((e - s).dot(up), 0.0001),
			"elbow_above_wrist_m": snappedf((e - w).dot(up), 0.0001),
		}
	return out


static func _vector(v: Vector3) -> Array:
	return [snappedf(v.x, 0.00001), snappedf(v.y, 0.00001), snappedf(v.z, 0.00001)]


static func _quaternion(q: Quaternion) -> Array:
	return [snappedf(q.x, 0.000001), snappedf(q.y, 0.000001), snappedf(q.z, 0.000001), snappedf(q.w, 0.000001)]
