extends TestCase

## PRES-FEEDBACK: CombatFeedbackDirector produces correct typed requests from
## events and snapshots, CameraFeedback implements trauma accumulation, and
## ImpactPresentationProfile defines the semantic feedback language.
##
## These test executable presentation logic — mapping, classification, math —
## not visual quality or game-feel aesthetics.
##
## See also: /docs/architecture/presentation-feedback.md


func _init() -> void:
	suite_name = "PRES-FEEDBACK"


## ──────────────────── REQUEST VALUE TYPES ───────────────────────────────────


func test_feedback_frame_reports_whether_it_has_requests() -> void:
	var empty := FeedbackFrame.new()
	assert_false(empty.has_requests(), "empty frame has no requests")
	var with_shake := FeedbackFrame.new()
	with_shake.camera_requests.append(CameraShakeRequest.create(50.0))
	assert_true(with_shake.has_requests(), "frame with camera request reports true")
	var with_audio := FeedbackFrame.new()
	with_audio.audio_requests.append(AudioCueRequest.create(PresentationKit.CUE_BLADE_LIGHT))
	assert_true(with_audio.has_requests(), "frame with audio request reports true")


func test_camera_shake_request_carries_intensity_and_profile() -> void:
	var req := CameraShakeRequest.create(75.0, Vector3(1, 0, 0), CameraShakeRequest.Profile.BLADE)
	assert_eq(req.intensity, 75.0, "intensity")
	assert_eq(req.direction, Vector3(1, 0, 0), "direction")
	assert_eq(req.profile, CameraShakeRequest.Profile.BLADE, "profile")


func test_hitstop_request_clamps_to_nonnegative() -> void:
	var positive := HitstopRequest.create(0.05)
	assert_eq(positive.duration, 0.05, "positive passes through")
	var negative := HitstopRequest.create(-0.1)
	assert_eq(negative.duration, 0.0, "negative clamped to 0")


func test_vfx_request_factories_set_correct_kind() -> void:
	var s := VfxRequest.sparks(Vector3.ZERO, Vector3.UP, Color.WHITE, 5, 2.0, 1.0)
	assert_eq(s.kind, VfxRequest.Kind.SPARKS, "sparks kind")
	assert_eq(s.count, 5, "spark count")
	var r := VfxRequest.ring(Vector3.ZERO, Color.RED, 0.8, 0.5)
	assert_eq(r.kind, VfxRequest.Kind.RING, "ring kind")
	assert_eq(r.size, 0.8, "ring size")
	var d := VfxRequest.dust(Vector3.ZERO, Vector3.FORWARD, Color.BROWN, 7, 1.4, 1.0)
	assert_eq(d.kind, VfxRequest.Kind.DUST, "dust kind")
	assert_eq(d.count, 7, "dust count")


func test_fighter_cue_request_factories() -> void:
	var flash := FighterCueRequest.hit_flash(1, 0.5)
	assert_eq(flash.slot, 1, "slot")
	assert_eq(flash.kind, FighterCueRequest.Kind.HIT_FLASH, "kind")
	assert_eq(flash.intensity, 0.5, "intensity")
	var haptic := FighterCueRequest.haptic(0, FighterCueRequest.Kind.HAPTIC_CRITICAL)
	assert_eq(haptic.kind, FighterCueRequest.Kind.HAPTIC_CRITICAL, "haptic kind")


## ──────────────────── IMPACT PRESENTATION PROFILES ─────────────────────────


func test_semantic_profiles_have_distinct_characteristics() -> void:
	var clash := ImpactPresentationProfile.clash()
	var slash := ImpactPresentationProfile.slash()
	var poke := ImpactPresentationProfile.poke()
	var thrust := ImpactPresentationProfile.thrust()
	var graze := ImpactPresentationProfile.graze()
	var kill := ImpactPresentationProfile.kill()
	assert_eq(clash.shake_profile, CameraShakeRequest.Profile.BLADE, "clash = blade shake")
	assert_eq(slash.shake_profile, CameraShakeRequest.Profile.BODY, "slash = body shake")
	assert_eq(poke.shake_profile, CameraShakeRequest.Profile.POKE, "poke = poke shake")
	assert_eq(thrust.shake_profile, CameraShakeRequest.Profile.THRUST, "thrust = thrust shake")
	assert_eq(kill.shake_profile, CameraShakeRequest.Profile.KILL, "kill = kill shake")
	assert_true(kill.shake_scale > slash.shake_scale, "kill > slash shake")
	assert_true(graze.shake_scale < clash.shake_scale, "graze < clash shake")
	assert_eq(kill.shake_scale, 100.0, "kill override is 100")
	assert_eq(clash.hitstop_band, ImpactPresentationProfile.HitstopBand.BLADE, "clash uses blade band")
	assert_eq(slash.hitstop_band, ImpactPresentationProfile.HitstopBand.BODY, "slash uses body band")
	assert_eq(kill.hitstop_band, ImpactPresentationProfile.HitstopBand.DEVASTATING, "kill uses devastating band")


