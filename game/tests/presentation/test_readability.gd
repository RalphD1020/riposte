extends TestCase

## PRES-READABILITY: every gameplay-critical combat cue is a projection of the
## solved physics, carried on at least two senses, and accessibility settings
## change only how strongly it is drawn (COMBAT-READABILITY-001).
##
## Implements: /spec/invariants.md#combat-readability-001
## See also: /docs/concepts/presentation.md

var _rules: DuelRules
var _kits: DuelKits


func _init() -> void:
	suite_name = "PRES-READABILITY"
	_rules = StandardDuelRules.create()
	_kits = DuelKits.resolve(RiposteKits.build_catalog(), _rules)


func _snapshot() -> PresentationSnapshot:
	return SnapshotProjector.project(DuelSetup.new_state(_rules, 1), _rules)


func _frame(type: StringName, data: Dictionary, particles: float = 1.0, flash: float = 1.0) -> FeedbackFrame:
	var events: Array[DuelEvent] = [DuelEvent.create(type, 1, 0, 1, data)]
	return CombatFeedbackDirector.process(_snapshot(), events, _kits.weapon, flash, particles)


func _clash() -> Dictionary:
	return {
		DuelEventKeys.X: 0.0, DuelEventKeys.Y: 0.0, DuelEventKeys.INTENSITY: 0.8,
		DuelEventKeys.CONTACT_CLASS: String(ContactResolver.CLASS_STRONG),
		DuelEventKeys.NORMAL_X: 1.0, DuelEventKeys.NORMAL_Y: 0.0, DuelEventKeys.STRIKE_X: 0.0, DuelEventKeys.STRIKE_Y: 1.0,
	}


func _hit() -> Dictionary:
	return {
		DuelEventKeys.X: 0.0, DuelEventKeys.Y: 0.0, DuelEventKeys.DAMAGE: 30.0, DuelEventKeys.QUALITY: 1.0,
		DuelEventKeys.GRADE: SwingSemantics.grade_label(SwingSemantics.Grade.HEAVY),
		DuelEventKeys.NORMAL_X: 1.0, DuelEventKeys.NORMAL_Y: 0.0, DuelEventKeys.STRIKE_X: 0.0, DuelEventKeys.STRIKE_Y: 1.0,
		DuelEventKeys.PUSH: 0.5,
	}


func _parry() -> Dictionary:
	return {
		DuelEventKeys.X: 0.0, DuelEventKeys.Y: 0.0, DuelEventKeys.MARGIN: CombatFeedbackDirector.PARRY_QUALITY_CEIL,
		DuelEventKeys.NORMAL_X: 1.0, DuelEventKeys.NORMAL_Y: 0.0, DuelEventKeys.STRIKE_X: 0.0, DuelEventKeys.STRIKE_Y: 1.0,
	}


static func _kinds(frame: FeedbackFrame) -> Array[VfxRequest.Kind]:
	var kinds: Array[VfxRequest.Kind] = []
	for request in frame.vfx_requests:
		if not kinds.has(request.kind):
			kinds.append(request.kind)
	return kinds


static func _has_flash(frame: FeedbackFrame) -> bool:
	for request in frame.fighter_requests:
		if request.kind == FighterCueRequest.Kind.HIT_FLASH or request.kind == FighterCueRequest.Kind.CRITICAL_FLASH:
			return true
	return false


func test_a_clash_is_seen_and_heard() -> void:
	var frame := _frame(DuelEventTypes.BLADE_CONTACT, _clash())
	assert_true(frame.vfx_requests.size() > 0, "a clash is seen (sparks at the contact)")
	assert_true(frame.audio_requests.size() > 0, "and heard (a clang)")


func test_a_body_hit_is_seen_and_heard() -> void:
	var frame := _frame(DuelEventTypes.BODY_HIT, _hit())
	assert_true(_has_flash(frame), "a body hit is seen on the victim")
	assert_true(frame.audio_requests.size() > 0, "and heard")


