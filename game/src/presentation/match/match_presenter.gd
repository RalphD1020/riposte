class_name MatchPresenter
extends Node3D

## The transient 3D root and the one presentation coordinator for a match.
##
## Per simulation tick: `push(snapshot, events)` stores the new snapshot and
## turns events into feedback (sparks, rings, sounds, hitstop, impulses,
## haptics) using the cues and feel values declared by the kits. Per frame:
## `render(alpha, delta)` interpolates between the last two snapshots with
## the tick driver's alpha and poses the passive proxies. It never steps,
## reads, or mutates the simulation; hitstop is a request to the clock owner.
## Generic code here never names a content identity.
##
## Implements: /spec/invariants.md#pres-001
## See also: /docs/concepts/presentation.md

signal hitstop_requested(seconds: float)

## Feedback constants live on CombatFeedbackDirector (PRES-002).  Aliases here
## keep call sites short while the presenter still owns inline dispatch.
## Spark geometry lives here because the director reads ImpactPresentationProfile
## instead; these four are only consumed by the presenter's own _on_blade_contact
## and _on_body_hit while the wiring coexists.
const SPARK_COUNT_MIN := 3
const SPARK_COUNT_MAX := 12
const SPARK_SPEED_MIN := 1.8
const SPARK_SPEED_MAX := 4.5

var _kits: DuelKits
var _options: PresentationOptions
var _camera: DuelCameraRig
var _haptics := Haptics.new()
var _arena: ArenaScaffold
var _fighters: Array[FighterPresentation3D] = []
var _trails: Array[SwordTrail3D] = []
var _vectors: DebugVectors3D
var _vfx: VfxDirector
var _audio: AudioDirector
var _previous: PresentationSnapshot
var _current: PresentationSnapshot
var _snap: bool = true
var _disposed: bool = false


static func create(kits: DuelKits, options: PresentationOptions, camera: DuelCameraRig, platform_radius: float, edge_warning_inset: float, first: PresentationSnapshot) -> MatchPresenter:
	var presenter := MatchPresenter.new()
	presenter.name = "MatchPresentation"
	presenter._kits = kits
	presenter._options = options
	presenter._camera = camera
	presenter._haptics.enabled = options.haptics
	presenter._build(platform_radius, edge_warning_inset, first)
	return presenter


func _ready() -> void:
	_audio.play_music(_kits.arena)


func push(snapshot: PresentationSnapshot, events: Array[DuelEvent]) -> void:
	var restarted := _current != null and snapshot.phase == MatchPhase.Id.ROUND_INTRO and _current.phase != MatchPhase.Id.ROUND_INTRO
	_previous = _current if _current != null and not restarted else snapshot
	_current = snapshot
	if restarted:
		_snap = true
		for ribbon in _trails:
			ribbon.clear_trail()
		for slot in 2:
			_audio.release_tension(slot)
	for event in events:
		_dispatch(event)


func render(alpha: float, delta: float) -> void:
	if _current == null or _disposed:
		return
	var weight := clampf(alpha, 0.0, 1.0)
	var first := _pose(0, weight, delta)
	var second := _pose(1, weight, delta)
	_vectors.update(_current)
	_vfx.advance(delta)
	if _camera != null:
		_camera.frame(first, second, delta, _options, _snap)
	_snap = false


func fighter_proxy(slot: int) -> FighterPresentation3D:
	return _fighters[slot]


func trail(slot: int) -> SwordTrail3D:
	return _trails[slot]


## The world-space debug vectors, so the screen that owns the debug toggle can
## show them beside the text overlay.
func debug_vectors() -> DebugVectors3D:
	return _vectors


func vfx() -> VfxDirector:
	return _vfx


func audio() -> AudioDirector:
	return _audio


func haptics() -> Haptics:
	return _haptics


func current_snapshot() -> PresentationSnapshot:
	return _current


## Remove from the tree and free. Idempotent; safe during teardown.
func detach_and_dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_vfx.clear_all()
	_audio.stop_all()
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)
	queue_free()


