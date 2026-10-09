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

var _rules: DuelRules


func _init() -> void:
	suite_name = "PRES-RIG"
	_rules = StandardDuelRules.create()


func _proxy(fighter_skin: StringName = &"") -> FighterPresentation3D:
	var catalog := RiposteKits.build_catalog()
	var skins: Array[StringName] = [fighter_skin, &""]
	var kits := DuelKits.resolve(catalog, _rules, skins)
	var proxy := FighterPresentation3D.create(0, DuelSide.Id.LIGHT_SOUTH, kits.combatant(0), _rules.fighter.body_radius, _rules.weapon.hilt_radius, _rules.weapon.tip_radius)
	(Engine.get_main_loop() as SceneTree).root.add_child(proxy)
	return proxy


func _row(angle: float) -> PresentationFighter:
	var row := PresentationFighter.new()
	row.health = 100.0
	row.weapon_angle = angle
	return row


## Pose the proxy and run the skeleton's modifier stack (chest follow, IK)
## once, reading the result where Godot exposes it: inside `skeleton_updated`.
## Modifier output is applied for the update and reverted after it.
func _settle(proxy: FighterPresentation3D, angle: float) -> Dictionary:
	proxy.apply_pose(Vector3.ZERO, PI * 0.5, angle, _row(angle), 1.0 / 60.0)
	var skeleton := proxy.rig().skeleton()
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var seen := {}
	var capture := func() -> void:
		for bone_name: String in ["Hand.R", "Hand.L", "Forearm.R", "Forearm.L", "Chest"]:
			seen[bone_name] = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name))
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
	assert_near(tip.z, _rules.weapon.tip_radius, 1e-3, "the authored tip is exactly the rules' reach")
	assert_near(SwordRig3D._marker(sword, &"TrailStart", 0.0).z, _rules.weapon.hilt_radius, 1e-3, "and the blade starts at the duelist's grip")
	sword.free()


func test_hands_stay_on_the_grip_through_the_whole_legal_arc() -> void:
	var proxy := _proxy()
	assert_true(proxy.rig() != null and proxy.rig().is_bound(), "precondition: the authored rig is bound to the sword")
	var limit := rad_to_deg(_rules.weapon.guard_limit)
	var worst := 0.0
	var flips := 0
	var trace := PackedStringArray()
	var degrees := -limit
	while degrees <= limit + 1e-6:
		var angle := deg_to_rad(degrees)
		var pose: Dictionary = await _settle(proxy, angle)
		assert_eq(pose.size(), 5, "precondition: the modifier stack ran at %.0f°" % degrees)
		var blade := proxy.blade_points()
		for index in 2:
			var target := proxy.rig().grip_target(index).global_position
			var palm := _palm(pose["Hand.R" if index == 0 else "Hand.L"])
			worst = maxf(worst, palm.distance_to(target))
			var wrist: Vector3 = (pose["Hand.R" if index == 0 else "Hand.L"] as Transform3D).origin
			trace.append("%.0f/%d:%.3f w%.3f" % [degrees, index, palm.distance_to(target), wrist.distance_to(target)])
		## Elbows stay on their own side of the chest: right elbow right of
		## centre, left elbow left of it, whatever the sword does.
		var chest: Transform3D = pose["Chest"]
		var right_elbow: Vector3 = chest.affine_inverse() * (pose["Forearm.R"] as Transform3D).origin
		var left_elbow: Vector3 = chest.affine_inverse() * (pose["Forearm.L"] as Transform3D).origin
		if right_elbow.x > 0.02 or left_elbow.x < -0.02:
			flips += 1
		var expected_tip := proxy.sword_pivot().global_transform * Vector3(0.0, 0.0, _rules.weapon.tip_radius)
		assert_true(blade[1].is_equal_approx(expected_tip), "the blade is where the simulation put it at %.0f°" % degrees)
		degrees += ARC_STEP_DEGREES
	assert_true(worst < GRIP_TOLERANCE, "hands stay on the grip across ±%.0f° (worst %.3f m: %s)" % [limit, worst, " ".join(trace)])
	assert_eq(flips, 0, "and no elbow ever inverts")
	proxy.queue_free()


