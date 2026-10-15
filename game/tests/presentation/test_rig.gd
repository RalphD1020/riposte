extends TestCase

## PRES-RIG: the authored Wolf follows the authoritative sword. Rotating the
## simulated blade through its whole legal arc (±135°) keeps both hands on the
## grip, never flips an elbow, and never moves the blade the simulation posed.
## Also proves the asset contract on the imported scenes and that skins swap
## without touching definitions.
##
## Implements: /spec/invariants.md#pres-kit-001
## See also: /docs/reference/godot.md

## A hand may sit this far from its grip marker (m): block hands are ~7 cm.
const GRIP_TOLERANCE := 0.035
const ARC_STEP_DEGREES := 15.0
## Bones `_settle` reads back from the modifier stack.
const SETTLED_BONES := 9
## IK may not stretch a segment by more than this (m).
const STRETCH_TOLERANCE := 0.01
## The most an elbow may move per degree of sword travel (m). Coarser sweeps
## scale with the angle step; a pop in the 1° release zone still fails.
const ELBOW_STEP_PER_DEGREE := 0.04
const STRAIGHT_ARM_SLACK := 0.02

var _rules: DuelRules


func _init() -> void:
	suite_name = "PRES-RIG"
	_rules = StandardDuelRules.create()


func _proxy(fighter_skin: StringName = &"") -> FighterPresentation3D:
	var catalog := RiposteKits.build_catalog()
	var skins: Array[StringName] = [fighter_skin, &""]
	var kits := DuelKits.resolve(catalog, _rules, skins)
	var proxy := FighterPresentation3D.create(0, DuelSide.Id.LIGHT_SOUTH, kits.combatant(0), _rules.combatant(0).fighter.push_radius, _rules.combatant(0))
	(Engine.get_main_loop() as SceneTree).root.add_child(proxy)
	return proxy


## The lift field sampled on the authoritative carriage at `angle`, as the
## proxy samples it.
func _lift(field: CombatPresentationField, angle: float, phase: CombatPhase.Id = CombatPhase.Id.NEUTRAL, progress: float = 1.0, charge: float = 0.0, swing_charge: float = 0.0, blade_height: float = 1.0, cut_dir: float = 1.0, committed: bool = false) -> CombatPresentationField:
	var planar := WeaponKinematics.pose_at(0.0, 0.0, 0.0, angle, _rules.combatant(0), BladePose.new())
	field.carriage_radius = _rules.combatant(0).handling.carriage_radius
	return field.sample(angle, planar.carriage_y, planar.carriage_x, phase, progress, charge, swing_charge, blade_height, cut_dir, committed)


func _row(angle: float, phase: CombatPhase.Id = CombatPhase.Id.NEUTRAL, progress: float = 1.0, charge: float = 0.0, swing_charge: float = 0.0) -> PresentationFighter:
	var row := PresentationFighter.new()
	row.health = 100.0
	row.weapon_angle = angle
	row.phase = phase
	row.swing_progress = progress
	row.charge = charge
	row.swing_charge = swing_charge
	return row


## Pose the proxy and run the skeleton's modifier stack (chest follow, IK)
## once, reading the result where Godot exposes it: inside `skeleton_updated`.
## Modifier output is applied for the update and reverted after it.
func _settle(proxy: FighterPresentation3D, angle: float, row: PresentationFighter = null, during: Callable = Callable()) -> Dictionary:
	var posed := row if row != null else _row(angle)
	## The opponent straight ahead: no heading lag for the head to look into.
	posed.target_bearing = PI * 0.5
	## A long first step lets any phase-change carry offset decay, so the
	## pose read is the field's own answer for this state.
	proxy.apply_pose(Vector3.ZERO, PI * 0.5, angle, posed, 1.0)
	proxy.apply_pose(Vector3.ZERO, PI * 0.5, angle, posed, 1.0 / 60.0)
	var skeleton := proxy.rig().skeleton()
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var seen := {}
	var capture := func() -> void:
		for bone_name: String in ["Hand.R", "Hand.L", "Forearm.R", "Forearm.L", "UpperArm.R", "UpperArm.L", "Chest", "Spine", "Hips"]:
			seen[bone_name] = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name))
		## Measurements that read the skeleton belong here, while the modifier
		## output (body support, IK) is live — after the update it is reverted.
		if during.is_valid():
			during.call()
	skeleton.skeleton_updated.connect(capture)
	skeleton.advance(1.0 / 60.0)
	await await_frames(1)
	skeleton.skeleton_updated.disconnect(capture)
	return seen


static func _palm(pose: Transform3D) -> Vector3:
	return pose.origin + pose.basis.y.normalized() * SwordRig3D.HAND_LENGTH


func test_the_authored_kits_load_with_their_contract() -> void:
	var catalog := RiposteKits.build_catalog()
	var fighter := catalog.resolve(ContentIds.FIGHTER_DUELIST, PresentationKit.PRIMITIVE_FIGHTER)
	var weapon := catalog.resolve(ContentIds.WEAPON_BASTARD_SWORD, PresentationKit.PRIMITIVE_BLADE)
	var arena := catalog.resolve(ContentIds.ARENA_STANDARD, PresentationKit.PRIMITIVE_ARENA)
	assert_true(fighter.scene != null and weapon.scene != null and arena.scene != null, "all three identities are authored")
	assert_eq(fighter.unknown_clip_semantics().size(), 0, "Wolf maps only semantics the proxy asks for")
	assert_eq(fighter.animation_clips.size(), PresentationKit.ANIM_SEMANTICS.size(), "and every one of them")
	var model := fighter.scene.instantiate()
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for semantic: Variant in fighter.animation_clips:
		assert_true(player.has_animation(StringName(str(fighter.animation_clips[semantic]))), "%s has its clip" % semantic)
	for target in fighter.color_targets:
		assert_true(model.find_child(target, true, false) is MeshInstance3D, "side accent %s exists" % target)
	model.free()
	assert_true(weapon.has_audio(PresentationKit.CUE_BLADE_STRONG), "an authored kit missing a cue is filled from the factory, never silent")
	var sword := weapon.scene.instantiate()
	for marker: String in ["GripDominant", "GripOffhand", "TrailStart", "Tip"]:
		assert_true(sword.find_child(marker, true, false) is Node3D, "weapon marker %s exists" % marker)
	var tip := SwordRig3D._marker(sword, &"Tip", 0.0)
	assert_near(tip.z, _rules.combatant(0).weapon.tip_radius, 1e-3, "the authored tip is exactly the rules' reach")
	assert_near(SwordRig3D._marker(sword, &"TrailStart", 0.0).z, _rules.combatant(0).weapon.blade_base_radius, 1e-3, "and the blade starts at the duelist's grip")
	sword.free()


## A right-handed hand-and-a-half grip, both hands on the handle: pommel <
## off hand < dominant hand < guard along the blade, the dominant hand's top
## just under the guard, the off hand's bottom just above the pommel, the two
## fists apart — read from the authored sword and held equal to the rules. The
## grip targets are fixed weapon-local points: they never swap, slide or
## bunch anywhere in the arc, on either side.
func test_the_grip_is_a_right_handed_hand_and_a_half_grip() -> void:
	var sword := RiposteKits.build_catalog().resolve(ContentIds.WEAPON_BASTARD_SWORD, PresentationKit.PRIMITIVE_BLADE).scene.instantiate()
	var offhand := SwordRig3D._marker(sword, &"GripOffhand", 0.0).z
	var dominant := SwordRig3D._marker(sword, &"GripDominant", 0.0).z
	sword.free()
	var hand := _rules.combatant(0).fighter.hand_radius
	assert_near(offhand, _rules.combatant(0).weapon.offhand_grip_radius, 1e-3, "the authored off hand is the rules' (%.4f m)" % offhand)
	assert_near(dominant, _rules.combatant(0).weapon.dominant_grip_radius, 1e-3, "and so is the dominant hand (%.4f m)" % dominant)
	assert_true(PhysicalBaseline.POMMEL_SHOULDER_M <= offhand - hand and dominant + hand <= PhysicalBaseline.GUARD_UNDERSIDE_M and PhysicalBaseline.GUARD_UNDERSIDE_M < _rules.combatant(0).weapon.blade_base_radius, "pommel < off hand < dominant hand < guard, both on the handle")
	assert_between(PhysicalBaseline.GUARD_UNDERSIDE_M - (dominant + hand), 0.005, 0.015, "the dominant hand sits just under the guard")
	assert_between(offhand - hand - PhysicalBaseline.POMMEL_SHOULDER_M, 0.0, 0.01, "the off hand just above the pommel")
	assert_true(dominant - offhand > 2.0 * hand + 0.03, "and the fists are apart, not bunched (%.3f m between centres)" % (dominant - offhand))
	var proxy := _proxy()
	var rest: Array[Vector3] = [proxy.rig().grip_target(0).position, proxy.rig().grip_target(1).position]
	assert_true(rest[0].z > rest[1].z, "fixture: the dominant (right) target is the guard-side one")
	for degrees: float in [-135.0, -45.0, 0.0, 45.0, 135.0]:
		var angle := deg_to_rad(degrees)
		for phase: CombatPhase.Id in [CombatPhase.Id.NEUTRAL, CombatPhase.Id.CHARGING, CombatPhase.Id.ACTIVE_THREAT]:
			proxy.apply_pose(Vector3.ZERO, 0.0, angle, _row(angle, phase, 0.5, 0.5, 0.5), 1.0 / 60.0)
			for index in 2:
				assert_true(proxy.rig().grip_target(index).position.is_equal_approx(rest[index]), "grip %d is fixed on the sword at %.0f° (phase %d)" % [index, degrees, phase])
	proxy.queue_free()


func test_hands_stay_on_the_grip_through_the_whole_legal_arc() -> void:
	var proxy := _proxy()
	assert_true(proxy.rig() != null and proxy.rig().is_bound(), "precondition: the authored rig is bound to the sword")
	var limit := rad_to_deg(_rules.combatant(0).weapon.guard_limit)
	var worst := 0.0
	var flips := 0
	var trace := PackedStringArray()
	var degrees := -limit
	while degrees <= limit + 1e-6:
		var angle := deg_to_rad(degrees)
		var pose: Dictionary = await _settle(proxy, angle)
		assert_eq(pose.size(), SETTLED_BONES, "precondition: the modifier stack ran at %.0f°" % degrees)
		var blade := proxy.blade_points()
		for index in 2:
			var target := proxy.rig().grip_target(index).global_position
			var palm := _palm(pose["Hand.R" if index == 0 else "Hand.L"])
			worst = maxf(worst, palm.distance_to(target))
			var wrist: Vector3 = (pose["Hand.R" if index == 0 else "Hand.L"] as Transform3D).origin
			trace.append("%.0f/%d:%.3f w%.3f" % [degrees, index, palm.distance_to(target), wrist.distance_to(target)])
		## No elbow ever folds behind the chest. (In a bladed stance the arm
		## reaching across may pass the chest's centreline; that is the reach,
		## not an inversion.)
		var chest: Transform3D = pose["Chest"]
		var right_elbow: Vector3 = chest.affine_inverse() * (pose["Forearm.R"] as Transform3D).origin
		var left_elbow: Vector3 = chest.affine_inverse() * (pose["Forearm.L"] as Transform3D).origin
		if right_elbow.z < -ELBOW_HIDDEN_DEPTH or left_elbow.z < -ELBOW_HIDDEN_DEPTH:
			flips += 1
		## The hands' sword is the authoritative one: its carriage on the
		## orbit, its yaw θ (WEAPON-ORBIT-005).
		var hands := proxy.carriage().carriage_point
		var carriage := proxy.authoritative_carriage()
		assert_true(Vector2(hands.x - carriage.x, hands.z - carriage.z).length() < 1e-6, "the drawn carriage is the authoritative one at %.0f°" % degrees)
		var origin := proxy.visual_root().global_transform.affine_inverse()
		var drawn_hilt := origin * blade[0]
		var drawn_tip := origin * blade[1]
		assert_near(angle_difference(angle, atan2(drawn_tip.x - drawn_hilt.x, drawn_tip.z - drawn_hilt.z)), 0.0, 1e-5, "and the drawn yaw is θ at %.0f°" % degrees)
		degrees += ARC_STEP_DEGREES
	assert_true(worst < GRIP_TOLERANCE, "hands stay on the grip across ±%.0f° (worst %.3f m: %s)" % [limit, worst, " ".join(trace)])
	assert_eq(flips, 0, "and no elbow ever inverts")
	proxy.queue_free()


