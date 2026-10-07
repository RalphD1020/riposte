extends TestCase

## PRES-CAMERA: fixed-orientation midpoint framing that breathes with
## separation (UX §4–§5, §35).
##
## See also: /docs/concepts/presentation.md

const DELTA := 1.0 / 60.0


func _init() -> void:
	suite_name = "PRES-CAMERA"


func _rig() -> DuelCameraRig:
	var rig := DuelCameraRig.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(rig)
	rig.configure(RiposteKits.camera_profile())
	return rig


func test_frames_the_midpoint_and_looks_at_it() -> void:
	var rig := _rig()
	rig.frame(Vector3(-2.0, 0.0, 0.0), Vector3(2.0, 0.0, -1.0), DELTA, PresentationOptions.new(), true)
	assert_true(rig.focus().is_equal_approx(Vector3(0.0, 0.0, -0.5)), "focus on the midpoint")
	var forward := -rig.camera().global_transform.basis.z
	var to_focus := (rig.focus() - rig.camera().global_position).normalized()
	assert_true(forward.is_equal_approx(to_focus), "camera looks at the focus")
	assert_true(rig.camera().global_position.y > 0.0, "elevated")
	assert_eq(rig.rotation, Vector3.ZERO, "no orientation of its own until a local side asks for one")
	rig.queue_free()


## The local player is always at the bottom of the screen, so a Dark player's
## view is turned half a revolution (SIDE-001). The world never turns — this
## is the one quantity two people watching the same match may disagree about,
## which is exactly why it lives in presentation and not in the hash.
func test_the_local_player_is_always_at_the_bottom_of_the_screen() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	for slot in 2:
		var rig := _rig()
		var me := state.fighter(slot)
		var them := state.opponent_of(slot)
		rig.look_from(me.side)
		rig.frame(ArenaTransform.to_world(me.x, me.y), ArenaTransform.to_world(them.x, them.y), DELTA, PresentationOptions.new(), true)
		var camera := rig.camera()
		var mine := camera.unproject_position(ArenaTransform.to_world(me.x, me.y))
		var theirs := camera.unproject_position(ArenaTransform.to_world(them.x, them.y))
		## Screen `y` grows downward, so "lower on screen" is the larger value.
		assert_true(mine.y > theirs.y, "the local %s fighter is below the opponent" % DuelSide.label(me.side))
		rig.queue_free()


## The payoff of expressing footwork in duel axes (MOVE-001): once the rig has
## turned, "step right" projects right on screen for *both* sides. Without
## this, one of the two ends would be playing mirrored controls.
func test_local_right_projects_right_on_screen_for_both_sides() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	for slot in 2:
		var rig := _rig()
		var me := state.fighter(slot)
		var them := state.opponent_of(slot)
		rig.look_from(me.side)
		rig.frame(ArenaTransform.to_world(me.x, me.y), ArenaTransform.to_world(them.x, them.y), DELTA, PresentationOptions.new(), true)
		var forward := DuelGeometry.duel_basis(me, them, me.duel_forward_x, me.duel_forward_y)
		var right := DuelGeometry.to_world(1.0, 0.0, forward[0], forward[1])
		var camera := rig.camera()
		var here := camera.unproject_position(ArenaTransform.to_world(me.x, me.y))
		var stepped := camera.unproject_position(ArenaTransform.to_world(me.x + right[0], me.y + right[1]))
		assert_true(stepped.x > here.x, "local D moves the %s fighter right on screen" % DuelSide.label(me.side))
		var ahead := camera.unproject_position(ArenaTransform.to_world(me.x + forward[0], me.y + forward[1]))
		assert_true(ahead.y < here.y, "and local W moves them up the screen")
		rig.queue_free()


## The hard half of SIDE-001: turning the view must cost the simulation
## *nothing*. If a camera could touch authoritative state then two networked
## players looking at opposite perspectives would desync, and the perspective
## flip would stop being a local convenience and become a rules change.
func test_a_camera_orientation_change_touches_no_authoritative_state() -> void:
	var rules := StandardDuelRules.create()
	var runner := SimRunner.create(rules, 41)
	runner.skip_intro()
	runner.drive(0.4, 1.0, 20)
	var before := StateHasher.hash_state(runner.state)
	var rig := _rig()
	for side in PackedInt32Array([DuelSide.Id.DARK_NORTH, DuelSide.Id.LIGHT_SOUTH, DuelSide.Id.DARK_NORTH]):
		rig.look_from(side as DuelSide.Id)
		var a := runner.state.fighter(0)
		var b := runner.state.fighter(1)
		rig.frame(ArenaTransform.to_world(a.x, a.y), ArenaTransform.to_world(b.x, b.y), DELTA, PresentationOptions.new(), true)
		assert_eq(StateHasher.hash_state(runner.state), before, "looking from the %s end changes nothing" % DuelSide.label(side as DuelSide.Id))
	assert_near(rig.yaw(), PI, 1e-9, "precondition: the rig really did turn")
	## And the duel carries on identically from there, so the camera has not
	## perturbed anything the hash happens not to cover either.
	runner.drive(0.4, 1.0, 20)
	var fresh := SimRunner.create(rules, 41)
	fresh.skip_intro()
	fresh.drive(0.4, 1.0, 40)
	assert_eq(StateHasher.hash_state(runner.state), StateHasher.hash_state(fresh.state), "and the duel continues identically")
	rig.queue_free()


func test_zoom_breathes_with_separation_within_limits() -> void:
	var rig := _rig()
	var profile := RiposteKits.camera_profile()
	rig.frame(Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0), DELTA, PresentationOptions.new(), true)
	var close := rig.distance()
	rig.frame(Vector3(-6.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0), DELTA, PresentationOptions.new(), true)
	var far := rig.distance()
	assert_true(far > close, "separated fighters pull the camera back")
	assert_between(close, profile.min_distance, profile.max_distance, "clamped near")
	assert_between(far, profile.min_distance, profile.max_distance, "clamped far")
	rig.queue_free()


func test_smoothing_moves_gradually_and_touch_biases_upward() -> void:
	var rig := _rig()
	rig.frame(Vector3.ZERO, Vector3.ZERO, DELTA, PresentationOptions.new(), true)
	rig.frame(Vector3(4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0), DELTA, PresentationOptions.new(), false)
	assert_true(rig.focus().x > 0.0 and rig.focus().x < 4.0, "focus eases instead of jumping")
	var touch := PresentationOptions.new()
	touch.touch_layout = true
	rig.frame(Vector3.ZERO, Vector3.ZERO, DELTA, touch, true)
	assert_true(rig.focus().z > 0.0, "touch framing shifts the duel up the screen")
	rig.queue_free()


func test_impulses_are_bounded_and_decay() -> void:
	var rig := _rig()
	var options := PresentationOptions.new()
	rig.impulse(5.0, options)
	assert_eq(rig.impulse_strength(), RiposteKits.camera_profile().max_impulse, "capped")
	for _i in 60:
		rig.frame(Vector3.ZERO, Vector3.ZERO, DELTA, options, false)
	assert_eq(rig.impulse_strength(), 0.0, "decays to rest within a second")
	options.screen_shake = false
	rig.impulse(0.1, options)
	assert_eq(rig.impulse_strength(), 0.0, "Screen Shake off means no impulse")
	rig.queue_free()


func test_profile_validation() -> void:
	assert_true(RiposteKits.camera_profile().is_valid(), "authored profile is valid")
	assert_false(CameraProfile.new().is_valid(), "neutral profile is not")
