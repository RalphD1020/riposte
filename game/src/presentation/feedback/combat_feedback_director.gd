class_name CombatFeedbackDirector
extends RefCounted

## Pure mapping from PresentationSnapshot + DuelEvents + options to a
## FeedbackFrame of typed requests. No SceneTree dependency, no node references,
## no mutation of authoritative state.
##
## The director classifies each event, reads physical quantities from the event
## payload and snapshot, and emits value-like requests that downstream presenters
## consume. It does not know where the camera lives, which bus plays sound, or
## how a spark is drawn.
##
## Force-scaled, not bucketed: every channel of a body strike reads one
## continuous `response()` of the resolver's own quality, so a graze is barely
## there, an ordinary cut is readable, a strong one is dramatic, and a lethal
## one is exceptional — with no step anywhere along the way. Contact *kind*
## (slash, poke, thrust, graze) picks the shape of the effect; it never picks
## how big it is.
##
## Implements: /spec/invariants.md#pres-002
## See also: /docs/architecture/presentation-feedback.md

## Body-hit audio: the light and heavy families crossfade across this damage
## band, centred where the old single threshold sat.
const DAMAGE_HEAVY := 15.0
const DAMAGE_BLEND := 15.0
## Below this a crossfaded layer is inaudible and is not started.
const LAYER_FLOOR := 0.08
## Camera impulse ceilings — the camera reinforces boundaries only.
const IMPULSE_BLADE_MAX := 0.045
const IMPULSE_BODY_MAX := 0.09
const IMPULSE_DEVASTATING_MAX := 0.14
## Spark geometry: the normal fan is the smaller half of a clash.
const SPARK_NORMAL_SHARE := 0.4
## Parry ring.
const PARRY_RING_SIZE := 0.8
## Parry quality: the beat margin (seconds the defender got ahead) read as 0..1
## against a clean-parry ceiling. A threshold deflection already reads; a
## decisive one is razor-bright. Presentation interpretation, not a measurement.
const PARRY_QUALITY_CEIL := 0.16
const PARRY_SPARKS_MIN := 4
const PARRY_SPARKS_MAX := 14
const PARRY_SPARK_SPEED := 3.2
const PARRY_VOLUME_MIN := 0.55
const PARRY_PITCH_MIN := 1.1
const PARRY_PITCH_MAX := 1.3
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
## Response curve. Severity is strike quality over the devastating grade, so
## 1.0 is the top of an ordinary strike; it may run to `SEVERITY_CEILING`.
## The exponent bends the low end flat (a graze stays subtle) and lets the
## top keep growing into the devastating range.
const SEVERITY_CEILING := 1.5
const RESPONSE_EXPONENT := 1.6
## Point strikes: the axial spray's length at full response (m).
const AXIAL_LENGTH := 0.9
## Body collision: below this fraction of the reference impulse a touch of
## shoulders is not punctuated at all.
const BODY_PUSH_FLOOR := 0.12
const BODY_PUSH_DUST := 5
## Lethal: a short exceptional freeze, then the blow plays out slowly.
const LETHAL_FLASH_SIZE := 1.4
const LETHAL_SPARKS := 18
const LETHAL_SLOW_SCALE := 0.35
const LETHAL_SLOW_SECONDS := 0.7
const RING_OUT_DUST := 9


## Monotonic, continuous, and flat at the bottom: the whole feedback ladder.
static func response(severity: float) -> float:
	return pow(clampf(severity, 0.0, SEVERITY_CEILING), RESPONSE_EXPONENT)


static func severity_of(quality: float) -> float:
	return clampf(quality / PresentationKit.QUALITY_FULL, 0.0, SEVERITY_CEILING)


## Variant key for an event: same event, same take, in every replay.
static func variant_key(event: DuelEvent) -> int:
	return event.tick * 4 + maxi(event.actor, 0) + maxi(event.target, 0) * 2