## The hilt track's landmarks and the Long Guard corridor's edges, held by the
## right-lead body: at each, the hands are on the grip, no arm stretches, no
## elbow hides behind the chest, the sword keeps air from its own wielder, and
## the right foot still leads — the legs keep one stance at ±135° as at 0°.
## Each arm's reach (shoulder → wrist over upper arm + forearm) is reported:
## it is the evidence the track's knots are reviewed against.
const LANDMARK_DEGREES: Array[float] = [-135.0, -80.0, -45.0, -18.0, -15.0, -12.0, 0.0, 12.0, 15.0, 18.0, 45.0, 80.0, 135.0]
const LEAD_FOOT_MIN := 0.06
## LONG-GUARD-GEOMETRY-001: inside the Long Guard corridor the limiting (left)
## arm reads clearly extended; anywhere on the track no arm comes nearer its
## lock than the reserve (shoulder to hand over upper arm + forearm).
const CORRIDOR_DEGREES_RIG := 18.0
const LONG_GUARD_EXTENDED := 0.88
const EXTENSION_RESERVE := 0.965


func test_the_hilt_track_landmarks_are_held_by_the_right_lead_body() -> void:
	var proxy := _proxy()
	var skeleton := proxy.rig().skeleton()
	var profile := _clearance()
	var rest := []
	for arm in 2:
		var bones := proxy.rig().dominant_bones if arm == 0 else proxy.rig().offhand_bones
		var shoulder := skeleton.get_bone_global_rest(skeleton.find_bone(bones[0])).origin
		var elbow := skeleton.get_bone_global_rest(skeleton.find_bone(bones[1])).origin
		var wrist := skeleton.get_bone_global_rest(skeleton.find_bone(bones[2])).origin
		rest.append([shoulder.distance_to(elbow), elbow.distance_to(wrist)])
	var measured := {}
	var measure := func() -> void:
		var into_skeleton := skeleton.global_transform.affine_inverse()
		measured["weapon"] = PoseClearance.weapon_gap(profile, skeleton, into_skeleton * proxy.sword_carriage().global_position, into_skeleton * proxy.blade_points()[1])
		measured["lead"] = _foot_lead(proxy)
	var report := PackedStringArray()
	for degrees: float in LANDMARK_DEGREES:
		var angle := deg_to_rad(degrees)
		measured.clear()
		var pose: Dictionary = await _settle(proxy, angle, null, measure)
		assert_eq(pose.size(), SETTLED_BONES, "fixture: the modifier stack ran at %.0f°" % degrees)
		if pose.size() != SETTLED_BONES or measured.is_empty():
			continue
		var chest: Transform3D = pose["Chest"]
		var reach := PackedFloat64Array()
		for arm in 2:
			var tag := "R" if arm == 0 else "L"
			var shoulder: Vector3 = (pose["UpperArm." + tag] as Transform3D).origin
			var elbow: Vector3 = (pose["Forearm." + tag] as Transform3D).origin
			var wrist: Vector3 = (pose["Hand." + tag] as Transform3D).origin
			var upper: float = rest[arm][0]
			var fore: float = rest[arm][1]
			var stretch := maxf(absf(shoulder.distance_to(elbow) - upper), absf(elbow.distance_to(wrist) - fore))
			assert_true(stretch < STRETCH_TOLERANCE, "%.0f°: the %s arm does not stretch (%.4f m)" % [degrees, tag, stretch])
			var palm := _palm(pose["Hand." + tag])
			var target := proxy.rig().grip_target(arm).global_position
			assert_true(palm.distance_to(target) < GRIP_TOLERANCE, "%.0f°: the %s hand is on its grip (%.3f m)" % [degrees, tag, palm.distance_to(target)])
			assert_true((chest.affine_inverse() * elbow).z > -ELBOW_HIDDEN_DEPTH, "%.0f°: the %s elbow is not behind the chest" % [degrees, tag])
			reach.append(shoulder.distance_to(wrist) / (upper + fore))
		for arm in 2:
			assert_true(reach[arm] <= EXTENSION_RESERVE, "%.0f°: the %s arm keeps its extension reserve (%.3f)" % [degrees, "R" if arm == 0 else "L", reach[arm]])
		if absf(degrees) <= CORRIDOR_DEGREES_RIG:
			assert_true(reach[1] >= LONG_GUARD_EXTENDED, "%.0f°: in Long Guard the limiting left arm reads extended (%.3f)" % [degrees, reach[1]])
		var weapon: float = measured["weapon"]
		var lead: float = measured["lead"]
		assert_true(weapon >= 0.0, "%.0f°: the sword keeps air from its wielder (%.3f m)" % [degrees, weapon])
		assert_true(lead >= LEAD_FOOT_MIN, "%.0f°: the right foot still leads (%.3f m)" % [degrees, lead])
		var hilt := proxy.authoritative_carriage()
		report.append("%+.0f° hilt fwd %.3f lat %+.3f | reach R %.2f L %.2f | sword air %.3f | lead %.3f" % [degrees, hilt.z, hilt.x, reach[0], reach[1], weapon, lead])
	print("HILT-TRACK landmarks (VisualRoot: +z forward, +x left):\n  " + "\n  ".join(report))
	proxy.queue_free()


## The named silhouettes read in threat order on the drawn sword (Phase 10):
## Longpoint reaches farthest toward the opponent, Mid Guard threatens less,
## and the High Load compresses — the point drawn back and raised. Only the
## presentation lift shapes these; the hilt track is frozen (7B.3), so this
## holds the look to the geometry rather than tuning either.
func test_the_silhouettes_read_in_threat_order() -> void:
	var proxy := _proxy()
	var forward := ArenaTransform.direction(PI * 0.5)
	var tips := {}
	for posture: Array in [["longpoint", 0.0, CombatPhase.Id.NEUTRAL, 0.0], ["mid guard", 45.0, CombatPhase.Id.NEUTRAL, 0.0], ["high load", 135.0, CombatPhase.Id.CHARGING, 1.0]]:
		var angle := deg_to_rad(float(posture[1]))
		var row := _row(angle, posture[2] as CombatPhase.Id, 1.0, float(posture[3]))
		row.target_bearing = PI * 0.5
		for _i in 30:
			proxy.apply_pose(Vector3.ZERO, PI * 0.5, angle, row, 1.0 / 60.0)
		tips[posture[0]] = proxy.blade_points()[1]
	var reach := func(name: String) -> float: return (tips[name] as Vector3).dot(forward)
	assert_true(reach.call("longpoint") > reach.call("mid guard"), "Longpoint reaches farther than Mid Guard (%.2f vs %.2f m)" % [reach.call("longpoint"), reach.call("mid guard")])
	assert_true(reach.call("mid guard") > reach.call("high load"), "and Mid Guard farther than the High Load (%.2f vs %.2f m)" % [reach.call("mid guard"), reach.call("high load")])
	assert_true((tips["high load"] as Vector3).y > (tips["longpoint"] as Vector3).y, "the High Load raises the point (%.2f vs %.2f m)" % [(tips["high load"] as Vector3).y, (tips["longpoint"] as Vector3).y])
	proxy.queue_free()



## A real cut from the weapon motor, charged to 0.6: charge → launch → active →
## overswing → recovery → back to guard, as faithful snapshot rows.
func _cut_rows() -> Array[PresentationFighter]:
	var rig := WeaponRig.create(_rules)
	rig.press()
	while rig.fighter.weapon.charge < 0.6 and rig.tick < 240:
		rig.step()
	rig.release()
	var rows: Array[PresentationFighter] = []
	for _i in 200:
		var row := SnapshotProjector._fighter(rig.fighter, rig.opponent, _rules)
		row.target_bearing = PI * 0.5
		rows.append(row)
		if row.phase == CombatPhase.Id.NEUTRAL and rows.size() > 30:
			break
		rig.step()
	return rows


## Draw `rows` on a fresh proxy as the presenter does between snapshots (angle
## and lift inputs interpolated, `MatchPresenter.lift_inputs`), refining every
## tick where the sword turns more than 1° or the phase changes into
## `refine` sub-steps. Returns the worst sub-step "excess" — how much farther
## the drawn point moved than the authoritative one — and where. With
## `legs`, reads the skeleton at every phase change and asserts the stance.
func _sweep(rows: Array[PresentationFighter], refine: int, legs: bool = false) -> Dictionary:
	var proxy := _proxy()
	proxy.animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var tick := 1.0 / 60.0
	proxy.apply_pose(Vector3.ZERO, PI * 0.5, rows[0].weapon_angle, rows[0], 1.0)
	var drawn := proxy.blade_points()[1]
	var held := proxy.authoritative_blade_points()[1]
	var result := {"worst": 0.0, "at": "", "transitions": 0}
	var side := 0.0
	for i in range(1, rows.size()):
		var row := rows[i]
		var changed := row.phase != rows[i - 1].phase
		var steps := refine if changed or absf(angle_difference(rows[i - 1].weapon_angle, row.weapon_angle)) > deg_to_rad(1.0) else 1
		for k in range(1, steps + 1):
			var weight := float(k) / float(steps)
			var angle := lerp_angle(rows[i - 1].weapon_angle, row.weapon_angle, weight)
			var lift := MatchPresenter.lift_inputs(rows[i - 1], row, weight)
			proxy.apply_pose(Vector3.ZERO, PI * 0.5, angle, row, tick / float(steps), 1.0, NAN, lift.x, lift.y)
			proxy.animation_player().advance(tick / float(steps))
			var now_drawn := proxy.blade_points()[1]
			var now_held := proxy.authoritative_blade_points()[1]
			var excess := now_drawn.distance_to(drawn) - now_held.distance_to(held)
			if excess > float(result["worst"]):
				result["worst"] = excess
				result["at"] = "tick %d %s→%s sub %d/%d θ %.1f°" % [i, CombatPhase.Id.keys()[rows[i - 1].phase], CombatPhase.Id.keys()[row.phase], k, steps, rad_to_deg(angle)]
			drawn = now_drawn
			held = now_held
		if changed:
			result["transitions"] = int(result["transitions"]) + 1
		if changed and legs:
			proxy.rig().skeleton().force_update_all_bone_transforms()
			await await_frames(1)
			var name: String = CombatPhase.Id.keys()[row.phase]
			assert_true(_foot_lead(proxy) >= LEAD_FOOT_MIN, "%s: the right foot still leads (%.3f m)" % [name, _foot_lead(proxy)])
			var skeleton := proxy.rig().skeleton()
			var into_proxy := proxy.global_transform.affine_inverse() * skeleton.global_transform
			var right := into_proxy * skeleton.get_bone_global_pose(skeleton.find_bone("Foot.R")).origin
			var left := into_proxy * skeleton.get_bone_global_pose(skeleton.find_bone("Foot.L")).origin
			var across := signf(right.x - left.x)
			if side == 0.0:
				side = across
			assert_eq(across, side, "%s: the feet never swap sides" % name)
			assert_true(right.y >= 0.0 and left.y >= 0.0, "%s: both ankles stay above the floor (%.3f, %.3f m)" % [name, right.y, left.y])
	proxy.queue_free()
	return result


## Swept rig validation (Phase 12) by adaptive refinement: a real cut, drawn
## as the presenter draws it between snapshots, is refined wherever the sword
## turns more than 1° or the phase changes. A pop is a step that keeps its size
## however finely it is sampled; motion is not. So the worst sub-step excess
## of the drawn point over the authoritative one must shrink when the
## refinement quadruples — or be under a centimetre to begin with. And at every
## phase change the legs hold: the right foot leads, the feet never swap
## sides, the ankles stay up.
func test_a_cut_is_continuous_through_every_phase_and_the_legs_hold() -> void:
	var rows := _cut_rows()
	var phases := {}
	for row in rows:
		phases[row.phase] = true
	assert_true(phases.has(CombatPhase.Id.OVERSWING) or phases.has(CombatPhase.Id.RECOVERY), "fixture: the cut ran on into its follow-through (%s)" % [phases.keys()])
	assert_true(phases.has(CombatPhase.Id.NEUTRAL), "fixture: and back to guard")
	var coarse: Dictionary = await _sweep(rows, 8, true)
	var fine: Dictionary = await _sweep(rows, 32)
	assert_true(int(coarse["transitions"]) >= 4, "fixture: the sweep crossed the cut's phase boundaries (%d)" % int(coarse["transitions"]))
	var worst := float(coarse["worst"])
	var refined := float(fine["worst"])
	assert_true(worst <= 0.01 or refined <= 0.5 * worst, "no pop: the worst sub-step excess shrinks under refinement (%.4f m at %s → %.4f m at %s)" % [worst, coarse["at"], refined, fine["at"]])


