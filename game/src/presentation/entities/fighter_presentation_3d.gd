class_name FighterPresentation3D
extends Node3D

## Passive fighter proxy built from the fighter and weapon kits. MatchPresenter
## poses it every frame; it never reads simulation state and never decides
## anything (PRES-001).
##
## Hierarchy: root (ground pose, combat heading) → VisualRoot (kit transform,
## procedural motion) → body / outline / facing notch or the kit's authored
## scene; WeaponOrigin (the authoritative planar sword: the domain's pommel on
## the blade plane, yaw θ — a reference, never drawn); SwordCarriage (the
## displayed sword: the same carriage `C(θ)` and yaw, lifted by
## `CombatPresentationField`) → blade + guard + grip targets; Shadow and
## ChargeRing stay on the ground outside VisualRoot. The blade ignores depth so
## its position is always readable (UX §18).
##
## Both sword nodes are posed from `WeaponKinematics` at the interpolated
## weapon angle, so every drawn pose lies on the orbit (WEAPON-ORBIT-005).
##
## Implements: /spec/invariants.md#weapon-orbit-005
## See also: /docs/concepts/presentation.md

const SHADOW_HEIGHT := 0.012
const RING_HEIGHT := 0.02
const RING_GAP := 0.14
const RING_WIDTH := 0.06
const RING_SEGMENTS := 32
## Tessellation of the primitive cylinders. Low on purpose: this is a mobile
## budget, and an authored kit scene replaces these meshes entirely.
const RADIAL_SEGMENTS := 24
const OUTLINE_GROW := 0.028
const FLASH_SECONDS := 0.12
## Peak emission of the hit flash (scaled down by Reduced Flash).
const FLASH_ENERGY := 1.6
const DEATH_SECONDS := 0.45
const DEATH_TILT := 1.35
## A cut-down fighter folds or sinks; a run-through one pitches harder. These
## shape the per-style death collapse so a slash and a stab death read apart.
const DEATH_KNEE_SINK := 0.45
const DEATH_STAB_PITCH := 1.2
const DEATH_CRUMPLE_PITCH := 1.1
const DEATH_WRITHE := 0.12
const DEATH_WRITHE_RATE := 8.0
const FALL_SPEED := 8.0
const FALL_TILT := 0.4
const STAGGER_WOBBLE := 0.09
const STAGGER_WOBBLE_RATE := 30.0
const CHARGE_CROUCH := 0.06
## Procedural stand-ins for clips, so a primitive kit still shows every
## semantic: a lean into footwork, a deeper lean into a dash, a carried-past
## twist on overswing, and a recoil on a hurt.
const MOVE_LEAN := 0.08
const DASH_LEAN := 0.2
const OVERSWING_TWIST := 0.18
const HURT_RECOIL := 0.16
const CRITICAL_RECOIL := 0.3
## A flinch outlasts the flash so it reads as a body reaction, not a blink.
const HURT_SECONDS := 0.22
const CRITICAL_SECONDS := 0.4
## A terminal — a death collapse, a ring fall — hands the body to its clip.
## From the terminal's start the sword pose (chest → spine → hips following
## the sword) fades out over this window; the hands stay on the grip only while
## the sword is still held, and leave it over the same window once it is
## released. Chosen deterministically from the terminal's event key.
const TERMINAL_FADE_MIN := 0.10
const TERMINAL_FADE_MAX := 0.22
const TERMINAL_FADE_STEPS := 4
## A lying body (FALLEN-BODY-001) is turned onto its authoritative axis at this
## rate (1/s, exponential) so a push or a spin never snaps it.
const BODY_TURN_RATE := 12.0
## Looseness of a body being moved: a roll about its long axis, at most
## `BODY_LOOSE_ROLL` rad, reached at `BODY_LOOSE_SPEED` m/s of surface motion
## (centre speed plus spin at the body's ends), wobbling at `BODY_LOOSE_RATE`.
const BODY_LOOSE_ROLL := 0.12
const BODY_LOOSE_SPEED := 2.0
const BODY_LOOSE_RATE := 9.0
## Cross-fade between clips. Short on purpose: block joints snap into poses.
const BLEND_SECONDS := 0.06
## Gait playback rate bounds (× authored): a crawl still steps, a sprint never
## blurs the feet.
const GAIT_RATE_MIN := 0.4
const GAIT_RATE_MAX := 1.75
## Decay time of a lift discontinuity at a phase boundary (inertialized).
const CARRY_BLEND_SECONDS := 0.06
## Over an authored blade, the x-ray blade is a ghost: visible through bodies,
## faint over the steel itself.
const BLADE_GHOST_ALPHA := 0.32
## High Contrast Weapons thickens the blade outline (UX §55).
const HIGH_CONTRAST_OUTLINE := Vector3(2.2, 1.6, 1.0)