static func process(
	snapshot: PresentationSnapshot,
	events: Array[DuelEvent],
	weapon_kit: PresentationKit,
	flash_scale: float,
	particle_scale: float = 1.0,
	style: VfxStyleKit = null
) -> FeedbackFrame:
	var frame := FeedbackFrame.new()
	var palette := style if style != null else VfxStyleKit.new()
	for event in events:
		_classify(event, snapshot, weapon_kit, flash_scale, clampf(particle_scale, 0.0, 1.0), palette, frame)
	return frame


static func _classify(event: DuelEvent, snapshot: PresentationSnapshot, weapon_kit: PresentationKit, flash: float, particles: float, palette: VfxStyleKit, frame: FeedbackFrame) -> void:
	match event.type:
		DuelEventTypes.ATTACK_RELEASED:
			_on_release(event, snapshot, frame)
		DuelEventTypes.BURST_STARTED:
			_on_burst(event, snapshot, flash, particles, palette, frame)
		DuelEventTypes.BLADE_CONTACT:
			_on_blade_contact(event, weapon_kit, flash, particles, palette, frame)
		DuelEventTypes.BIND_STARTED:
			_on_bind(event, weapon_kit, frame)
		DuelEventTypes.PARRY:
			_on_parry(event, weapon_kit, flash, particles, palette, frame)
		DuelEventTypes.BODY_HIT:
			_on_body_hit(event, snapshot, weapon_kit, flash, particles, palette, frame)
		DuelEventTypes.BODY_POKE:
			_on_point_strike(event, weapon_kit, PresentationKit.CUE_BODY_POKE, frame)
		DuelEventTypes.BODY_THRUST:
			_on_point_strike(event, weapon_kit, PresentationKit.CUE_BODY_THRUST, frame)
		DuelEventTypes.CRITICAL_HIT:
			var world := _contact_world(event, weapon_kit)
			frame.audio_requests.append(AudioCueRequest.create(PresentationKit.CUE_CRITICAL, world, DEVASTATING_VOLUME_DB, 1.0, AudioCueRequest.KitSource.WEAPON, variant_key(event)))
			frame.fighter_requests.append(FighterCueRequest.hit_flash(event.target, flash))
			frame.fighter_requests[-1].kind = FighterCueRequest.Kind.CRITICAL_FLASH
			frame.fighter_requests.append(FighterCueRequest.haptic(event.actor, FighterCueRequest.Kind.HAPTIC_CRITICAL))
		DuelEventTypes.BODY_PUSH:
			_on_body_push(event, snapshot, flash, particles, palette, frame)
		DuelEventTypes.RING_OUT:
			_on_ring_out(event, snapshot, flash, particles, palette, frame)
		DuelEventTypes.ROUND_STARTED:
			frame.audio_requests.append(AudioCueRequest.create(PresentationKit.CUE_ROUND, Vector3.ZERO, ROUND_VOLUME_DB, 1.0, AudioCueRequest.KitSource.ARENA, variant_key(event)))
		DuelEventTypes.ROUND_ENDED:
			frame.audio_requests.append(AudioCueRequest.create(PresentationKit.CUE_ROUND_WIN, Vector3.ZERO, ROUND_VOLUME_DB, 1.0, AudioCueRequest.KitSource.ARENA, variant_key(event)))


static func _on_release(event: DuelEvent, snapshot: PresentationSnapshot, frame: FeedbackFrame) -> void:
	var potential := snapshot.fighter(event.actor).swing_potential
	var world := _fighter_world(snapshot, event.actor)
	frame.audio_requests.append(AudioCueRequest.create(
		PresentationKit.CUE_SWING, world,
		lerpf(SWING_VOLUME_DB_TAP, SWING_VOLUME_DB_FULL, potential),
		lerpf(SWING_PITCH_TAP, SWING_PITCH_FULL, potential),
		AudioCueRequest.KitSource.WEAPON, variant_key(event)
	))


