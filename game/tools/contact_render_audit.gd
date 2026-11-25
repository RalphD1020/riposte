class_name ContactRenderAudit
extends RefCounted

## WEAPON-PATH-CONSISTENCY (WEAPON-PATH-004 Stage 5, CONTACT-PRESENTATION-001): how a solved sword contact reads on the
## drawn swords at one rendered instant. Readings only — nothing here decides or moves anything. Tools only, never the
## game.
##
## Every comparison is anchored on the solver's own manifold point: its pair names each side's feature (blade or guard
## root), its fraction places a blade's centreline witness and the guard root's nearest centreline point a guard's (a
## guard reads fraction 0), at the poses drawn this tick; its own normal and that feature's radius (blade or crossguard)
## give the surface witness. The drawn side is
## each sword's `WeaponPoseEvaluator` at the same material location (along the blade, and across the bar on a guard).
## The visible contact is a declared approximation (the swords are never moved for it), so these are measurements:
##
## - `witness_m` / `witness_px`: per sword, the drawn surface point against the solver's surface witness lifted to the
##   drawn station's height (the station/foreshortening error; 3D m, screen px), the worse of the two swords.
## - `steel_gap_m` / `steel_gap_px`: the drawn steel features' closest distance (blade capsules; a blade against the
##   filled guard-root triangle), negative overlap; and its screen size.
## - `station_m`: blade on blade, how far the drawn swords' closest place is from the solver's stations along each
##   blade; omitted (`ambiguous`) where the blades are within `PARALLEL_SINE` of parallel, whose closest place is not
##   well determined.
## - `onset_m` / `onset_px`: on a contact's first tick, how far the drawn swords moved at the solver's stations between
##   the last frame drawn before it and the first frame of it, at the same physical state (expected 0).
## - `dz_m`: the drawn swords' vertical separation at their contact stations (the projection's own mismatch).

const FIELDS := ["witness_px", "witness_m", "steel_gap_m", "steel_gap_px", "station_m", "onset_m", "onset_px", "dz_m"]
## Below this |sin| between the two blades the closest station is reported ambiguous.
const PARALLEL_SINE := 0.2
const TRIANGLE_SAMPLES := 64


## The world transforms of both drawn swords (pommel frame), for a later `onset`.
static func weapons(presenter: MatchPresenter) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for slot in 2:
		var proxy := presenter.fighter_proxy(slot)
		out.append(proxy.visual_root().global_transform * proxy.weapon_pose().weapon)
	return out