var slot: int = 0
var side: DuelSide.Id = DuelSide.Id.LIGHT_SOUTH
var _combatant: CombatantPresentationKit
var _fighter_kit: PresentationKit
var _weapon_kit: PresentationKit
var _spec: CombatantPhysicsSpec
var _weapon: WeaponDefinition
var _hilt: float = 0.0
var _tip: float = 0.0
var _visual_root: Node3D
var _body_material: StandardMaterial3D
var _weapon_origin: Node3D
var _carriage_node: Node3D
## The authoritative planar sword at this frame's angle, in the combat frame.
var _planar := BladePose.new()
var _field := CombatPresentationField.new()
var _inflection := CutPresentationCurve.Inflection.new()
## Inertialized lift: where the field's answer jumps (a phase boundary), the
## jump in (height, pitch, roll) is carried as an offset that decays, so the
## drawn sword never pops — and never leaves the orbit horizontally.
var _carriage_phase: CombatPhase.Id = CombatPhase.Id.NEUTRAL
var _carriage_committed: bool = false
var _carry_lift := Vector3.ZERO
var _shown_lift := Vector3.ZERO
## Whether the last frame's sword was anchored at a contact.
var _anchored: bool = false
## Target bearing τ minus combat heading φ this frame (+ to the left).
var _look_offset: float = 0.0
var _blade_core: StandardMaterial3D
var _blade_edge: StandardMaterial3D
var _blade_outline: MeshInstance3D
var _charge_ring: MeshInstance3D
var _charge_mesh: ImmediateMesh
var _animation: AnimationPlayer
var _rig: SwordRig3D
var _pose_debug: ElbowDebugOverlay3D
var _guard := GuardPoseField.new()
var _support := BodySupportPose.new()
var _weapon_model: Node3D
var _flash: float = 0.0
var _flash_scale: float = 1.0
var _hurt: float = 0.0
var _critical: float = 0.0
var _finisher: float = 0.0
var _death: float = 0.0
var _death_hold: float = 0.0
var _death_style: StringName = DeathPresentationProfile.STYLE_DEAD_DROP
var _fall_offset: float = 0.0
var _is_falling: bool = false
var _fall_request: FallPresentationRequest
var _fall_time: float = 0.0
var _weapon_dropped: bool = false
var _grip_release: float = 0.0
## This terminal's fade window and how long it has been presented.
var _terminal_fade: float = TERMINAL_FADE_MAX
var _terminal_time: float = 0.0
var _terminal_key: int = 0
## The facing a lying body is drawn at (NAN until it lies), how loose it reads
## this frame, and how long it has been falling over the edge as a body.
var _body_facing: float = NAN
var _body_loose: float = 0.0
var _corpse_fall_time: float = -1.0
var _time: float = 0.0
var _shown_charge: float = -1.0
var _semantic: StringName = &""
var _playing_clip: StringName = &""


static func create(
	fighter_slot: int,
	fighter_side: DuelSide.Id,
	combatant: CombatantPresentationKit,
	push_radius: float,
	spec: CombatantPhysicsSpec
) -> FighterPresentation3D:
	var proxy := FighterPresentation3D.new()
	proxy.name = "Fighter%d" % fighter_slot
	proxy.slot = fighter_slot
	proxy.side = fighter_side
	proxy._combatant = combatant
	proxy._fighter_kit = combatant.fighter
	proxy._weapon_kit = combatant.weapon
	proxy._spec = spec
	proxy._weapon = spec.weapon
	proxy._hilt = spec.weapon.hilt_radius
	proxy._tip = spec.weapon.tip_radius
	proxy._field.carriage_radius = spec.handling.carriage_radius
	proxy._build(push_radius)
	return proxy


func body_color() -> Color:
	return RiposteTheme.body_for(side)


func outline_color() -> Color:
	return RiposteTheme.outline_for(side)


func blade_color() -> Color:
	return RiposteTheme.blade_for(side)


