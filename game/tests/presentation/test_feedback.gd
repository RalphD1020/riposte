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


## ──────────────────── FORCE-SCALED FEEDBACK ─────────────────────────────────


func _strike(quality: float, damage: float, kind: String = "slash", lethal: bool = false) -> Array[DuelEvent]:
	var grade := SwingSemantics.Grade.DEVASTATING if quality >= PresentationKit.QUALITY_FULL else SwingSemantics.Grade.HEAVY
	var events: Array[DuelEvent] = [
		DuelEvent.create(DuelEventTypes.BODY_HIT, 10, 0, 1, {
			DuelEventKeys.DAMAGE: damage,
			DuelEventKeys.QUALITY: quality,
			DuelEventKeys.GRADE: SwingSemantics.grade_label(grade),
			DuelEventKeys.CONTACT_KIND: kind,
			DuelEventKeys.LETHAL: lethal,
			DuelEventKeys.NORMAL_X: 0.0,
			DuelEventKeys.NORMAL_Y: 1.0,
			DuelEventKeys.STRIKE_X: 1.0,
			DuelEventKeys.STRIKE_Y: 0.0,
			DuelEventKeys.PUSH: 0.5,
			DuelEventKeys.X: 0.0,
			DuelEventKeys.Y: 0.0,
		})
	]
	return events


func _frame(events: Array[DuelEvent], particles: float = 1.0) -> FeedbackFrame:
	var rules := StandardDuelRules.create()
	var snapshot := SnapshotProjector.project(DuelSetup.new_state(rules, 1), rules)
	return CombatFeedbackDirector.process(snapshot, events, PresentationKit.missing(PresentationKit.PRIMITIVE_BLADE), 1.0, particles)


func _spark_total(frame: FeedbackFrame) -> int:
	var total := 0
	for request in frame.vfx_requests:
		if request.kind == VfxRequest.Kind.SPARKS or request.kind == VfxRequest.Kind.AXIAL:
			total += request.count
	return total


func test_the_response_curve_is_continuous_monotonic_and_flat_at_the_bottom() -> void:
	var previous := CombatFeedbackDirector.response(0.0)
	assert_eq(previous, 0.0, "no severity, no response")
	var largest_step := 0.0
	for i in range(1, 151):
		var value := CombatFeedbackDirector.response(float(i) / 100.0)
		assert_true(value >= previous, "monotonic at %.2f" % (float(i) / 100.0))
		largest_step = maxf(largest_step, value - previous)
		previous = value
	assert_true(largest_step < 0.03, "no step anywhere along the ladder (largest %.4f)" % largest_step)
	assert_true(CombatFeedbackDirector.response(0.1) < 0.05, "a graze-level severity is barely there")
	assert_near(CombatFeedbackDirector.response(1.0), 1.0, 1e-9, "the top of an ordinary strike is full response")
	assert_true(CombatFeedbackDirector.response(1.5) > 1.5, "devastating severity keeps growing")


func test_a_graze_is_subtle_and_a_devastating_strike_is_exceptional() -> void:
	var graze := _frame(_strike(0.1, 1.0, "graze"))
	var devastating := _frame(_strike(PresentationKit.QUALITY_FULL * 1.2, 60.0))
	assert_true(graze.camera_requests[0].intensity < 1.0, "a graze barely moves the camera (%.2f)" % graze.camera_requests[0].intensity)
	assert_true(devastating.camera_requests[0].intensity > graze.camera_requests[0].intensity * 20.0, "a devastating strike moves it far more")
	assert_true(_spark_total(devastating) > _spark_total(graze), "and throws more sparks")
	assert_eq(devastating.camera_requests[0].profile, CameraShakeRequest.Profile.KILL, "devastating takes the kill shape")


func test_strike_channels_have_no_step_at_class_boundaries() -> void:
	var previous_shake := -1.0
	var previous_sparks := -1
	for i in range(0, 100):
		var quality := float(i) / 100.0 * PresentationKit.QUALITY_FULL * 0.99
		var frame := _frame(_strike(quality, 10.0))
		var shake := frame.camera_requests[0].intensity
		var sparks := _spark_total(frame)
		if previous_shake >= 0.0:
			assert_true(shake >= previous_shake and shake - previous_shake < 0.5, "shake climbs smoothly at quality %.3f" % quality)
			assert_true(sparks >= previous_sparks and sparks - previous_sparks <= 1, "spark count climbs one at a time at quality %.3f" % quality)
		previous_shake = shake
		previous_sparks = sparks