func _build(platform_radius: float, edge_warning_inset: float, first: PresentationSnapshot) -> void:
	_arena = ArenaScaffold.create(_kits.arena, platform_radius, edge_warning_inset, first.spawn_offset)
	add_child(_arena)
	for slot in 2:
		var row := first.fighter(slot)
		var proxy := FighterPresentation3D.create(slot, row.side, _kits.fighter, _kits.weapon, row.body_radius, row.hilt_radius, row.tip_radius)
		proxy.set_charge_indicator(_options.show_charge_indicator)
		proxy.set_high_contrast(_options.high_contrast_weapons)
		add_child(proxy)
		_fighters.append(proxy)
		var capacity := _kits.weapon.trail_samples * (2 if _options.high_contrast_weapons else 1)
		var ribbon := SwordTrail3D.create(proxy.blade_color(), capacity)
		ribbon.set_strength(_options.trail_strength, _options.sweet_spot_cue)
		add_child(ribbon)
		_trails.append(ribbon)
	_vectors = DebugVectors3D.create(_kits.weapon.blade_height)
	add_child(_vectors)
	_vfx = VfxDirector.new()
	add_child(_vfx)
	_audio = AudioDirector.new()
	add_child(_audio)
	_previous = first
	_current = first


## Interpolate one fighter between the last two snapshots, pose its proxy
## and trail, and return where it stands in the world.
func _pose(slot: int, weight: float, delta: float) -> Vector3:
	var from := _previous.fighter(slot)
	var to := _current.fighter(slot)
	var world := ArenaTransform.to_world(lerpf(from.x, to.x, weight), lerpf(from.y, to.y, weight))
	var proxy := _fighters[slot]
	proxy.apply_pose(world, lerp_angle(from.facing, to.facing, weight), lerpf(from.weapon_angle, to.weapon_angle, weight), to.charge, to.phase, to.is_alive(), to.is_falling, delta)
	var blade := proxy.blade_points()
	_trails[slot].add_sample(blade[0], blade[1], to.swing_potential, to.blade_speed, _kits.weapon.trail_min_speed)
	_trails[slot].advance(delta)
	_tension(slot, to, world)
	return world


## The wind-back needs no invented cue: the blade physically travels backwards,
## which is already the best anticipation the game has. Audio only tightens
## behind it, rising with the wind-back actually earned and plateauing when
## there is no more to earn. No charge glow (UX §19).
func _tension(slot: int, row: PresentationFighter, world: Vector3) -> void:
	if row.phase == CombatPhase.Id.CHARGING and row.is_alive():
		_audio.hold_tension(slot, _kits.weapon, world, row.charge)
	else:
		_audio.release_tension(slot)


func _fighter_world(slot: int, height: float = 0.0) -> Vector3:
	var fighter := _current.fighter(slot)
	return ArenaTransform.to_world(fighter.x, fighter.y, height)


## Contact audio stays categorical, because these are different *situations*,
## but the class comes from the resolver rather than from a threshold this file
## invents for itself.
func _clash_cue(event: DuelEvent) -> StringName:
	match StringName(event.text(DuelEventKeys.CONTACT_CLASS)):
		ContactResolver.CLASS_STRONG:
			return PresentationKit.CUE_BLADE_STRONG
		ContactResolver.CLASS_SOLID:
			return PresentationKit.CUE_BLADE_SOLID
		_:
			return PresentationKit.CUE_BLADE_LIGHT


func _contact_world(event: DuelEvent) -> Vector3:
	return ArenaTransform.to_world(event.number(DuelEventKeys.X), event.number(DuelEventKeys.Y), _kits.weapon.blade_height)