## The neutral-guard silhouette gate: in the resting guard the elbows must
## project out of the torso, not clamp the weapon against the ribs. Each
## elbow, in chest-local space, is lateral beyond the body radius and forward
## of the chest (+Z), while the hands stay on the grip. This is the gameplay-
## camera read the backward-biased pole used to fail.
func test_the_neutral_guard_opens_the_elbows_away_from_the_torso() -> void:
	var proxy := _proxy()
	var pose: Dictionary = await _settle(proxy, -PhysicalBaseline.GUARD_ANGLE_RAD)
	assert_eq(pose.size(), SETTLED_BONES, "precondition: the modifier stack ran")
	var chest: Transform3D = pose["Chest"]
	## In a bladed stance the off-hand reaches across the body, so "elbow
	## lateral of the torso" is the wrong test; air between elbow and clothes,
	## and an elbow that is not tucked behind the chest, is the right one.
	for arm: Array in [["Forearm.R", "Hand.R", -1.0], ["Forearm.L", "Hand.L", 1.0]]:
		var elbow_world: Vector3 = (pose[arm[0]] as Transform3D).origin
		var elbow: Vector3 = chest.affine_inverse() * elbow_world
		var side: float = arm[2]
		assert_true(_penetration(proxy.rig().skeleton(), pose, elbow_world) <= 0.0, "%s elbow keeps air from the torso" % arm[0])
		assert_true(elbow.z > -ELBOW_HIDDEN_DEPTH, "%s elbow is not tucked behind the chest (local z %.3f)" % [arm[0], elbow.z])
		var index := 0 if side < 0.0 else 1
		var palm := _palm(pose[arm[1]])
		assert_true(palm.distance_to(proxy.rig().grip_target(index).global_position) < GRIP_TOLERANCE, "%s hand stays on its grip" % arm[1])
	var hands := proxy.carriage().carriage_point
	var carriage := proxy.authoritative_carriage()
	assert_true(Vector2(hands.x - carriage.x, hands.z - carriage.z).length() < 1e-6, "the hands are where the orbit carries them (%s vs %s)" % [hands, carriage])
	assert_true(carriage.z > _rules.combatant(0).fighter.hurt_radius, "forward of the torso")
	assert_true(hands.y > proxy.blade_height() + 0.08, "and lifted above the blade plane (%s)" % str(hands))
	proxy.queue_free()


## The Mittelhau kinetic chain: the body supports the sword with the chest
## turning most, the spine less, the hips least, and the head counter-rotating
## so it stays on the opponent. The ordering is the contract, not the numbers.
func test_the_body_supports_the_cut_as_a_kinetic_chain() -> void:
	assert_eq(CombatPoseModifier3D.world_follow(&"Chest", 0.0), 0.0, "guard: no twist")
	var angle := PI * 0.5
	var hips := CombatPoseModifier3D.world_follow(&"Hips", angle)
	var spine := CombatPoseModifier3D.world_follow(&"Spine", angle)
	var chest := CombatPoseModifier3D.world_follow(&"Chest", angle)
	var head := CombatPoseModifier3D.world_follow(&"Head", angle)
	assert_true(chest > spine and spine > 0.0, "falloff down the chain: chest %.3f > spine %.3f > 0" % [chest, spine])
	assert_eq(hips, 0.0, "the pelvis is the stance's: it never follows the sword, so the planted feet never swivel")
	assert_true(chest > angle * 0.3 and chest < angle * 0.45, "the chest follows roughly a third of the sword (%.3f of %.3f)" % [chest, angle])
	assert_true(head < chest, "the head counter-rotates toward the opponent rather than turning with the chest (head %.3f < chest %.3f)" % [head, chest])
	assert_true(head >= 0.0 and head < spine, "and stays substantially opponent-oriented (head %.3f)" % head)
	assert_near(CombatPoseModifier3D.world_follow(&"Chest", -angle), -chest, 1e-9, "symmetric")


## The follow is not permanent: it is quiet in guard, peaks through the swing,
## and softens in recovery. A dead fighter's body stops supporting the blade.
func test_the_body_commits_more_to_a_swing_than_to_a_guard() -> void:
	var ready_angle := -PhysicalBaseline.GUARD_ANGLE_RAD
	var guard_thrust := BodySupportPose.effort_for(CombatPhase.Id.NEUTRAL, 0.0)
	var guard_ready := BodySupportPose.effort_for(CombatPhase.Id.NEUTRAL, ready_angle)
	var swing := BodySupportPose.effort_for(CombatPhase.Id.ACTIVE_THREAT, ready_angle)
	var recovery := BodySupportPose.effort_for(CombatPhase.Id.RECOVERY, ready_angle)
	var dead := BodySupportPose.effort_for(CombatPhase.Id.DEAD, ready_angle)
	assert_true(guard_thrust < guard_ready, "a held point loads the body less than a ready guard")
	assert_true(swing > guard_ready and swing >= 1.0, "the swing commits the whole chain")
	assert_true(recovery < swing and recovery > 0.0, "recovery is softer than the swing but still present")
	assert_eq(dead, 0.0, "a dead body does not support the blade")
	var scaled := CombatPoseModifier3D.world_follow(&"Chest", PI * 0.5, guard_thrust)
	var full := CombatPoseModifier3D.world_follow(&"Chest", PI * 0.5)
	assert_true(scaled < full and scaled > 0.0, "effort scales the follow magnitude without reordering it")


## BodySupportPose (PRES-STANCE-001): the body's support is one continuous,
## mirrored function of θ. The guard bands still flip (they are readings with
## hysteresis), but crossing one never steps the torso — through the Long Guard
## corridor included.
const SUPPORT_STEP_DEGREES := 0.1
## Most the chest may turn between two 0.1° samples in guard.
const CHEST_STEP_LIMIT := deg_to_rad(0.2)


func _guard_chest(angle: float) -> float:
	var effort := BodySupportPose.guard_effort(angle)
	effort *= CombatPoseModifier3D.coil_scale(angle, effort, CombatPoseModifier3D.COIL_LIMIT_GUARD)
	return CombatPoseModifier3D.world_follow(&"Chest", angle, effort)


func test_body_support_is_continuous_and_mirrored_over_the_whole_track() -> void:
	var limit := rad_to_deg(_rules.combatant(0).weapon.guard_limit)
	var guard := GuardPoseField.new()
	guard.update(deg_to_rad(-limit))
	var band_flips := 0
	var previous_band := guard.band()
	var worst_effort_step := 0.0
	var worst_chest_step := 0.0
	var worst_mirror := 0.0
	var samples := int(round(2.0 * limit / SUPPORT_STEP_DEGREES))
	for i in range(1, samples + 1):
		var before := deg_to_rad(-limit + (i - 1) * SUPPORT_STEP_DEGREES)
		var angle := deg_to_rad(-limit + i * SUPPORT_STEP_DEGREES)
		guard.update(angle)
		if guard.band() != previous_band:
			band_flips += 1
			previous_band = guard.band()
		worst_effort_step = maxf(worst_effort_step, absf(BodySupportPose.guard_effort(angle) - BodySupportPose.guard_effort(before)))
		worst_chest_step = maxf(worst_chest_step, absf(_guard_chest(angle) - _guard_chest(before)))
		worst_mirror = maxf(worst_mirror, absf(BodySupportPose.guard_effort(angle) - BodySupportPose.guard_effort(-angle)))
	assert_eq(band_flips, 4, "fixture: the sweep crosses every guard band edge (load → ready → point → ready → load)")
	assert_eq(worst_mirror, 0.0, "support is an exact mirror: the same |θ| gets the same effort on either side")
	assert_true(worst_effort_step < 0.01, "the effort never steps between 0.1° samples (worst %.4f)" % worst_effort_step)
	assert_true(worst_chest_step < CHEST_STEP_LIMIT, "nor does the chest (worst %.3f°)" % rad_to_deg(worst_chest_step))
	## Perturb-by-contrast: a band-stepped effort (the old reading) jumps the
	## chest by more than the limit right at the corridor's leave edge.
	var edge := GuardPoseField.THRUST_LEAVE
	var stepped := absf(CombatPoseModifier3D.world_follow(&"Chest", edge, BodySupportPose.EFFORT_READY) - CombatPoseModifier3D.world_follow(&"Chest", edge, BodySupportPose.EFFORT_POINT))
	assert_true(stepped > 3.0 * CHEST_STEP_LIMIT, "control: stepping the effort on the band would snap the chest %.2f° at the edge" % rad_to_deg(stepped))
	## Long Guard −20° → +20°: quietest at the point, rising smoothly either way.
	var previous := BodySupportPose.guard_effort(0.0)
	var falls := 0
	for tenth in range(1, 201):
		var effort := BodySupportPose.guard_effort(deg_to_rad(tenth * SUPPORT_STEP_DEGREES))
		if effort < previous:
			falls += 1
		previous = effort
	assert_eq(falls, 0, "support never falls moving out of Long Guard to 20°")
	assert_eq(BodySupportPose.guard_effort(0.0), BodySupportPose.EFFORT_POINT, "the point's quiet support at the centre")


## The guard reading is continuous and crosses centre only through Longpoint,
## with hysteresis so a blade wavering around straight-ahead never flickers.
func test_the_guard_reading_never_snaps_across_centre() -> void:
	var field := GuardPoseField.new()
	## Negative is the fighter's right: the canonical guard is −45°.
	assert_eq(field.update(deg_to_rad(-90.0)), GuardPoseField.State.RIGHT_LOAD, "a far-right blade is a loaded cut")
	assert_eq(field.side(), -1.0, "on the right shoulder")
	assert_eq(field.update(deg_to_rad(-40.0)), GuardPoseField.State.RIGHT_READY, "drawing in is the mid guard")
	## Inside the leave threshold but not yet inside the enter threshold: it must
	## hold the right reading rather than flicker to the other side.
	assert_eq(field.update(deg_to_rad(-15.0)), GuardPoseField.State.RIGHT_READY, "hysteresis holds the side near centre")
	assert_eq(field.update(deg_to_rad(-5.0)), GuardPoseField.State.LONGPOINT, "only a clearly centred point is Longpoint")
	assert_eq(field.side(), 0.0, "which belongs to neither shoulder")
	assert_eq(field.update(deg_to_rad(5.0)), GuardPoseField.State.LONGPOINT, "and it stays Longpoint across centre")
	assert_eq(field.update(deg_to_rad(40.0)), GuardPoseField.State.LEFT_READY, "a clearly left blade commits to the left")
	assert_eq(field.band(), GuardPoseField.Band.READY, "a drawn-in guard is the ready band")
	assert_eq(field.update(deg_to_rad(100.0)), GuardPoseField.State.LEFT_LOAD, "and far round it is loaded")
	assert_eq(field.band(), GuardPoseField.Band.LOAD, "the load band")


## A cut-down death and a run-through death are distinct collapses: a slash drops
## the body backward, a stab pitches it forward, and the folding styles sink it.
func test_a_slash_death_and_a_stab_death_fall_differently() -> void:
	var drop := FighterPresentation3D.death_pose(DeathPresentationProfile.STYLE_DEAD_DROP, 1.0, 0.0)
	var stab := FighterPresentation3D.death_pose(DeathPresentationProfile.STYLE_STAB_PITCH, 1.0, 0.0)
	var crumple := FighterPresentation3D.death_pose(DeathPresentationProfile.STYLE_STAB_CRUMPLE, 1.0, 0.0)
	var flop := FighterPresentation3D.death_pose(DeathPresentationProfile.STYLE_KNEES_FLOP, 1.0, 0.0)
	assert_true(drop.x > 0.0, "a cut drops the body backward")
	assert_true(stab.x < 0.0 and crumple.x < 0.0, "a run-through pitches the body forward")
	assert_true(crumple.z > 0.0 and flop.z > 0.0 and drop.z == 0.0, "folding deaths sink the body, a dead drop does not")
	assert_true(FighterPresentation3D.death_pose(DeathPresentationProfile.STYLE_DEAD_DROP, 0.0, 0.0).is_equal_approx(Vector3.ZERO), "the collapse starts from standing")


## On the authored Wolf a run-through and a cut-down play different clips, on
## the base body and the Training Gear skin alike.
func test_the_wolf_falls_differently_to_a_thrust_and_a_cut() -> void:
	for skin: StringName in [&"", RiposteKits.SKIN_DUELIST_TRAINING]:
		var proxy := _proxy(skin)
		proxy.begin_death(DeathPresentationProfile.Family.STAB, 3)
		assert_eq(proxy.animation_clip(PresentationKit.ANIM_DEATH), &"death_stab", "a killing thrust plays the run-through (%s)" % skin)
		proxy.begin_death(DeathPresentationProfile.Family.SLASH, 3)
		assert_eq(proxy.animation_clip(PresentationKit.ANIM_DEATH), &"death", "a killing cut plays the cut-down (%s)" % skin)
		assert_eq(proxy.animation_clip(PresentationKit.ANIM_IDLE), &"idle", "while every other semantic maps straight to its clip")
		assert_eq(proxy.animation_clip(PresentationKit.ANIM_DASH_FORWARD), &"dash_forward", "a dash is a dash")
		proxy.begin_finisher()
		assert_eq(proxy.animation_clip(PresentationKit.ANIM_DASH_FORWARD), &"run_through", "but a killing thrust's striker holds the run-through")
		proxy.queue_free()