func test_body_audio_crossfades_light_and_heavy_by_damage() -> void:
	var light := _frame(_strike(0.5, 2.0))
	assert_eq(light.audio_requests.size(), 1, "a scratch is only the light family")
	var middle := _frame(_strike(0.5, 14.0))
	assert_eq(middle.audio_requests[0].cue, PresentationKit.CUE_BODY_LIGHT, "just under the centre the light family leads")
	assert_eq(middle.audio_requests[1].cue, PresentationKit.CUE_BODY_HEAVY, "with the heavy family underneath")
	assert_true(middle.audio_requests[1].volume_db < middle.audio_requests[0].volume_db, "and quieter")
	var heavy := _frame(_strike(0.5, 30.0))
	assert_eq(heavy.audio_requests.size(), 1, "a heavy blow is only the heavy family")
	assert_eq(heavy.audio_requests[0].cue, PresentationKit.CUE_BODY_HEAVY, "heavy leads")


func test_point_strikes_draw_an_axial_line_not_a_fan() -> void:
	var thrust := _frame(_strike(0.8, 100.0, "thrust"))
	var kinds: Array[VfxRequest.Kind] = []
	for request in thrust.vfx_requests:
		kinds.append(request.kind)
	assert_true(kinds.has(VfxRequest.Kind.AXIAL), "a thrust draws its line")
	assert_false(kinds.has(VfxRequest.Kind.SPARKS), "not a slash fan")
	assert_eq(thrust.camera_requests[0].profile, CameraShakeRequest.Profile.THRUST, "with the thrust shake shape")


func test_a_lethal_blow_gets_the_full_stack_and_slow_motion() -> void:
	var ordinary := _frame(_strike(0.9, 40.0))
	var lethal := _frame(_strike(0.9, 40.0, "slash", true))
	assert_eq(ordinary.slow_motion_requests.size(), 0, "precondition: an ordinary strike never slows time")
	assert_eq(lethal.slow_motion_requests.size(), 1, "the terminal blow plays out slowly")
	assert_true(lethal.slow_motion_requests[0].time_scale < 1.0, "slower than real time")
	var cues: Array[StringName] = []
	for request in lethal.audio_requests:
		cues.append(request.cue)
	assert_true(cues.has(PresentationKit.CUE_LETHAL_ACCENT), "with its signature accent")
	assert_eq(lethal.hitstop_requests.size(), 1, "one freeze, not two stacked")
	assert_true(lethal.hitstop_requests[0].duration > ordinary.hitstop_requests[0].duration, "and a longer one")
	var flashes := lethal.vfx_requests.filter(func(request: VfxRequest) -> bool: return request.kind == VfxRequest.Kind.FLASH)
	assert_eq(flashes.size(), 1, "and the exceptional directional effect")


func test_particle_intensity_zero_drops_particles_but_keeps_the_hit() -> void:
	var full := _frame(_strike(0.8, 30.0))
	var none := _frame(_strike(0.8, 30.0), 0.0)
	assert_true(_spark_total(full) > 0, "precondition: a hit sparks")
	assert_eq(_spark_total(none), 0, "no particles when asked for none")
	assert_eq(none.audio_requests.size(), full.audio_requests.size(), "the hit is still heard")
	assert_eq(none.hitstop_requests.size(), 1, "still felt in the pacing")
	var streaks := none.vfx_requests.filter(func(request: VfxRequest) -> bool: return request.kind == VfxRequest.Kind.STREAK)
	assert_eq(streaks.size(), 1, "and still marked in the world by its recoil streak")


func test_every_contact_request_carries_a_deterministic_variant_key() -> void:
	var first := _frame(_strike(0.8, 30.0))
	var second := _frame(_strike(0.8, 30.0))
	assert_eq(first.audio_requests[0].key, second.audio_requests[0].key, "the same event picks the same take")
	var later := _strike(0.8, 30.0)
	later[0].tick += 1
	assert_ne(_frame(later).audio_requests[0].key, first.audio_requests[0].key, "a later event may pick another")