## A parry, a steel contact and a body hit are told apart by shape, timing and
## sound, never by color alone. The parry rings out and throws sparks with no
## hitstop and a raised pitch; the clash throws sparks and holds a hitstop at
## the clang's own pitch; the hit marks the victim's body with its own cue.
## This asserts what is dispatched from each authoritative event; whether it
## reads at the match camera is a capture.
func test_parry_steel_and_body_differ_by_shape_timing_and_sound() -> void:
	var clash := _frame(DuelEventTypes.BLADE_CONTACT, _clash())
	var parry := _frame(DuelEventTypes.PARRY, _parry())
	var hit := _frame(DuelEventTypes.BODY_HIT, _hit())
	assert_true(clash.vfx_requests.size() > 0 and parry.vfx_requests.size() > 0, "fixture: both steel events draw")
	assert_true(_kinds(parry).has(VfxRequest.Kind.RING), "a parry rings out")
	assert_false(_kinds(clash).has(VfxRequest.Kind.RING), "a clash does not, so the two differ in shape")
	assert_true(clash.hitstop_requests.size() > 0, "a clash holds a hitstop")
	assert_eq(parry.hitstop_requests.size(), 0, "a parry does not, so they differ in timing")
	assert_true(_has_flash(hit) and not _has_flash(clash) and not _has_flash(parry), "only the hit marks a body")
	var clash_pitch := clash.audio_requests[0].pitch
	var parry_pitch := parry.audio_requests[0].pitch
	assert_true(parry_pitch > CombatFeedbackDirector.CLASH_PITCH_FOIBLE and clash_pitch <= CombatFeedbackDirector.CLASH_PITCH_FOIBLE, "a parry rings above every clang (%.2f vs %.2f)" % [parry_pitch, clash_pitch])
	var hit_cues: Array[StringName] = []
	for request in hit.audio_requests:
		hit_cues.append(request.cue)
	assert_false(hit_cues.has(clash.audio_requests[0].cue) or hit_cues.has(parry.audio_requests[0].cue), "a hit sounds like flesh, not steel")


## A true whiff is heard as its own hollow follow-through and seen in the
## body's overswing — and never punctuated like a hit.
func test_a_whiff_is_heard_and_seen_but_never_punctuated() -> void:
	var tap := _frame(DuelEventTypes.ATTACK_WHIFFED, {DuelEventKeys.CHARGE: 0.0})
	var full := _frame(DuelEventTypes.ATTACK_WHIFFED, {DuelEventKeys.CHARGE: 1.0})
	assert_eq(tap.audio_requests.size(), 1, "a whiff is heard")
	if tap.audio_requests.is_empty() or full.audio_requests.is_empty():
		return
	assert_eq(tap.audio_requests[0].cue, PresentationKit.CUE_WHIFF, "as its own cue, not a hit's")
	assert_true(tap.audio_requests[0].pitch < CombatFeedbackDirector.SWING_PITCH_FULL, "lower than any swing: hollow")
	assert_true(full.audio_requests[0].volume_db > tap.audio_requests[0].volume_db, "louder for a harder launch")
	assert_eq(tap.vfx_requests.size() + tap.hitstop_requests.size() + tap.camera_requests.size() + tap.fighter_requests.size(), 0, "and never sparks, stops, shakes or buzzes")
	var row := _snapshot().fighter(0)
	row.phase = CombatPhase.Id.OVERSWING
	assert_eq(FighterAnimationSelector.select(row, false, false), PresentationKit.ANIM_OVERSWING, "seen: the body runs on into its overswing")


## Turning every visual intensity down never removes a cue's other sense.
func test_reduced_visuals_keep_every_cue_audible() -> void:
	var clash := _frame(DuelEventTypes.BLADE_CONTACT, _clash(), 0.0, 0.0)
	var hit := _frame(DuelEventTypes.BODY_HIT, _hit(), 0.0, 0.0)
	assert_eq(clash.vfx_requests.size(), 0, "fixture: particles off draws no sparks")
	assert_true(clash.audio_requests.size() > 0, "the clash is still heard")
	assert_true(hit.audio_requests.size() > 0, "the hit is still heard")
	assert_true(_has_flash(hit), "and still marked on the victim")


## Presentation settings change the drawing, never the duel: the same match
## presented two very different ways ends on the same state hash.
func test_presentation_settings_never_change_the_simulation() -> void:
	var hashes := PackedStringArray()
	for reduced: bool in [false, true]:
		var runner := SimRunner.create(_rules, 7)
		var options := PresentationOptions.new()
		if reduced:
			options.reduced_motion = true
			options.reduced_flash = true
			options.screen_shake = false
			options.particle_intensity = 0.0
			options.trail_strength = 0.0
			options.haptics = false
			options.high_contrast_weapons = true
		var root := Node3D.new()
		(Engine.get_main_loop() as SceneTree).root.add_child(root)
		var presenter := MatchPresenter.create(_kits, options, null, _rules.platform_radius, _rules.edge_warning_inset, SnapshotProjector.project(runner.state, _rules))
		root.add_child(presenter)
		var first := Pilot.wander(7, 11)
		var second := Pilot.wander(7, 23)
		for _tick in 240:
			var before := runner.events.size()
			runner.push(first.command(runner.state, 0), second.command(runner.state, 1))
			var events: Array[DuelEvent] = []
			for index in range(before, runner.events.size()):
				events.append(runner.events[index])
			presenter.push(SnapshotProjector.project(runner.state, _rules), events)
			presenter.render(1.0, 1.0 / 60.0)
		hashes.append(StateHasher.hash_state(runner.state))
		presenter.detach_and_dispose()
		root.queue_free()
	assert_true(hashes.size() == 2, "fixture: two presentations of one match")
	assert_eq(hashes[1], hashes[0], "the same duel whatever the accessibility settings")