## Footwork writes on the floor, never in the air.
static func _on_burst(event: DuelEvent, snapshot: PresentationSnapshot, flash: float, particles: float, palette: VfxStyleKit, frame: FeedbackFrame) -> void:
	var heading := Vector3(event.number(DuelEventKeys.HEADING_X), 0.0, -event.number(DuelEventKeys.HEADING_Y))
	var world := _fighter_world(snapshot, event.actor)
	_append_particles(frame, VfxRequest.dust(world, heading, palette.dust, DUST_COUNT, DUST_SPEED, flash), particles)
	frame.audio_requests.append(AudioCueRequest.create(PresentationKit.CUE_DASH, world, 0.0, 1.0, AudioCueRequest.KitSource.WEAPON, variant_key(event)))


static func _on_blade_contact(event: DuelEvent, weapon_kit: PresentationKit, flash: float, particles: float, palette: VfxStyleKit, frame: FeedbackFrame) -> void:
	var world := _contact_world(event, weapon_kit)
	var intensity := clampf(event.number(DuelEventKeys.INTENSITY), 0.0, 1.0)
	var profile := ImpactPresentationProfile.clash()
	var count := lerpf(float(profile.spark_count_min), float(profile.spark_count_max), intensity)
	var speed := lerpf(profile.spark_speed_min, profile.spark_speed_max, intensity)
	var tangent := _direction(event, DuelEventKeys.STRIKE_X, DuelEventKeys.STRIKE_Y)
	var normal := _direction(event, DuelEventKeys.NORMAL_X, DuelEventKeys.NORMAL_Y)
	var hot := palette.spark.lerp(palette.spark_hot, intensity)
	_append_particles(frame, VfxRequest.sparks(world, tangent, hot, roundi(count * (1.0 - SPARK_NORMAL_SHARE)), speed, flash), particles)
	_append_particles(frame, VfxRequest.sparks(world, normal, hot, roundi(count * SPARK_NORMAL_SHARE), speed, flash), particles)
	frame.audio_requests.append(AudioCueRequest.create(_clash_cue(event), world, 0.0, 1.0, AudioCueRequest.KitSource.WEAPON, variant_key(event)))
	frame.hitstop_requests.append(HitstopRequest.create(weapon_kit.hitstop_for_clash(intensity)))
	frame.camera_requests.append(CameraShakeRequest.create(IMPULSE_BLADE_MAX * intensity * 100.0, normal, CameraShakeRequest.Profile.BLADE))
	frame.fighter_requests.append(FighterCueRequest.haptic(event.actor, FighterCueRequest.Kind.HAPTIC_BLADE))


## A parry is the defender ending up threatening first (COMBAT): the cleaner the
## beat — how far ahead the defender got, DuelEventKeys.MARGIN — the brighter the
## deflection reads. A decisive deflection flashes a tight ring, throws a hot
## spark fan, rings a crisp high TING, and snaps the camera a frame. There is no
## hitstop, no slow motion, no damage, and no stun: the simulation already
## settled the exchange and this only tells the eye how clean it was.
static func _on_parry(event: DuelEvent, weapon_kit: PresentationKit, flash: float, particles: float, palette: VfxStyleKit, frame: FeedbackFrame) -> void:
	var world := _contact_world(event, weapon_kit)
	var quality := clampf(event.number(DuelEventKeys.MARGIN) / PARRY_QUALITY_CEIL, 0.0, 1.0)
	frame.vfx_requests.append(VfxRequest.ring(world, palette.spark, PARRY_RING_SIZE * (0.7 + 0.3 * quality), flash))
	var hot := palette.spark.lerp(palette.spark_hot, quality)
	var count := roundi(lerpf(float(PARRY_SPARKS_MIN), float(PARRY_SPARKS_MAX), quality))
	_append_particles(frame, VfxRequest.sparks(world, Vector3.ZERO, hot, count, PARRY_SPARK_SPEED, flash), particles)
	frame.audio_requests.append(AudioCueRequest.create(
		PresentationKit.CUE_BLADE_STRONG, world,
		linear_to_db(lerpf(PARRY_VOLUME_MIN, 1.0, quality)),
		lerpf(PARRY_PITCH_MIN, PARRY_PITCH_MAX, quality),
		AudioCueRequest.KitSource.WEAPON, variant_key(event)
	))
	frame.camera_requests.append(CameraShakeRequest.create(IMPULSE_BLADE_MAX * quality * 100.0, Vector3.ZERO, CameraShakeRequest.Profile.BLADE))
	frame.fighter_requests.append(FighterCueRequest.haptic(event.actor, FighterCueRequest.Kind.HAPTIC_BLADE))