## Readings for manifold point `point` of `state`'s contact, drawn now through `camera`; `geometry` is scratch.
static func measure(presenter: MatchPresenter, state: MatchState, rules: DuelRules, camera: Camera3D, point: int, geometry: SwordContactGeometry) -> Dictionary:
	var contact := state.blade_contact
	var pair := contact.pair[point]
	var out := {"pair": pair, "contact_id": contact.contact_id[point], "age": contact.age[point],
		"fraction_a": contact.fraction_a[point], "fraction_b": contact.fraction_b[point]}
	var poses: Array[BladePose] = []
	for slot in 2:
		poses.append(WeaponKinematics.pose_of(state.fighter(slot), rules.combatant(slot), BladePose.new()))
		out["theta_%d" % slot] = state.fighter(slot).weapon.angle
		out["phase_%d" % slot] = int(state.fighter(slot).weapon.phase)
	var a := poses[0]
	var b := poses[1]
	var on_guard := [pair == SwordContactSet.PAIR_GUARD_ON_BLADE, pair == SwordContactSet.PAIR_BLADE_ON_GUARD]
	var normal := Vector2(contact.point_nx[point], contact.point_ny[point])
	var solver := Vector2(contact.point_x[point], contact.point_y[point])
	## Each sword's centreline witness at the poses drawn this tick: a blade at the solver's own fraction, a guard at its
	## root's nearest point to the solver's point (a guard reads fraction 0).
	var centre: Array[Vector2] = []
	for slot in 2:
		var weapon := rules.combatant(slot).weapon
		var pose := poses[slot]
		if on_guard[slot]:
			centre.append(_on_guard_root(pose, weapon, solver, geometry))
		else:
			var fraction := contact.fraction_a[point] if slot == 0 else contact.fraction_b[point]
			var along := ContactPresentation.along(fraction, weapon)
			centre.append(Vector2(pose.point_x(along), pose.point_y(along)))
	out["feature"] = true
	var plane := _plane_axes()
	var drawn_centre: Array[Vector3] = []
	var drawn_surface: Array[Vector3] = []
	var witness_m := 0.0
	var witness_px := 0.0
	for slot in 2:
		var weapon := rules.combatant(slot).weapon
		var radius := weapon.crossguard_radius if on_guard[slot] else weapon.blade_radius
		var pose := poses[slot]
		var offset := centre[slot] - Vector2(pose.origin_x, pose.origin_y)
		var along := offset.dot(Vector2(pose.ux, pose.uy))
		var across := offset.dot(Vector2(-pose.uy, pose.ux))
		var proxy := presenter.fighter_proxy(slot)
		var into_world := proxy.visual_root().global_transform
		var drawn := proxy.weapon_pose().weapon
		## The sword frame's crossguard axis against the plane's perp(û), so a guard point keeps its side of the bar.
		var side := signf(_to_plane(into_world.basis * drawn.basis.x, plane).dot(Vector2(-pose.uy, pose.ux)))
		var here := into_world * (drawn * Vector3(across * side if on_guard[slot] else 0.0, 0.0, along))
		## Toward the other sword: +n for b, −n for a, made perpendicular to the drawn blade.
		var toward := _to_world(-normal if slot == 0 else normal, plane)
		var axis := (into_world.basis * drawn.basis.z).normalized()
		toward = (toward - axis * toward.dot(axis)).normalized()
		var surface := here + toward * radius
		var witness_2d := centre[slot] + (-normal if slot == 0 else normal) * radius
		var authoritative := ArenaTransform.to_world(witness_2d.x, witness_2d.y, surface.y)
		witness_m = maxf(witness_m, surface.distance_to(authoritative))
		witness_px = maxf(witness_px, camera.unproject_position(surface).distance_to(camera.unproject_position(authoritative)))
		drawn_centre.append(here)
		drawn_surface.append(surface)
	out["witness_m"] = witness_m
	out["witness_px"] = witness_px
	out["dz_m"] = absf(drawn_centre[0].y - drawn_centre[1].y)
	var gap := _steel_gap(presenter, rules, pair)
	out["steel_gap_m"] = gap[0]
	out["steel_gap_px"] = 0.0 if gap[0] <= 0.0 else camera.unproject_position(gap[1]).distance_to(camera.unproject_position(gap[2]))
	if pair == SwordContactSet.PAIR_BLADES:
		var sine := absf(a.ux * b.uy - a.uy * b.ux)
		out["ambiguous"] = sine < PARALLEL_SINE
		if sine >= PARALLEL_SINE:
			var steel := _steel(presenter, rules)
			var closest := closest_on_segments(steel[0], steel[1], steel[2], steel[3])
			var station := 0.0
			for slot in 2:
				var weapon := rules.combatant(slot).weapon
				var pose := poses[slot]
				var solver_along := (centre[slot] - Vector2(pose.origin_x, pose.origin_y)).dot(Vector2(pose.ux, pose.uy))
				var drawn_along := lerpf(weapon.guard_root_apex_radius(), weapon.tip_radius, closest[1 + slot])
				station = maxf(station, absf(drawn_along - solver_along))
			out["station_m"] = station
	return out


## How far the drawn swords moved at the solver's stations between `before` (both swords' world transforms on the
## last frame drawn before this contact began) and now, at the same physical state: 3D m and screen px.
static func onset(presenter: MatchPresenter, state: MatchState, rules: DuelRules, camera: Camera3D, point: int, before: Array[Transform3D]) -> Dictionary:
	var contact := state.blade_contact
	var fractions := [contact.fraction_a[point], contact.fraction_b[point]]
	var now := weapons(presenter)
	var worst_m := 0.0
	var worst_px := 0.0
	for slot in 2:
		var station := Vector3(0.0, 0.0, ContactPresentation.along(fractions[slot], rules.combatant(slot).weapon))
		var was := before[slot] * station
		var is_now := now[slot] * station
		worst_m = maxf(worst_m, was.distance_to(is_now))
		worst_px = maxf(worst_px, camera.unproject_position(was).distance_to(camera.unproject_position(is_now)))
	return {"onset_m": worst_m, "onset_px": worst_px}


## The nearest point to `at` on the planar guard-root triangle's centreline edges (`SwordContactGeometry.place_guard`).
static func _on_guard_root(pose: BladePose, weapon: WeaponDefinition, at: Vector2, geometry: SwordContactGeometry) -> Vector2:
	var root := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	if geometry == null or not SwordContactGeometry.place_guard(pose.origin_x, pose.origin_y, pose.ux, pose.uy, weapon, root):
		return Vector2(pose.point_x(weapon.crossguard_centre_radius), pose.point_y(weapon.crossguard_centre_radius))
	var corners := [Vector2(root[0], root[1]), Vector2(root[2], root[3]), Vector2(root[4], root[5])]
	var best: Vector2 = corners[0]
	var nearest := INF
	for edge: Array in [[corners[0], corners[1]], [corners[0], corners[2]], [corners[1], corners[2]]]:
		var from: Vector2 = edge[0]
		var span: Vector2 = (edge[1] as Vector2) - from
		var on := from + span * clampf((at - from).dot(span) / maxf(span.length_squared(), 1.0e-18), 0.0, 1.0)
		if on.distance_to(at) < nearest:
			nearest = on.distance_to(at)
			best = on
	return best