## The death sequence is a killing-blow lock, not a stab reaction: it fires only
## on the blow that leaves the target not alive, and reads the family from the
## contact so a cut collapses differently from a run-through.
func test_only_a_killing_blow_requests_a_death_sequence() -> void:
	var survived := _body_hit_frame("thrust", false)
	var killed_by_thrust := _body_hit_frame("thrust", true)
	var killed_by_slash := _body_hit_frame("slash", true)
	assert_true(survived.death_requests.is_empty(), "a non-lethal stab locks nothing")
	assert_eq(killed_by_thrust.death_requests.size(), 1, "a killing thrust locks one death")
	var thrust: DeathPresentationRequest = killed_by_thrust.death_requests[0]
	assert_eq(thrust.cause, DeathPresentationProfile.Family.STAB, "a thrust kill reads as a stab death")
	assert_eq(killed_by_slash.death_requests[0].cause, DeathPresentationProfile.Family.SLASH, "a cut kill reads as a slash death")
	assert_eq(thrust.slot, 1, "the dead fighter collapses, not the striker")
	assert_eq(thrust.killer, 0, "and the striker is named, so a killing thrust can hold the run-through")
	assert_true(thrust.impact_direction.is_equal_approx(Vector3(1.0, 0.0, 0.0)), "the request carries the direction the blow travelled")
	assert_true(thrust.impact_severity > 0.0, "and how hard it landed")


## The controller starts each death once, on the first backend that can run it,
## and falls through to the always-available primitive when a richer backend
## (a ragdoll on a rig without a physical skeleton) is unavailable.
func test_a_death_starts_once_on_the_first_available_backend() -> void:
	var ragdoll := FakeDeathBackend.new(false)
	var primitive := FakeDeathBackend.new(true)
	var backends: Array[DeathPresentationBackend] = [ragdoll, primitive]
	var deaths := DeathPresentationController.new(backends)
	var request := DeathPresentationRequest.create(1, DeathPresentationProfile.Family.STAB, Vector3.RIGHT, 1.0, 7)
	deaths.present(request)
	deaths.present(request)
	assert_eq(ragdoll.started.size(), 0, "an unavailable backend is skipped")
	assert_eq(primitive.started.size(), 1, "the death falls through to the primitive, and starts only once")
	assert_eq(primitive.started[0], request, "with the request the simulation produced")
	assert_true(deaths.has_started(1), "the fighter is marked down")
	assert_false(deaths.has_started(0), "the survivor is not")
	deaths.reset()
	deaths.present(request)
	assert_eq(primitive.started.size(), 2, "a new round lets the same fighter die again")


func test_an_available_richer_backend_takes_the_death_ahead_of_the_primitive() -> void:
	var ragdoll := FakeDeathBackend.new(true)
	var primitive := FakeDeathBackend.new(true)
	var backends: Array[DeathPresentationBackend] = [ragdoll, primitive]
	var deaths := DeathPresentationController.new(backends)
	deaths.present(DeathPresentationRequest.create(0, DeathPresentationProfile.Family.SLASH, Vector3.FORWARD, 0.5, 3))
	assert_eq(ragdoll.started.size(), 1, "the preferred backend carries the death when it can")
	assert_eq(primitive.started.size(), 0, "so the fallback does not also run")


## A ring-out hands presentation the exact exit point and the momentum carried
## over the edge, so the fall can read the knockback that caused it.
func test_a_ring_out_requests_a_fall_with_the_exit_momentum_preserved() -> void:
	var events: Array[DuelEvent] = [DuelEvent.create(DuelEventTypes.RING_OUT, 30, 1, DuelEvent.NONE, {
		DuelEventKeys.POSITION_X: 2.5,
		DuelEventKeys.POSITION_Y: 1.0,
		DuelEventKeys.VELOCITY_X: 3.0,
		DuelEventKeys.VELOCITY_Y: -2.0,
		DuelEventKeys.TOI: 0.5,
	})]
	var frame := _frame(events)
	assert_eq(frame.fall_requests.size(), 1, "a ring-out requests one fall")
	var fall: FallPresentationRequest = frame.fall_requests[0]
	assert_eq(fall.slot, 1, "for the fighter who went over")
	assert_true(fall.exit_position.is_equal_approx(ArenaTransform.to_world(2.5, 1.0)), "from exactly where they crossed the edge")
	assert_true(fall.exit_velocity.is_equal_approx(Vector3(3.0, 0.0, 2.0)), "carrying the exit velocity unchanged into world space")
	assert_true(_frame(_strike(0.8, 30.0)).fall_requests.is_empty(), "a hit on the platform is not a fall")