## Pinned blades are their own situation: a held grind, no hitstop.
static func _on_bind(event: DuelEvent, weapon_kit: PresentationKit, frame: FeedbackFrame) -> void:
	var request := AudioCueRequest.create(PresentationKit.CUE_BIND, _contact_world(event, weapon_kit), 0.0, 1.0, AudioCueRequest.KitSource.WEAPON, variant_key(event))
	request.hold = true
	frame.audio_requests.append(request)
	frame.fighter_requests.append(FighterCueRequest.haptic(event.actor, FighterCueRequest.Kind.HAPTIC_BLADE))


static func _on_body_hit(event: DuelEvent, snapshot: PresentationSnapshot, weapon_kit: PresentationKit, flash: float, particles: float, palette: VfxStyleKit, frame: FeedbackFrame) -> void:
	var damage := event.number(DuelEventKeys.DAMAGE)
	var severity := severity_of(event.number(DuelEventKeys.QUALITY))
	var gain := response(severity)
	var devastating := event.text(DuelEventKeys.GRADE) == SwingSemantics.grade_label(SwingSemantics.Grade.DEVASTATING)
	var lethal := bool(event.data.get(DuelEventKeys.LETHAL, false))
	var profile := _profile_for(event)
	var world := _contact_world(event, weapon_kit)
	var normal := _direction(event, DuelEventKeys.NORMAL_X, DuelEventKeys.NORMAL_Y)
	var strike := _direction(event, DuelEventKeys.STRIKE_X, DuelEventKeys.STRIKE_Y)
	frame.fighter_requests.append(FighterCueRequest.hit_flash(event.target, flash))
	if devastating or lethal:
		frame.fighter_requests[-1].kind = FighterCueRequest.Kind.CRITICAL_FLASH
	## Recoil along the push the simulation applied, at the scale it applied
	## it: a measured displacement is never exaggerated.
	var reach := maxf(event.number(DuelEventKeys.PUSH) * RECOIL_SECONDS, RECOIL_MIN_LENGTH)
	frame.vfx_requests.append(VfxRequest.streak(world, world + normal * reach, palette.body_impact, flash))
	var count := roundi(lerpf(float(profile.spark_count_min), float(profile.spark_count_max), minf(gain, 1.0)))
	var speed := lerpf(profile.spark_speed_min, profile.spark_speed_max, minf(gain, 1.0))
	if profile.shake_profile == CameraShakeRequest.Profile.POKE or profile.shake_profile == CameraShakeRequest.Profile.THRUST:
		_append_particles(frame, VfxRequest.axial(world, strike, palette.body_impact, count, speed, AXIAL_LENGTH * minf(gain, 1.0), flash), particles)
	else:
		_append_particles(frame, VfxRequest.sparks(world, strike, palette.body_impact, count, speed, flash), particles)
	_body_audio(event, world, damage, devastating, frame)
	var hitstop := weapon_kit.hitstop_for_strike(event.number(DuelEventKeys.QUALITY), devastating)
	frame.hitstop_requests.append(HitstopRequest.create(maxf(hitstop, weapon_kit.hitstop_devastating.y) if lethal else hitstop))
	var shake := CameraShakeRequest.Profile.KILL if devastating or lethal else profile.shake_profile
	var impulse := minf(IMPULSE_BODY_MAX * gain, IMPULSE_DEVASTATING_MAX)
	frame.camera_requests.append(CameraShakeRequest.create(impulse * 100.0, normal, shake))
	frame.fighter_requests.append(FighterCueRequest.haptic(event.target, FighterCueRequest.Kind.HAPTIC_BODY))
	if lethal:
		_lethal(event, world, strike, flash, particles, palette, frame)
	## The lock is the killing blow, not the stab: a death sequence is requested
	## only on the blow that leaves the target not alive. A non-lethal thrust or
	## poke lands its contact feel above and stops there (COMBAT-011).
	if not snapshot.fighter(event.target).is_alive():
		var family := DeathPresentationProfile.family_of(event.text(DuelEventKeys.CONTACT_KIND))
		frame.death_requests.append(DeathPresentationRequest.create(event.target, family, strike, gain, variant_key(event), event.actor))
		frame.weapon_drop_requests.append(WeaponDropRequest.from_blade(event.target, WeaponDropRequest.DEATH_DELAY, snapshot.fighter(event.target), variant_key(event)))


