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
var charge: float = 0.0
## +1 sweeps counter-clockwise (right → left), -1 clockwise (left → right).
var swing_dir: float = 1.0
var windup_base: float = 0.0
var swing_start: float = 0.0
var swing_end: float = 0.0
var swing_charge: float = 0.0
var swing_hit: bool = false
var swing_contact: bool = false
## Commitment K ∈ [0, 1], recomputed every tick (COMBAT §20).
var commitment: float = 0.0
var recovery_ticks: int = 0
var recovery_left: int = 0
var recovery_commitment: float = 0.0
var bind_left: int = 0


func set_phase(next: CombatPhase.Id) -> void:
	if phase != next:
		phase = next
		phase_ticks = 0


func reset(guard_angle: float) -> void:
	phase = CombatPhase.Id.NEUTRAL
	phase_ticks = 0
	angle = guard_angle
	speed = 0.0
	charge = 0.0
	swing_dir = 1.0
	windup_base = guard_angle
	swing_start = guard_angle
	swing_end = guard_angle
	swing_charge = 0.0
	swing_hit = false
	swing_contact = false
	commitment = 0.0
	recovery_ticks = 0
	recovery_left = 0
	recovery_commitment = 0.0
	bind_left = 0
