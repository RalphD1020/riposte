class_name CombatFeedbackDirector
extends RefCounted

## Pure mapping from PresentationSnapshot + DuelEvents + PlayerSettings to a
## FeedbackFrame of typed requests. No SceneTree dependency, no node references,
## no mutation of authoritative state.
##
## The director classifies each event, reads physical quantities from the event
## payload and snapshot, and emits value-like requests that downstream presenters
## consume. It does not know where the camera lives, which bus plays sound, or
## how a spark is drawn.
##
## Implements: /spec/invariants.md#pres-002
## See also: /docs/architecture/presentation-feedback.md

## Body-hit audio tiers by damage: light < heavy.
const DAMAGE_HEAVY := 15.0
## Camera impulse ceilings — the camera reinforces boundaries only.
const IMPULSE_BLADE_MAX := 0.045
const IMPULSE_BODY_MAX := 0.09
const IMPULSE_DEVASTATING_MAX := 0.14
## Spark geometry: the normal fan is the smaller half of a clash.
const SPARK_NORMAL_SHARE := 0.4
## Parry ring.
const PARRY_RING_SIZE := 0.8
## Recoil streak: one tick of push distance.
const RECOIL_SECONDS := SimulationTimebase.TICK_SECONDS
const RECOIL_MIN_LENGTH := 0.05
## Swing whoosh volume/pitch from potential.
const SWING_VOLUME_DB_TAP := -6.0
const SWING_VOLUME_DB_FULL := 0.0
const SWING_PITCH_TAP := 1.15
const SWING_PITCH_FULL := 0.9
## Dust burst.
const DUST_COUNT := 7
const DUST_SPEED := 1.4
const ROUND_VOLUME_DB := -4.0
const DEVASTATING_VOLUME_DB := 2.0


static func process(snapshot: PresentationSnapshot, events: Array[DuelEvent], weapon_kit: PresentationKit, flash_scale: float) -> FeedbackFrame:
	var frame := FeedbackFrame.new()
	for event in events:
		_classify(event, snapshot, weapon_kit, flash_scale, frame)
	return frame


static func _classify(event: DuelEvent, snapshot: PresentationSnapshot, weapon_kit: PresentationKit, flash: float, frame: FeedbackFrame) -> void:
	match event.type:
		DuelEventTypes.ATTACK_RELEASED:
			_on_release(event, snapshot, weapon_kit, frame)
		DuelEventTypes.BURST_STARTED:
			_on_burst(event, snapshot, flash, frame)
		DuelEventTypes.BLADE_CONTACT:
			_on_blade_contact(event, weapon_kit, flash, frame)
		DuelEventTypes.BIND_STARTED:
			_on_bind(event, weapon_kit, frame)
		DuelEventTypes.PARRY:
			frame.vfx_requests.append(VfxRequest.ring(_contact_world(event, weapon_kit), RiposteTheme.SPARK, PARRY_RING_SIZE, flash))
		DuelEventTypes.BODY_HIT:
			_on_body_hit(event, weapon_kit, flash, frame)
		DuelEventTypes.BODY_POKE:
			_on_point_strike(event, weapon_kit, PresentationKit.CUE_BODY_POKE, frame)
		DuelEventTypes.BODY_THRUST:
			_on_point_strike(event, weapon_kit, PresentationKit.CUE_BODY_THRUST, frame)
		DuelEventTypes.CRITICAL_HIT:
			var world := _contact_world(event, weapon_kit)
			frame.audio_requests.append(AudioCueRequest.create(PresentationKit.CUE_CRITICAL, world, DEVASTATING_VOLUME_DB))
			frame.fighter_requests.append(FighterCueRequest.haptic(event.actor, FighterCueRequest.Kind.HAPTIC_CRITICAL))
		DuelEventTypes.ROUND_STARTED, DuelEventTypes.ROUND_ENDED:
			frame.audio_requests.append(AudioCueRequest.create(PresentationKit.CUE_ROUND, Vector3.ZERO, ROUND_VOLUME_DB, 1.0, AudioCueRequest.KitSource.ARENA))


static func _on_release(event: DuelEvent, snapshot: PresentationSnapshot, _weapon_kit: PresentationKit, frame: FeedbackFrame) -> void:
	var potential := snapshot.fighter(event.actor).swing_potential
	var world := _fighter_world(snapshot, event.actor)
	frame.audio_requests.append(AudioCueRequest.create(
		PresentationKit.CUE_SWING, world,
		lerpf(SWING_VOLUME_DB_TAP, SWING_VOLUME_DB_FULL, potential),
		lerpf(SWING_PITCH_TAP, SWING_PITCH_FULL, potential)
	))


static func _on_burst(event: DuelEvent, snapshot: PresentationSnapshot, flash: float, frame: FeedbackFrame) -> void:
	var heading := Vector3(event.number(DuelEventKeys.HEADING_X), 0.0, -event.number(DuelEventKeys.HEADING_Y))
	var world := _fighter_world(snapshot, event.actor)
	frame.vfx_requests.append(VfxRequest.dust(world, heading, RiposteTheme.WORLD_FLOOR_EDGE, DUST_COUNT, DUST_SPEED, flash))


