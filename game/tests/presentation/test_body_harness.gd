extends TestCase

## PRES-BODY: the body-agnostic integration harness (WEAPON-PATH-004 Stages 7.1 / 8). One harness, run per body, each
## body's results its own: the shipping blockout (the common grip), a controlled authored-hand-contact fixture (the
## blockout's own rig and mesh with known authored contacts, packed as a fighter skin, through the real integration
## code), and the F8 production candidate, which the art plan delivers — until it exists its status reads "not yet
## available", and a blockout or fixture pass is never production evidence.
##
## For every body, over the guard window, a charge, both cut origins, recovery and a real full-charge cut (the X
## sequence), the final post-modifier bones are read at `modification_processed` of the stack's last modifier
## (`GripHandsModifier3D`), and:
## - the weapon owns the grip stations (`WeaponPresentationConfig.weapon_grip_stations`); art's markers agree;
## - each feasible hand reaches its resolved wrist within 2 mm; an unreachable one is reported infeasible (its reach),
##   never stretched: arm segments keep their rest lengths;
## - an authored contact holds the hand exactly on `T_sword · T_weapon_grip · T_rig_hand_offset`; the common grip keeps
##   its knuckle line on the handle;
## - the dominant (right) hand holds nearer the guard; elbows keep their branch through the X sequence;
## - the skinned mesh's hand surrounds the drawn handle;
## - the same presentation instant gives the same final bones at 30 / 60 / 120 / 144 FPS.
##
## Implements: /spec/invariants.md#weapon-path-004
## See also: /docs/concepts/presentation.md

const STATUS_AVAILABLE := "available"
const STATUS_NOT_YET := "not yet available"
## The F8 production Wolf's wrapper, delivered by the art plan.
const PRODUCTION_CANDIDATE := "res://assets/presentation/fighters/duelist/wolf_candidate_wrapper.tscn"
const SHIPPING_WRAPPER := "res://assets/presentation/fighters/duelist/wolf_wrapper.tscn"
## The IK reaches a feasible wrist target within the established grip tolerance.
const WRIST_TOLERANCE := 0.002
const ORIENTATION_TOLERANCE_DEG := 2.0
## Arm segments keep their rest length (PRES-RIG's stretch tolerance).
const STRETCH_TOLERANCE := 0.01
## The hand's mesh surrounds the handle (PRES-RIG / PRES-PRODUCTION's grip tolerance; block hands are ~7 cm).
const HAND_ON_HANDLE := 0.035
const RENDER_RATES: PackedInt32Array = [30, 60, 120, 144]
const KEYS_PER_SECOND := 720
const KEYS_PER_TICK := 12
## Every 1/30 s: an instant all four rates draw.
const SHARED_KEYS := 24
const BONES: Array[String] = ["UpperArm.R", "Forearm.R", "Hand.R", "UpperArm.L", "Forearm.L", "Hand.L"]

var _rules: DuelRules


func _init() -> void:
	suite_name = "PRES-BODY"
	_rules = StandardDuelRules.create()


## The bodies the harness can run today, and the production candidate's status.
func _bodies() -> Array[Dictionary]:
	return [
		{"label": "blockout", "kind": "shipping baseline", "scene": null, "authored": false},
		{"label": "authored-contact fixture", "kind": "fixture", "scene": _authored_fixture(), "authored": true},
	]


static func candidate_status() -> String:
	return STATUS_AVAILABLE if ResourceLoader.exists(PRODUCTION_CANDIDATE) else STATUS_NOT_YET


## The shipping blockout's own wrapper with known authored contacts: each hand's contact frame equal to the common
## grip's rest frame (`T_contact = (H⁻¹, (0, hand length, 0))`, H the common grip's hand turn), so the expected hand
## transform on the sword is known exactly. No grip diagonal (an authored contact carries its own).
func _authored_fixture() -> PackedScene:
	var rig := (load(SHIPPING_WRAPPER) as PackedScene).instantiate() as SwordRig3D
	var contacts: Array[Transform3D] = []
	for index in 2:
		var turn := SwordGripFrame.hand_basis(SwordGripFrame.COMMON_HAND_AXIS, rig.hand_span_axes[index])
		contacts.append(Transform3D(turn.inverse(), Vector3(0.0, SwordRig3D.HAND_LENGTH, 0.0)))
	rig.grip_contacts = contacts
	rig.grip_diagonal_deg = 0.0
	var packed := PackedScene.new()
	packed.pack(rig)
	rig.free()
	return packed


