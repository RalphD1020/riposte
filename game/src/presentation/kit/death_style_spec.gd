class_name DeathStyleSpec
extends RefCounted

## One killing blow's death, resolved once from the kit: the style, its
## authored clip (empty → generic DEATH clip → procedural collapse), and its
## timings. The backend plays it and the presenter times the sword release from
## it, so the collapse and the release can never drift onto different styles.
##
## See also: /docs/concepts/presentation.md

var style: StringName = DeathPresentationProfile.STYLE_DEAD_DROP
var clip: StringName = &""
var weapon_release_time: float = DeathPresentationProfile.DEFAULT_WEAPON_RELEASE
var ragdoll_handoff_time: float = -1.0
## Seconds the victim holds before the collapse may begin (a killing thrust:
## until the striker's blade is clear). Zero for a cut.
var collapse_delay: float = 0.0
## The killing thrust's shared timeline, which also times the striker; null
## for a cut.
var finisher: StabFinisherProfile