## A finished one-shot holds its last frame for as long as its state lasts: a
## dead body stays down instead of standing back up to fall again.
func test_a_finished_death_stays_down() -> void:
	var proxy := _proxy()
	var row := _row(0.0)
	row.health = 0.0
	proxy.begin_death(DeathPresentationProfile.Family.SLASH, 3)
	proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, 0.016)
	var player := proxy.animation_player()
	assert_eq(player.current_animation, &"death", "precondition: the death is playing")
	player.advance(player.get_animation(&"death").length + 0.5)
	assert_false(player.is_playing(), "precondition: the clip has run to its end")
	for _i in 3:
		proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, 0.016)
	assert_false(player.is_playing(), "the finished death is not started again")
	row.health = 100.0
	proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, 0.016)
	assert_eq(player.current_animation, &"idle", "a new round plays the guard again")
	proxy.queue_free()


## The paired run-through belongs to the killing thrust alone: the striker holds
## the lunge only when the thrust killed, and a killing cut leaves the striker
## to follow through on their own swing. A thrust that does not kill makes no
## death request, so it can never reach this.
func test_only_a_killing_thrust_locks_the_striker() -> void:
	var striker := _proxy()
	var victim := _proxy()
	var fighters: Array[FighterPresentation3D] = [striker, victim]
	var backend := PrimitiveDeathBackend.new(fighters)
	backend.start(DeathPresentationRequest.create(1, DeathPresentationProfile.Family.SLASH, Vector3.RIGHT, 1.0, 4, 0))
	assert_false(striker.is_finishing(), "a killing cut does not lock the striker")
	backend.start(DeathPresentationRequest.create(1, DeathPresentationProfile.Family.STAB, Vector3.RIGHT, 1.0, 4, 0))
	assert_true(striker.is_finishing(), "a killing thrust holds the striker in the run-through")
	assert_false(victim.is_finishing(), "the victim collapses rather than lunging")
	var alone := _proxy()
	var solo: Array[FighterPresentation3D] = [alone, _proxy()]
	PrimitiveDeathBackend.new(solo).start(DeathPresentationRequest.create(0, DeathPresentationProfile.Family.STAB, Vector3.RIGHT, 1.0, 4, 0))
	assert_false(alone.is_finishing(), "a fighter is never the striker of their own death")
	var row := _row(0.0)
	for _i in 60:
		striker.apply_pose(Vector3.ZERO, 0.0, 0.0, row, 1.0 / 60.0)
	assert_false(striker.is_finishing(), "the hold releases after the kill beat")
	for proxy: FighterPresentation3D in [striker, victim, alone, solo[1]]:
		proxy.queue_free()


## Letting go hides the held sword (the authoritative one stays where the
## simulation put it);
## the prop that falls is a fresh look built from the same kits, never a clone of
## the live subtree; the next round puts the sword back in hand. A released
## sword starts with the presented body's motion: still for a death in place,
## the fall trajectory over the edge.
func test_a_dropped_sword_leaves_the_hands_and_returns_next_round() -> void:
	var proxy := _proxy()
	var row := _row(0.0)
	assert_true(proxy.root_velocity().is_zero_approx(), "a standing body is not moving")
	var origin_before := proxy.weapon_origin().global_transform
	var held_children := proxy.sword_carriage().get_child_count()
	proxy.detach_weapon()
	assert_true(proxy.is_weapon_dropped(), "the hands let go")
	assert_false(proxy.sword_carriage().visible, "the held sword is hidden")
	assert_eq(proxy.sword_carriage().get_child_count(), held_children, "nothing is lifted out of the live carriage")
	var look := CombatantVisuals.weapon_look(proxy.combatant_kit(), proxy.side, row.blade_base_radius, row.tip_radius)
	assert_true(look.get_child_count() > 0, "the prop gets a look built fresh from the kits")
	if proxy.weapon_model() != null:
		assert_true(look.get_child(0) != proxy.weapon_model(), "not the held model itself")
		assert_eq(look.get_child(0).scene_file_path, proxy.weapon_model().scene_file_path, "but the same authored weapon")
	assert_true(proxy.weapon_origin().global_transform.is_equal_approx(origin_before), "the authoritative sword itself is never moved")
	row.health = 0.0
	proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, 0.016)
	assert_true(proxy.is_weapon_dropped(), "a dead fighter stays empty-handed")
	row.health = 100.0
	proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, 0.016)
	assert_false(proxy.is_weapon_dropped(), "a new round puts the sword back in hand")
	assert_true(proxy.sword_carriage().visible, "visibly")
	proxy.begin_fall(FallPresentationRequest.create(0, Vector3.ZERO, Vector3(3.0, 0.0, 0.0), 1))
	row.is_falling = true
	proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, 0.1)
	var falling := proxy.root_velocity()
	assert_near(falling.x, 3.0, 1e-6, "over the edge the body carries its exit momentum")
	assert_true(falling.y < 0.0, "and is already falling when the hands let go")
	look.free()
	proxy.queue_free()


## Presentation physics touches only presentation geometry: the dropped sword
## collides with the presentation floor and nothing on the default layer, and the
## floor is the platform top at the rules' radius on either arena path.
func test_presentation_physics_stays_on_its_own_layers() -> void:
	var body := DroppedWeapon3D.create(Node3D.new(), PhysicalBaseline.SWORD_MASS_KG, 1.0, 0.05, 0.75)
	assert_near(body.mass, PhysicalBaseline.SWORD_MASS_KG, 1e-6, "the prop weighs what the simulated sword weighs")
	assert_eq(body.collision_layer, PresentationPhysicsLayers.DROPPED_WEAPON, "a dropped sword is on its own layer")
	assert_eq(body.collision_mask, PresentationPhysicsLayers.PRESENTATION_GROUND, "and meets only the presentation floor")
	assert_eq(body.collision_mask & 1, 0, "never the default layer")
	body.free()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	var arena := ArenaScaffold.create(kits.arena, _rules.platform_radius, 0.4, 2.0)
	var ground := arena.presentation_ground()
	assert_true(ground != null, "the arena carries a presentation floor")
	assert_eq(ground.collision_layer, PresentationPhysicsLayers.PRESENTATION_GROUND, "on the presentation ground layer")
	assert_eq(ground.collision_mask, 0, "which reaches for nothing itself")
	var shape := (ground.get_child(0) as CollisionShape3D).shape as CylinderShape3D
	assert_near(shape.radius, _rules.platform_radius, 1e-6, "exactly as wide as the platform, so a sword past the edge falls")
	arena.free()


## A fighter knocked over the edge flies out along the momentum they carried,
## not straight down at the lip — the fall reads the knockback that caused it.
func test_a_ring_out_flies_out_along_the_exit_momentum() -> void:
	var proxy := _proxy()
	var exit := Vector3(3.0, 0.0, 0.0)
	var velocity := Vector3(4.0, 0.0, 0.0)
	proxy.begin_fall(FallPresentationRequest.create(0, exit, velocity, 1))
	var row := _row(0.0)
	row.is_falling = true
	for _i in 10:
		proxy.apply_pose(exit, 0.0, 0.0, row, 0.05)
	assert_near(proxy.position.x, exit.x + velocity.x * 0.5, 1e-3, "carried outward by the exit momentum")
	assert_true(proxy.position.y < 0.0, "and pulled down by gravity")
	assert_true(proxy.position.x > exit.x + 1.0, "so it lands well past the lip, not straight below it")
	row.is_falling = false
	proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, 0.016)
	assert_true(proxy.position.is_equal_approx(Vector3.ZERO), "a new round stands the fighter back where the state says")
	proxy.queue_free()


## The skeleton as the modifiers leave it this frame (animation, then the
## sword pose and the grip IK), read inside `skeleton_updated`.
func _bones_now(proxy: FighterPresentation3D) -> Dictionary:
	var skeleton := proxy.rig().skeleton()
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var seen := {}
	var capture := func() -> void:
		for bone_name: String in ["Hand.R", "Hand.L", "UpperArm.R", "UpperArm.L"]:
			seen[bone_name] = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name))
	skeleton.skeleton_updated.connect(capture)
	skeleton.advance(1.0 / 60.0)
	await await_frames(1)
	skeleton.skeleton_updated.disconnect(capture)
	return seen


## Over the edge the Wolf flails one of its authored ring falls, chosen from the
## fall's event key: the same key always the same variant, and the keys spread
## over all of them (PRES-TERMINAL-001).
func test_a_ring_fall_flails_a_deterministic_variant() -> void:
	var seen := {}
	for key in 6:
		var proxy := _proxy()
		proxy.begin_fall(FallPresentationRequest.create(0, Vector3.ZERO, Vector3(3.0, 0.0, 0.0), key))
		var clip := proxy.animation_clip(PresentationKit.ANIM_RING_FALL)
		assert_true(proxy.animation_player().has_animation(clip), "key %d: an authored ring fall (%s)" % [key, clip])
		seen[clip] = true
		var again := _proxy()
		again.begin_fall(FallPresentationRequest.create(0, Vector3.ZERO, Vector3(-2.0, 0.0, 1.0), key))
		assert_eq(again.animation_clip(PresentationKit.ANIM_RING_FALL), clip, "key %d: the same key falls the same way whatever the momentum" % key)
		proxy.queue_free()
		again.queue_free()
	assert_eq(seen.size(), 3, "the keys reach every authored variant (%s)" % [seen.keys()])
	var row := _row(0.0)
	row.is_falling = true
	assert_eq(FighterAnimationSelector.select(row, true, true), PresentationKit.ANIM_RING_FALL, "a fall outranks a flinch")
	row.health = 0.0
	assert_eq(FighterAnimationSelector.select(row, false, false), PresentationKit.ANIM_DEATH, "but a dead body is a death, not a flail")


## A ring fall hands the body to its clip (Phase 13): the sword pose fades out
## from the fall's first instant; the hands stay on the grip while the sword is
## still held, let go of it at the release, and leave it within the same fade;
## an arm is thrown above its shoulder within a quarter second; the next round
## restores the guard.
func test_a_ring_fall_hands_the_body_to_its_clip() -> void:
	for key in 3:
		var proxy := _proxy()
		var player := proxy.animation_player()
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var row := _row(0.0)
		proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, 1.0 / 60.0)
		assert_eq(proxy.rig().pose_influence(), 1.0, "key %d: fixture: standing, the body follows the sword fully" % key)
		var fade := FighterPresentation3D.terminal_fade_seconds(key)
		assert_true(fade >= FighterPresentation3D.TERMINAL_FADE_MIN and fade <= FighterPresentation3D.TERMINAL_FADE_MAX, "key %d: the fade is %.2f s, inside 0.10–0.22 s" % [key, fade])
		var release := WeaponDropRequest.ring_out_delay(key)
		assert_true(release >= 0.12 and release <= 0.18, "key %d: the hands let go %.2f s after the ledge" % [key, release])
		proxy.begin_fall(FallPresentationRequest.create(0, Vector3.ZERO, Vector3(3.0, 0.0, 0.0), key))
		row.is_falling = true
		assert_eq(proxy.terminal_kind(row), TerminalPresentationKind.Id.RING_FALL, "key %d: the body presents a ring fall" % key)
		var step := 1.0 / 60.0
		var elapsed := 0.0
		var raised := false
		var released := false
		while elapsed < 0.25 - 1.0e-9:
			proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, step)
			player.advance(step)
			elapsed += step
			if not released and elapsed >= release:
				proxy.detach_weapon()
				released = true
			if not released:
				assert_eq(proxy.rig().grip_influence(), 1.0, "key %d at %.3f s: the held sword stays in both hands" % [key, elapsed])
			var bones: Dictionary = await _bones_now(proxy)
			for side: String in ["R", "L"]:
				var hand: Transform3D = bones["Hand.%s" % side]
				var shoulder: Transform3D = bones["UpperArm.%s" % side]
				raised = raised or hand.origin.y > shoulder.origin.y
		assert_true(released, "key %d: fixture: the sword was released within the window" % key)
		assert_true(raised, "key %d: a hand is thrown above its shoulder within 250 ms (%s)" % [key, proxy.playing_clip()])
		for _i in ceili(fade / step) + 1:
			proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, step)
			player.advance(step)
		assert_eq(proxy.rig().pose_influence(), 0.0, "key %d: the sword pose has faded out" % key)
		assert_eq(proxy.rig().grip_influence(), 0.0, "key %d: and the hands have left the grip" % key)
		var bones_after: Dictionary = await _bones_now(proxy)
		var grip := proxy.rig().grip_target(0).global_position
		var palm := _palm(bones_after["Hand.R"])
		assert_true(palm.distance_to(grip) > 0.05, "key %d: the dominant hand is clear of the empty grip (%.3f m)" % [key, palm.distance_to(grip)])
		proxy.reset_terminal()
		row.is_falling = false
		proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, step)
		assert_eq(proxy.rig().pose_influence(), 1.0, "key %d: the next round restores the sword pose" % key)
		assert_eq(proxy.rig().grip_influence(), 1.0, "key %d: and the grip" % key)
		assert_eq(proxy.terminal_kind(row), TerminalPresentationKind.Id.NONE, "key %d: and presents no terminal" % key)
		proxy.queue_free()