## Pose for this frame. `world`, `facing`, and `weapon_angle` are the
## interpolated pose; `row` is the latest snapshot's facts for this fighter;
## `delta` is presentation-scaled time and `time_scale` its ratio to real time
## (0 in hitstop), which the clips play at (PRES-TIME-001). `contact_height`
## is the shared rendered height of a sword contact (`ContactPresentation`),
## NAN when the swords are apart. `lift_progress` / `lift_charge` are the lift's
## inputs interpolated between snapshots (`MatchPresenter.lift_inputs`); NAN
## reads the row's own.
func apply_pose(world: Vector3, facing: float, weapon_angle: float, row: PresentationFighter, delta: float, time_scale: float = 1.0, contact_height: float = NAN, lift_progress: float = NAN, lift_charge: float = NAN) -> void:
	_time += delta
	_is_falling = row.is_falling
	if not _is_falling:
		_fall_offset = 0.0
		_fall_time = 0.0
		_fall_request = null
		position = world
	elif _fall_request != null:
		## Authority stopped at the ledge; the fall owns the root from here,
		## carrying the real exit momentum outward under presentation gravity.
		_fall_time += delta
		position = _fall_request.root_at(_fall_time)
		_fall_offset = _fall_request.exit_position.y - position.y
	else:
		_fall_offset += FALL_SPEED * delta
		position = world - Vector3(0.0, _fall_offset, 0.0)
	rotation.y = ArenaTransform.yaw(facing)
	_present_body(row, facing, delta)
	_look_offset = angle_difference(facing, row.target_bearing)
	_pose_planar(weapon_angle)
	_guard.update(weapon_angle)
	var committed := false
	if CombatPresentationField.is_swing(row.phase) or row.phase == CombatPhase.Id.RECOVERY:
		committed = _inflection.update(CutPresentationCurve.cut_angle(weapon_angle, row.cut_dir), row.weapon_speed * signf(row.cut_dir))
	else:
		_inflection.reset()
	var progress := row.swing_progress if is_nan(lift_progress) else lift_progress
	var charge := row.charge if is_nan(lift_charge) else lift_charge
	_field.sample(weapon_angle, _planar.carriage_y, _planar.carriage_x, row.phase, progress, charge, row.swing_charge, _weapon_kit.blade_height, row.cut_dir, committed)
	var anchored := not is_nan(contact_height)
	if anchored:
		## CONTACT-PRESENTATION-001: level at the shared contact height. The
		## carriage and yaw stay the authoritative ones; roll is untouched.
		_field.raise = contact_height - position.y - _visual_root.transform.origin.y - _weapon_kit.blade_height
		_field.pitch = 0.0
	_carry(row.phase, delta, anchored, committed)
	if _rig != null:
		## The elbows inflect on the blade's beat: the cut's own hand-back to
		## the stance (its ends and the committed rise) is theirs too.
		var cut := CutPresentationCurve.cut_angle(weapon_angle, row.cut_dir)
		var settled := maxf(_field.stance_weight, CutPresentationCurve.stance_share(cut, committed))
		_rig.pose_sword(_support.sample(weapon_angle, row.phase, _guard.side(), _field.carriage_point.x, _field.gather, settled, cut))
		## The head faces the combat heading, where the weapon window is, and
		## only glances toward the target bearing: a committed fighter who has
		## not yet turned back onto the opponent reads that way.
		_rig.look_toward(_look_offset)
	if _weapon_dropped:
		if row.is_alive() and not row.is_falling:
			_restore_weapon()
		else:
			_grip_release = maxf(_grip_release - delta, 0.0)
			if _rig != null:
				_rig.set_grip_influence(_grip_release / _terminal_fade)
	_flash = maxf(_flash - delta, 0.0)
	_hurt = maxf(_hurt - delta, 0.0)
	_critical = maxf(_critical - delta, 0.0)
	_finisher = maxf(_finisher - delta, 0.0)
	if not row.is_alive() and _death_hold > 0.0:
		## Run through: the body stays up until the striker's blade is out.
		_death_hold = maxf(_death_hold - delta, 0.0)
	else:
		_death = clampf(_death + (delta / DEATH_SECONDS if not row.is_alive() else -_death), 0.0, 1.0)
	## A run-through's victim is still standing on the blade: the terminal
	## starts when the collapse does.
	var terminal := row.is_falling or (not row.is_alive() and _death_hold <= 0.0)
	_terminal_time = _terminal_time + delta if terminal else 0.0
	if _rig != null:
		_rig.set_pose_influence(terminal_influence())
	_animate(row)
	if _animation != null:
		_animation.speed_scale = maxf(time_scale, 0.0) * gait_rate(row)
	_update_charge_ring(row.charge if row.phase == CombatPhase.Id.CHARGING else 0.0)
	if _body_material != null:
		_body_material.emission_energy_multiplier = (_flash / FLASH_SECONDS) * FLASH_ENERGY * _flash_scale


## A killed body once it lies (FALLEN-BODY-001): drawn along its authoritative
## axis, loose while it is moved, dropping as a body when carried over the
## edge. Its centre of mass is the authoritative position, already placed.
func _present_body(row: PresentationFighter, facing: float, delta: float) -> void:
	if row.is_alive() or not (row.body_lying or row.body_over_edge):
		if not is_nan(_body_facing):
			_visual_root.transform = _fighter_kit.visual_transform
		_body_facing = NAN
		_body_loose = 0.0
		_corpse_fall_time = -1.0
		return
	if is_nan(_body_facing):
		_body_facing = facing
	_body_facing = turn_toward(_body_facing, body_facing(row.body_yaw, _body_facing), BODY_TURN_RATE, delta)
	rotation.y = ArenaTransform.yaw(_body_facing)
	var surface := Vector2(row.vx, row.vy).length() + absf(row.body_spin) * _fighter_kit.body_height * 0.5
	_body_loose = BODY_LOOSE_ROLL * clampf(surface / BODY_LOOSE_SPEED, 0.0, 1.0)
	if row.body_over_edge:
		if _corpse_fall_time < 0.0:
			_corpse_fall_time = 0.0
		_corpse_fall_time += delta
		position.y -= 0.5 * FallPresentationRequest.GRAVITY * _corpse_fall_time * _corpse_fall_time


## The facing a lying body is drawn at: its authoritative axis is symmetric, so
## of `yaw` and `yaw + π` the one nearer to where it already lies (`shown`) —
## the death clip decided which end is the head, and a push never flips it.
static func body_facing(yaw: float, shown: float) -> float:
	var forward := wrapf(yaw, -PI, PI)
	var backward := wrapf(yaw + PI, -PI, PI)
	return forward if absf(angle_difference(shown, forward)) <= absf(angle_difference(shown, backward)) else backward