## ──────────────────── COMBAT FEEDBACK DIRECTOR ─────────────────────────────


func test_director_produces_empty_frame_with_no_events() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	var snapshot := SnapshotProjector.project(state, rules)
	var kit := PresentationKit.missing(PresentationKit.PRIMITIVE_BLADE)
	var events: Array[DuelEvent] = []
	var frame := CombatFeedbackDirector.process(snapshot, events, kit, 1.0)
	assert_false(frame.has_requests(), "no events = no requests")


func test_director_classifies_blade_contact_into_typed_requests() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	var snapshot := SnapshotProjector.project(state, rules)
	var kit := PresentationKit.missing(PresentationKit.PRIMITIVE_BLADE)
	var events: Array[DuelEvent] = [
		DuelEvent.create(DuelEventTypes.BLADE_CONTACT, 10, 0, 1, {
			DuelEventKeys.INTENSITY: 0.5,
			DuelEventKeys.STRIKE_X: 1.0,
			DuelEventKeys.STRIKE_Y: 0.0,
			DuelEventKeys.NORMAL_X: 0.0,
			DuelEventKeys.NORMAL_Y: 1.0,
			DuelEventKeys.X: 0.0,
			DuelEventKeys.Y: 0.0,
			DuelEventKeys.CONTACT_CLASS: ContactResolver.CLASS_SOLID,
		})
	]
	var frame := CombatFeedbackDirector.process(snapshot, events, kit, 1.0)
	assert_true(frame.has_requests(), "blade contact produces requests")
	assert_true(frame.vfx_requests.size() >= 2, "sparks in tangent and normal fans")
	assert_true(frame.audio_requests.size() > 0, "audio cue emitted")
	assert_eq(frame.audio_requests[0].cue, PresentationKit.CUE_BLADE_SOLID, "solid class maps to solid cue")
	assert_true(frame.hitstop_requests.size() > 0, "hitstop emitted")
	assert_true(frame.camera_requests.size() > 0, "camera shake emitted")
	assert_eq(frame.camera_requests[0].profile, CameraShakeRequest.Profile.BLADE, "blade shake profile")


func test_director_classifies_body_hit_with_correct_audio_tier() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	var snapshot := SnapshotProjector.project(state, rules)
	var kit := PresentationKit.missing(PresentationKit.PRIMITIVE_BLADE)
	var light_events: Array[DuelEvent] = [
		DuelEvent.create(DuelEventTypes.BODY_HIT, 10, 0, 1, {
			DuelEventKeys.DAMAGE: 5.0,
			DuelEventKeys.QUALITY: 0.3,
			DuelEventKeys.GRADE: SwingSemantics.grade_label(SwingSemantics.Grade.LIGHT),
			DuelEventKeys.NORMAL_X: 0.0,
			DuelEventKeys.NORMAL_Y: 1.0,
			DuelEventKeys.STRIKE_X: 1.0,
			DuelEventKeys.STRIKE_Y: 0.0,
			DuelEventKeys.PUSH: 0.5,
			DuelEventKeys.X: 0.0,
			DuelEventKeys.Y: 0.0,
		})
	]
	var frame := CombatFeedbackDirector.process(snapshot, light_events, kit, 1.0)
	assert_true(frame.audio_requests.size() > 0, "audio emitted")
	assert_eq(frame.audio_requests[0].cue, PresentationKit.CUE_BODY_LIGHT, "light damage = light cue")
	assert_true(frame.fighter_requests.size() >= 2, "hit flash + haptic")
	var heavy_events: Array[DuelEvent] = [
		DuelEvent.create(DuelEventTypes.BODY_HIT, 10, 0, 1, {
			DuelEventKeys.DAMAGE: 20.0,
			DuelEventKeys.QUALITY: 1.0,
			DuelEventKeys.GRADE: SwingSemantics.grade_label(SwingSemantics.Grade.HEAVY),
			DuelEventKeys.NORMAL_X: 0.0,
			DuelEventKeys.NORMAL_Y: 1.0,
			DuelEventKeys.STRIKE_X: 1.0,
			DuelEventKeys.STRIKE_Y: 0.0,
			DuelEventKeys.PUSH: 1.0,
			DuelEventKeys.X: 0.0,
			DuelEventKeys.Y: 0.0,
		})
	]
	var heavy_frame := CombatFeedbackDirector.process(snapshot, heavy_events, kit, 1.0)
	assert_eq(heavy_frame.audio_requests[0].cue, PresentationKit.CUE_BODY_HEAVY, "heavy damage = heavy cue")