## The fall owns the root: exit momentum carried forward unchanged, gravity
## drawing the body down, starting exactly at the edge.
func test_the_fall_trajectory_preserves_exit_momentum_under_gravity() -> void:
	var exit := Vector3(3.0, 0.0, -1.0)
	var velocity := Vector3(4.0, 0.0, 2.0)
	var fall := FallPresentationRequest.create(0, exit, velocity, 1)
	assert_true(fall.root_at(0.0).is_equal_approx(exit), "the fall starts at the edge, with no jump")
	var t := 0.5
	var root := fall.root_at(t)
	assert_near(root.x - exit.x, velocity.x * t, 1e-6, "the exit momentum carries the body out unchanged")
	assert_near(root.z - exit.z, velocity.z * t, 1e-6, "on both plane axes")
	assert_near(root.y, -0.5 * FallPresentationRequest.GRAVITY * t * t, 1e-6, "while gravity draws it down")
	assert_true(fall.root_at(1.0).y < root.y, "and keeps falling")
	var dropped := FallPresentationRequest.create(0, exit, Vector3(0.0, 5.0, 0.0), 1)
	assert_eq(dropped.exit_velocity.y, 0.0, "only horizontal momentum crosses the edge; the fall supplies the vertical")


## The sword leaves the hands only when the fighter is out of the round: a
## killing blow slackens the dead hand at once, a ring-out lets go a beat after
## the ledge, and a hit the fighter survives keeps the sword in hand.
func test_only_a_kill_or_a_ring_out_drops_the_sword() -> void:
	assert_true(_body_hit_frame("thrust", false).weapon_drop_requests.is_empty(), "a survived stab keeps the sword in hand")
	var killed := _body_hit_frame("slash", true)
	assert_eq(killed.weapon_drop_requests.size(), 1, "a killing blow drops one sword")
	assert_eq(killed.weapon_drop_requests[0].slot, 1, "the dead fighter's, not the striker's")
	assert_eq(killed.weapon_drop_requests[0].delay, WeaponDropRequest.DEATH_DELAY, "as the collapse begins")
	var events: Array[DuelEvent] = [DuelEvent.create(DuelEventTypes.RING_OUT, 30, 0, DuelEvent.NONE, {
		DuelEventKeys.POSITION_X: 2.5, DuelEventKeys.POSITION_Y: 0.0,
		DuelEventKeys.VELOCITY_X: 3.0, DuelEventKeys.VELOCITY_Y: 0.0, DuelEventKeys.TOI: 0.5,
	})]
	var fell := _frame(events)
	assert_eq(fell.weapon_drop_requests.size(), 1, "a ring-out drops the sword too")
	var delay := fell.weapon_drop_requests[0].delay
	assert_true(delay >= WeaponDropRequest.RING_OUT_DELAY_MIN and delay <= WeaponDropRequest.RING_OUT_DELAY_MAX, "a beat after the ledge (%.2f s)" % delay)
	assert_eq(_frame(events).weapon_drop_requests[0].delay, delay, "the same beat in every replay")


## The released blade carries its own spin: a still blade drops dead, a turning
## one flies off along its tangent at ω·r, and sim CCW is world +Y spin.
func test_a_released_blade_carries_its_own_spin() -> void:
	assert_true(WeaponDropRequest.blade_velocity(0.7, 0.0, 0.7).is_zero_approx(), "a still blade has no velocity of its own")
	var angle := 0.4
	var velocity := WeaponDropRequest.blade_velocity(angle, 6.0, 0.7)
	var along := Vector3(cos(angle), 0.0, -sin(angle))
	assert_near(velocity.dot(along), 0.0, 1e-6, "it moves across the blade, never along it")
	assert_near(velocity.length(), 6.0 * 0.7, 1e-6, "at ω·r")
	var row := PresentationFighter.new()
	row.blade_speed = 5.0
	row.swing_dir = -1.0
	row.hilt_radius = 0.25
	row.tip_radius = 1.25
	var drop := WeaponDropRequest.from_blade(0, 0.0, row, 1)
	assert_eq(drop.angular_velocity, Vector3(0.0, -5.0, 0.0), "the spin keeps its direction")
	assert_near(drop.linear_velocity.length(), 5.0 * 0.75, 1e-6, "measured at the blade's centre")


