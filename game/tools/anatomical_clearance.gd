class_name AnatomicalClearance
extends RefCounted
## ART-ANATOMY-001 in Godot: evaluate a body's anatomical collision profile
## (`<body>.anatomy.json`, fitted from the production mesh by tools/blender/inspect/anatomical_bounds.py)
## on a final skeleton pose. A port of tools/blender/anatomical_bounds_core.py's geometry: capsules
## (segment swept by a radius) and convex prisms (polygon outline extruded along the bone) in bone-local rest frames,
## which WolfRig shares between Blender and Godot. Every checked pair's signed clearance
## (distance between cores minus both radii; negative overlaps) and its band. Art validation and
## offline pose fitting only: nothing here moves the sword, a palm, a bone or touches physics.

const BANDS := [[3.0, "minor"], [8.0, "warning"], [15.0, "significant"]]
const HARD_BAND := "hard"
const NEAR_MARGIN_M := 0.005
const PRISM_SEARCH_ITERATIONS := 60


static func load_profile(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## bone name -> world Transform3D (final pose) to every enabled pair's {a, b, clearance_m, penetration_mm, band}.
static func evaluate(profile: Dictionary, bones: Dictionary) -> Array:
	var posed := {}
	for volume: Dictionary in profile.get("volumes", []):
		var bone: String = volume["attached_bone"]
		if bones.has(bone):
			posed[volume["region_id"]] = pose_volume(volume, bones[bone])
	var out := []
	for pair: Dictionary in profile.get("collision_pairs", []):
		if not pair.get("enabled", true) or not posed.has(pair["a"]) or not posed.has(pair["b"]):
			continue
		var c := clearance(posed[pair["a"]], posed[pair["b"]], _range(pair, "a_range"), _range(pair, "b_range"))
		var b := band(c)
		if pair.get("warning_only", false) and (b == "significant" or b == HARD_BAND):
			b = "warning"
		out.append({"a": pair["a"], "b": pair["b"], "clearance_m": snappedf(c, 0.0001), "penetration_mm": snappedf(maxf(0.0, -c) * 1000.0, 0.1), "band": b})
	return out


## The worst pair and the count per band.
static func summary(results: Array) -> Dictionary:
	var counts := {}
	var worst: Dictionary = {}
	for r: Dictionary in results:
		counts[r["band"]] = int(counts.get(r["band"], 0)) + 1
		if worst.is_empty() or float(r["clearance_m"]) < float(worst["clearance_m"]):
			worst = r
	return {"worst": worst, "bands": counts}


static func band(clearance_m: float) -> String:
	if clearance_m >= NEAR_MARGIN_M:
		return "clear"
	if clearance_m >= 0.0:
		return "near"
	var mm := -clearance_m * 1000.0
	for entry: Array in BANDS:
		if mm <= float(entry[0]):
			return entry[1]
	return HARD_BAND


static func pose_volume(volume: Dictionary, bone: Transform3D) -> Dictionary:
	var out := {"id": volume["region_id"], "shape": volume["shape"], "radius": float(volume["radius"])}
	if volume["shape"] == "capsule":
		out["a"] = bone * _v(volume["a"])
		out["b"] = bone * _v(volume["b"])
	else:
		var polygon := PackedVector2Array()
		for corner: Array in volume["polygon"]:
			polygon.append(Vector2(float(corner[0]), float(corner[1])))
		out["to_local"] = bone.affine_inverse()
		out["polygon"] = polygon
		out["y0"] = float(volume["y0"])
		out["y1"] = float(volume["y1"])
	return out


static func clearance(a: Dictionary, b: Dictionary, a_range := Vector2(0.0, 1.0), b_range := Vector2(0.0, 1.0)) -> float:
	if a["shape"] == "prism" and b["shape"] != "prism":
		return clearance(b, a, b_range, a_range)
	var radii := float(a["radius"]) + float(b["radius"])
	var p: Vector3 = (a["a"] as Vector3).lerp(a["b"], a_range.x)
	var q: Vector3 = (a["a"] as Vector3).lerp(a["b"], a_range.y)
	if b["shape"] == "capsule":
		var r: Vector3 = (b["a"] as Vector3).lerp(b["b"], b_range.x)
		var s: Vector3 = (b["a"] as Vector3).lerp(b["b"], b_range.y)
		return segment_segment(p, q, r, s) - radii
	return segment_prism(p, q, b) - radii


## Shortest distance between segments (Ericson, Real-Time Collision Detection 5.1.9).
static func segment_segment(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		return r.length()
	if a <= 1e-12:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-12:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 1e-12 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return ((p1 + d1 * s) - (p2 + d2 * t)).length()


## Distance from a bone-local point to the solid prism polygon (x, z) x [y0, y1]: the product of two convex sets, so the
## closest point is the 2D closest point with y clamped.
static func point_prism_local(p: Vector3, polygon: PackedVector2Array, y0: float, y1: float) -> float:
	var flat := Vector2(p.x, p.z)
	var d2 := 0.0 if _inside(flat, polygon) else _edge_distance(flat, polygon)
	var dy := y0 - p.y if p.y < y0 else (p.y - y1 if p.y > y1 else 0.0)
	return Vector2(d2, dy).length()


## Segment to a posed prism; the distance is convex along the segment, so a ternary search is exact to tolerance.
static func segment_prism(p: Vector3, q: Vector3, prism: Dictionary) -> float:
	var to_local: Transform3D = prism["to_local"]
	var a := to_local * p
	var b := to_local * q
	var polygon: PackedVector2Array = prism["polygon"]
	var y0: float = prism["y0"]
	var y1: float = prism["y1"]
	var lo := 0.0
	var hi := 1.0
	for _i in PRISM_SEARCH_ITERATIONS:
		var m1 := lo + (hi - lo) / 3.0
		var m2 := hi - (hi - lo) / 3.0
		if point_prism_local(a.lerp(b, m1), polygon, y0, y1) <= point_prism_local(a.lerp(b, m2), polygon, y0, y1):
			hi = m2
		else:
			lo = m1
	return minf(point_prism_local(a.lerp(b, (lo + hi) * 0.5), polygon, y0, y1), minf(point_prism_local(a, polygon, y0, y1), point_prism_local(b, polygon, y0, y1)))


## Inside a counter-clockwise convex polygon.
static func _inside(p: Vector2, polygon: PackedVector2Array) -> bool:
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		if (b - a).cross(p - a) < 0.0:
			return false
	return true


static func _edge_distance(p: Vector2, polygon: PackedVector2Array) -> float:
	var best := INF
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0) if ab.length_squared() > 1e-18 else 0.0
		best = minf(best, p.distance_to(a + ab * t))
	return best


## ---------------------------------------------------------------- joints (ArtAnatomyProfile)

## Twist (radians, signed) of a rotation about local +Y, and its swing as a rotation vector (radians).
static func swing_twist(q: Quaternion) -> Array:
	var r := q.normalized()
	if r.w < 0.0:
		r = -r
	var twist := Quaternion(0.0, r.y, 0.0, r.w).normalized() if absf(r.y) + absf(r.w) > 1e-12 else Quaternion.IDENTITY
	var swing := (r * twist.inverse()).normalized()
	var swing_vec := swing.get_axis() * swing.get_angle() if swing.get_angle() > 1e-9 else Vector3.ZERO
	var angle := twist.get_angle() * signf(twist.y)
	if angle > PI:
		angle -= TAU
	elif angle < -PI:
		angle += TAU
	return [angle, swing_vec]


## The hinge-constrained arm for a candidate elbow (ART-ANATOMY-001): the humerus oriented so the elbow bends purely about its
## calibrated hinge (`elbow_X.hinge_axis`, upper-arm local), the forearm rolled about its own axis (pronation, within the
## profile's hard roll range) to take the grip's axial turn, the hand on its grip. Returns the three world bases and the
## readings. `parent` is the shoulder (clavicle) bone's world basis; `rest_*` the bones' local rest bases.
static func hinge_chain(profile: Dictionary, side: String, s: Vector3, e: Vector3, w: Vector3, hand: Basis, parent: Basis, rest_u: Basis, rest_f: Basis, rest_h: Basis) -> Dictionary:
	var joints: Dictionary = profile["joints"]
	var hinge := _v(joints["elbow_" + side]["hinge_axis"]).normalized()
	var y_u := (e - s).normalized()
	var y_f := (w - e).normalized()
	var normal := y_u.cross(y_f)
	if normal.length() < 1e-6:
		normal = (parent * rest_u * hinge).normalized()
	normal = normal.normalized()
	var local := Basis(hinge, Vector3.UP, hinge.cross(Vector3.UP)).orthonormalized()
	var world := Basis(normal, y_u, normal.cross(y_u)).orthonormalized()
	var upper := world * local.transposed()
	var flex := atan2(y_u.cross(y_f).dot(normal), y_u.dot(y_f))
	var rest_flex := atan2((rest_u * rest_f * Vector3.UP).cross(Vector3.UP).dot(hinge), Vector3.UP.dot(rest_f * Vector3.UP))
	var fore0 := Basis(normal, flex - rest_flex) * upper * rest_f
	var limits: Array = profile["joint_constraints"]["forearm"]["roll"]["hard"]
	var wrist0 := swing_twist(((fore0 * rest_h).inverse() * hand).get_rotation_quaternion())
	var roll := clampf(float(wrist0[0]), deg_to_rad(float(limits[0])), deg_to_rad(float(limits[1])))
	var fore := fore0 * Basis(Vector3.UP, roll)
	return {"upper": upper, "fore": fore, "readings": arm_readings(profile, side, parent, upper, fore, hand, rest_u, rest_f, rest_h)}


## Relationship-level readings for one arm in its calibrated anatomical frames (degrees) with verdicts.
static func arm_readings(profile: Dictionary, side: String, parent: Basis, upper: Basis, fore: Basis, hand: Basis, rest_u: Basis, rest_f: Basis, rest_h: Basis) -> Dictionary:
	var joints: Dictionary = profile["joints"]
	var limits: Dictionary = profile["joint_constraints"]
	var hinge := upper * _v(joints["elbow_" + side]["hinge_axis"]).normalized()
	var y_u := upper * Vector3.UP
	var y_f := fore * Vector3.UP
	var flex := rad_to_deg(atan2(y_u.cross(y_f).dot(hinge), y_u.dot(y_f)))
	var normal := y_u.cross(y_f)
	var plane_error := rad_to_deg(normal.normalized().angle_to(hinge)) if normal.length() > sin(deg_to_rad(10.0)) else 0.0
	var rest_flex := atan2((rest_u * rest_f * Vector3.UP).cross(Vector3.UP).dot(_v(joints["elbow_" + side]["hinge_axis"]).normalized()), Vector3.UP.dot(rest_f * Vector3.UP))
	var fore0 := Basis(hinge, deg_to_rad(flex) - rest_flex) * upper * rest_f
	var roll := rad_to_deg(float(swing_twist((fore0.inverse() * fore).get_rotation_quaternion())[0]))
	var wrist := swing_twist(((fore * rest_h).inverse() * hand).get_rotation_quaternion())
	var wrist_vec: Vector3 = wrist[1]
	var wrist_flex := rad_to_deg(wrist_vec.dot(_v(joints["wrist_" + side]["flexion_axis"]).normalized()))
	var wrist_dev := rad_to_deg(wrist_vec.dot(_v(joints["wrist_" + side]["deviation_axis"]).normalized()))
	var shoulder := swing_twist(((parent * rest_u).inverse() * upper).get_rotation_quaternion())
	var out := {
		"shoulder_twist_deg": snappedf(rad_to_deg(float(shoulder[0])), 0.1), "shoulder_swing_deg": snappedf(rad_to_deg((shoulder[1] as Vector3).length()), 0.1),
		"elbow_flexion_deg": snappedf(flex, 0.1), "elbow_bend_plane_error_deg": snappedf(plane_error, 0.1),
		"forearm_roll_deg": snappedf(roll, 0.1), "wrist_flexion_deg": snappedf(wrist_flex, 0.1), "wrist_deviation_deg": snappedf(wrist_dev, 0.1),
		"wrist_residual_twist_deg": snappedf(rad_to_deg(float(wrist[0])), 0.1),
	}
	var checks := {
		"shoulder_twist_valid": _range_verdict(out["shoulder_twist_deg"], limits["shoulder"]["twist"]),
		"elbow_flexion_valid": _range_verdict(out["elbow_flexion_deg"], limits["elbow"]["flexion"]),
		"elbow_bend_plane_valid": _max_verdict(out["elbow_bend_plane_error_deg"], limits["elbow"]["bend_plane_error"]),
		"forearm_roll_valid": _range_verdict(out["forearm_roll_deg"], limits["forearm"]["roll"]),
		"wrist_flexion_valid": _range_verdict(out["wrist_flexion_deg"], limits["wrist"]["flexion"]),
		"wrist_deviation_valid": _range_verdict(out["wrist_deviation_deg"], limits["wrist"]["deviation"]),
		"wrist_residual_twist_valid": _max_verdict(out["wrist_residual_twist_deg"], limits["wrist"]["residual_twist"]),
	}
	out["checks"] = checks
	var verdict := "PASS"
	for value: String in checks.values():
		if value == "FAIL":
			verdict = "FAIL"
		elif value == "WARNING" and verdict == "PASS":
			verdict = "WARNING"
	out["verdict"] = verdict
	return out


## PASS inside the preferred range, WARNING outside it (or within 10% of the hard range of its edge), FAIL outside hard.
static func _range_verdict(value: float, limit: Dictionary) -> String:
	var hard: Array = limit["hard"]
	var preferred: Array = limit["preferred"]
	if value < float(hard[0]) or value > float(hard[1]):
		return "FAIL"
	var margin := 0.1 * (float(hard[1]) - float(hard[0]))
	if value < float(preferred[0]) or value > float(preferred[1]) or value < float(hard[0]) + margin or value > float(hard[1]) - margin:
		return "WARNING"
	return "PASS"


static func _max_verdict(value: float, limit: Dictionary) -> String:
	var magnitude := absf(value)
	if magnitude > float(limit["hard"]):
		return "FAIL"
	return "WARNING" if magnitude > float(limit["preferred"]) else "PASS"


static func _v(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


static func _range(pair: Dictionary, key: String) -> Vector2:
	var values: Array = pair.get(key, [0.0, 1.0])
	return Vector2(float(values[0]), float(values[1]))
