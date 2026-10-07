class_name DuelEventTypes
extends RefCounted

## Canonical duel event names (PLAN Phase 11 schema). The simulation emits
## these as returned values; presentation, analytics, CPU, and tutorials
## consume them downstream. Never a Godot signal inside the simulation.
##
## See also: /docs/concepts/simulation.md

const ROUND_STARTED := &"round_started"
const ROUND_ENDED := &"round_ended"
const MATCH_ENDED := &"match_ended"
const ATTACK_STARTED := &"attack_started"
const CHARGE_STARTED := &"charge_started"
const ATTACK_RELEASED := &"attack_released"
const ATTACK_CANCELED := &"attack_canceled"
const ATTACK_WHIFFED := &"attack_whiffed"
const BLADE_CONTACT := &"blade_collision"
const PARRY := &"parry"
const BIND_STARTED := &"bind_started"
const BIND_ENDED := &"bind_ended"
const BODY_HIT := &"body_hit"
const BODY_POKE := &"body_poke"
const BODY_THRUST := &"body_thrust"
const CRITICAL_HIT := &"critical_hit"
const STAGGERED := &"staggered"
const FIGHTER_KILLED := &"fighter_killed"
## A double tap in one duel direction earned a burst of footwork.
const BURST_STARTED := &"burst_started"
## Two fighter bodies collided. Not a blade hit — a shoulder check or an
## accidental bump. Resolved with inverse-mass impulse (PHYS-005).
const BODY_PUSH := &"body_push"
## The chronological contact loop hit its bound. A diagnostic, not a hit: the
## pair is held in contact rather than allowed to tunnel.
const CONTACT_SATURATED := &"contact_saturated"
## Authoritative state violated an invariant; the match is a no-contest.
const SIMULATION_FAULT := &"simulation_fault"
## A fighter's center crossed the arena edge.
const RING_OUT := &"ring_out"
## Winner followed over the edge during POST_ROUND_FREE (presentation only).
const POST_ROUND_FALL := &"post_round_fall"