## `current` eased toward `target` at `rate` (1/s), along the shorter way.
static func turn_toward(current: float, target: float, rate: float, delta: float) -> float:
	return wrapf(current + angle_difference(current, target) * (1.0 - exp(-rate * maxf(delta, 0.0))), -PI, PI)


## How loose the presented body reads this frame (roll amplitude, rad).
func body_looseness() -> float:
	return _body_loose


## The body's roll about its long axis this frame: its looseness, wobbling.
func body_roll() -> float:
	return _body_loose * sin(_time * BODY_LOOSE_RATE)


func is_corpse_falling() -> bool:
	return _corpse_fall_time >= 0.0


## Place the authoritative planar sword at `angle`: the domain's pommel on the
## blade plane, yaw θ, in the combat frame (+X left, +Z forward).
func _pose_planar(angle: float) -> void:
	WeaponKinematics.pose_at(0.0, 0.0, 0.0, angle, _spec, _planar)
	_weapon_origin.position = Vector3(_planar.origin_y, _weapon_kit.blade_height, _planar.origin_x)
	_weapon_origin.rotation.y = angle


## How far the target bearing τ sits off the combat heading φ this frame
## (radians, + to the fighter's left): where the head looks.
func look_offset() -> float:
	return _look_offset


## The authoritative carriage (grip centre) on the blade plane at the last
## posed angle, VisualRoot space.
func authoritative_carriage() -> Vector3:
	return Vector3(_planar.carriage_y, _weapon_kit.blade_height, _planar.carriage_x)


## The elbow guides solved for the last pose (for tests, captures, debug).
func elbow_guides() -> ElbowGuideField:
	return _rig.combat_pose().elbow_guides() if _rig != null and _rig.combat_pose() != null else null


## The elbow / clearance debug draw. One mode with the world vectors (F3).
func pose_debug() -> ElbowDebugOverlay3D:
	return _pose_debug


func set_pose_debug(on: bool) -> void:
	_pose_debug.visible = on
	if on:
		_pose_debug.redraw(self)
	else:
		_pose_debug.clear()


## Show this frame's sword. On a phase change, or when a cut commits into the
## opposite side, the field may answer from a different branch (guard ↔ cut,
## gather ↔ none, the committed rise); the difference in lift from
## what was on screen is kept as an offset and decays over
## `CARRY_BLEND_SECONDS` of presentation time, so continuity never depends on
## the branches agreeing. The carriage and yaw are the authoritative ones
## every frame; only height, pitch and roll are blended.
##
## A sword contact is exact the moment it exists (CONTACT-PRESENTATION-001):
## anchored, nothing is carried — the drawn sword is where the contact says.
## Leaving a contact carries the anchored lift and lets it decay into the
## free one, so the release never pops.
func _carry(phase: CombatPhase.Id, delta: float, anchored: bool = false, committed: bool = false) -> void:
	var target := Vector3(_field.raise, _field.pitch, _field.roll)
	if anchored:
		_carriage_phase = phase
		_carriage_committed = committed
		_carry_lift = Vector3.ZERO
	elif phase != _carriage_phase or committed != _carriage_committed or _anchored:
		_carriage_phase = phase
		_carriage_committed = committed
		_carry_lift = _shown_lift - target
	_anchored = anchored
	_carry_lift *= exp(-maxf(delta, 0.0) / CARRY_BLEND_SECONDS)
	_field.raise += _carry_lift.x
	_field.pitch += _carry_lift.y
	_field.roll += _carry_lift.z
	_field.compose()
	_shown_lift = Vector3(_field.raise, _field.pitch, _field.roll)
	_carriage_node.transform = _field.transform


## World positions of the displayed blade's hilt and tip (for trails and
## effects — what the player sees).
func blade_points() -> PackedVector3Array:
	var origin := _carriage_node.global_transform
	return PackedVector3Array([origin * Vector3(0.0, 0.0, _hilt), origin * Vector3(0.0, 0.0, _tip)])


## Whether the last pose anchored the sword at a contact.
func is_contact_anchored() -> bool:
	return _anchored


## World position of the drawn sword's axis `distance` from its pommel.
func drawn_point(distance: float) -> Vector3:
	return _carriage_node.global_transform * Vector3(0.0, 0.0, distance)


## World positions of the authoritative blade's hilt and tip on the blade plane
## — where collision has them at this frame's angle.
func authoritative_blade_points() -> PackedVector3Array:
	var origin := _weapon_origin.global_transform
	return PackedVector3Array([origin * Vector3(0.0, 0.0, _hilt), origin * Vector3(0.0, 0.0, _tip)])


## The sword trail's sample (TRAIL-PARITY-001): the authoritative blade's
## planar hilt and tip — where collision has them, so the ribbon's ground
## footprint is exactly the dangerous swept space — raised to the drawn
## sword's height, so it still rides the blade the player sees. A pitched or
## lifted drawn sword never shrinks or shifts the footprint.
func trail_points() -> PackedVector3Array:
	var planar := authoritative_blade_points()
	var drawn := blade_points()
	return PackedVector3Array([Vector3(planar[0].x, drawn[0].y, planar[0].z), Vector3(planar[1].x, drawn[1].y, planar[1].z)])


