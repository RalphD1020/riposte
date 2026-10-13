class_name StabFinisherProfile
extends Resource

## One timeline for a killing thrust, shared by the striker, the victim, and
## the victim's sword (PRES-STAB-001): IMPALE → HOLD → WITHDRAW → BLADE CLEAR →
## VICTIM COLLAPSE → WEAPON RELEASE. Seconds of presentation-scaled time from
## the killing contact (PRES-TIME-001), so the whole sequence slows and
## freezes with the lethal slow motion and hitstop. The authored clips
## (`run_through`, `death_stab`) are keyed to these same beats; PRES-RIG
## proves they agree.
##
## The kill is already authoritative; nothing here delays or recomputes it.
##
## See also: /docs/concepts/presentation.md

## The victim's impact reaction has settled into the impaled hold.
@export var impale_end: float = 0.08
## The striker holds the blade in until here, then draws it back along the
## thrust axis.
@export var withdraw_start: float = 0.38
## The blade is visibly out of the body.
@export var withdraw_clear: float = 0.58
## Only now may the victim's knees go — never while the blade is in them.
@export var victim_collapse_start: float = 0.62
## The victim's own sword leaves the slack hands as the collapse takes them.
@export var victim_weapon_release: float = 0.72
## The striker is back in guard and the finisher hold ends.
@export var striker_recover_end: float = 0.8
## The victim is down; the round may move on.
@export var end: float = 1.05


## True when the beats are in causal order: the victim cannot fall while
## impaled, and cannot drop the sword before falling.
func is_causal() -> bool:
	return (
		impale_end <= withdraw_start
		and withdraw_start < withdraw_clear
		and victim_collapse_start >= withdraw_clear
		and victim_weapon_release >= victim_collapse_start
		and striker_recover_end >= withdraw_clear
		and end >= victim_collapse_start
	)
