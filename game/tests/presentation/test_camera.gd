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
	assert_eq(rig.rotation, Vector3.ZERO, "fixed world orientation")
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
