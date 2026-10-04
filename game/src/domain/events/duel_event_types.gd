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
const CRITICAL_HIT := &"critical_hit"
const STAGGERED := &"staggered"
const FIGHTER_KILLED := &"fighter_killed"