## A death collapse hands the body over the same way, but only once it
## collapses: a run-through's victim stands on the blade at full pose until the
## striker withdraws, then fades; a finished collapse is a fallen body.
func test_a_death_fades_the_sword_pose_from_its_collapse() -> void:
	var proxy := _proxy()
	var row := _row(0.0)
	row.health = 0.0
	var hold := 0.3
	proxy.begin_death_style(DeathPresentationProfile.STYLE_STAB_PITCH, hold, 2)
	var step := 1.0 / 60.0
	for _i in int(hold / step) - 2:
		proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, step)
	assert_eq(proxy.rig().pose_influence(), 1.0, "held up on the blade, the body still follows the sword")
	assert_eq(proxy.terminal_kind(row), TerminalPresentationKind.Id.STAB_DEATH, "presenting a stab death")
	for _i in int((hold + FighterPresentation3D.TERMINAL_FADE_MAX) / step) + 4:
		proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, step)
	assert_eq(proxy.rig().pose_influence(), 0.0, "once it collapses the sword pose fades out")
	for _i in int(FighterPresentation3D.DEATH_SECONDS / step) + 4:
		proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, step)
	assert_eq(proxy.terminal_kind(row), TerminalPresentationKind.Id.FALLEN_BODY, "and a finished collapse is a fallen body")
	proxy.begin_death_style(DeathPresentationProfile.STYLE_DEAD_DROP, 0.0, 2)
	assert_eq(TerminalPresentationKind.of(false, false, DeathPresentationProfile.STYLE_DEAD_DROP, false), TerminalPresentationKind.Id.SLASH_DEATH, "a cut down body collapsing is a slash death")
	assert_eq(TerminalPresentationKind.of(false, true, DeathPresentationProfile.STYLE_DEAD_DROP, true), TerminalPresentationKind.Id.FALLING_CORPSE, "and a dead body over the edge a falling corpse")
	proxy.queue_free()


## A lying body (Phase 16) is drawn on its authoritative axis: it turns with
## the body's yaw as it is pushed and spun, never flips end over end (the axis
## is symmetric, so the death clip's head stays the head), and keeps the
## authoritative centre of mass. Still it lies still; moved, it reads loose.
func test_a_lying_body_follows_its_authoritative_axis() -> void:
	var proxy := _proxy()
	var row := _row(0.0)
	row.health = 0.0
	proxy.begin_death_style(DeathPresentationProfile.STYLE_DEAD_DROP, 0.0, 1)
	var step := 1.0 / 60.0
	var facing := 0.3
	proxy.apply_pose(Vector3(1.0, 0.0, 2.0), facing, 0.0, row, step)
	assert_true(is_equal_approx(proxy.rotation.y, ArenaTransform.yaw(facing)), "fixture: collapsing, the body keeps its facing")
	row.body_lying = true
	row.body_yaw = facing + PI + 0.2
	for _i in 60:
		proxy.apply_pose(Vector3(1.0, 0.0, 2.0), facing, 0.0, row, step)
	assert_near(angle_difference(proxy.rotation.y, ArenaTransform.yaw(facing + 0.2)), 0.0, 1.0e-3, "drawn along the body's axis, the nearer way round (not flipped end over end)")
	assert_true(proxy.position.is_equal_approx(Vector3(1.0, 0.0, 2.0)), "at the authoritative centre of mass")
	assert_eq(proxy.body_looseness(), 0.0, "a body at rest lies still")
	row.vx = 1.5
	row.body_spin = 1.0
	proxy.apply_pose(Vector3(1.0, 0.0, 2.0), facing, 0.0, row, step)
	assert_true(proxy.body_looseness() > 0.05, "a body being moved reads loose (%.3f rad)" % proxy.body_looseness())
	assert_eq(FighterPresentation3D.body_facing(0.1, PI - 0.05), wrapf(0.1 + PI, -PI, PI), "the axis is chosen by the nearer end")
	row.health = 100.0
	row.body_lying = false
	proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, step)
	assert_true(proxy.visual_root().transform.is_equal_approx(proxy.combatant_kit().fighter.visual_transform), "the next round stands the body back up exactly")
	proxy.queue_free()


## A body carried over the edge drops as a body (Phase 16): it falls under
## presentation gravity from where authority carries it, flailing one of the
## authored falls, and presents a falling corpse.
func test_a_body_carried_over_the_edge_falls_as_a_body() -> void:
	var proxy := _proxy()
	var row := _row(0.0)
	row.health = 0.0
	row.body_lying = true
	proxy.begin_death_style(DeathPresentationProfile.STYLE_DEAD_DROP, 0.0, 4)
	var step := 1.0 / 60.0
	proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, step)
	assert_false(proxy.is_corpse_falling(), "fixture: lying on the platform")
	row.body_over_edge = true
	for _i in 30:
		proxy.apply_pose(Vector3(8.5, 0.0, 0.0), 0.0, 0.0, row, step)
	assert_true(proxy.is_corpse_falling(), "over the edge it falls")
	assert_true(proxy.position.y < -0.5, "dropping under gravity (%.2f m)" % proxy.position.y)
	assert_near(proxy.position.x, 8.5, 1.0e-6, "from where authority carries it")
	assert_eq(proxy.terminal_kind(row), TerminalPresentationKind.Id.FALLING_CORPSE, "a falling corpse")
	var clip := proxy.animation_clip(PresentationKit.ANIM_DEATH)
	assert_true(String(clip).begins_with("ring_fall"), "flailing an authored fall (%s)" % clip)
	assert_eq(clip, proxy.combatant_kit().fighter.ring_fall_clip(4), "chosen by its key")
	proxy.reset_terminal()
	assert_false(proxy.is_corpse_falling(), "and the next round clears it")
	proxy.queue_free()


func test_skins_swap_the_body_without_touching_the_rig_or_rules() -> void:
	var base := _proxy()
	var training := _proxy(RiposteKits.SKIN_DUELIST_TRAINING)
	assert_true(training.rig() != null and training.rig().is_bound(), "the training gear binds the same rig")
	assert_true(base.find_child("FurCollar", true, false) != null, "precondition: the base look has its fur collar")
	assert_true(training.find_child("FurCollar", true, false) == null, "the training gear does not")
	assert_eq(training.blade_points()[1], base.blade_points()[1], "and the blade is in exactly the same place")
	assert_eq(_rules.combatant(0).weapon.tip_radius, StandardDuelRules.create().combatant(0).weapon.tip_radius, "nothing about the rules moved")
	base.queue_free()
	training.queue_free()


## Air kept between a sampled arm point (on the bone axis) and the clothes.
const BODY_CLEARANCE := 0.02
## An elbow this far behind the chest's centre plane is behind the torso —
## hidden from the camera, the read the poles exist to prevent.
const ELBOW_HIDDEN_DEPTH := 0.15


## How far `point` (world) falls short of `required` air from the torso
## proxies (m, ≤ 0 means it keeps at least that much) — PoseClearance over the
## fighter's own SelfClearanceProfile, the same geometry the runtime uses.
func _penetration(skeleton: Skeleton3D, _pose: Dictionary, point: Vector3, required: float = BODY_CLEARANCE) -> float:
	var profile := _clearance()
	return required - PoseClearance.torso_gap(profile, skeleton, skeleton.global_transform.affine_inverse() * point)


func _clearance() -> SelfClearanceProfile:
	return RiposteKits.build_catalog().resolve(ContentIds.FIGHTER_DUELIST, PresentationKit.PRIMITIVE_FIGHTER).stance.self_clearance()


## PRES-POSE-001's body gate on the authoritative orbit: across the guard field,
## the charge, the cut and recovery, no palm, wrist, or forearm sample enters
## Wolf's clothes — with nothing at runtime moving the sword to make it so.
func test_no_hand_wrist_or_forearm_enters_the_torso() -> void:
	var proxy := _proxy()
	var skeleton := proxy.rig().skeleton()
	var worst := -INF
	var where := ""
	var poses := 0
	var cases: Array[Array] = []
	## The offline gate is the primary guard (the runtime keeps only cheap
	## clamps), so it sweeps the whole field densely.
	for step in range(-135, 136, 5):
		var degrees := float(step)
		cases.append([degrees, CombatPhase.Id.NEUTRAL, 1.0, 0.0, 0.0])
		cases.append([degrees, CombatPhase.Id.ACTIVE_THREAT, 0.5, 0.0, 0.5])
		cases.append([degrees, CombatPhase.Id.RECOVERY, 1.0, 0.0, 0.0])
	for charge: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		for side: float in [-1.0, 1.0]:
			cases.append([side * lerpf(45.0, 135.0, charge), CombatPhase.Id.CHARGING, 1.0, charge, 0.0])
	var profile := _clearance()
	var worst_elbow := INF
	var worst_weapon := INF
	var elbow_where := ""
	var weapon_where := ""
	var measured := {}
	## Every gap is read inside the same modifier pass that posed the arms,
	## so the torso shells and the head are where the drawn body has them.
	var measure := func() -> void:
		var into_skeleton := skeleton.global_transform.affine_inverse()
		var at := func(bone_name: String) -> Transform3D:
			return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name))
		measured["elbows"] = PackedFloat64Array([PoseClearance.torso_gap(profile, skeleton, into_skeleton * (at.call("Forearm.R") as Transform3D).origin), PoseClearance.torso_gap(profile, skeleton, into_skeleton * (at.call("Forearm.L") as Transform3D).origin)])
		measured["weapon"] = PoseClearance.weapon_gap(profile, skeleton, into_skeleton * proxy.sword_carriage().global_position, into_skeleton * proxy.blade_points()[1])
		var depths := PackedFloat64Array()
		for arm: Array in [["Hand.R", "Forearm.R"], ["Hand.L", "Forearm.L"]]:
			var hand: Transform3D = at.call(arm[0])
			var elbow: Vector3 = (at.call(arm[1]) as Transform3D).origin
			for sample: Vector3 in [_palm(hand), hand.origin, elbow.lerp(hand.origin, 0.25), elbow.lerp(hand.origin, 0.5), elbow.lerp(hand.origin, 0.75)]:
				depths.append(BODY_CLEARANCE - PoseClearance.torso_gap(profile, skeleton, into_skeleton * sample))
		measured["arms"] = depths
	var parts: Array[String] = []
	for arm_name: String in ["Hand.R", "Hand.L"]:
		for part: String in ["palm", "wrist", "forearm 25%", "forearm 50%", "forearm 75%"]:
			parts.append("%s %s" % [arm_name, part])
	for entry: Array in cases:
		var angle := deg_to_rad(float(entry[0]))
		measured.clear()
		var pose: Dictionary = await _settle(proxy, angle, _row(angle, entry[1], entry[2], entry[3], entry[4]), measure)
		if pose.size() != SETTLED_BONES or measured.is_empty():
			continue
		poses += 1
		var label := "%.0f° phase %d charge %.2f" % [float(entry[0]), int(entry[1]), float(entry[3])]
		var elbows: PackedFloat64Array = measured["elbows"]
		for side in 2:
			if elbows[side] < worst_elbow:
				worst_elbow = elbows[side]
				elbow_where = "%s at %s" % ["R" if side == 0 else "L", label]
		var weapon: float = measured["weapon"]
		if weapon < worst_weapon:
			worst_weapon = weapon
			weapon_where = label
		var depths: PackedFloat64Array = measured["arms"]
		for index in depths.size():
			if depths[index] > worst:
				worst = depths[index]
				where = "%s at %s" % [parts[index], label]
	assert_eq(poses, cases.size(), "precondition: the modifier stack ran for every case")
	assert_true(worst <= 0.0, "every arm sample keeps %.0f cm of air from the clothes (worst %.3f m inside: %s)" % [BODY_CLEARANCE * 100.0, worst, where])
	## Hard (PRES-POSE-001): nothing penetrates. The profile's visible-air
	## targets (`min_elbow_gap`, `min_weapon_gap`) are the tuning goal above
	## that, reported here so a regression in margin is visible.
	assert_true(worst_elbow >= 0.0, "no elbow enters the clothes (worst %.3f m of air at %s; target %.2f m)" % [worst_elbow, elbow_where, profile.min_elbow_gap])
	assert_true(worst_weapon >= 0.0, "the sword never passes through its own wielder's torso or head (worst %.3f m of air at %s; target %.2f m)" % [worst_weapon, weapon_where, profile.min_weapon_gap])
	print("PRES-POSE margins: arm %.3f m inside the %.2f m air (%s), elbow %.3f m (target %.2f, %s), weapon %.3f m (target %.2f, %s)" % [worst, BODY_CLEARANCE, where, worst_elbow, profile.min_elbow_gap, elbow_where, worst_weapon, profile.min_weapon_gap, weapon_where])
	proxy.queue_free()


