class_name ContactOutcome
extends RefCounted

## What one solved sword contact did, read from the solve's own result
## (CONTACT-OUTCOME-001): never consumed by the solver, never an input to any
## physics. PARRY and DEFLECTION are classified from it, the BLADE_CONTACT
## event carries it, and tests, telemetry, presentation and probes read the
## same description instead of each rebuilding the contact.
##
## The direction of the outcome is the impulse the blades exchanged — never a
## direction made up from either fighter's facing.
##
## Implements: /spec/invariants.md#contact-outcome-001
## See also: /docs/concepts/combat.md

## Touching points the solve used (1 or 2 per feature pair).
var point_count: int = 0
## Total normal and friction impulse over every row (N·s).
var normal_impulse: float = 0.0
var tangent_impulse: float = 0.0
## The impulse fighter 0's sword received, summed over every row
## (`Jn·n + Jt·t`, N·s); fighter 1's is its negative.
var impulse_x: float = 0.0
var impulse_y: float = 0.0
## The largest share of its friction cone any frictional row used (0 none,
## 1 sliding at the Coulomb limit).
var friction_saturation: float = 0.0
## The fastest closing speed over the rows before the solve, and after it
## (m/s). After the solve a negative value is the rows separating.
var closing_before: float = 0.0
var closing_after: float = 0.0
## Each fighter's root velocity change and weapon-speed change (`Δθ̇`, rad/s)
## from this solve, by slot. The heading is not among them: contact never
## acts on it (CONTACT-HEADING-001).
var delta_vx := PackedFloat64Array([0.0, 0.0])
var delta_vy := PackedFloat64Array([0.0, 0.0])
var delta_weapon_speed := PackedFloat64Array([0.0, 0.0])
## Whether each side's cut was arrested by the one arrest law
## (`ContactResolver.arrests`, RIGID-CONTACT-002).
var arrested: Array[bool] = [false, false]
## The swinging side, or `DuelEvent.NONE` when both or neither swing.
var attacker: int = DuelEvent.NONE
## The attacker's cut speed along its own direction before and after
## (`θ̇·dir`, rad/s): how much of the attack's motion the contact took.
var attack_progress_before: float = 0.0
var attack_progress_after: float = 0.0
## Whether the attacker's cut in flight reached the defender's body with its
## own remaining sweep before the solve — the heading reacquiring as it would,
## no new footwork (THREAT-001, the unopposed estimate): the cut was on the
## line. Read only for the attack's first opponent contact, the one that can
## mark a deflection; false otherwise.
var threatened_before: bool = false


## The rows separate after the solve: the blades are leaving each other, not
## held or pressing.
func separating() -> bool:
	return closing_after < 0.0


## Protective steel took a positive impulse from a cut on the line and did not
## arrest it. Whether that was a deflection is decided by what the attack then
## does: it is one only if the attack ends having struck nothing
## (DEFLECTION-001). `protective` is whether the defender's steel at the
## contact protects (DEFENSE-ROLE-001).
func redirects(protective: bool) -> bool:
	return attacker != DuelEvent.NONE and protective and normal_impulse > 0.0 and not arrested[attacker] and threatened_before


## A protective contact that arrested the cut (PARRY-001).
func parries(protective: bool) -> bool:
	return attacker != DuelEvent.NONE and protective and normal_impulse > 0.0 and arrested[attacker]