## Light and heavy families crossfade by damage, so there is no audible step
## where one tier used to end. The louder family leads the request list.
static func _body_audio(event: DuelEvent, world: Vector3, damage: float, devastating: bool, frame: FeedbackFrame) -> void:
	var heavy := clampf((damage - (DAMAGE_HEAVY - DAMAGE_BLEND * 0.5)) / DAMAGE_BLEND, 0.0, 1.0)
	var loud := DEVASTATING_VOLUME_DB if devastating else 0.0
	var key := variant_key(event)
	var lead := PresentationKit.CUE_BODY_HEAVY if heavy >= 0.5 else PresentationKit.CUE_BODY_LIGHT
	var trail := PresentationKit.CUE_BODY_LIGHT if heavy >= 0.5 else PresentationKit.CUE_BODY_HEAVY
	var trail_weight := 1.0 - heavy if heavy >= 0.5 else heavy
	frame.audio_requests.append(AudioCueRequest.create(lead, world, loud, 1.0, AudioCueRequest.KitSource.WEAPON, key))
	if trail_weight >= LAYER_FLOOR:
		frame.audio_requests.append(AudioCueRequest.create(trail, world, loud + linear_to_db(trail_weight), 1.0, AudioCueRequest.KitSource.WEAPON, key))


## The terminal blow: the full impact stack plus a signature accent, the
## exceptional directional effect, a very short freeze, then slow motion.
static func _lethal(event: DuelEvent, world: Vector3, strike: Vector3, flash: float, particles: float, palette: VfxStyleKit, frame: FeedbackFrame) -> void:
	frame.audio_requests.append(AudioCueRequest.create(PresentationKit.CUE_LETHAL_ACCENT, world, DEVASTATING_VOLUME_DB, 1.0, AudioCueRequest.KitSource.WEAPON, variant_key(event)))
	_append_particles(frame, VfxRequest.lethal_flash(world, strike, palette.lethal_accent, LETHAL_FLASH_SIZE, LETHAL_SPARKS, flash), particles, true)
	frame.camera_requests.append(CameraShakeRequest.create(IMPULSE_DEVASTATING_MAX * 100.0, strike, CameraShakeRequest.Profile.KILL))
	frame.slow_motion_requests.append(SlowMotionRequest.create(LETHAL_SLOW_SCALE, LETHAL_SLOW_SECONDS))
	frame.fighter_requests.append(FighterCueRequest.haptic(event.target, FighterCueRequest.Kind.HAPTIC_CRITICAL))


static func _on_point_strike(event: DuelEvent, weapon_kit: PresentationKit, cue: StringName, frame: FeedbackFrame) -> void:
	frame.audio_requests.append(AudioCueRequest.create(cue, _contact_world(event, weapon_kit), 0.0, 1.0, AudioCueRequest.KitSource.WEAPON, variant_key(event)))
	frame.fighter_requests.append(FighterCueRequest.haptic(event.target, FighterCueRequest.Kind.HAPTIC_BODY))


