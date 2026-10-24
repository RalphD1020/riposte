class_name ContentIds
extends RefCounted

## Canonical content identities. Gameplay definitions and presentation kits
## bind to these ids; generic runtime code never names them.
##
## See also: /docs/concepts/presentation.md

const RULES_STANDARD_DUEL := &"rules.standard_duel"
const RULES_TRAINING := &"rules.training"
const FIGHTER_DUELIST := &"fighter.duelist"
const WEAPON_BASTARD_SWORD := &"weapon.bastard_sword"
## The duelist's two-handed carriage of the bastard sword (LOADOUT-001).
const HANDLING_DUELIST_BASTARD_SWORD := &"handling.duelist.bastard_sword"
const ARENA_STANDARD := &"arena.standard"
## The open deck. Presentation only: it does not enter the rules hash.
const ARENA_END := &"arena.end"
## The version-58 open disc on the Arena kit. A fixture stage: never listed.
const STAGE_OPEN_DISC := &"stage.open_disc"