func blade_height() -> float:
	return _weapon_kit.blade_height


## A resolved strike landed on this fighter. `critical` picks the heavier
## flinch; neither moves the body, which stays where the state says.
func flash_hit(flash_scale: float, critical: bool = false) -> void:
	_flash = FLASH_SECONDS
	_flash_scale = flash_scale
	_hurt = HURT_SECONDS
	if critical:
		_critical = CRITICAL_SECONDS


## The killing blow landed: latch the death collapse for this fighter. Called
## once, on the blow that leaves them not alive, so the style is fixed for the
## whole fall. The snapshot's `is_alive` keeps them down; this only chooses how.
func begin_death(family: DeathPresentationProfile.Family, key: int) -> void:
	begin_death_style(_fighter_kit.death_style(family, key), 0.0, key)


## Latch an already-resolved death style (the presenter resolves it once).
## `collapse_delay` holds the body up first — a killing thrust's victim waits
## for the blade to clear (PRES-STAB-001). `key` is the killing blow's event
## key, which picks the terminal fade.
func begin_death_style(style: StringName, collapse_delay: float = 0.0, key: int = 0) -> void:
	_death_style = style
	_death_hold = maxf(collapse_delay, 0.0)
	_terminal_fade = terminal_fade_seconds(key)
	_terminal_key = key


## The terminal fade window for event `key`: a deterministic beat in
## [`TERMINAL_FADE_MIN`, `TERMINAL_FADE_MAX`].
static func terminal_fade_seconds(key: int) -> float:
	var step := absi(key) % TERMINAL_FADE_STEPS
	return lerpf(TERMINAL_FADE_MIN, TERMINAL_FADE_MAX, float(step) / float(TERMINAL_FADE_STEPS - 1))


## How much of the sword pose is left on the body: 1 while no terminal is
## presented, falling to 0 over the terminal's fade window.
func terminal_influence() -> float:
	return 1.0 - clampf(_terminal_time / _terminal_fade, 0.0, 1.0)


## What terminal this body is presenting (`TerminalPresentationKind`).
func terminal_kind(row: PresentationFighter) -> TerminalPresentationKind.Id:
	return TerminalPresentationKind.of(row.is_alive(), row.is_falling or row.body_over_edge, _death_style, _death >= 1.0 and _death_hold <= 0.0)


## Seconds the collapse is still held off (for tests and debug).
func death_hold() -> float:
	return _death_hold


func death_style() -> StringName:
	return _death_style


## This fighter's thrust killed: hold the run-through — drive, impaled hold,
## withdrawal along the thrust — for `seconds` of the shared stab timeline
## (`StabFinisherProfile.striker_recover_end`). Only the death backend calls
## this, and only for a killing thrust.
func begin_finisher(seconds: float = -1.0) -> void:
	_finisher = seconds if seconds > 0.0 else StabFinisherProfile.new().striker_recover_end


func is_finishing() -> bool:
	return _finisher > 0.0


## A new round: drop every terminal latch this body carried — the finisher
## hold, the fall trajectory, the latched death style — and take the sword
## back in hand. The next pose starts from the round's fresh state.
func reset_terminal() -> void:
	_finisher = 0.0
	_fall_request = null
	_fall_time = 0.0
	_fall_offset = 0.0
	_death = 0.0
	_death_hold = 0.0
	_terminal_time = 0.0
	_terminal_fade = TERMINAL_FADE_MAX
	if not is_nan(_body_facing):
		_visual_root.transform = _fighter_kit.visual_transform
	_body_facing = NAN
	_body_loose = 0.0
	_corpse_fall_time = -1.0
	_inflection.reset()
	_death_style = DeathPresentationProfile.STYLE_DEAD_DROP
	if _rig != null:
		_rig.set_pose_influence(1.0)
	if _weapon_dropped:
		_restore_weapon()


## The hands let go: hide the held sword and ease the arms off the grip. The
## prop that falls is built fresh from the kits (`CombatantVisuals`), never
## cloned from this live subtree; the carriage keeps being posed, only its look
## is hidden.
func detach_weapon() -> void:
	_carriage_node.visible = false
	_weapon_dropped = true
	_grip_release = _terminal_fade


## The combatant this proxy draws, so a prop or showcase can be built from the
## same resolved kits.
func combatant_kit() -> CombatantPresentationKit:
	return _combatant


func is_weapon_dropped() -> bool:
	return _weapon_dropped


## How the presented body is moving now (world, m/s): along the fall trajectory
## over the edge, still for a collapse in place. A released sword starts with
## this, so it leaves the hand moving with the body that held it.
func root_velocity() -> Vector3:
	if _is_falling and _fall_request != null:
		return _fall_request.exit_velocity + Vector3(0.0, -FallPresentationRequest.GRAVITY * _fall_time, 0.0)
	return Vector3.ZERO


func _restore_weapon() -> void:
	_weapon_dropped = false
	_grip_release = 0.0
	_carriage_node.visible = true
	if _rig != null:
		_rig.set_grip_influence(1.0)