func _dispatch(event: DuelEvent) -> void:
	var weapon := _kits.weapon
	var flash := _options.flash_scale()
	match event.type:
		DuelEventTypes.ATTACK_RELEASED:
			_on_release(event, weapon)
		DuelEventTypes.BURST_STARTED:
			_on_burst(event, flash)
		DuelEventTypes.BLADE_CONTACT:
			_on_blade_contact(event, weapon, flash)
		DuelEventTypes.BIND_STARTED:
			_on_bind(event, weapon)
		DuelEventTypes.PARRY:
			_vfx.ring(_contact_world(event), RiposteTheme.SPARK, CombatFeedbackDirector.PARRY_RING_SIZE, flash)
		DuelEventTypes.BODY_HIT:
			_on_body_hit(event, weapon, flash)
		DuelEventTypes.BODY_POKE:
			_on_point_strike(event, weapon, flash, PresentationKit.CUE_BODY_POKE)
		DuelEventTypes.BODY_THRUST:
			_on_point_strike(event, weapon, flash, PresentationKit.CUE_BODY_THRUST)
		DuelEventTypes.CRITICAL_HIT:
			## The sweet layer, over the body hit that is already playing. The
			## hitstop and the impulse were sized by the strike itself; a
			## critical adds recognition, not a second helping of force.
			_audio.play(PresentationKit.CUE_CRITICAL, weapon, _contact_world(event), CombatFeedbackDirector.DEVASTATING_VOLUME_DB)
			_haptics.pulse(Haptics.CRITICAL)
		DuelEventTypes.ROUND_STARTED, DuelEventTypes.ROUND_ENDED:
			_audio.play_flat(PresentationKit.CUE_ROUND, _kits.arena, CombatFeedbackDirector.ROUND_VOLUME_DB)


## Footwork writes on the floor, never in the air. Dust at the feet, kicked
## opposite the heading the simulation froze, keeps a dash visually separate
## from a swing — the two must never share a silhouette (UX §19).
func _on_burst(event: DuelEvent, flash: float) -> void:
	var heading := Vector3(event.number(DuelEventKeys.HEADING_X), 0.0, -event.number(DuelEventKeys.HEADING_Y))
	_vfx.dust(_fighter_world(event.actor), heading, RiposteTheme.WORLD_FLOOR_EDGE, CombatFeedbackDirector.DUST_COUNT, CombatFeedbackDirector.DUST_SPEED, flash)


## The swing whoosh is sized by the swing, not by how long a button was held.
## `swing_potential` is already a bounded reading of the blade's real tip
## speed — which carries the weapon's length and the motor's authority with it
## — so a heavy sword and a fast one do not need separate samples.
func _on_release(event: DuelEvent, weapon: PresentationKit) -> void:
	var potential := _current.fighter(event.actor).swing_potential
	_audio.play(
		PresentationKit.CUE_SWING,
		weapon,
		_fighter_world(event.actor),
		lerpf(CombatFeedbackDirector.SWING_VOLUME_DB_TAP, CombatFeedbackDirector.SWING_VOLUME_DB_FULL, potential),
		lerpf(CombatFeedbackDirector.SWING_PITCH_TAP, CombatFeedbackDirector.SWING_PITCH_FULL, potential)
	)


## Blades sliding past each other, not a generic burst. The larger fan runs
## along the direction the striking point was travelling and the smaller one
## along the normal the blades met on — both carried from the resolver, so the
## sparks cannot disagree with the contact that produced them.
func _on_blade_contact(event: DuelEvent, weapon: PresentationKit, flash: float) -> void:
	var world := _contact_world(event)
	var intensity := event.number(DuelEventKeys.INTENSITY)
	var count := lerpf(float(SPARK_COUNT_MIN), float(SPARK_COUNT_MAX), intensity)
	var speed := lerpf(SPARK_SPEED_MIN, SPARK_SPEED_MAX, intensity)
	var tangent := _direction(event, DuelEventKeys.STRIKE_X, DuelEventKeys.STRIKE_Y)
	var normal := _direction(event, DuelEventKeys.NORMAL_X, DuelEventKeys.NORMAL_Y)
	_vfx.sparks(world, tangent, RiposteTheme.SPARK, roundi(count * (1.0 - CombatFeedbackDirector.SPARK_NORMAL_SHARE)), speed, flash)
	_vfx.sparks(world, normal, RiposteTheme.SPARK, roundi(count * CombatFeedbackDirector.SPARK_NORMAL_SHARE), speed, flash)
	_audio.play(_clash_cue(event), weapon, world)
	hitstop_requested.emit(weapon.hitstop_for_clash(intensity))
	_impulse(CombatFeedbackDirector.IMPULSE_BLADE_MAX * intensity, normal)
	_haptics.pulse(Haptics.BLADE)