## Both drawn blades' steel axes (guard-root apex → point), world: [a from, a to, b from, b to].
static func _steel(presenter: MatchPresenter, rules: DuelRules) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for slot in 2:
		var proxy := presenter.fighter_proxy(slot)
		var into_world := proxy.visual_root().global_transform
		var pose := proxy.weapon_pose()
		out.append(into_world * pose.station(rules.combatant(slot).weapon.guard_root_apex_radius()))
		out.append(into_world * pose.tip())
	return out


## The drawn steel features' distance for `pair`: [surface gap, closest surface point on one, on the other].
static func _steel_gap(presenter: MatchPresenter, rules: DuelRules, pair: int) -> Array:
	var steel := _steel(presenter, rules)
	if pair == SwordContactSet.PAIR_BLADES:
		var closest := closest_on_segments(steel[0], steel[1], steel[2], steel[3])
		var on_a := steel[0].lerp(steel[1], closest[1])
		var on_b := steel[2].lerp(steel[3], closest[2])
		var gap := closest[0] - rules.combatant(0).weapon.blade_radius - rules.combatant(1).weapon.blade_radius
		return [gap, on_a + (on_b - on_a).normalized() * rules.combatant(0).weapon.blade_radius, on_b + (on_a - on_b).normalized() * rules.combatant(1).weapon.blade_radius]
	var guard_slot := 1 if pair == SwordContactSet.PAIR_BLADE_ON_GUARD else 0
	var blade_slot := 1 - guard_slot
	var proxy := presenter.fighter_proxy(guard_slot)
	var into_world := proxy.visual_root().global_transform
	var corners := proxy.weapon_pose().guard_root_corners()
	var triangle := [into_world * corners[0], into_world * corners[1], into_world * corners[2]]
	var from := steel[blade_slot * 2]
	var to := steel[blade_slot * 2 + 1]
	var best := INF
	var on_blade := from
	var on_guard := from
	for index in TRIANGLE_SAMPLES + 1:
		var at := from.lerp(to, float(index) / float(TRIANGLE_SAMPLES))
		var near := _closest_on_triangle(at, triangle[0], triangle[1], triangle[2])
		var distance := at.distance_to(near)
		if distance < best:
			best = distance
			on_blade = at
			on_guard = near
	var radii := rules.combatant(blade_slot).weapon.blade_radius + rules.combatant(guard_slot).weapon.crossguard_radius
	var direction := (on_guard - on_blade).normalized()
	return [best - radii, on_blade + direction * rules.combatant(blade_slot).weapon.blade_radius, on_guard - direction * rules.combatant(guard_slot).weapon.crossguard_radius]


## The nearest point of the filled triangle `p0 p1 p2` to `at`.
static func _closest_on_triangle(at: Vector3, p0: Vector3, p1: Vector3, p2: Vector3) -> Vector3:
	var normal := (p1 - p0).cross(p2 - p0)
	if normal.length_squared() > 1.0e-18:
		var unit := normal.normalized()
		var on_plane := at - unit * (at - p0).dot(unit)
		var inside := true
		for edge: Array in [[p0, p1], [p1, p2], [p2, p0]]:
			if ((edge[1] as Vector3) - (edge[0] as Vector3)).cross(on_plane - (edge[0] as Vector3)).dot(normal) < 0.0:
				inside = false
		if inside:
			return on_plane
	var best := p0
	var nearest := INF
	for edge: Array in [[p0, p1], [p1, p2], [p2, p0]]:
		var on := _closest_point_on_segment(at, edge[0], edge[1])
		if at.distance_to(on) < nearest:
			nearest = at.distance_to(on)
			best = on
	return best


## [distance, parameter on the first segment, parameter on the second] between segments p1→q1 and p2→q2.
static func closest_on_segments(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> PackedFloat64Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1.0e-12 and e <= 1.0e-12:
		return PackedFloat64Array([r.length(), 0.0, 0.0])
	if a <= 1.0e-12:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1.0e-12:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = 0.0 if denom <= 1.0e-12 else clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return PackedFloat64Array([(p1 + d1 * s).distance_to(p2 + d2 * t), s, t])


static func _closest_point_on_segment(point: Vector3, from: Vector3, to: Vector3) -> Vector3:
	var span := to - from
	var length_squared := span.length_squared()
	if length_squared <= 1.0e-12:
		return from
	return from + span * clampf((point - from).dot(span) / length_squared, 0.0, 1.0)


## The world directions of the arena plane's +x and +y (`ArenaTransform`).
static func _plane_axes() -> Array[Vector3]:
	var zero := ArenaTransform.to_world(0.0, 0.0, 0.0)
	return [ArenaTransform.to_world(1.0, 0.0, 0.0) - zero, ArenaTransform.to_world(0.0, 1.0, 0.0) - zero]


static func _to_world(v: Vector2, plane: Array[Vector3]) -> Vector3:
	return plane[0] * v.x + plane[1] * v.y


static func _to_plane(v: Vector3, plane: Array[Vector3]) -> Vector2:
	return Vector2(v.dot(plane[0]) / plane[0].length_squared(), v.dot(plane[1]) / plane[1].length_squared())