## The neutral-guard silhouette gate: in the resting guard the elbows must
## project out of the torso, not clamp the weapon against the ribs. Each
## elbow, in chest-local space, is lateral beyond the body radius and forward
## of the chest (+Z), while the hands stay on the grip. This is the gameplay-
## camera read the backward-biased pole used to fail.
func test_the_neutral_guard_opens_the_elbows_away_from_the_torso() -> void:
	var proxy := _proxy()
	var pose: Dictionary = await _settle(proxy, 0.0)
	assert_eq(pose.size(), 5, "precondition: the modifier stack ran")
	var chest: Transform3D = pose["Chest"]
	var body_radius := _rules.fighter.body_radius
	for arm: Array in [["Forearm.R", "Hand.R", -1.0], ["Forearm.L", "Hand.L", 1.0]]:
		var elbow: Vector3 = chest.affine_inverse() * (pose[arm[0]] as Transform3D).origin
		var side: float = arm[2]
		assert_true(elbow.x * side > body_radius, "%s elbow projects laterally past the torso (local x %.3f, side %.0f)" % [arm[0], elbow.x, side])
		assert_true(elbow.z > -0.05, "%s elbow is not tucked behind the chest (local z %.3f)" % [arm[0], elbow.z])
		var index := 0 if side < 0.0 else 1
		var palm := _palm(pose[arm[1]])
		assert_true(palm.distance_to(proxy.rig().grip_target(index).global_position) < GRIP_TOLERANCE, "%s hand stays on its grip" % arm[1])
	var tip := proxy.sword_pivot().global_transform * Vector3(0.0, 0.0, _rules.weapon.tip_radius)
	assert_true(proxy.blade_points()[1].is_equal_approx(tip), "the blade did not move for the guard pose")
	proxy.queue_free()


## The Mittelhau kinetic chain: the body supports the sword with the chest
## turning most, the spine less, the hips least, and the head counter-rotating
## so it stays on the opponent. The ordering is the contract, not the numbers.
func test_the_body_supports_the_cut_as_a_kinetic_chain() -> void:
	assert_eq(KineticChainModifier3D.world_follow(&"Chest", 0.0), 0.0, "guard: no twist")
	var angle := PI * 0.5
	var hips := KineticChainModifier3D.world_follow(&"Hips", angle)
	var spine := KineticChainModifier3D.world_follow(&"Spine", angle)
	var chest := KineticChainModifier3D.world_follow(&"Chest", angle)
	var head := KineticChainModifier3D.world_follow(&"Head", angle)
	assert_true(chest > spine and spine > hips and hips > 0.0, "falloff down the chain: chest %.3f > spine %.3f > hips %.3f > 0" % [chest, spine, hips])
	assert_true(chest > angle * 0.3 and chest < angle * 0.45, "the chest follows roughly a third of the sword (%.3f of %.3f)" % [chest, angle])
	assert_true(head < chest, "the head counter-rotates toward the opponent rather than turning with the chest (head %.3f < chest %.3f)" % [head, chest])
	assert_true(head >= 0.0 and head < spine, "and stays substantially opponent-oriented (head %.3f)" % head)
	assert_near(KineticChainModifier3D.world_follow(&"Chest", -angle), -chest, 1e-9, "symmetric")


## The follow is not permanent: it is quiet in guard, peaks through the swing,
## and softens in recovery. A dead fighter's body stops supporting the blade.
func test_the_body_commits_more_to_a_swing_than_to_a_guard() -> void:
	var guard_thrust := KineticChainModifier3D.effort_scale(CombatPhase.Id.NEUTRAL, GuardPoseField.Band.THRUST)
	var guard_ready := KineticChainModifier3D.effort_scale(CombatPhase.Id.NEUTRAL, GuardPoseField.Band.READY)
	var swing := KineticChainModifier3D.effort_scale(CombatPhase.Id.ACTIVE_THREAT, GuardPoseField.Band.READY)
	var recovery := KineticChainModifier3D.effort_scale(CombatPhase.Id.RECOVERY, GuardPoseField.Band.READY)
	var dead := KineticChainModifier3D.effort_scale(CombatPhase.Id.DEAD, GuardPoseField.Band.READY)
	assert_true(guard_thrust < guard_ready, "a held point loads the body less than a ready guard")
	assert_true(swing > guard_ready and swing >= 1.0, "the swing commits the whole chain")
	assert_true(recovery < swing and recovery > 0.0, "recovery is softer than the swing but still present")
	assert_eq(dead, 0.0, "a dead body does not support the blade")
	var scaled := KineticChainModifier3D.world_follow(&"Chest", PI * 0.5, guard_thrust)
	var full := KineticChainModifier3D.world_follow(&"Chest", PI * 0.5)
	assert_true(scaled < full and scaled > 0.0, "effort scales the follow magnitude without reordering it")