## Pinned blades are their own situation and get their own sound. No hitstop:
## a bind is already a hard stop in the simulation, and freezing the frame on
## top of it would read as a hitch rather than as pressure.
func _on_bind(event: DuelEvent, weapon: PresentationKit) -> void:
	_audio.play(PresentationKit.CUE_BIND, weapon, _contact_world(event))
	_haptics.pulse(Haptics.BLADE)


func _on_body_hit(event: DuelEvent, weapon: PresentationKit, flash: float) -> void:
	var damage := event.number(DuelEventKeys.DAMAGE)
	var quality := event.number(DuelEventKeys.QUALITY)
	var devastating := event.text(DuelEventKeys.GRADE) == SwingSemantics.grade_label(SwingSemantics.Grade.DEVASTATING)
	var world := _contact_world(event)
	var normal := _direction(event, DuelEventKeys.NORMAL_X, DuelEventKeys.NORMAL_Y)
	_fighters[event.target].flash_hit(flash)
	## Recoil along the push the simulation applied, at the scale it applied
	## it. Presentation may exaggerate a normalized value, but a displacement
	## is a measured one: this streak must never throw the target further than
	## the impulse actually did.
	var reach := maxf(event.number(DuelEventKeys.PUSH) * CombatFeedbackDirector.RECOIL_SECONDS, CombatFeedbackDirector.RECOIL_MIN_LENGTH)
	_vfx.streak(world, world + normal * reach, RiposteTheme.BODY_IMPACT, flash)
	_vfx.sparks(world, _direction(event, DuelEventKeys.STRIKE_X, DuelEventKeys.STRIKE_Y), RiposteTheme.BODY_IMPACT, SPARK_COUNT_MIN, SPARK_SPEED_MIN, flash)
	var loud := CombatFeedbackDirector.DEVASTATING_VOLUME_DB if devastating else 0.0
	if damage >= CombatFeedbackDirector.DAMAGE_HEAVY:
		_audio.play(PresentationKit.CUE_BODY_HEAVY, weapon, world, loud)
	else:
		_audio.play(PresentationKit.CUE_BODY_LIGHT, weapon, world, loud)
	hitstop_requested.emit(weapon.hitstop_for_strike(quality, devastating))
	var ceiling := CombatFeedbackDirector.IMPULSE_DEVASTATING_MAX if devastating else CombatFeedbackDirector.IMPULSE_BODY_MAX
	_impulse(ceiling * clampf(quality / PresentationKit.QUALITY_FULL, 0.0, 1.0), normal)
	_haptics.pulse(Haptics.BODY)


## Point-first body contact (BODY_POKE / BODY_THRUST). These are companion
## events that arrive alongside the BODY_HIT on the same tick — the hit
## already did VFX, hitstop, and camera; a point strike adds only its own
## audio cue so the player hears a distinct sound for the contact kind.
func _on_point_strike(event: DuelEvent, weapon: PresentationKit, _flash: float, cue: StringName) -> void:
	var world := _contact_world(event)
	_audio.play(cue, weapon, world)
	_haptics.pulse(Haptics.BODY)


## A carried lane-space direction as a world direction. Degenerate contacts
## (a pivot exactly on the contact point) legitimately carry no direction, so
## this stays total and hands back a zero vector rather than a guess.
func _direction(event: DuelEvent, key_x: String, key_y: String) -> Vector3:
	var direction := Vector3(event.number(key_x), 0.0, -event.number(key_y))
	return direction.normalized() if direction.length_squared() > 0.0 else Vector3.ZERO


func _impulse(strength: float, direction: Vector3 = Vector3.ZERO) -> void:
	if _camera != null:
		_camera.impulse(strength, _options, direction)