## The controller is pure time bookkeeping: a drop waits for its delay, releases
## once, ignores a repeat for the same fighter, and a new round starts fresh.
func test_a_sword_drops_once_after_its_hands_let_go() -> void:
	var drops := WeaponDropController.new()
	var drop := WeaponDropRequest.create(1, 0.2, Vector3.ZERO, Vector3.ZERO, 3)
	drops.request(drop)
	drops.request(WeaponDropRequest.create(1, 0.0, Vector3.ZERO, Vector3.ZERO, 4))
	assert_true(drops.advance(0.1).is_empty(), "not before the hands let go")
	var due := drops.advance(0.15)
	assert_eq(due.size(), 1, "then exactly one sword")
	assert_eq(due[0], drop, "the first request, not the repeat")
	assert_true(drops.has_released(1), "the fighter has let go")
	drops.request(drop)
	assert_true(drops.advance(1.0).is_empty(), "a sword already dropped is not dropped again")
	drops.reset()
	drops.request(drop)
	assert_eq(drops.advance(0.25).size(), 1, "a new round lets the same fighter drop again")


## Records what the controller asked of it, without any engine physics.
class FakeDeathBackend:
	extends DeathPresentationBackend

	var available: bool
	var started: Array[DeathPresentationRequest] = []

	func _init(p_available: bool) -> void:
		available = p_available

	func is_available(_request: DeathPresentationRequest) -> bool:
		return available

	func start(request: DeathPresentationRequest) -> void:
		started.append(request)


func _body_hit_frame(contact_kind: String, kills: bool) -> FeedbackFrame:
	var rules := StandardDuelRules.create()
	var state := DuelSetup.new_state(rules, 1)
	if kills:
		state.fighter(1).health = 0.0
	var snapshot := SnapshotProjector.project(state, rules)
	var events: Array[DuelEvent] = [DuelEvent.create(DuelEventTypes.BODY_HIT, 10, 0, 1, {
		DuelEventKeys.DAMAGE: 40.0,
		DuelEventKeys.QUALITY: 1.0,
		DuelEventKeys.GRADE: SwingSemantics.grade_label(SwingSemantics.Grade.HEAVY),
		DuelEventKeys.CONTACT_KIND: contact_kind,
		DuelEventKeys.STRIKE_X: 1.0,
		DuelEventKeys.STRIKE_Y: 0.0,
		DuelEventKeys.X: 0.0,
		DuelEventKeys.Y: 0.0,
	})]
	return CombatFeedbackDirector.process(snapshot, events, PresentationKit.missing(PresentationKit.PRIMITIVE_BLADE), 1.0)


## A parry reads as a physical deflection whose brightness is the beat margin,
## and never borrows the weight of a hit: no hitstop, no slow motion, no damage.
func test_a_cleaner_parry_reads_brighter_but_never_hits() -> void:
	var threshold: Array[DuelEvent] = [DuelEvent.create(DuelEventTypes.PARRY, 10, 0, 1, {DuelEventKeys.MARGIN: 0.08, DuelEventKeys.X: 0.0, DuelEventKeys.Y: 0.0})]
	var decisive: Array[DuelEvent] = [DuelEvent.create(DuelEventTypes.PARRY, 10, 0, 1, {DuelEventKeys.MARGIN: 0.2, DuelEventKeys.X: 0.0, DuelEventKeys.Y: 0.0})]
	var faint := _frame(threshold)
	var sharp := _frame(decisive)
	assert_true(faint.has_requests(), "even a threshold parry is marked")
	assert_eq(faint.audio_requests[0].cue, PresentationKit.CUE_BLADE_STRONG, "a parry rings the crisp clash cue")
	assert_true(sharp.audio_requests[0].volume_db > faint.audio_requests[0].volume_db, "a cleaner beat rings louder")
	assert_true(sharp.audio_requests[0].pitch >= faint.audio_requests[0].pitch, "and no lower")
	assert_true(_spark_total(sharp) > _spark_total(faint), "and throws a hotter spark fan")
	assert_true(sharp.camera_requests[0].intensity > faint.camera_requests[0].intensity, "and snaps the camera harder")
	assert_eq(sharp.camera_requests[0].profile, CameraShakeRequest.Profile.BLADE, "a parry is a blade snap, not a body blow")
	for frame: FeedbackFrame in [faint, sharp]:
		assert_eq(frame.hitstop_requests.size(), 0, "a parry never freezes the clock")
		assert_eq(frame.slow_motion_requests.size(), 0, "and never slows time")
