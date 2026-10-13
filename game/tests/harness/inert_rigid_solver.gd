class_name InertRigidSolver
extends RigidContactSolver

## Test-only: a persistent-contact solver that does nothing. Swapped into a
## duel, it shows what the persistent constraint changed — anything that
## differs between this run and the real one is the constraint's doing, and
## anything that must not differ (a clean first impact) can be compared bit for
## bit.
##
## See also: /docs/reference/testing.md


func solve_velocity(_state: MatchState, _rules: DuelRules, _warm: bool = false) -> float:
	weapon_delta[0] = 0.0
	weapon_delta[1] = 0.0
	return 0.0


func project(_state: MatchState, _rules: DuelRules) -> void:
	pass
