class_name ThreatEstimate
extends RefCounted

## What the bounded threat predictor knows, and no more (THREAT-001). Inside
## its horizon it has a real predicted time; past it, it has no time to give —
## only how much was still left when it stopped looking. Readings that need a
## time clamp at the horizon; a consumer ranking two out-of-horizon options
## orders them by what is left, never by an invented number of seconds.
##
## See also: /docs/concepts/combat.md

## The predicted blade reached the target's torso inside the horizon.
var within_horizon: bool = false
## Seconds to that first overlap; the horizon itself when there was none,
## and `InitiativeModel.UNREACHABLE` for a fighter who cannot strike at all.
var hit_time: float = 0.0
## Surface gap (m) between the predicted blade and the target's torso at the
## end of the horizon: the geometric progress still left. 0 within it.
var residual_gap: float = 0.0
## Seconds of readiness (recovery floor, brake to control, stagger) still
## owed past the horizon. 0 within it.
var readiness_remaining: float = 0.0
## What the predicted blade meets first (`NONE`, `BODY`, `HAND`, or — only
## when the prediction also swept the target's sword — `STEEL`).
var first_contact: int = NONE
## Seconds to that steel contact when `first_contact` is `STEEL`.
var steel_time: float = 0.0

## The prediction began with the blades already in contact (a bind). That
## contact is the starting state, not an obstruction: `first_contact` then
## names the first *new* contact — steel met again after the blades parted,
## or the body or a hand reached.
var starts_bound: bool = false

const NONE := 0
const BODY := 1
const HAND := 2
const STEEL := 3
