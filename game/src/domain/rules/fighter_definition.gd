class_name FighterDefinition
extends RefCounted

## Immutable fighter body and footwork semantics. Every value is authored in
## content (StandardDuelRules); defaults here are neutral. Units: meters,
## seconds, radians. Treat instances as frozen after creation.
##
## See also: /docs/concepts/combat.md
## Source: game/content/rules/standard_duel_rules.gd

var id: StringName = &""
## Physical build, in SI units relative to the PhysicalBaseline duelist.
## Height is the honest scale of the body; `body_radius` is the gameplay
## footprint, and presentation derives body size from both.
##
## Size and mass are **independent** authored facts (PHYS-005). A taller
## fighter is not automatically heavier, and `mass` is never a function of
## `height` at runtime — a lean duelist and a heavy one of the same height are
## both legitimate, and the physics is what makes them play differently.
var height: float = 0.0
var body_radius: float = 0.0
## Distance from the swing pivot to the guard, where this fighter's hands
## hold any weapon. Authored gameplay reach, never measured from a model:
## `WeaponDefinition.hilt_radius` is this, and `tip_radius` adds the blade.
var grip_radius: float = 0.0
var max_health: float = 0.0
## Mass resists *everything*: acceleration, displacement under impulse,
## turning. It is never a damage multiplier — a heavy fighter does not hit
## harder with the same sword at the same speed, they are merely harder to
## move and slower to get going.
var mass: float = 0.0
## Mass-distribution factor for `moment_of_inertia()`. A solid cylinder about
## its own axis is 0.5; a body with mass held closer in authors less.
var body_inertia_coefficient: float = 0.0

## Stamina pool at full health. The current ceiling is derived from health by
## `StaminaModel.max_for_health()` — never stored in FighterState — so injury
## is the cause and reduced stamina ceiling is the consequence.
var base_stamina: float = 100.0

## Strength, authored as **forces and torques** — never as accelerations
## (PHYS-005). Mass and strength are separate facts, and the fighter's
## acceleration is their quotient: `a = F / m`. Authoring acceleration
## directly would let a fighter be heavy without paying for it.
var locomotion_force: float = 0.0
var braking_force: float = 0.0
var burst_force: float = 0.0
## How hard this fighter drives *any* weapon, as a multiple of the baseline
## duelist's arm (COMBAT §27). This is how the same sword behaves differently
## in different hands. It scales the wielder's effort; it never alters the
## weapon's own mass or inertia, which are properties of the object.
var weapon_torque_scale: float = 0.0

## Footwork. Desired velocity = input × max_speed × direction multiplier.
var max_speed: float = 0.0
var speed_forward: float = 0.0
var speed_lateral: float = 0.0
var speed_backward: float = 0.0

## Facing. Rotation is never snapped (COMBAT §9) and never clamped down
## instantly: the body turns under bounded torque, so `α = τ / I_body`.
var turn_speed_max: float = 0.0
var turn_torque: float = 0.0
var track_gain: float = 0.0

## Commitment penalties (COMBAT §20, §62): authority = 1 - penalty × K.
## Commitment spends the ability to *change* motion, never motion itself
## (PHYS-003), so these scale acceleration and torque — not velocity.
var accel_commit_penalty: float = 0.0
var tracking_commit_penalty: float = 0.0
var overswing_tracking_penalty: float = 0.0
var min_move_authority: float = 0.0
var min_tracking: float = 0.0

## Counter-rotation (COMBAT §26): tracking × (1 - k × K × O), O from orbit rate.
var counter_rotation_penalty: float = 0.0
var counter_rotation_reference_rate: float = 0.0

## Stability B (COMBAT §36), smoothed toward a target each tick.
var stability_floor: float = 0.0
var stability_rate: float = 0.0
var stability_accel_weight: float = 0.0
var stability_turn_weight: float = 0.0

## Stagger: translation and tracking multipliers while staggered.
var stagger_translation: float = 0.0
var stagger_tracking: float = 0.0