## This fighter went over the edge: from now until the next round the fall owns
## the root, along the momentum they carried out. The first request wins; a
## fighter falls once.
func begin_fall(request: FallPresentationRequest) -> void:
	if _fall_request == null:
		_fall_request = request
		_fall_time = 0.0
		_terminal_fade = terminal_fade_seconds(request.key)
		_terminal_key = request.key


## The authoritative planar sword (the domain's pommel on the blade plane,
## yaw θ). Never drawn.
func weapon_origin() -> Node3D:
	return _weapon_origin


## The displayed sword's mount: the authoritative carriage and yaw, lifted by
## `CombatPresentationField` every frame. Authored rigs aim their hands at
## grip markers under it (two-hand IK); nothing may write its transform back.
func sword_carriage() -> Node3D:
	return _carriage_node


## Whether the cut in flight has committed to its opposite-side recovery (the
## pitch inflection), for tests, captures, and debug.
func is_cut_committed() -> bool:
	return _inflection.committed


## The lift solved for the last pose (hand position, stance weight, gather).
func carriage() -> CombatPresentationField:
	return _field


func visual_root() -> Node3D:
	return _visual_root


## The authored rig, when the kit scene has one (two-hand IK + chest follow).
func rig() -> SwordRig3D:
	return _rig


func weapon_model() -> Node3D:
	return _weapon_model


func set_charge_indicator(visible_now: bool) -> void:
	_charge_ring.visible = visible_now


func set_high_contrast(enabled: bool) -> void:
	var alpha := _blade_core.albedo_color.a
	_blade_core.albedo_color = Color(RiposteTheme.BLADE_HIGH_CONTRAST_CORE if enabled else blade_color(), 1.0 if enabled else alpha)
	_blade_outline.scale = HIGH_CONTRAST_OUTLINE if enabled else Vector3.ONE


func is_falling() -> bool:
	return _is_falling


## Whether a ring-out trajectory owns the root this round.
func has_fall_request() -> bool:
	return _fall_request != null


## The clip this body last started (empty when procedural), for tests and debug.
func playing_clip() -> StringName:
	return _playing_clip


func fall_offset() -> float:
	return _fall_offset


func current_semantic() -> StringName:
	return _semantic


func _build(push_radius: float) -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	_visual_root.transform = _fighter_kit.visual_transform
	add_child(_visual_root)
	if _combatant.body_scene() != null:
		_build_scene()
	else:
		_build_primitive_body(push_radius)
	_build_sword()
	_build_ground(push_radius)
	_pose_debug = ElbowDebugOverlay3D.create()
	add_child(_pose_debug)
	if _rig != null and _rig.skeleton() != null:
		_rig.skeleton().skeleton_updated.connect(_pose_debug.redraw.bind(self))


func _build_scene() -> void:
	var model := CombatantVisuals.body_model(_combatant, side)
	_visual_root.add_child(model)
	_rig = model as SwordRig3D
	_animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation != null:
		## Clips play on Godot's own process step, ahead of the skeleton's
		## modifiers (chain, IK) as the engine orders them; presentation time
		## reaches them as `speed_scale`, so a death collapses through the
		## lethal slow motion and freezes in hitstop (PRES-TIME-001).
		for semantic in PresentationKit.LOOPING_SEMANTICS:
			var clip := _fighter_kit.clip_for(semantic)
			if clip != &"" and _animation.has_animation(clip):
				_animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


func _build_primitive_body(push_radius: float) -> void:
	var height := _fighter_kit.body_height
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = push_radius
	body_mesh.bottom_radius = push_radius
	body_mesh.height = height
	body_mesh.radial_segments = RADIAL_SEGMENTS
	_body_material = _material(body_color(), false)
	_body_material.emission_enabled = true
	_body_material.emission = RiposteTheme.CRITICAL
	_body_material.emission_energy_multiplier = 0.0
	_add_mesh(_visual_root, "Body", body_mesh, _body_material, Vector3(0.0, height * 0.5, 0.0))
	var outline_mesh := CylinderMesh.new()
	outline_mesh.top_radius = push_radius + OUTLINE_GROW
	outline_mesh.bottom_radius = push_radius + OUTLINE_GROW
	outline_mesh.height = height + OUTLINE_GROW
	outline_mesh.radial_segments = RADIAL_SEGMENTS
	var outline := _material(outline_color(), true)
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	_add_mesh(_visual_root, "Outline", outline_mesh, outline, Vector3(0.0, height * 0.5, 0.0))
	var notch_mesh := BoxMesh.new()
	notch_mesh.size = Vector3(push_radius * 0.6, 0.05, push_radius * 0.55)
	_add_mesh(_visual_root, "FacingNotch", notch_mesh, _material(outline_color(), true), Vector3(0.0, height + 0.01, push_radius * 0.55))


