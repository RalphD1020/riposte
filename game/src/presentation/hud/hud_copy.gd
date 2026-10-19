class_name HudCopy
extends RefCounted

## Every string the duel HUD shows, and the banner each match moment earns.
## Presentation-owned so the HUD never reaches into application copy; menus
## live in AppCopy.
##
## See also: /docs/concepts/ux.md

const PAUSE := "Pause"
const ROUND := "ROUND %d"
## The round-start card (PRES-ROUND-START-001): presentation says "Match N"
## for the domain's round N; the domain keeps its own word.
const MATCH := "MATCH %d"
const FIGHT := "FIGHT!"
const ROUND_WON := "ROUND WON"
const ROUND_LOST := "ROUND LOST"
const ROUND_DRAWN := "ROUND DRAWN"
const MATCH_WON := "MATCH WON"
const MATCH_LOST := "MATCH LOST"
const MATCH_DRAWN := "MATCH DRAWN"
const TIME_UP := "TIME"
const TRADE := "TRADE"
const VICTORY := "VICTORY"
const DEFEAT := "DEFEAT"
const DRAW := "DRAW"
## Side belongs on the plate, not only in the arena's colours (SIDE-001):
## colour alone is not a label, and a player who cannot distinguish the two
## palettes still needs to know which end is theirs.
const SIDED := "%s · %s"
const HEALTH := "%s health"
const HEALTH_VALUE := "%d of %d"
const STAMINA := "%s stamina"
const STAMINA_VALUE := "%d of 100"
const STAMINA_DASH := "%s, dash ready"
const STAMINA_SPENT := "%s, too spent to dash"
const ROUNDS_WON := "%s rounds won: %d of %d"
## Sound captions (`SoundCaptions`): what was heard, in brackets, the way
## captions mark non-speech sound.
const SOUND_CAPTIONS := {
	PresentationKit.CUE_CRITICAL: "[Critical hit]",
	PresentationKit.CUE_BODY_HEAVY: "[Heavy hit]",
	PresentationKit.CUE_BODY_LIGHT: "[Light hit]",
	PresentationKit.CUE_BODY_THRUST: "[Thrust lands]",
	PresentationKit.CUE_BODY_POKE: "[Point touches]",
	PresentationKit.CUE_BLADE_STRONG: "[Heavy clash]",
	PresentationKit.CUE_BLADE_SOLID: "[Blades clash]",
	PresentationKit.CUE_BLADE_LIGHT: "[Blades tap]",
	PresentationKit.CUE_FALL: "[Body falls]",
	PresentationKit.CUE_WHIFF: "[Swing misses]",
}
const SOUND_SCRAPE := "[Blades scrape]"


static func sound_caption(cue: StringName) -> String:
	return SOUND_CAPTIONS.get(cue, "")


## Name a fighter by who they are *and* which end they hold.
static func sided(label: String, side: DuelSide.Id) -> String:
	return SIDED % [label, DuelSide.label(side)]


## Result and match end name the outcome from the human's side. Empty while
## fighting, and through the round intro, which belongs to the round-start
## card rather than the gameplay HUD.
static func banner(snapshot: PresentationSnapshot, human_slot: int) -> String:
	match snapshot.phase:
		MatchPhase.Id.ROUND_RESULT:
			var match_end := snapshot.set_winner != MatchPhase.NO_WINNER
			var won := MATCH_WON if match_end else ROUND_WON
			var lost := MATCH_LOST if match_end else ROUND_LOST
			var drawn := MATCH_DRAWN if match_end else ROUND_DRAWN
			var outcome := _outcome(snapshot.round_winner, human_slot, won, lost, drawn)
			var cause := _cause(snapshot.end_reason)
			return outcome if cause.is_empty() else "%s · %s" % [cause, outcome]
		MatchPhase.Id.MATCH_ENDED:
			return outcome_title(snapshot.match_winner, human_slot)
	return ""


static func outcome_title(winner: int, human_slot: int) -> String:
	return _outcome(winner, human_slot, VICTORY, DEFEAT, DRAW)


static func clock(ticks: int) -> String:
	return SimulationTimebase.format_clock(ticks)


## Two endings would otherwise look arbitrary: the clock running out, and a
## round won while dying because the opponent's blade arrived later.
static func _cause(reason: StringName) -> String:
	match reason:
		MatchPhase.REASON_TIMEOUT:
			return TIME_UP
		MatchPhase.REASON_TRADE_FIRST_CONTACT:
			return TRADE
	return ""


static func _outcome(winner: int, human_slot: int, won: String, lost: String, drawn: String) -> String:
	if winner == human_slot:
		return won
	if winner == 1 - human_slot:
		return lost
	return drawn
