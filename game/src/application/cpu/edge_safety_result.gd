class_name EdgeSafetyResult
extends RefCounted

## Outcome of a predictive trajectory evaluation against the platform edge.
## Pure value type returned by EdgeSafetyEvaluator. Knows nothing about CPU
## difficulty — the safety layer is the same for all profiles.
##
## See also: /docs/concepts/cpu.md

## Whether the predicted trajectory crosses the platform edge at any tick.
var crosses_platform: bool = false
## Minimum clearance (platform_radius - max |P(t)|) over the prediction
## horizon. Negative when the trajectory leaves the platform.
var min_clearance: float = 0.0
## Stopping margin at the point of minimum clearance:
## v_r² / (2 × a_inward), where v_r is outward radial velocity.
## Measures how much distance the fighter needs to arrest outward motion.
var stopping_margin: float = 0.0
## Whether the fighter can brake to a stop before leaving the platform,
## considering current velocity and available inward acceleration.
var recoverable: bool = true