func test_director_devastating_hit_uses_kill_shake_profile() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	var snapshot := SnapshotProjector.project(state, rules)
	var kit := PresentationKit.missing(PresentationKit.PRIMITIVE_BLADE)
	var events: Array[DuelEvent] = [
		DuelEvent.create(DuelEventTypes.BODY_HIT, 10, 0, 1, {
			DuelEventKeys.DAMAGE: 50.0,
			DuelEventKeys.QUALITY: 2.0,
			DuelEventKeys.GRADE: SwingSemantics.grade_label(SwingSemantics.Grade.DEVASTATING),
			DuelEventKeys.NORMAL_X: 0.0,
			DuelEventKeys.NORMAL_Y: 1.0,
			DuelEventKeys.STRIKE_X: 1.0,
			DuelEventKeys.STRIKE_Y: 0.0,
			DuelEventKeys.PUSH: 2.0,
			DuelEventKeys.X: 0.0,
			DuelEventKeys.Y: 0.0,
		})
	]
	var frame := CombatFeedbackDirector.process(snapshot, events, kit, 1.0)
	assert_eq(frame.camera_requests[0].profile, CameraShakeRequest.Profile.KILL, "devastating = kill profile")
	assert_true(frame.camera_requests[0].intensity > 0.0, "nonzero shake intensity")


func test_director_round_events_use_arena_kit_source() -> void:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	var snapshot := SnapshotProjector.project(state, rules)
	var kit := PresentationKit.missing(PresentationKit.PRIMITIVE_BLADE)
	var events: Array[DuelEvent] = [DuelEvent.create(DuelEventTypes.ROUND_STARTED, 1)]
	var frame := CombatFeedbackDirector.process(snapshot, events, kit, 1.0)
	assert_true(frame.audio_requests.size() > 0, "round start emits audio")
	assert_eq(frame.audio_requests[0].kit_source, AudioCueRequest.KitSource.ARENA, "round cue from arena kit")


## ──────────────────── CAMERA FEEDBACK ──────────────────────────────────────


func test_camera_feedback_starts_at_zero_trauma() -> void:
	var cam := CameraFeedback.new()
	assert_eq(cam.trauma(), 0.0, "initial trauma is zero")
	assert_eq(cam.advance(0.016), Vector3.ZERO, "zero trauma produces zero offset")


func test_camera_feedback_accumulates_trauma_from_requests() -> void:
	var cam := CameraFeedback.new()
	var requests: Array[CameraShakeRequest] = [CameraShakeRequest.create(50.0, Vector3(1, 0, 0))]
	cam.apply_requests(requests, 1.0)
	assert_true(cam.trauma() > 0.0, "trauma increased")
	var offset := cam.advance(0.001)
	assert_true(offset.length() > 0.0, "nonzero offset at nonzero trauma")


func test_camera_feedback_trauma_is_quadratic() -> void:
	var cam := CameraFeedback.new()
	var requests: Array[CameraShakeRequest] = [CameraShakeRequest.create(100.0)]
	cam.apply_requests(requests, 1.0)
	var full_trauma := cam.trauma()
	assert_near(full_trauma, 1.0, 1e-6, "100 intensity at scale 1.0 = full trauma")
	var offset := cam.advance(0.001)
	assert_true(offset.length() > 0.0, "nonzero offset")


func test_camera_feedback_decays_to_zero() -> void:
	var cam := CameraFeedback.new()
	var requests: Array[CameraShakeRequest] = [CameraShakeRequest.create(50.0)]
	cam.apply_requests(requests, 1.0)
	assert_true(cam.trauma() > 0.0, "precondition: trauma exists")
	for _i in 120:
		cam.advance(0.016)
	assert_near(cam.trauma(), 0.0, 1e-6, "trauma decays to zero over ~2 seconds")


func test_camera_feedback_respects_settings_scale() -> void:
	var cam_full := CameraFeedback.new()
	var cam_off := CameraFeedback.new()
	var requests: Array[CameraShakeRequest] = [CameraShakeRequest.create(50.0)]
	cam_full.apply_requests(requests, 1.0)
	cam_off.apply_requests(requests, 0.0)
	assert_true(cam_full.trauma() > 0.0, "full settings = trauma")
	assert_eq(cam_off.trauma(), 0.0, "zero settings = no trauma")


func test_camera_feedback_clamps_trauma_to_one() -> void:
	var cam := CameraFeedback.new()
	var requests: Array[CameraShakeRequest] = [
		CameraShakeRequest.create(100.0),
		CameraShakeRequest.create(100.0),
		CameraShakeRequest.create(100.0),
	]
	cam.apply_requests(requests, 1.0)
	assert_near(cam.trauma(), 1.0, 1e-6, "trauma clamped to 1.0")


func test_camera_feedback_reset_clears_state() -> void:
	var cam := CameraFeedback.new()
	var requests: Array[CameraShakeRequest] = [CameraShakeRequest.create(80.0)]
	cam.apply_requests(requests, 1.0)
	assert_true(cam.trauma() > 0.0, "precondition")
	cam.reset()
	assert_eq(cam.trauma(), 0.0, "reset clears trauma")
	assert_eq(cam.advance(0.016), Vector3.ZERO, "reset clears offset")