## Shoulders meeting: floor dust and a low transient, both from how hard the
## bodies actually met relative to the reference strike. No hitstop.
static func _on_body_push(event: DuelEvent, snapshot: PresentationSnapshot, flash: float, particles: float, palette: VfxStyleKit, frame: FeedbackFrame) -> void:
	if snapshot.reference_impulse <= 0.0:
		return
	var impulse01 := clampf(event.number(DuelEventKeys.IMPULSE) / snapshot.reference_impulse, 0.0, 1.0)
	if impulse01 < BODY_PUSH_FLOOR:
		return
	var world := ArenaTransform.to_world(event.number(DuelEventKeys.X), event.number(DuelEventKeys.Y))
	var normal := _direction(event, DuelEventKeys.NORMAL_X, DuelEventKeys.NORMAL_Y)
	_append_particles(frame, VfxRequest.dust(world, normal, palette.dust, BODY_PUSH_DUST, DUST_SPEED * impulse01, flash), particles)
	frame.audio_requests.append(AudioCueRequest.create(PresentationKit.CUE_IMPACT_LOW, world, linear_to_db(impulse01), 1.0, AudioCueRequest.KitSource.WEAPON, variant_key(event)))
	frame.camera_requests.append(CameraShakeRequest.create(IMPULSE_BLADE_MAX * impulse01 * 100.0, normal, CameraShakeRequest.Profile.BODY))
	frame.fighter_requests.append(FighterCueRequest.haptic(0, FighterCueRequest.Kind.HAPTIC_BODY))


## Losing footing at the edge: dust kicked back from the lip, the fall sound,
## and the fall itself — handed to presentation from the exact exit position and
## carried momentum, so the body flies out along the knockback that caused it.
static func _on_ring_out(event: DuelEvent, snapshot: PresentationSnapshot, flash: float, particles: float, palette: VfxStyleKit, frame: FeedbackFrame) -> void:
	var world := _fighter_world(snapshot, event.actor)
	var heading := Vector3(event.number(DuelEventKeys.VELOCITY_X), 0.0, -event.number(DuelEventKeys.VELOCITY_Y))
	_append_particles(frame, VfxRequest.dust(world, -heading, palette.dust, RING_OUT_DUST, DUST_SPEED, flash), particles)
	frame.audio_requests.append(AudioCueRequest.create(PresentationKit.CUE_FALL, world, 0.0, 1.0, AudioCueRequest.KitSource.WEAPON, variant_key(event)))
	var exit := ArenaTransform.to_world(event.number(DuelEventKeys.POSITION_X), event.number(DuelEventKeys.POSITION_Y))
	frame.fall_requests.append(FallPresentationRequest.create(event.actor, exit, heading, variant_key(event)))
	var key := variant_key(event)
	frame.weapon_drop_requests.append(WeaponDropRequest.from_blade(event.actor, WeaponDropRequest.ring_out_delay(key), snapshot.fighter(event.actor), key))


## Particle-bearing requests honour `particle_intensity`; at zero they are
## dropped and the moment is carried by flash, sound, and pacing instead.
static func _append_particles(frame: FeedbackFrame, request: VfxRequest, particles: float, keep_at_zero: bool = false) -> void:
	if particles <= 0.0 and not keep_at_zero:
		return
	request.count = maxi(1, roundi(float(request.count) * maxf(particles, 0.0))) if request.count > 0 else 0
	frame.vfx_requests.append(request)


static func _profile_for(event: DuelEvent) -> ImpactPresentationProfile:
	match event.text(DuelEventKeys.CONTACT_KIND):
		"poke":
			return ImpactPresentationProfile.poke()
		"thrust":
			return ImpactPresentationProfile.thrust()
		"graze":
			return ImpactPresentationProfile.graze()
	return ImpactPresentationProfile.slash()


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