## A full-charge release from `side`'s high load at physical progress `p`.
func _cut_row(side: float, p: float) -> PresentationFighter:
	var row := _row(side * deg_to_rad(135.0 - 180.0 * p), CombatPhase.Id.ACTIVE_THREAT, p, 0.0, 1.0)
	row.cut_dir = -side
	return row


## PRES-ARMS-001, before IK: through the right-release zone and its mirror,
## every pole is a unit bulge perpendicular to that arm, and the bulge turns
## continuously — a sign flip here is the pop the release used to show.
func test_the_elbow_pole_stays_perpendicular_and_continuous() -> void:
	var profile := RiposteKits.build_catalog().resolve(ContentIds.FIGHTER_DUELIST, PresentationKit.PRIMITIVE_FIGHTER).stance.arm_structure()
	var field := ElbowGuideField.new()
	var shoulders: Array[Vector3] = [Vector3(-0.18, 1.35, 0.04), Vector3(0.18, 1.35, -0.02)]
	var yaw := deg_to_rad(22.0)
	var worst_align := 0.0
	var worst_turn := 1.0
	for side: float in [-1.0, 1.0]:
		var previous: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
		var seen := false
		for degrees in range(30, 121):
			var angle := side * deg_to_rad(-float(degrees))
			var reach := 0.55
			var hands: Array[Vector3] = [
				shoulders[0] + Vector3(sin(angle), -0.15, cos(angle)) * reach,
				shoulders[1] + Vector3(sin(angle) * 0.6, -0.1, cos(angle)) * reach,
			]
			field.sample(profile, yaw, shoulders, hands, angle, 0.0, 0.0, absf(rad_to_deg(angle)) * 0.5, side)
			for arm in 2:
				var line := (hands[arm] - shoulders[arm]).normalized()
				var bend := field.bends[arm]
				worst_align = maxf(worst_align, absf(bend.dot(line)))
				assert_near(bend.length(), 1.0, 1e-4, "the bulge is a unit direction")
				if seen:
					worst_turn = minf(worst_turn, bend.dot(previous[arm]))
				previous[arm] = bend
			seen = true
	assert_true(worst_align < 1e-3, "no bulge has a component along its arm (worst %.5f)" % worst_align)
	assert_true(worst_turn > 0.0, "the bulge does not reverse between 1° samples (worst dot %.3f)" % worst_turn)


## The elbow overlay is the same diagnostic as the world vectors: nothing while
## hidden, the arm and the clearance proxies once F3 asks for them.
func test_the_elbow_overlay_draws_only_when_asked() -> void:
	var proxy := _proxy()
	var overlay := proxy.pose_debug()
	await _settle(proxy, -PhysicalBaseline.GUARD_ANGLE_RAD)
	assert_false(overlay.visible, "hidden by default")
	assert_eq(overlay.line_count(), 0, "and it costs nothing while hidden")
	proxy.set_pose_debug(true)
	assert_eq(overlay.line_count(), 1, "one line surface once shown")
	proxy.set_pose_debug(false)
	assert_eq(overlay.line_count(), 0, "hidden again, the mesh is empty")
	proxy.queue_free()


## PRES-ARMS-001: through the whole guard field, both charge gathers, and both
## full-charge X cuts (the old failure zone at 1°), each
## elbow bends away from the torso (never toward its axis — the IK-flip
## detector), moves continuously, and the IK never stretches the arm.
func test_the_elbows_hold_a_stable_open_structure() -> void:
	var proxy := _proxy()
	var skeleton := proxy.rig().skeleton()
	var rest_upper := [0.0, 0.0]
	var rest_fore := [0.0, 0.0]
	for arm in 2:
		var bones := proxy.rig().dominant_bones if arm == 0 else proxy.rig().offhand_bones
		var shoulder := skeleton.get_bone_global_rest(skeleton.find_bone(bones[0])).origin
		var elbow := skeleton.get_bone_global_rest(skeleton.find_bone(bones[1])).origin
		var wrist := skeleton.get_bone_global_rest(skeleton.find_bone(bones[2])).origin
		rest_upper[arm] = shoulder.distance_to(elbow)
		rest_fore[arm] = elbow.distance_to(wrist)
	var sweeps: Array[Array] = []
	var guard: Array = []
	for degrees in range(-135, 136, 5):
		guard.append(_row(deg_to_rad(float(degrees))))
	sweeps.append(guard)
	for side: float in [-1.0, 1.0]:
		var gather: Array = []
		for i in 21:
			var charge := i / 20.0
			gather.append(_row(side * deg_to_rad(lerpf(45.0, 135.0, charge)), CombatPhase.Id.CHARGING, 1.0, charge))
		sweeps.append(gather)
		## The full-charge X cut from that side's load across centre, and the
		## zone the right release once flipped in (−120°…−30°, mirrored) at 1°.
		var cut: Array = []
		for i in 37:
			var p := i / 36.0
			cut.append(_cut_row(side, p))
		sweeps.append(cut)
		var zone: Array = []
		for degrees in range(120, 29, -1):
			zone.append(_cut_row(side, (135.0 - float(degrees)) / 180.0))
		sweeps.append(zone)
	var inward := 0
	var colinear := 0
	var jumps := 0
	var worst_stretch := 0.0
	var trace := PackedStringArray()
	for sweep: Array in sweeps:
		var previous: Array[Vector3] = []
		var previous_angle := 0.0
		for row: PresentationFighter in sweep:
			var pose: Dictionary = await _settle(proxy, row.weapon_angle, row)
			if pose.size() != SETTLED_BONES:
				continue
			var elbows: Array[Vector3] = []
			for arm in 2:
				var tag := "R" if arm == 0 else "L"
				var shoulder: Vector3 = (pose["UpperArm." + tag] as Transform3D).origin
				var elbow: Vector3 = (pose["Forearm." + tag] as Transform3D).origin
				var wrist: Vector3 = (pose["Hand." + tag] as Transform3D).origin
				elbows.append(elbow)
				worst_stretch = maxf(worst_stretch, maxf(absf(shoulder.distance_to(elbow) - float(rest_upper[arm])), absf(elbow.distance_to(wrist) - float(rest_fore[arm]))))
				var line := wrist - shoulder
				var on_line := shoulder + line * clampf((elbow - shoulder).dot(line) / maxf(line.length_squared(), 1e-8), 0.0, 1.0)
				## "Toward the torso" is toward the chest as posed: a support
				## clip that shifts the upper body carries it off the ground
				## origin.
				var chest_at: Vector3 = (pose["Chest"] as Transform3D).origin
				var away := Vector3(on_line.x - chest_at.x, 0.0, on_line.z - chest_at.z).normalized()
				## A near-straight arm's elbow sits on its own line within a
				## couple of centimetres either way; past that, it has flipped.
				var bend := (elbow - on_line).dot(away)
				if bend < -STRAIGHT_ARM_SLACK:
					inward += 1
					trace.append("%s %.0f° phase %d charge %.2f: %.3f (reach %.2f)" % [tag, rad_to_deg(row.weapon_angle), int(row.phase), row.charge, bend, line.length()])
			var guides := proxy.elbow_guides()
			for arm in 2:
				## The pole plane is never degenerate: the bulge is perpendicular
				## to shoulder→hand by construction, so it must be a unit vector.
				if absf(guides.bends[arm].length() - 1.0) > 1e-3:
					colinear += 1
			if not previous.is_empty():
				var step_degrees := absf(rad_to_deg(angle_difference(row.weapon_angle, previous_angle)))
				var allowed := ELBOW_STEP_PER_DEGREE * maxf(step_degrees, 1.0)
				for arm in 2:
					if elbows[arm].distance_to(previous[arm]) > allowed:
						jumps += 1
						trace.append("jump %d %.0f° phase %d (%.3f m)" % [arm, rad_to_deg(row.weapon_angle), int(row.phase), elbows[arm].distance_to(previous[arm])])
			previous = elbows
			previous_angle = row.weapon_angle
	assert_eq(colinear, 0, "no pole plane goes degenerate (colinear with the arm)")
	assert_eq(inward, 0, "no elbow bends toward the torso (%s)" % " ".join(trace))
	assert_eq(jumps, 0, "no elbow jumps between neighbouring samples (%s)" % " ".join(trace))
	assert_true(worst_stretch < STRETCH_TOLERANCE, "the IK never stretches an arm (worst %.4f m)" % worst_stretch)
	proxy.queue_free()


## The lifted sword is one mirrored function: a left-side pose is the
## right-side pose reflected across the combat frame.
func test_the_carriage_mirrors_left_and_right() -> void:
	var right := CombatPresentationField.new()
	var left := CombatPresentationField.new()
	for degrees: float in [0.0, 20.0, 45.0, 80.0, 90.0, 135.0]:
		for phase: CombatPhase.Id in [CombatPhase.Id.NEUTRAL, CombatPhase.Id.CHARGING]:
			_lift(right, deg_to_rad(-degrees), phase, 1.0, 0.7, 0.0)
			_lift(left, deg_to_rad(degrees), phase, 1.0, 0.7, 0.0)
			var mirrored := Vector3(-left.carriage_point.x, left.carriage_point.y, left.carriage_point.z)
			assert_true(right.carriage_point.is_equal_approx(mirrored), "hands mirror at %.0f° (phase %d)" % [degrees, phase])
			var tip_right := right.tip(_rules.combatant(0).weapon.tip_radius)
			var tip_left := left.tip(_rules.combatant(0).weapon.tip_radius)
			assert_true(tip_right.is_equal_approx(Vector3(-tip_left.x, tip_left.y, tip_left.z)), "and so does the point")


## No pop anywhere in the field: one-degree steps through the guard and the
## charge, and 0.5% steps through a tap and a full-charge cut, move the hands
## and turn the blade by small amounts only — through centre included.
func test_the_carriage_never_pops() -> void:
	var field := CombatPresentationField.new()
	var worst_move := 0.0
	var worst_turn := 0.0
	var sweeps: Array[Array] = []
	var guard: Array = []
	for degrees in range(-135, 136):
		guard.append([float(degrees), CombatPhase.Id.NEUTRAL, 1.0, 0.0, 0.0])
	sweeps.append(guard)
	var charge: Array = []
	for i in 101:
		charge.append([lerpf(-45.0, -135.0, i / 100.0), CombatPhase.Id.CHARGING, 1.0, i / 100.0, 0.0])
	sweeps.append(charge)
	for launch: Array in [[-45.0, 90.0, 0.0], [-135.0, 180.0, 1.0]]:
		var cut: Array = []
		for i in 201:
			var p := i / 200.0
			cut.append([float(launch[0]) + float(launch[1]) * p, CombatPhase.Id.ACTIVE_THREAT, p, 0.0, float(launch[2])])
		sweeps.append(cut)
	for sweep: Array in sweeps:
		var previous := Transform3D.IDENTITY
		for index in sweep.size():
			var step: Array = sweep[index]
			_lift(field, deg_to_rad(float(step[0])), step[1], step[2], step[3], step[4])
			var now := Transform3D(field.transform.basis, field.carriage_point)
			if index > 0:
				worst_move = maxf(worst_move, now.origin.distance_to(previous.origin))
				worst_turn = maxf(worst_turn, (previous.basis.inverse() * now.basis).get_rotation_quaternion().get_angle())
			previous = now
	assert_true(worst_move < 0.02, "hands move under 2 cm per step (worst %.4f m)" % worst_move)
	assert_true(worst_turn < deg_to_rad(4.0), "the blade turns under 4° per step (worst %.2f°)" % rad_to_deg(worst_turn))