static func _on_blade_contact(event: DuelEvent, weapon_kit: PresentationKit, flash: float, frame: FeedbackFrame) -> void:
	var world := _contact_world(event, weapon_kit)
	var intensity := event.number(DuelEventKeys.INTENSITY)
	var count := lerpf(float(ImpactPresentationProfile.clash().spark_count_min), float(ImpactPresentationProfile.clash().spark_count_max), intensity)
	var speed := lerpf(ImpactPresentationProfile.clash().spark_speed_min, ImpactPresentationProfile.clash().spark_speed_max, intensity)
	var tangent := _direction(event, DuelEventKeys.STRIKE_X, DuelEventKeys.STRIKE_Y)
	var normal := _direction(event, DuelEventKeys.NORMAL_X, DuelEventKeys.NORMAL_Y)
	frame.vfx_requests.append(VfxRequest.sparks(world, tangent, RiposteTheme.SPARK, roundi(count * (1.0 - SPARK_NORMAL_SHARE)), speed, flash))
	frame.vfx_requests.append(VfxRequest.sparks(world, normal, RiposteTheme.SPARK, roundi(count * SPARK_NORMAL_SHARE), speed, flash))
	frame.audio_requests.append(AudioCueRequest.create(_clash_cue(event), world))
	frame.hitstop_requests.append(HitstopRequest.create(weapon_kit.hitstop_for_clash(intensity)))
	frame.camera_requests.append(CameraShakeRequest.create(IMPULSE_BLADE_MAX * intensity * 100.0, normal, CameraShakeRequest.Profile.BLADE))
	frame.fighter_requests.append(FighterCueRequest.haptic(event.actor, FighterCueRequest.Kind.HAPTIC_BLADE))


static func _on_bind(event: DuelEvent, weapon_kit: PresentationKit, frame: FeedbackFrame) -> void:
	frame.audio_requests.append(AudioCueRequest.create(PresentationKit.CUE_BIND, _contact_world(event, weapon_kit)))
	frame.fighter_requests.append(FighterCueRequest.haptic(event.actor, FighterCueRequest.Kind.HAPTIC_BLADE))


static func _on_body_hit(event: DuelEvent, weapon_kit: PresentationKit, flash: float, frame: FeedbackFrame) -> void:
	var damage := event.number(DuelEventKeys.DAMAGE)
	var quality := event.number(DuelEventKeys.QUALITY)
	var devastating := event.text(DuelEventKeys.GRADE) == SwingSemantics.grade_label(SwingSemantics.Grade.DEVASTATING)
	var world := _contact_world(event, weapon_kit)
	var normal := _direction(event, DuelEventKeys.NORMAL_X, DuelEventKeys.NORMAL_Y)
	var strike := _direction(event, DuelEventKeys.STRIKE_X, DuelEventKeys.STRIKE_Y)
	frame.fighter_requests.append(FighterCueRequest.hit_flash(event.target, flash))
	var reach := maxf(event.number(DuelEventKeys.PUSH) * RECOIL_SECONDS, RECOIL_MIN_LENGTH)
	frame.vfx_requests.append(VfxRequest.streak(world, world + normal * reach, RiposteTheme.BODY_IMPACT, flash))
	var profile := ImpactPresentationProfile.slash()
	frame.vfx_requests.append(VfxRequest.sparks(world, strike, RiposteTheme.BODY_IMPACT, profile.spark_count_min, profile.spark_speed_min, flash))
	var loud := DEVASTATING_VOLUME_DB if devastating else 0.0
	var cue := PresentationKit.CUE_BODY_HEAVY if damage >= DAMAGE_HEAVY else PresentationKit.CUE_BODY_LIGHT
	frame.audio_requests.append(AudioCueRequest.create(cue, world, loud))
	frame.hitstop_requests.append(HitstopRequest.create(weapon_kit.hitstop_for_strike(quality, devastating)))
	var ceiling := IMPULSE_DEVASTATING_MAX if devastating else IMPULSE_BODY_MAX
	var severity01 := clampf(quality / PresentationKit.QUALITY_FULL, 0.0, 1.0)
	frame.camera_requests.append(CameraShakeRequest.create(ceiling * severity01 * 100.0, normal, CameraShakeRequest.Profile.KILL if devastating else CameraShakeRequest.Profile.BODY))
	frame.fighter_requests.append(FighterCueRequest.haptic(event.target, FighterCueRequest.Kind.HAPTIC_BODY))


static func _on_point_strike(event: DuelEvent, weapon_kit: PresentationKit, cue: StringName, frame: FeedbackFrame) -> void:
	frame.audio_requests.append(AudioCueRequest.create(cue, _contact_world(event, weapon_kit)))
	frame.fighter_requests.append(FighterCueRequest.haptic(event.target, FighterCueRequest.Kind.HAPTIC_BODY))


static func _clash_cue(event: DuelEvent) -> StringName:
	match StringName(event.text(DuelEventKeys.CONTACT_CLASS)):
		ContactResolver.CLASS_STRONG:
			return PresentationKit.CUE_BLADE_STRONG
		ContactResolver.CLASS_SOLID:
			return PresentationKit.CUE_BLADE_SOLID
		_:
			return PresentationKit.CUE_BLADE_LIGHT


static func _contact_world(event: DuelEvent, weapon_kit: PresentationKit) -> Vector3:
	return ArenaTransform.to_world(event.number(DuelEventKeys.X), event.number(DuelEventKeys.Y), weapon_kit.blade_height)


static func _fighter_world(snapshot: PresentationSnapshot, slot: int) -> Vector3:
	var fighter := snapshot.fighter(slot)
	return ArenaTransform.to_world(fighter.x, fighter.y)


static func _direction(event: DuelEvent, key_x: String, key_y: String) -> Vector3:
	var direction := Vector3(event.number(key_x), 0.0, -event.number(key_y))
	return direction.normalized() if direction.length_squared() > 0.0 else Vector3.ZERO
