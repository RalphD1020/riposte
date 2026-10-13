class_name TerminalPresentationKind
extends RefCounted

## What terminal a body is presenting, as one reading: how a fighter left the
## round and where their body is now. Pure, from facts authority already
## settled (alive, falling) and the death style presentation latched from the
## killing blow (PRES-TERMINAL-001); it chooses how to look, never what
## happened.
##
## ```text
## NONE            alive and on the platform
## SLASH_DEATH     cut down, collapsing
## STAB_DEATH      run through, collapsing (after the striker's withdrawal)
## RING_FALL       alive and over the edge
## FALLEN_BODY     dead and down — the collapse has finished
## FALLING_CORPSE  dead and over the edge
## ```
##
## See also: /docs/concepts/presentation.md

enum Id {
	NONE,
	SLASH_DEATH,
	STAB_DEATH,
	RING_FALL,
	FALLEN_BODY,
	FALLING_CORPSE,
}


## `collapsed`: the death ramp has reached the ground.
static func of(alive: bool, falling: bool, death_style: StringName, collapsed: bool) -> Id:
	if alive:
		return Id.RING_FALL if falling else Id.NONE
	if falling:
		return Id.FALLING_CORPSE
	if collapsed:
		return Id.FALLEN_BODY
	if DeathPresentationProfile.family_of_style(death_style) == DeathPresentationProfile.Family.STAB:
		return Id.STAB_DEATH
	return Id.SLASH_DEATH