## Point height is the charge cue (rises with charge to the high load); a
## loaded cut comes down off it, is near horizontal through centre, dips past
## it, and — once committed into the opposite side — inflects back up.
func test_charge_raises_the_point_and_the_cut_descends_then_inflects() -> void:
	var field := CombatPresentationField.new()
	var pitches: Array[float] = []
	for charge: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		_lift(field, deg_to_rad(lerpf(-45.0, -135.0, charge)), CombatPhase.Id.CHARGING, 1.0, charge, 0.0)
		pitches.append(rad_to_deg(asin(field.transform.basis.z.y)))
	for index in range(1, pitches.size()):
		assert_true(pitches[index] > pitches[index - 1], "the point rises with charge (%s)" % str(pitches))
	assert_between(pitches[0], 10.0, 15.0, "from the mid guard's raised point")
	assert_between(pitches[-1], 60.0, 70.0, "to the high shoulder load")
	## SLASH-SHAPE-001: the load is drawn in toward the body — on the striking
	## side, never overhead, but inside the shoulder line.
	assert_between(field.carriage_point.x, -0.18, -0.1, "and the load sits on the striking (right) side, not overhead (%.2f)" % field.carriage_point.x)
	var descent: Array[float] = []
	for p: float in [0.0, 0.15, 0.3, 0.45]:
		_lift(field, deg_to_rad(-135.0 + 180.0 * p), CombatPhase.Id.ACTIVE_THREAT, p, 0.0, 1.0)
		descent.append(rad_to_deg(asin(field.transform.basis.z.y)))
	for index in range(1, descent.size()):
		assert_true(descent[index] < descent[index - 1], "the loaded cut descends through its first half (%s)" % str(descent))
	_lift(field, 0.0, CombatPhase.Id.ACTIVE_THREAT, 0.75, 0.0, 1.0)
	assert_between(rad_to_deg(asin(field.transform.basis.z.y)), 0.0, 8.0, "near horizontal through centre")
	_lift(field, deg_to_rad(50.0), CombatPhase.Id.OVERSWING, 1.0, 0.0, 1.0, 1.0, 1.0, false)
	var low := rad_to_deg(asin(field.transform.basis.z.y))
	assert_between(low, -20.0, -10.0, "a low follow-through past centre, never a chop at the floor")
	_lift(field, deg_to_rad(75.0), CombatPhase.Id.OVERSWING, 1.0, 0.0, 1.0, 1.0, 1.0, true)
	assert_true(rad_to_deg(asin(field.transform.basis.z.y)) > low + 10.0, "committed into the opposite side, the point inflects back up")
	var inflection := CutPresentationCurve.Inflection.new()
	assert_false(inflection.update(50.0, -2.0), "a rebound past the threshold does not commit")
	assert_true(inflection.update(50.0, 2.0), "travel into the side does")
	assert_true(inflection.update(35.0, -2.0), "and hysteresis holds it inside the enter threshold")
	assert_false(inflection.update(25.0, -2.0), "until it is back inside the leave threshold")


## Contact happens near level, through the centre: there the drawn tip's
## ground projection is the authoritative tip's to within the lift's
## foreshortening, so what the player sees hit is what hit. Everywhere, the
## carriage is the authoritative one and the yaw is θ — only lifted.
const CORRIDOR_DEGREES := 20.0
## Pitch ≤ ~12° there foreshortens a ~1 m blade beyond the hands by ≤ ~2.3 cm.
const CORRIDOR_TIP_ERROR := 0.03


func test_the_drawn_sword_is_the_authoritative_sword_lifted() -> void:
	var field := CombatPresentationField.new()
	var worst := 0.0
	var worst_carriage := 0.0
	var worst_yaw := 0.0
	for launch: Array in [[-45.0, 90.0, 0.0], [-135.0, 180.0, 1.0], [135.0, -180.0, 1.0]]:
		for i in 201:
			var p := i / 200.0
			var degrees := float(launch[0]) + float(launch[1]) * p
			var angle := deg_to_rad(degrees)
			var cut_dir := signf(float(launch[1]))
			_lift(field, angle, CombatPhase.Id.ACTIVE_THREAT, p, 0.0, float(launch[2]), 1.0, cut_dir)
			var planar := WeaponKinematics.pose_at(0.0, 0.0, 0.0, angle, _rules.combatant(0), BladePose.new())
			worst_carriage = maxf(worst_carriage, Vector2(field.carriage_point.x - planar.carriage_y, field.carriage_point.z - planar.carriage_x).length())
			var axis := field.transform.basis.z
			worst_yaw = maxf(worst_yaw, absf(angle_difference(angle, atan2(axis.x, axis.z))))
			if absf(degrees) > CORRIDOR_DEGREES:
				continue
			var tip := field.tip(_rules.combatant(0).weapon.tip_radius)
			var simulated := Vector2(planar.point_y(_rules.combatant(0).weapon.tip_radius), planar.point_x(_rules.combatant(0).weapon.tip_radius))
			worst = maxf(worst, Vector2(tip.x, tip.z).distance_to(simulated))
	assert_true(worst_carriage < 1e-6, "the carriage never leaves the orbit (worst %.9f m; Vector3 is single precision)" % worst_carriage)
	assert_true(worst_yaw < 1e-6, "the yaw is never corrected (worst %.9f rad)" % worst_yaw)
	assert_true(worst <= CORRIDOR_TIP_ERROR, "within %.2f m through the corridor (worst %.4f)" % [CORRIDOR_TIP_ERROR, worst])


## The bladed stance turns the body, never the combat frame (PRES-STANCE-001):
## Wolf's rig stands quarter-turned with the right shoulder forward while the
## carriage — and the hands' targets — stay exactly where the square body's
## would be.
func test_the_stance_blades_the_body_not_the_combat_frame() -> void:
	var proxy := _proxy()
	var stance := proxy.combatant_kit().fighter.stance
	assert_true(stance != null, "fixture: Wolf has a stance")
	assert_eq(stance.lead_side, FighterStanceProfile.LeadSide.RIGHT, "a fixed right-foot lead")
	assert_near(proxy.rig().rotation.y, stance.hip_yaw(), 1e-6, "the body turns by the pelvis's blade")
	assert_true(stance.hip_yaw() > 0.0, "toward his left, bringing the right shoulder forward")
	var square := _lift(CombatPresentationField.new(), -PhysicalBaseline.GUARD_ANGLE_RAD, CombatPhase.Id.NEUTRAL, 1.0, 0.0, 0.0, proxy.blade_height())
	proxy.apply_pose(Vector3.ZERO, 0.0, -PhysicalBaseline.GUARD_ANGLE_RAD, _row(-PhysicalBaseline.GUARD_ANGLE_RAD), 1.0)
	assert_true(proxy.sword_carriage().transform.origin.is_equal_approx(square.transform.origin), "the carriage is the combat frame's, not the body's")
	assert_true(stance.load_coil(1.0) > stance.load_coil(-1.0), "the rear-side (left) load coils a little more than the lead side")
	proxy.queue_free()


## Yaw (degrees, + toward the fighter's left) of `axis` of `bone` off the
## combat heading, read in the proxy's frame (combat-forward +Z). Only valid
## inside a skeleton update, where the modifier pass is live.
func _bone_yaw(proxy: FighterPresentation3D, bone: String, axis: int) -> float:
	var skeleton := proxy.rig().skeleton()
	var into := proxy.global_transform.affine_inverse() * skeleton.global_transform
	var direction := (into.basis * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).basis)[axis]
	return rad_to_deg(atan2(direction.x, direction.z))


## STANCE-FOOT-001, head to foot: Wolf stands a fixed right lead, semi-bladed
## — the lead toe close to the combat heading, the rear foot more open, the
## pelvis bladed, the chest more so, and the head on the target — wherever the
## sword rests in its arc, and still while walking, orbiting and charging. No
## gait clip squares the feet. Relationships, not exact angles.
func test_the_stance_is_semi_bladed_head_to_foot() -> void:
	var proxy := _proxy()
	var stance := proxy.combatant_kit().fighter.stance
	var guard_chest := Vector2(stance.chest_yaw_degrees - stance.guard_coil_degrees - 0.1, stance.chest_yaw_degrees + stance.guard_coil_degrees + 0.1)
	assert_true(guard_chest.x >= 19.85 and guard_chest.y <= 25.15, "fixture: Wolf's guard chest band is the 20–25° target (%.1f–%.1f°)" % [guard_chest.x, guard_chest.y])
	var read := {}
	var reading := func() -> void:
		read["lead"] = _bone_yaw(proxy, "Foot.R", 1)
		read["rear"] = _bone_yaw(proxy, "Foot.L", 1)
		read["pelvis"] = _bone_yaw(proxy, "Hips", 2)
		read["chest"] = _bone_yaw(proxy, "Chest", 2)
		read["head"] = _bone_yaw(proxy, "Head", 2)
		read["ahead"] = _foot_lead(proxy)
		read["width"] = _foot_width(proxy)
	var check := func(label: String, chest_range: Vector2) -> void:
		var lead: float = read["lead"]
		var rear: float = read["rear"]
		var pelvis: float = read["pelvis"]
		var chest: float = read["chest"]
		assert_true(float(read["ahead"]) > 0.0, "%s: the right foot is ahead (%.3f m)" % [label, float(read["ahead"])])
		assert_true(absf(lead) < absf(rear) - 10.0, "%s: the lead toe points down the line (%.1f°), the rear foot opens (%.1f°)" % [label, lead, rear])
		assert_between(lead, -2.0, 12.0, "%s: the lead toe stays near the combat heading (%.1f°)" % [label, lead])
		assert_true(pelvis > lead, "%s: the pelvis is bladed past the lead toe (%.1f° > %.1f°)" % [label, pelvis, lead])
		assert_between(pelvis, 10.0, 15.0, "%s: the pelvis is modestly bladed (%.1f°)" % [label, pelvis])
		assert_between(chest, chest_range.x, chest_range.y, "%s: chest blade %.1f° in [%.1f, %.1f]" % [label, chest, chest_range.x, chest_range.y])
		assert_between(float(read["head"]), -6.0, 6.0, "%s: the head is back on the target (%.1f°)" % [label, float(read["head"])])
		assert_true(float(read["width"]) > 0.10, "%s: the feet never gather onto one line (%.3f m apart)" % [label, float(read["width"])])
	for degrees: float in [-135.0, -80.0, -45.0, -15.0, 0.0, 15.0, 45.0, 80.0, 135.0]:
		var angle := deg_to_rad(degrees)
		await _settle(proxy, angle, null, reading)
		assert_eq(read.size(), 7, "fixture: read inside the modifier pass at %.0f°" % degrees)
		check.call("guard %.0f°" % degrees, guard_chest)
		assert_true(float(read["chest"]) > float(read["pelvis"]), "guard %.0f°: the chest is bladed past the pelvis" % degrees)
		## A stable two-handed base: well clear of a narrow 14 cm stance, short
		## of the ~40 cm shoulders (authored in the clips, STANCE-FOOT-001).
		assert_between(float(read["width"]), 0.20, 0.28, "guard %.0f°: the ankles stand a base apart across the line (%.3f m)" % [degrees, float(read["width"])])
	var seen := {}
	for velocity: Vector2 in [Vector2(0.0, 2.4), Vector2(0.0, -2.4), Vector2(2.4, 0.0), Vector2(-2.4, 0.0)]:
		var row := _row(-PhysicalBaseline.GUARD_ANGLE_RAD)
		row.vx = velocity.x
		row.vy = velocity.y
		for step in 3:
			await _settle(proxy, row.weapon_angle, row, reading)
			proxy.animation_player().advance(0.21)
			seen[proxy.current_semantic()] = true
			check.call("%s, step %d" % [proxy.current_semantic(), step], guard_chest + Vector2(-2.0, 2.0))
	for semantic: StringName in [PresentationKit.ANIM_MOVE_FORWARD, PresentationKit.ANIM_ORBIT_LEFT, PresentationKit.ANIM_ORBIT_RIGHT]:
		assert_true(seen.has(semantic), "fixture: %s was exercised" % semantic)
	## A right-side charge coils the shoulders toward the loaded (lead) side, on
	## top of the base blade and within the lead load cap.
	var base := stance.chest_yaw_degrees
	await _settle(proxy, -PhysicalBaseline.GUARD_ANGLE_RAD, _row(-PhysicalBaseline.GUARD_ANGLE_RAD, CombatPhase.Id.CHARGING, 0.0, 0.6), reading)
	check.call("right charge", Vector2(base - stance.lead_load_coil_degrees - 0.1, base - stance.guard_coil_degrees))
	proxy.queue_free()