static func _requests(cues: Array[StringName]) -> Array[AudioCueRequest]:
	var requests: Array[AudioCueRequest] = []
	for cue in cues:
		requests.append(AudioCueRequest.create(cue))
	return requests


## A sound caption is a third sense for the same cue, and it keeps the
## physical hierarchy: a tap reads smaller than a heavy clash, a clash smaller
## than a hit, one caption per tick, and decorative layers never add text.
func test_sound_captions_keep_the_physical_hierarchy() -> void:
	assert_eq(SoundCaptions.pick(_requests([])), "", "fixture: silence captions nothing")
	assert_eq(SoundCaptions.pick(_requests([PresentationKit.CUE_BLADE_LIGHT])), "[Blades tap]", "a tap")
	assert_eq(SoundCaptions.pick(_requests([PresentationKit.CUE_BLADE_STRONG, PresentationKit.CUE_METAL_TAIL, PresentationKit.CUE_IMPACT_LOW])), "[Heavy clash]", "a heavy clash, its layers silent in text")
	assert_eq(SoundCaptions.pick(_requests([PresentationKit.CUE_BLADE_SOLID, PresentationKit.CUE_BODY_HEAVY])), "[Heavy hit]", "a hit outranks the clash in the same tick")
	assert_eq(SoundCaptions.pick(_requests([PresentationKit.CUE_BODY_LIGHT, PresentationKit.CUE_BODY_HEAVY])), "[Light hit]", "a cut's lead take names it, not its trailing layer")
	assert_eq(SoundCaptions.pick(_requests([PresentationKit.CUE_BODY_HEAVY, PresentationKit.CUE_CRITICAL])), "[Critical hit]", "and a critical outranks everything")
	assert_eq(SoundCaptions.pick(_requests([PresentationKit.CUE_SWING, PresentationKit.CUE_DASH, PresentationKit.CUE_CHARGE])), "", "swings, footwork and tension are seen, not captioned")
	for event: Array in [[DuelEventTypes.BLADE_CONTACT, _clash()], [DuelEventTypes.BODY_HIT, _hit()], [DuelEventTypes.ATTACK_WHIFFED, {DuelEventKeys.CHARGE: 0.5}]]:
		var frame := _frame(event[0], event[1])
		var text := SoundCaptions.pick(frame.audio_requests)
		assert_ne(text, "", "%s is captioned from the sounds the director asked for" % event[0])
		var cues: Array[StringName] = []
		for request in frame.audio_requests:
			cues.append(request.cue)
		assert_true(cues.any(func(cue: StringName) -> bool: return HudCopy.sound_caption(cue) == text), "%s: the caption names a sound that plays" % event[0])


## Captions are asked for only when the player turns them on, and turning them
## on never changes what is played.
func test_the_presenter_captions_sounds_only_when_asked() -> void:
	var counts := PackedInt32Array()
	var texts := PackedStringArray()
	var expected := ""
	for on: bool in [false, true]:
		var options := PresentationOptions.new()
		options.sound_captions = on
		var root := Node3D.new()
		(Engine.get_main_loop() as SceneTree).root.add_child(root)
		var presenter := MatchPresenter.create(_kits, options, null, _rules.platform_radius, _rules.edge_warning_inset, _snapshot())
		root.add_child(presenter)
		var heard: Array[String] = []
		presenter.sound_caption_requested.connect(func(text: String, seconds: float) -> void:
			heard.append(text)
			assert_eq(seconds, SoundCaptions.HOLD_SECONDS, "held for the caption time")
		)
		var events: Array[DuelEvent] = [DuelEvent.create(DuelEventTypes.BLADE_CONTACT, 1, 0, 1, _clash())]
		presenter.push(_snapshot(), events)
		counts.append(presenter.last_frame().audio_requests.size())
		texts.append(",".join(PackedStringArray(heard)))
		expected = SoundCaptions.pick(presenter.last_frame().audio_requests)
		presenter.detach_and_dispose()
		root.queue_free()
	assert_true(counts[0] > 0, "fixture: the clash is heard either way")
	assert_eq(texts[0], "", "off: nothing is captioned")
	assert_ne(expected, "", "fixture: the clash has a caption")
	assert_eq(texts[1], expected, "on: exactly one caption, for the sound that played")
	assert_eq(counts[1], counts[0], "and the same sounds are played")