func _build_sword() -> void:
	_weapon_origin = Node3D.new()
	_weapon_origin.name = "WeaponOrigin"
	_visual_root.add_child(_weapon_origin)
	var rest := -PhysicalBaseline.GUARD_ANGLE_RAD
	_pose_planar(rest)
	_field.sample(rest, _planar.carriage_y, _planar.carriage_x, CombatPhase.Id.NEUTRAL, 0.0, 0.0, 0.0, _weapon_kit.blade_height)
	_shown_lift = Vector3(_field.raise, _field.pitch, _field.roll)
	_carriage_node = Node3D.new()
	_carriage_node.name = "SwordCarriage"
	_carriage_node.transform = _field.transform
	_visual_root.add_child(_carriage_node)
	var length := _tip - _hilt
	var center := Vector3(0.0, 0.0, _hilt + length * 0.5)
	_weapon_model = CombatantVisuals.weapon_model(_combatant, side)
	if _weapon_model != null:
		_carriage_node.add_child(_weapon_model)
	var outline_mesh := BoxMesh.new()
	outline_mesh.size = Vector3(_weapon_kit.blade_width + 0.03, 0.03, length + 0.03)
	_blade_edge = _material(RiposteTheme.BLADE_OUTLINE, true)
	_x_ray(_blade_edge, 0)
	_blade_outline = _add_mesh(_carriage_node, "BladeOutline", outline_mesh, _blade_edge, center)
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(_weapon_kit.blade_width, 0.035, length)
	_blade_core = _material(blade_color(), true)
	_x_ray(_blade_core, 1)
	_add_mesh(_carriage_node, "Blade", blade_mesh, _blade_core, center)
	if _weapon_model != null:
		## The authored steel is the look; the x-ray blade stays as a faint
		## ghost so the sword still reads through bodies (combat-critical).
		for ghost: StandardMaterial3D in [_blade_edge, _blade_core]:
			ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost.albedo_color.a = BLADE_GHOST_ALPHA
	else:
		var guard_mesh := BoxMesh.new()
		guard_mesh.size = Vector3(0.2, 0.04, 0.04)
		var guard := _material(RiposteTheme.BLADE_OUTLINE, true)
		_x_ray(guard, 0)
		_add_mesh(_carriage_node, "Guard", guard_mesh, guard, Vector3(0.0, 0.0, _hilt))
	if _rig != null:
		_rig.bind_sword(_carriage_node, _weapon_model)
		_rig.apply_stance(_fighter_kit.stance)


func _build_ground(push_radius: float) -> void:
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = push_radius * 1.2
	shadow_mesh.bottom_radius = push_radius * 1.2
	shadow_mesh.height = 0.002
	shadow_mesh.radial_segments = RADIAL_SEGMENTS
	var shadow := _material(RiposteTheme.SHADOW, true)
	shadow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add_mesh(self, "Shadow", shadow_mesh, shadow, Vector3(0.0, SHADOW_HEIGHT, 0.0))
	_charge_mesh = ImmediateMesh.new()
	_charge_ring = MeshInstance3D.new()
	_charge_ring.name = "ChargeRing"
	_charge_ring.mesh = _charge_mesh
	_charge_ring.material_override = _material(RiposteTheme.CHARGE_RING, true)
	_charge_ring.position = Vector3(0.0, RING_HEIGHT, 0.0)
	_charge_ring.visible = false
	_charge_ring.set_meta("inner", push_radius + RING_GAP)
	add_child(_charge_ring)


## Authored scenes play the mapped clip; a semantic with no clip, and every
## primitive kit, gets the procedural stand-in so nothing freezes.
## The procedural collapse for a death style, as (pitch, roll, sink) over the
## 0→1 death ramp. Pure, so a slash death (backward drop) and a stab death
## (pitched forward, run through) are provably distinct silhouettes. Positive
## pitch falls backward, negative folds forward; sink lowers the body. An
## authored DEATH clip, when a kit maps one, overrides all of this upstream.
static func death_pose(style: StringName, progress: float, time: float) -> Vector3:
	var d := clampf(progress, 0.0, 1.0)
	match style:
		DeathPresentationProfile.STYLE_KNEES_FLOP:
			return Vector3(-DEATH_TILT * d, 0.0, DEATH_KNEE_SINK * d)
		DeathPresentationProfile.STYLE_GROUND_WRITHE:
			return Vector3(-DEATH_TILT * d, sin(time * DEATH_WRITHE_RATE) * DEATH_WRITHE * d, DEATH_KNEE_SINK * 0.5 * d)
		DeathPresentationProfile.STYLE_STAB_CRUMPLE:
			return Vector3(-DEATH_TILT * DEATH_CRUMPLE_PITCH * d, 0.0, DEATH_KNEE_SINK * d)
		DeathPresentationProfile.STYLE_STAB_PITCH:
			return Vector3(-DEATH_TILT * DEATH_STAB_PITCH * d, 0.0, 0.0)
		_:
			return Vector3(DEATH_TILT * d, 0.0, 0.0)