## PRES-HEADING-001 on the body: head and stance face the combat heading φ,
## the centre of the weapon domain, and only glance toward the target bearing
## τ. A small lag is glanced at in full; a committed cut's large lag is not
## covered — the head stays within `LOOK_LIMIT` of φ, so the opening reads.
func test_the_head_faces_the_heading_and_only_glances_at_the_target() -> void:
	var proxy := _proxy()
	var facing := PI * 0.5
	var head_yaw := func(offset: float) -> float:
		var row := _row(-PhysicalBaseline.GUARD_ANGLE_RAD)
		row.facing = facing
		row.target_bearing = facing + offset
		var pose: Dictionary = await _settle_facing(proxy, row, facing)
		var head: Transform3D = pose["Head"]
		var flat := Vector3(head.basis.z.x, 0.0, head.basis.z.z)
		return atan2(flat.x, flat.z)
	var limit := CombatPoseModifier3D.LOOK_LIMIT
	assert_between(rad_to_deg(limit), 10.0, 15.0, "the glance is a few degrees, not a lock-on")
	var square: float = await head_yaw.call(0.0)
	assert_near(proxy.look_offset(), 0.0, 1e-9, "fixture: no lag, no look")
	var sword_before := proxy.authoritative_blade_points()
	var glance: float = await head_yaw.call(limit * 0.5)
	assert_near(angle_difference(square, glance), limit * 0.5, 0.02, "a small lag is glanced at in full (%.3f rad)" % angle_difference(square, glance))
	var lagging: float = await head_yaw.call(0.4)
	assert_near(proxy.rig().combat_pose().look_offset, 0.4, 1e-9, "the proxy hands the lag to the head")
	assert_near(angle_difference(square, lagging), limit, 0.02, "a committed lag is not covered: the head stays within the glance of φ (%.3f rad)" % angle_difference(square, lagging))
	assert_true(proxy.authoritative_blade_points()[1].is_equal_approx(sword_before[1]), "while the sword stays on the combat heading")
	proxy.queue_free()


## `_settle` at an explicit facing, reading the head too.
func _settle_facing(proxy: FighterPresentation3D, row: PresentationFighter, facing: float) -> Dictionary:
	proxy.apply_pose(Vector3.ZERO, facing, row.weapon_angle, row, 1.0)
	proxy.apply_pose(Vector3.ZERO, facing, row.weapon_angle, row, 1.0 / 60.0)
	var skeleton := proxy.rig().skeleton()
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var seen := {}
	var capture := func() -> void:
		seen["Head"] = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Head"))
	skeleton.skeleton_updated.connect(capture)
	skeleton.advance(1.0 / 60.0)
	await await_frames(1)
	skeleton.skeleton_updated.disconnect(capture)
	return seen


## The right foot's lead (m) along the fighter's facing, measured on the
## imported skeleton as shown (the stance yaw on the rig and the modifier stack
## included). Skeleton global poses refresh on the skeleton's own update, so
## callers await a frame after posing before reading.
func _foot_lead(proxy: FighterPresentation3D) -> float:
	var skeleton := proxy.rig().skeleton()
	var into_proxy := proxy.global_transform.affine_inverse() * skeleton.global_transform
	var right := into_proxy * skeleton.get_bone_global_pose(skeleton.find_bone("Foot.R")).origin
	var left := into_proxy * skeleton.get_bone_global_pose(skeleton.find_bone("Foot.L")).origin
	return right.z - left.z


## How far apart (m) the ankles stand across the line — the base's width,
## measured like `_foot_lead`.
func _foot_width(proxy: FighterPresentation3D) -> float:
	var skeleton := proxy.rig().skeleton()
	var into_proxy := proxy.global_transform.affine_inverse() * skeleton.global_transform
	var right := into_proxy * skeleton.get_bone_global_pose(skeleton.find_bone("Foot.R")).origin
	var left := into_proxy * skeleton.get_bone_global_pose(skeleton.find_bone("Foot.L")).origin
	return absf(right.x - left.x)


## PRES-STANCE-001, by geometry rather than by flag: in the combat frame Wolf's
## right foot is ahead of his left — clearly at every settled moment, and
## never behind through any footwork clip. Gathering steps, not passing ones.
func test_the_right_foot_leads_through_every_footwork_clip() -> void:
	var proxy := _proxy()
	var kit := proxy.combatant_kit().fighter
	var animation := proxy.animation_player()
	assert_true(animation != null, "fixture: Wolf's authored scene has clips")
	proxy.apply_pose(Vector3.ZERO, 0.0, -PhysicalBaseline.GUARD_ANGLE_RAD, _row(-PhysicalBaseline.GUARD_ANGLE_RAD), 1.0 / 60.0)
	for semantic: StringName in [PresentationKit.ANIM_IDLE, PresentationKit.ANIM_CHARGE]:
		animation.play(kit.clip_for(semantic), 0.0)
		animation.seek(0.0, true)
		await await_frames(1)
		assert_true(_foot_lead(proxy) >= 0.06, "%s stands right foot forward by ≥ 6 cm (%.3f)" % [semantic, _foot_lead(proxy)])
	for semantic: StringName in [
		PresentationKit.ANIM_MOVE_FORWARD, PresentationKit.ANIM_MOVE_BACKWARD, PresentationKit.ANIM_ORBIT_LEFT, PresentationKit.ANIM_ORBIT_RIGHT,
		PresentationKit.ANIM_DASH_FORWARD, PresentationKit.ANIM_DASH_BACK, PresentationKit.ANIM_DASH_LEFT, PresentationKit.ANIM_DASH_RIGHT,
	]:
		var clip := kit.clip_for(semantic)
		assert_true(animation.has_animation(clip), "fixture: %s has a clip" % semantic)
		var length := animation.get_animation(clip).length
		animation.play(clip, 0.0)
		var worst := INF
		for step in 25:
			animation.seek(length * step / 24.0, true)
			await await_frames(1)
			worst = minf(worst, _foot_lead(proxy))
		assert_true(worst > 0.0, "%s never puts the right foot behind (worst lead %.3f m)" % [semantic, worst])
	proxy.queue_free()


## PRES-LOCO-001: charging never replaces locomotion. A fighter walking into a
## charge keeps the same gait clip — its phase running straight through, its
## rate following the slower ground speed — and keeps it through the release;
## a charge from a standstill keeps the idle legs under the charged torso.
func test_charging_slows_the_gait_instead_of_freezing_the_feet() -> void:
	var proxy := _proxy()
	var animation := proxy.animation_player()
	var walking := _row(-PhysicalBaseline.GUARD_ANGLE_RAD)
	walking.vx = 2.4
	proxy.apply_pose(Vector3.ZERO, 0.0, walking.weapon_angle, walking, 1.0 / 60.0)
	for _i in 20:
		proxy.apply_pose(Vector3.ZERO, 0.0, walking.weapon_angle, walking, 1.0 / 60.0)
		animation.advance(1.0 / 60.0)
	assert_eq(proxy.current_semantic(), PresentationKit.ANIM_MOVE_FORWARD, "fixture: walking forward")
	var gait := animation.current_animation
	await await_frames(1)
	var before := animation.current_animation_position
	var feet_before := _foot_lead(proxy)
	var charging := _row(-PhysicalBaseline.GUARD_ANGLE_RAD, CombatPhase.Id.CHARGING, 0.0, 0.5)
	charging.vx = 1.2
	proxy.apply_pose(Vector3.ZERO, 0.0, charging.weapon_angle, charging, 1.0 / 60.0)
	assert_eq(proxy.current_semantic(), PresentationKit.ANIM_MOVE_FORWARD, "a charge while walking keeps the gait")
	assert_eq(animation.current_animation, gait, "the same clip — never swapped for a standing support clip")
	assert_near(animation.speed_scale, 0.5, 1e-6, "playing at actual speed over the reference: slower feet for a slower body")
	for _i in 6:
		proxy.apply_pose(Vector3.ZERO, 0.0, charging.weapon_angle, charging, 1.0 / 60.0)
		animation.advance(1.0 / 60.0)
	var during := animation.current_animation_position
	assert_true(during != before, "the gait phase keeps running through the charge (%.3f → %.3f)" % [before, during])
	await await_frames(1)
	assert_true(absf(_foot_lead(proxy) - feet_before) > 1e-4, "and the feet keep moving")
	var released := _row(-PhysicalBaseline.GUARD_ANGLE_RAD, CombatPhase.Id.ACTIVE_EARLY, 0.2, 0.0, 0.5)
	released.vx = 1.2
	proxy.apply_pose(Vector3.ZERO, 0.0, released.weapon_angle, released, 1.0 / 60.0)
	assert_eq(animation.current_animation, gait, "the release does not restart the gait")
	var standing := _row(-PhysicalBaseline.GUARD_ANGLE_RAD, CombatPhase.Id.CHARGING, 0.0, 0.5)
	proxy.apply_pose(Vector3.ZERO, 0.0, standing.weapon_angle, standing, 1.0 / 60.0)
	assert_eq(proxy.current_semantic(), PresentationKit.ANIM_CHARGE, "a standing charge shows the support clip")
	assert_near(animation.speed_scale, 1.0, 1e-6, "at its authored rate")
	## Past the cross-fade, so the legs read are the clip's alone.
	animation.advance(0.5)
	await await_frames(1)
	var charge_lead := _foot_lead(proxy)
	animation.play(proxy.combatant_kit().fighter.clip_for(PresentationKit.ANIM_IDLE), 0.0)
	animation.seek(0.0, true)
	await await_frames(1)
	assert_near(charge_lead, _foot_lead(proxy), 1e-3, "whose legs are the idle stance's")
	proxy.queue_free()


## One stab timeline (PRES-STAB-001): its beats are causal, the striker holds
## and withdraws on them, and the victim's clip holds impaled on supporting
## legs until the blade is clear, and only then goes down.
func test_a_killing_thrust_plays_one_causal_timeline() -> void:
	var profile := RiposteKits.build_catalog().resolve(ContentIds.FIGHTER_DUELIST, PresentationKit.PRIMITIVE_FIGHTER).death
	var finisher := profile.stab_timeline()
	assert_true(finisher.is_causal(), "the authored beats are in causal order")
	assert_true(finisher.victim_collapse_start >= finisher.withdraw_clear, "the victim never falls while impaled")
	var spec := profile.resolve(DeathPresentationProfile.Family.STAB, 3)
	assert_near(spec.collapse_delay, finisher.victim_collapse_start, 1e-9, "the victim waits for the blade")
	assert_near(spec.weapon_release_time, finisher.victim_weapon_release, 1e-9, "and drops the sword only once falling")
	assert_eq(profile.resolve(DeathPresentationProfile.Family.SLASH, 3).collapse_delay, 0.0, "a cut-down body does not wait")
	var victim := _proxy()
	var player := victim.animation_player()
	var clip := player.get_animation(&"death_stab")
	var skeleton := victim.rig().skeleton()
	var legs := [&"Hips", &"UpperLeg.L", &"UpperLeg.R", &"LowerLeg.L", &"LowerLeg.R"]
	var held := {}
	for bone: StringName in legs:
		var track := clip.find_track(NodePath("%s:%s" % [player.get_node(player.root_node).get_path_to(skeleton), bone]), Animation.TYPE_ROTATION_3D)
		assert_true(track >= 0, "fixture: the clip keys %s" % bone)
		## Inside the hold (a frame clear of each beat, whichever way the
		## exporter maps frame numbers to seconds).
		## Within half a degree: imported clips are compressed, so "held" is a
		## tolerance, not bit equality.
		held[bone] = clip.rotation_track_interpolate(track, finisher.withdraw_start)
		var through := (held[bone] as Quaternion).angle_to(clip.rotation_track_interpolate(track, finisher.withdraw_clear))
		var until := (held[bone] as Quaternion).angle_to(clip.rotation_track_interpolate(track, finisher.victim_collapse_start - 1.0 / 60.0))
		assert_true(through < deg_to_rad(0.5), "%s holds impaled through the withdrawal (%.2f°)" % [bone, rad_to_deg(through)])
		assert_true(until < deg_to_rad(0.5), "%s still holds when the blade is clear (%.2f°)" % [bone, rad_to_deg(until)])
	var fallen := false
	for bone: StringName in legs:
		var track := clip.find_track(NodePath("%s:%s" % [player.get_node(player.root_node).get_path_to(skeleton), bone]), Animation.TYPE_ROTATION_3D)
		fallen = fallen or (held[bone] as Quaternion).angle_to(clip.rotation_track_interpolate(track, finisher.end)) > deg_to_rad(10.0)
	assert_true(fallen, "and only then goes down")
	var striker := _proxy()
	var victim_slot := _proxy()
	var fighters: Array[FighterPresentation3D] = [striker, victim_slot]
	var request := DeathPresentationRequest.create(1, DeathPresentationProfile.Family.STAB, Vector3.RIGHT, 1.0, 3, 0)
	request.spec = spec
	PrimitiveDeathBackend.new(fighters).start(request)
	assert_true(striker.is_finishing(), "the striker holds the run-through")
	assert_near(victim_slot.death_hold(), finisher.victim_collapse_start, 1e-9, "the victim's collapse is held for the blade")
	var row := _row(0.0)
	for _i in roundi(finisher.striker_recover_end * 60.0) + 2:
		striker.apply_pose(Vector3.ZERO, 0.0, 0.0, row, 1.0 / 60.0)
	assert_false(striker.is_finishing(), "and is back in guard at the timeline's recovery")
	for proxy: FighterPresentation3D in [victim, striker, victim_slot]:
		proxy.queue_free()