func _proxy_for(scene: PackedScene) -> FighterPresentation3D:
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	if scene != null:
		var skin := FighterSkinKit.new()
		skin.skin_id = &"test.body_harness"
		skin.scene = scene
		kits.combatant(0).fighter_skin = skin
	var spec := _rules.combatant(0)
	var proxy := FighterPresentation3D.create(0, DuelSide.Id.LIGHT_SOUTH, kits.combatant(0), spec.fighter.push_radius, spec)
	(Engine.get_main_loop() as SceneTree).root.add_child(proxy)
	return proxy


func _row(angle: float, phase: CombatPhase.Id, progress: float = 0.5, charge: float = 0.0, cut_dir: float = 1.0) -> PresentationFighter:
	var row := PresentationFighter.new()
	row.health = 100.0
	row.weapon_angle = angle
	row.phase = phase
	row.swing_progress = progress
	row.charge = charge
	row.swing_charge = charge
	row.cut_dir = cut_dir
	row.target_bearing = PI * 0.5
	return row


## Pose `row` (twice: a long first step lets any carry settle) and read the final bones and resolved targets inside
## `modification_processed` of the last modifier, where the modified pose is live.
func _final(proxy: FighterPresentation3D, row: PresentationFighter) -> Dictionary:
	proxy.apply_pose(Vector3.ZERO, PI * 0.5, row.weapon_angle, row, 1.0)
	proxy.apply_pose(Vector3.ZERO, PI * 0.5, row.weapon_angle, row, 1.0 / 60.0)
	return await _read(proxy, 1.0 / 60.0)


func _read(proxy: FighterPresentation3D, delta: float) -> Dictionary:
	var skeleton := proxy.rig().skeleton()
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var seen := {}
	var capture := func() -> void:
		for bone_name in BONES:
			seen[bone_name] = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name))
		var targets := []
		for target in proxy.rig().hand_targets():
			targets.append({"target": target.target, "feasible": target.feasible, "reach": target.reach, "valid": target.valid})
		seen["targets"] = targets
		seen["globals"] = _globals(skeleton)
	var last := proxy.rig().grip_hands()
	last.modification_processed.connect(capture)
	skeleton.advance(delta)
	await await_frames(1)
	last.modification_processed.disconnect(capture)
	return seen


