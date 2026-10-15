class_name WeaponState
extends RefCounted

## Authoritative weapon state (COMBAT §6). Angles are relative to facing;
## positive is counter-clockwise (the fighter's left). The sword never resets
## to an idle pose: `angle` is wherever physics last left it (COMBAT §12).
##
## See also: /docs/concepts/combat.md

var phase: CombatPhase.Id = CombatPhase.Id.NEUTRAL
var phase_ticks: int = 0
var angle: float = 0.0
var speed: float = 0.0
## Charge C ∈ [0, 1] while charging; the launched swing keeps `swing_charge`.
## Charge is never a timer: it is `earned_windback` expressed as a fraction.
var charge: float = 0.0
## Where the blade was when the current hold began. Winding back only earns
## charge beyond this (or beyond the canonical guard, whichever is further),
## so neither restoring an under-prepared blade nor inheriting a collision's
## displacement is worth anything.
var hold_start_angle: float = 0.0
## Outward travel this hold has actually bought, in radians. Monotonic within
## a hold — letting the blade drift back does not refund it — and reset the
## moment the hold ends.
var earned_windback: float = 0.0
## Which side of the facing the blade is committed to: +1 the fighter's left,
## -1 their right. Updated only once the blade is clear of the centre
## deadzone, so a blade hovering near 0° cannot chatter between sides and
## flip the next swing's direction tick to tick.
var stable_side: float = -1.0
## +1 sweeps counter-clockwise (right → left), -1 clockwise (left → right).
var swing_dir: float = 1.0
## Motor authority this swing was launched with, from the release angle
## (`WeaponDefinition.preparation`). Captured once and never recomputed in
## flight: an under-prepared cut must not gain power by crossing centre.
var launch_preparation: float = 0.0
var swing_start: float = 0.0
var swing_end: float = 0.0
## The charge this swing was launched with. Like `launch_preparation`, read once
## at release and never recomputed in flight.
var swing_charge: float = 0.0
## Whether the current attack has met the opponent with a solved, positive
## impulse — a body hit, a blade clash, a grip wound, or a held contact
## pressing on them (WHIFF-001). Reset at release. It exists
## only so `ATTACK_WHIFFED` is emitted exactly once, and only for a miss;
## nothing in the simulation's physics reads it.
var attack_contacted: bool = false
## Whether the current swing has already wounded the opponent's grip region
## (GRIP-NONBLOCKING-001): one GRIP damage episode per swing, however many
## times or on however many of its parts the blade meets it. Reset at release.
var grip_struck: bool = false
## Whether the current attack's first opponent contact was protective steel
## that took a positive impulse without arresting the cut while the cut was on
## the line (DEFLECTION-001); cleared by any body or hand strike. It exists
## only so `DEFLECTION` is emitted once, when the attack ends having struck
## nothing; nothing in the simulation's physics or the CPU reads it.
var deflection_pending: bool = false
## Commitment K ∈ [0, 1], recomputed every tick (COMBAT §20).
var commitment: float = 0.0
## The torque (N·m, + toward +θ) the weapon motor actually applied last tick:
## its effort, read back from what it did to θ̇ through the coordinate's one
## inertia. Directional commitment reads it as drive still being committed
## (DIRECTIONAL-COMMIT-001); nothing drives the motor from it.
var motor_torque: float = 0.0
var recovery_ticks: int = 0
var recovery_left: int = 0
var recovery_commitment: float = 0.0


func set_phase(next: CombatPhase.Id) -> void:
	if phase != next:
		phase = next
		phase_ticks = 0


## `resting_angle` is the signed canonical guard this fighter starts from.
func reset(resting_angle: float) -> void:
	phase = CombatPhase.Id.NEUTRAL
	phase_ticks = 0
	angle = resting_angle
	speed = 0.0
	charge = 0.0
	hold_start_angle = resting_angle
	earned_windback = 0.0
	stable_side = 1.0 if resting_angle > 0.0 else -1.0
	swing_dir = -stable_side
	launch_preparation = 0.0
	swing_start = resting_angle
	swing_end = resting_angle
	swing_charge = 0.0
	attack_contacted = false
	grip_struck = false
	deflection_pending = false
	commitment = 0.0
	motor_torque = 0.0
	recovery_ticks = 0
	recovery_left = 0
	recovery_commitment = 0.0