## The clip this body plays for `semantic`. A death plays the clip authored for
## its latched style when this scene has it (a run-through and a cut-down fall
## differently), else the generic DEATH clip; the striker of a killing thrust
## holds the authored run-through rather than the dash lunge, which returns to
## guard on its own. Every other semantic maps directly.
func animation_clip(semantic: StringName) -> StringName:
	if _animation != null:
		var special := &""
		if semantic == PresentationKit.ANIM_DEATH and _corpse_fall_time >= 0.0:
			special = _fighter_kit.ring_fall_clip(_terminal_key)
		elif semantic == PresentationKit.ANIM_DEATH:
			special = _fighter_kit.death_clip(_death_style)
		elif semantic == PresentationKit.ANIM_RING_FALL and _fall_request != null:
			special = _fighter_kit.ring_fall_clip(_fall_request.key)
		elif semantic == PresentationKit.ANIM_DASH_FORWARD and _finisher > 0.0:
			special = _fighter_kit.finisher_clip()
		if special != &"" and _animation.has_animation(special):
			return special
	return _fighter_kit.clip_for(semantic)


func animation_player() -> AnimationPlayer:
	return _animation


## The clip rate for this frame's semantic: a gait plays at actual ground
## speed over the kit's reference (PRES-LOCO-001); every other clip at 1.
func gait_rate(row: PresentationFighter) -> float:
	if not FighterAnimationSelector.is_locomotion(_semantic):
		return 1.0
	var reference := maxf(_fighter_kit.gait_reference_speed, 0.01)
	return clampf(Vector2(row.vx, row.vy).length() / reference, GAIT_RATE_MIN, GAIT_RATE_MAX)


func _animate(row: PresentationFighter) -> void:
	var semantic := FighterAnimationSelector.select(row, _hurt > 0.0, _critical > 0.0, _finisher > 0.0)
	_semantic = semantic
	if _animation != null:
		var clip := animation_clip(semantic)
		if clip != &"" and _animation.has_animation(clip):
			## Start a clip when it changes, never because the last one ended:
			## a finished one-shot clears `current_animation`, and replaying it
			## then would stand a dead body back up to fall again.
			if _playing_clip != clip:
				_animation.play(clip, BLEND_SECONDS)
				_playing_clip = clip
			if not is_nan(_body_facing):
				_visual_root.transform = _fighter_kit.visual_transform * Transform3D(Basis(Vector3.FORWARD, body_roll()), Vector3.ZERO)
			return
		_playing_clip = &""
	var pitch := 0.0
	var roll := body_roll() if not is_nan(_body_facing) else 0.0
	var twist := 0.0
	var sink := 0.0
	if not row.is_alive():
		var collapse := death_pose(_death_style, _death, _time)
		pitch = collapse.x
		roll += collapse.y
		sink = collapse.z
	if _is_falling:
		pitch += FALL_TILT * clampf(_fall_offset, 0.0, 1.0)
	match semantic:
		PresentationKit.ANIM_STAGGER:
			roll = sin(_time * STAGGER_WOBBLE_RATE) * STAGGER_WOBBLE
		PresentationKit.ANIM_MOVE_FORWARD:
			pitch -= MOVE_LEAN
		PresentationKit.ANIM_MOVE_BACKWARD:
			pitch += MOVE_LEAN
		PresentationKit.ANIM_ORBIT_LEFT:
			roll -= MOVE_LEAN
		PresentationKit.ANIM_ORBIT_RIGHT:
			roll += MOVE_LEAN
		PresentationKit.ANIM_DASH_FORWARD:
			pitch -= DASH_LEAN
		PresentationKit.ANIM_DASH_BACK:
			pitch += DASH_LEAN
		PresentationKit.ANIM_DASH_LEFT:
			roll -= DASH_LEAN
		PresentationKit.ANIM_DASH_RIGHT:
			roll += DASH_LEAN
		PresentationKit.ANIM_OVERSWING:
			twist = OVERSWING_TWIST * -row.swing_dir
		PresentationKit.ANIM_HURT:
			pitch += HURT_RECOIL * (_hurt / HURT_SECONDS)
		PresentationKit.ANIM_CRITICAL:
			pitch += CRITICAL_RECOIL * (_critical / CRITICAL_SECONDS)
	var scale_y := clampf(1.0 - CHARGE_CROUCH * row.charge - sink, 0.1, 1.0)
	var pose := Basis.from_euler(Vector3(pitch, twist, roll)).scaled(Vector3(1.0, scale_y, 1.0))
	_visual_root.transform = _fighter_kit.visual_transform * Transform3D(pose, Vector3.ZERO)


func _update_charge_ring(charge: float) -> void:
	if not _charge_ring.visible or is_equal_approx(charge, _shown_charge):
		return
	_shown_charge = charge
	_charge_mesh.clear_surfaces()
	if charge <= 0.0:
		return
	var inner := float(_charge_ring.get_meta("inner"))
	var outer := inner + RING_WIDTH
	var segments := maxi(2, ceili(RING_SEGMENTS * charge))
	_charge_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in segments + 1:
		var angle := TAU * charge * float(i) / float(segments)
		var direction := Vector3(sin(angle), 0.0, cos(angle))
		_charge_mesh.surface_add_vertex(direction * inner)
		_charge_mesh.surface_add_vertex(direction * outer)
	_charge_mesh.surface_end()


static func _material(color: Color, unshaded: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## Always drawn on top so the blade reads through bodies.
static func _x_ray(material: StandardMaterial3D, priority: int) -> void:
	material.no_depth_test = true
	material.render_priority = priority


static func _add_mesh(parent: Node3D, mesh_name: String, mesh: Mesh, material: Material, offset: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