static func _globals(skeleton: Skeleton3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		out.append(skeleton.get_bone_global_pose(bone))
	return out


## The guard window, a charge, both cut origins and recovery.
func _samples() -> Array[PresentationFighter]:
	var out: Array[PresentationFighter] = []
	for degrees in range(-135, 136, 45):
		var angle := deg_to_rad(float(degrees))
		out.append(_row(angle, CombatPhase.Id.NEUTRAL))
		out.append(_row(angle, CombatPhase.Id.CHARGING, 0.0, 0.6))
		out.append(_row(angle, CombatPhase.Id.ACTIVE_THREAT, 0.5, 0.5, 1.0))
		out.append(_row(angle, CombatPhase.Id.ACTIVE_THREAT, 0.5, 0.5, -1.0))
		out.append(_row(angle, CombatPhase.Id.RECOVERY, 1.0, 0.0, 1.0))
	return out


## Every body: grips on the weapon's own stations, feasible wrists reached within 2 mm and unreachable ones reported,
## arm segments never stretched, an authored contact exact on its full grip frame (the common grip's knuckle line on
## the handle), the dominant hand nearer the guard, and the skinned hand surrounding the drawn handle.
func test_every_body_holds_the_weapon_on_its_own_grip_stations() -> void:
	for body in _bodies():
		var label: String = body["label"]
		## ARRANGE
		var proxy := _proxy_for(body["scene"])
		var config := proxy.weapon_config()
		var stations := WeaponPresentationConfig.weapon_grip_stations(_rules.combatant(0).weapon)
		assert_eq(proxy.rig().has_contacts(), bool(body["authored"]), "fixture: %s holds the sword through %s" % [label, "authored contacts" if body["authored"] else "the common grip"])
		assert_eq(proxy.rig().contract_problems().size(), 0, "fixture: %s's rig contract is clean: %s" % [label, ", ".join(proxy.rig().contract_problems())])
		for index in 2:
			assert_true(config.grip_stations[index] == stations[index], "%s hand %d: holds the weapon's own grip station" % [label, index])
			var marker := proxy.rig().marker_stations(proxy.weapon_model())[index]
			assert_true(marker.distance_to(stations[index]) < 1.0e-3, "%s hand %d: art's grip marker agrees with the weapon's station (%.5f m)" % [label, index, marker.distance_to(stations[index])])
		var skinned := HandMesh.new()
		skinned.read(proxy.visual_root(), proxy.rig().skeleton())
		assert_true(skinned.has_hands(), "fixture: %s has a skinned mesh with rigid hands" % label)
		var reached := 0
		var infeasible := 0
		var worst_wrist := 0.0
		var worst_turn := 0.0
		var worst_stretch := 0.0
		var worst_mesh := 0.0
		var samples := _samples()
		for row in samples:
			## ACT
			var final: Dictionary = await _final(proxy, row)
			## ASSERT
			var into_world := proxy.visual_root().global_transform
			var weapon := into_world * proxy.weapon_pose().weapon
			for index in 2:
				var target: Dictionary = (final["targets"] as Array)[index]
				var hand: Transform3D = final[BONES[2 + 3 * index]]
				assert_true(bool(target["valid"]), "%s: the hand targets were resolved this update" % label)
				var miss := hand.origin.distance_to((target["target"] as Transform3D).origin)
				if bool(target["feasible"]):
					worst_wrist = maxf(worst_wrist, miss)
					reached += 1
				else:
					infeasible += 1
					assert_true(float(target["reach"]) > 1.0 - 1.0e-6, "%s: a target is reported infeasible only past its arm's reach (%.4f)" % [label, float(target["reach"])])
				if bool(body["authored"]):
					var expected := weapon * config.grip_frames[index]
					worst_turn = maxf(worst_turn, rad_to_deg((expected.basis.orthonormalized().inverse() * hand.basis.orthonormalized()).get_rotation_quaternion().get_angle()))
					assert_true(expected.basis.orthonormalized().is_equal_approx((weapon * Transform3D(Basis.IDENTITY, stations[index]) * proxy.rig().grip_contacts[index].affine_inverse()).basis.orthonormalized()), "%s hand %d: the frame is T_sword · T_weapon_grip · T_rig_hand_offset" % [label, index])
				else:
					## The common grip: the hand completes its resolved target; the hand tilts `TILT_MIN..TILT_MAX` off
					## the handle following its arm, so the knuckle line (the handle across the hand) sits within
					## `90° − TILT_MIN` of the handle, plus any declared grip diagonal.
					var resolved := (target["target"] as Transform3D).basis.orthonormalized()
					worst_turn = maxf(worst_turn, rad_to_deg((resolved.inverse() * hand.basis.orthonormalized()).get_rotation_quaternion().get_angle()))
					var span := (hand.basis * proxy.rig().hand_span_axes[index]).normalized()
					var diagonal := rad_to_deg(acos(clampf(absf(span.dot(weapon.basis.z.normalized())), 0.0, 1.0)))
					var allowed := 90.0 - rad_to_deg(SwordGripFrame.TILT_MIN) + proxy.rig().grip_diagonal_deg + 1.0
					assert_true(diagonal <= allowed, "%s hand %d at %.0f° phase %d: the knuckle line within the common grip's range of the handle (%.1f° of %.1f°)" % [label, index, rad_to_deg(row.weapon_angle), row.phase, diagonal, allowed])
			worst_stretch = maxf(worst_stretch, _stretch(proxy.rig().skeleton(), final))
			var along_r := (_palm(final["Hand.R"]) - weapon.origin).dot(weapon.basis.z.normalized())
			var along_l := (_palm(final["Hand.L"]) - weapon.origin).dot(weapon.basis.z.normalized())
			assert_true(along_r > along_l, "%s: the dominant hand holds nearer the guard (%.3f vs %.3f m)" % [label, along_r, along_l])
			var handle_from := weapon.origin
			var handle_to := weapon * Vector3(0.0, 0.0, _rules.combatant(0).weapon.crossguard_centre_radius)
			worst_mesh = maxf(worst_mesh, skinned.hands_off_handle(final["globals"], proxy.rig().skeleton().global_transform, handle_from, handle_to))
		assert_true(worst_wrist <= WRIST_TOLERANCE, "%s: every feasible wrist reached within 2 mm (worst %.5f m, %d reached, %d infeasible)" % [label, worst_wrist, reached, infeasible])
		assert_true(reached > infeasible, "fixture: %s reaches most of its targets (%d of %d)" % [label, reached, reached + infeasible])
		assert_true(worst_stretch <= STRETCH_TOLERANCE, "%s: arm segments keep their rest lengths (worst %.4f)" % [label, worst_stretch])
		assert_true(worst_mesh <= HAND_ON_HANDLE, "%s: the skinned hands surround the drawn handle (worst %.4f m)" % [label, worst_mesh])
		assert_true(worst_turn <= ORIENTATION_TOLERANCE_DEG, "%s: the hand holds its %s (worst %.2f°)" % [label, "full authored grip frame" if bool(body["authored"]) else "resolved target", worst_turn])
		print("PRES-BODY %s (%s): %d samples, wrist worst %.2f mm, infeasible %d, stretch worst %.2f %%, hand-to-handle worst %.1f mm, hand turn worst %.2f°" % [label, body["kind"], samples.size(), worst_wrist * 1000.0, infeasible, worst_stretch * 100.0, worst_mesh * 1000.0, worst_turn])
		proxy.queue_free()


## Stage 7.1 reach on every available body: the real full-charge cut from both origins (the X sequence). Both hands'
## targets are feasible or reported, and the elbows keep their branch: each elbow's bend direction (its offset from the
## shoulder–wrist line) never swings past 90° between consecutive samples — a flip to the other side of the arm.
func test_every_body_follows_the_x_sequence_on_a_stable_elbow_branch() -> void:
	for body in _bodies():
		var label: String = body["label"]
		var proxy := _proxy_for(body["scene"])
		var sequences := 0
		for side: float in [-1.0, 1.0]:
			## ARRANGE: a real full-charge cut from `side`.
			var rows := _cut_rows(side)
			assert_true(rows.size() > 10, "fixture: %s's cut from %s travels (%d ticks)" % [label, "right" if side < 0.0 else "left", rows.size()])
			var previous := {}
			var worst := 0.0
			var infeasible := 0
			for row in rows:
				## ACT
				var final: Dictionary = await _final(proxy, row)
				## ASSERT
				for target: Dictionary in final["targets"]:
					infeasible += 0 if bool(target["feasible"]) else 1
				for side_name: String in ["R", "L"]:
					var shoulder := (final["UpperArm." + side_name] as Transform3D).origin
					var elbow := (final["Forearm." + side_name] as Transform3D).origin
					var wrist := (final["Hand." + side_name] as Transform3D).origin
					var line := (wrist - shoulder).normalized()
					var bend := (elbow - shoulder) - line * (elbow - shoulder).dot(line)
					if bend.length() < 1.0e-4:
						continue
					bend = bend.normalized()
					if previous.has(side_name):
						worst = maxf(worst, rad_to_deg(bend.angle_to(previous[side_name])))
					previous[side_name] = bend
			assert_true(worst < 90.0, "%s, cut from the %s: the elbows keep their branch (worst bend swing %.1f° between samples)" % [label, "right" if side < 0.0 else "left", worst])
			print("PRES-BODY %s X sequence from the %s: %d samples, worst elbow bend swing %.1f°, %d infeasible targets" % [label, "right" if side < 0.0 else "left", rows.size(), worst, infeasible])
			sequences += 1
		assert_eq(sequences, 2, "both origins drawn")
		proxy.queue_free()


## Render-rate independence on the real fighter: guard snapshots then a real cut, drawn as `MatchPresenter` draws them
## at 30 / 60 / 120 / 144 FPS (clips stepped by each frame's presentation delta, as the engine steps them), compared at
## the instants all four rates share. The drawn weapon is identical at any rate; an authored contact's hand targets and
## final hands are too (they read only the weapon). The body clip layer under the IK is measured and reported, not
## asserted: the AnimationPlayer starts a snapshot's clip on the first frame drawn after it — a recorded limitation
## owned by the art plan's AnimationTree clip layer.
func test_every_body_draws_the_same_bones_at_every_render_rate() -> void:
	for body in _bodies():
		var label: String = body["label"]
		## Guard snapshots, then the cut: the clip switches at a snapshot boundary inside the compared span.
		var cut := _cut_rows(-1.0)
		var rows: Array[PresentationFighter] = []
		for _step in 4:
			rows.append(_row(cut[0].weapon_angle, CombatPhase.Id.NEUTRAL))
		rows.append_array(cut.slice(0, 10))
		var drawn: Array[Dictionary] = []
		var switches := {label: 0}
		for rate in RENDER_RATES:
			## ACT
			var proxy := _proxy_for(body["scene"])
			## The engine's own per-frame clip step, driven here with each frame's presentation delta.
			proxy.animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			var at := {}
			var clip := &""
			var drawn_at := NAN
			var step := roundi(float(KEYS_PER_SECOND) / float(rate))
			var key := 0
			for i in range(1, rows.size()):
				proxy.advance(rows[i - 1], rows[i], SimulationTimebase.ticks_to_seconds(i - 1))
				while key <= i * KEYS_PER_TICK:
					var weight := float(key - (i - 1) * KEYS_PER_TICK) / float(KEYS_PER_TICK)
					var lift := MatchPresenter.lift_inputs(rows[i - 1], rows[i], weight)
					var sample := lerpf(SimulationTimebase.ticks_to_seconds(i - 1), SimulationTimebase.ticks_to_seconds(i), weight)
					## The presentation time since the last drawn frame (none before the first).
					var delta := 0.0 if is_nan(drawn_at) else sample - drawn_at
					drawn_at = sample
					proxy.apply_pose(Vector3.ZERO, PI * 0.5, lerpf(rows[i - 1].weapon_angle, rows[i].weapon_angle, weight), rows[i], delta, 1.0, lift.x, lift.y, sample)
					proxy.animation_player().advance(delta)
					if proxy.playing_clip() != clip:
						if clip != &"":
							switches[label] += 1
						clip = proxy.playing_clip()
					var final: Dictionary = await _read(proxy, delta)
					final["weapon"] = proxy.weapon_pose().weapon
					if key % SHARED_KEYS == 0:
						at[key] = final
					key += step
			drawn.append(at)
			proxy.queue_free()
		## ASSERT: the weapon-critical chain is rate-independent; the body clip layer is measured.
		var shared := 0
		var worst_weapon := 0.0
		var worst_target := 0.0
		var worst_hand := 0.0
		var body_layer := {}
		for key: int in drawn[0]:
			for index in range(1, drawn.size()):
				if not drawn[index].has(key):
					continue
				shared += 1
				var weapon_a: Transform3D = drawn[0][key]["weapon"]
				var weapon_b: Transform3D = drawn[index][key]["weapon"]
				worst_weapon = maxf(worst_weapon, maxf(weapon_a.origin.distance_to(weapon_b.origin), (weapon_a.basis.z - weapon_b.basis.z).length()))
				for hand in 2:
					var a: Transform3D = (drawn[0][key]["targets"] as Array)[hand]["target"]
					var b: Transform3D = (drawn[index][key]["targets"] as Array)[hand]["target"]
					worst_target = maxf(worst_target, a.origin.distance_to(b.origin))
					var hand_bone: String = BONES[2 + 3 * hand]
					worst_hand = maxf(worst_hand, (drawn[0][key][hand_bone] as Transform3D).origin.distance_to((drawn[index][key][hand_bone] as Transform3D).origin))
				for bone_name: String in ["UpperArm.R", "Forearm.R", "UpperArm.L", "Forearm.L"]:
					var apart := (drawn[0][key][bone_name] as Transform3D).origin.distance_to((drawn[index][key][bone_name] as Transform3D).origin)
					body_layer[bone_name] = maxf(float(body_layer.get(bone_name, 0.0)), apart)
		assert_true(shared >= 3, "fixture: %s shares instants across rates (%d)" % [label, shared])
		assert_true(switches[label] >= 1, "fixture: %s switched clips inside the compared span (%d)" % [label, switches[label]])
		assert_true(worst_weapon <= 1.0e-6, "%s: the same instant draws the same weapon at any rate (worst %.8f)" % [label, worst_weapon])
		if bool(body["authored"]):
			## An authored contact holds the hand on the weapon alone: its target and the hand never read the body.
			assert_true(worst_target <= 1.0e-4, "%s: the same instant resolves the same hand targets at any rate (worst %.6f m)" % [label, worst_target])
			assert_true(worst_hand <= 1.0e-4, "%s: and the final hands land on them alike (worst %.6f m)" % [label, worst_hand])
		## Recorded limitation (art plan, AnimationTree clip layer): the AnimationPlayer starts a snapshot's clip and its
		## cross-fade on the first frame drawn after it, so shoulders and elbows under the IK can differ by rate.
		print("PRES-BODY %s render rates: weapon worst %s, hand targets worst %.3f mm, hands worst %.3f mm; body clip layer (limitation) %s" % [label, String.num_scientific(worst_weapon), worst_target * 1000.0, worst_hand * 1000.0, str(body_layer)])


## The production candidate runs this same harness the moment the art plan delivers it; until then it is reported
## "not yet available", never folded into a passing summary.
func test_the_production_candidate_is_reported_until_it_exists() -> void:
	var status := candidate_status()
	print("PRES-BODY production candidate (%s): %s" % [PRODUCTION_CANDIDATE, status])
	assert_eq(status, STATUS_AVAILABLE if ResourceLoader.exists(PRODUCTION_CANDIDATE) else STATUS_NOT_YET, "the candidate's status is what exists, never assumed")
	var labels := PackedStringArray()
	for body in _bodies():
		labels.append(body["label"])
	assert_false(labels.has("production candidate") and status == STATUS_NOT_YET, "a missing candidate is never among the bodies run")


func _cut_rows(side: float) -> Array[PresentationFighter]:
	var rig := WeaponRig.create(_rules)
	rig.fighter.weapon.reset(_rules.combatant(0).weapon.guard_angle * side)
	rig.press()
	while rig.fighter.weapon.charge < 1.0 and rig.tick < 240:
		rig.step()
	rig.release()
	var rows: Array[PresentationFighter] = []
	for _i in 120:
		var row := SnapshotProjector._fighter(rig.fighter, rig.opponent, _rules)
		row.target_bearing = PI * 0.5
		rows.append(row)
		if row.phase == CombatPhase.Id.NEUTRAL and rows.size() > 20:
			break
		rig.step()
	return rows


static func _palm(pose: Transform3D) -> Vector3:
	return pose.origin + pose.basis.y.normalized() * SwordRig3D.HAND_LENGTH


## The worst relative change of any arm segment from its rest length.
static func _stretch(skeleton: Skeleton3D, final: Dictionary) -> float:
	var worst := 0.0
	for side: String in ["R", "L"]:
		var chain: Array[String] = ["UpperArm." + side, "Forearm." + side, "Hand." + side]
		for link in 2:
			var posed := (final[chain[link]] as Transform3D).origin.distance_to((final[chain[link + 1]] as Transform3D).origin)
			var rest := skeleton.get_bone_global_rest(skeleton.find_bone(chain[link])).origin.distance_to(skeleton.get_bone_global_rest(skeleton.find_bone(chain[link + 1])).origin)
			worst = maxf(worst, absf(posed / rest - 1.0))
	return worst


## The skinned mesh's rigid hand vertices, skinned on demand with final bone poses.
class HandMesh:
	var _hands: Array = [[], []]

	func read(root: Node, skeleton: Skeleton3D) -> void:
		var bones := [skeleton.find_bone("Hand.R"), skeleton.find_bone("Hand.L")]
		for node: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.mesh == null or mesh.skin == null:
				continue
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var slots: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var stride := roundi(float(slots.size()) / float(maxi(1, verts.size())))
				for index in verts.size():
					for slot in stride:
						var bind := slots[index * stride + slot]
						var bone := mesh.skin.get_bind_bone(bind)
						if bone < 0:
							bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
						var hand := bones.find(bone)
						if hand >= 0 and weights[index * stride + slot] >= 0.99:
							(_hands[hand] as Array).append([bone, mesh.skin.get_bind_pose(bind) * verts[index]])

	func has_hands() -> bool:
		return not (_hands[0] as Array).is_empty() and not (_hands[1] as Array).is_empty()

	## The worst distance from either skinned hand's vertex centroid to the handle segment.
	func hands_off_handle(globals: Array[Transform3D], skeleton_world: Transform3D, from: Vector3, to: Vector3) -> float:
		var worst := 0.0
		for hand: Array in _hands:
			var sum := Vector3.ZERO
			for vertex: Array in hand:
				sum += skeleton_world * (globals[int(vertex[0])] * (vertex[1] as Vector3))
			var centre := sum / float(hand.size())
			var span := to - from
			var on := from + span * clampf((centre - from).dot(span) / span.length_squared(), 0.0, 1.0)
			worst = maxf(worst, centre.distance_to(on))
		return worst