## Burst footwork (COMBAT §25.2). A double tap in one duel direction buys a
## short, hard, bounded push. Spam control is physical — the intent has to
## return to neutral before a new gesture is even recognized, and a burst
## cannot be reversed while it runs — so there is no stamina bar and no
## cooldown.
##
## Hysteresis band for reading a cardinal sector out of the intent: a clear
## deflection enters one, a near-centred stick leaves it. Without the gap an
## intent hovering on a boundary would chatter and invent gestures.
var burst_enter_deflection: float = 0.0
var burst_neutral_deflection: float = 0.0
## What counts as the intent actually coming to **rest** between two taps, as
## opposed to merely passing through the neutral band between two headings.
## A released key or a lifted thumb lands here; a continuous steer does not.
var burst_rest_deflection: float = 0.0
## A deflection held longer than this is a walk, not a tap.
var tap_window_ticks: int = 0
## How long the second tap has to arrive. Small on purpose: a long window
## fires a dash after the player has mentally moved on.
var double_tap_window_ticks: int = 0
var burst_ticks: int = 0
## Peak speed, bounded. Dashes along the line between the fighters are
## stronger than a lateral slide-step, because the whole body drives them.
var burst_speed_axial: float = 0.0
var burst_speed_lateral: float = 0.0
## Recovery window after a forward dash ends (hit or miss). Authority
## recovers progressively over this window. Authored tuning, not physics
## truth; requires manual playtest (MOVE-002).
var dash_recovery_ticks: int = 0


func is_valid() -> bool:
	return (
		height > 0.0
		and body_radius > 0.0
		and body_radius < height
		and grip_radius > 0.0
		and max_health > 0.0
		and mass > 0.0
		and body_inertia_coefficient > 0.0
		and base_stamina > 0.0
		and max_speed > 0.0
		and locomotion_force > 0.0
		and braking_force > locomotion_force
		and burst_force > braking_force
		and weapon_torque_scale > 0.0
		and turn_speed_max > 0.0
		and turn_torque > 0.0
		and track_gain > 0.0
		and min_move_authority > 0.0
		and min_move_authority <= 1.0
		and burst_enter_deflection > burst_neutral_deflection
		and burst_neutral_deflection > burst_rest_deflection
		and burst_rest_deflection > 0.0
		and burst_enter_deflection <= 1.0
		and tap_window_ticks > 0
		and double_tap_window_ticks > tap_window_ticks
		and burst_ticks > 0
		and burst_speed_axial > max_speed
		and burst_speed_lateral > 0.0
		and burst_speed_lateral < burst_speed_axial
		and dash_recovery_ticks > 0
	)


## Peak speed this burst is allowed to reach.
func burst_speed(kind: MovementGestureState.BurstKind) -> float:
	return burst_speed_axial if MovementGestureState.is_axial(kind) else burst_speed_lateral


## Linear acceleration available to drive footwork, `a = F / m`. Derived, not
## authored: this is the single place a fighter's mass pays for itself in
## movement, so a heavier build is slower to start and slower to stop without
## anyone writing a speed penalty.
func move_accel() -> float:
	return locomotion_force / mass


func brake_accel() -> float:
	return braking_force / mass


func burst_accel() -> float:
	return burst_force / mass


## Precompute hook for immutable definitions. Currently a no-op: the public
## API always computes fresh because test-time mutation must remain correct.
## Catalogs call this after construction so the callsite exists when a future
## hot-loop inline path needs it.
func precompute() -> void:
	pass


## Moment of inertia of the body about its own vertical axis. The fighter is
## a cylinder in the simulation, so this is `coefficient × mass × radius²`.
##
## Turning is torque against this, which is why a body already rotating into
## its swing must arrest that rotation before it can reverse.
func moment_of_inertia() -> float:
	return body_inertia_coefficient * mass * body_radius * body_radius


## Angular acceleration available to turn the body, `α = τ / I_body`.
func turn_accel() -> float:
	return turn_torque / moment_of_inertia()


## Normalized diagnostics against the baseline duelist (COMBAT §33). These
## exist so a designer can see at a glance that a fighter is "1.1× tall and
## 1.3× heavy"; nothing in the simulation may read them, because every effect
## of scale is already carried by the absolute values above. Reading a ratio
## *and* the quantity it came from would count scale twice.
func height_ratio() -> float:
	return height / PhysicalBaseline.FIGHTER_HEIGHT_M


func mass_ratio() -> float:
	return mass / PhysicalBaseline.FIGHTER_MASS_KG


func radius_ratio() -> float:
	return body_radius / PhysicalBaseline.FIGHTER_RADIUS_M
