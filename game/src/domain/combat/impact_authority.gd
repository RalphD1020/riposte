class_name ImpactAuthority
extends RefCounted

## One fighter's remaining authority to return the blade after a steel impact
## (IMPACT-AUTHORITY-001, rules 57). A new blade episode dips it from that
## sword's own contact-caused change in angular velocity:
## `share = |Δθ̇| / (|Δθ̇| + ω_full)`, `authority' = max(floor, authority · (1 − share))`.
## The ratio is `|J_θ| / (|J_θ| + I·ω_full)` with `J_θ = I·Δθ̇`: the inertia
## cancels, and a shared normal magnitude is not an input. A zero angular
## change leaves the value alone. Between dips the deficit fades at the guard
## return's natural frequency, `da/dt = ωn·(1 − a)`. A torso entry is not a dip.
## Stamina is not an input.
##
## Implements: /spec/invariants.md#impact-authority-001


## `authority` after one new steel episode whose contact changed this sword's
## angular velocity by `delta_omega` (rad/s, signed). `full_swing` is that
## sword's full-charge swing speed. A zero change, or a sword with no swing
## speed, leaves the value alone. The result is `authority · (1 − share)`,
## and it does not fall below `floor_value`.
static func after_episode(authority: float, delta_omega: float, full_swing: float, floor_value: float) -> float:
	var change := absf(delta_omega)
	if change <= 0.0 or full_swing <= 0.0:
		return authority
	var share := change / (change + full_swing)
	return maxf(floor_value, authority * (1.0 - share))


## One tick of recovery toward 1. `natural_frequency` is the guard return's
## ωn (rad/s). The step is the exact integral of `da/dt = ωn·(1 − a)` over
## `dt` seconds, through `SimMath.exp_minus`. At 1 it stays 1. It never runs
## on a tick that dipped.
static func recover(authority: float, natural_frequency: float, dt: float) -> float:
	if authority >= 1.0:
		return 1.0
	var step := 1.0 - SimMath.exp_minus(maxf(natural_frequency, 0.0) * dt)
	return minf(1.0, authority + (1.0 - authority) * step)