## The guard reading is continuous and crosses centre only through Longpoint,
## with hysteresis so a blade wavering around straight-ahead never flickers.
func test_the_guard_reading_never_snaps_across_centre() -> void:
	var field := GuardPoseField.new()
	assert_eq(field.update(deg_to_rad(90.0)), GuardPoseField.State.RIGHT_WIND_BACK, "a far-right blade is a wound-back cut")
	assert_eq(field.update(deg_to_rad(40.0)), GuardPoseField.State.RIGHT_READY, "drawing in is a ready guard")
	## Inside the leave threshold but not yet inside the enter threshold: it must
	## hold the right reading rather than flicker to the other side.
	assert_eq(field.update(deg_to_rad(15.0)), GuardPoseField.State.RIGHT_READY, "hysteresis holds the side near centre")
	assert_eq(field.update(deg_to_rad(5.0)), GuardPoseField.State.LONGPOINT, "only a clearly centred point is Longpoint")
	assert_eq(field.update(deg_to_rad(-5.0)), GuardPoseField.State.LONGPOINT, "and it stays Longpoint across centre")
	assert_eq(field.update(deg_to_rad(-40.0)), GuardPoseField.State.LEFT_READY, "a clearly left blade commits to the left")
	assert_eq(field.band(), GuardPoseField.Band.READY, "a drawn-in guard is the ready band")


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


## Letting go hides the held sword (the pivot stays where the simulation put it)
## and hands back a copy of its look; the next round puts the sword back in hand.
## A released sword starts with the presented body's motion: still for a death
## in place, the fall trajectory over the edge.
func test_a_dropped_sword_leaves_the_hands_and_returns_next_round() -> void:
	var proxy := _proxy()
	var row := _row(0.0)
	assert_true(proxy.root_velocity().is_zero_approx(), "a standing body is not moving")
	var pivot_before := proxy.sword_pivot().global_transform
	var look := proxy.detach_weapon()
	assert_true(proxy.is_weapon_dropped(), "the hands let go")
	assert_false(proxy.sword_pivot().visible, "the held sword is hidden")
	assert_true(look.get_child_count() > 0, "and its look is handed over to be carried")
	assert_true(proxy.sword_pivot().global_transform.is_equal_approx(pivot_before), "the pivot itself is never moved")
	row.health = 0.0
	proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, 0.016)
	assert_true(proxy.is_weapon_dropped(), "a dead fighter stays empty-handed")
	row.health = 100.0
	proxy.apply_pose(Vector3.ZERO, 0.0, 0.0, row, 0.016)
	assert_false(proxy.is_weapon_dropped(), "a new round puts the sword back in hand")
	assert_true(proxy.sword_pivot().visible, "visibly")
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
	var body := DroppedWeapon3D.create(Node3D.new(), Vector3.ZERO, Vector3.ZERO, 1.0, 0.05, 0.75)
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


func test_skins_swap_the_body_without_touching_the_rig_or_rules() -> void:
	var base := _proxy()
	var training := _proxy(RiposteKits.SKIN_DUELIST_TRAINING)
	assert_true(training.rig() != null and training.rig().is_bound(), "the training gear binds the same rig")
	assert_true(base.find_child("FurCollar", true, false) != null, "precondition: the base look has its fur collar")
	assert_true(training.find_child("FurCollar", true, false) == null, "the training gear does not")
	assert_eq(training.blade_points()[1], base.blade_points()[1], "and the blade is in exactly the same place")
	assert_eq(_rules.weapon.tip_radius, StandardDuelRules.create().weapon.tip_radius, "nothing about the rules moved")
	base.queue_free()
	training.queue_free()
