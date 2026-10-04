class_name HudCopy
extends RefCounted

## Every string the duel HUD shows, and the banner each match moment earns.
## Presentation-owned so the HUD never reaches into application copy; menus
## live in AppCopy.
##
## See also: /docs/concepts/ux.md

const PAUSE := "Pause"
const ROUND := "ROUND %d"
const READY := "READY"
const DUEL := "DUEL"
const ROUND_WON := "ROUND WON"
const ROUND_LOST := "ROUND LOST"
const ROUND_DRAWN := "ROUND DRAWN"
const TIME_UP := "TIME"
const VICTORY := "VICTORY"
const DEFEAT := "DEFEAT"
const DRAW := "DRAW"
const HEALTH := "%s health"
const HEALTH_VALUE := "%d of %d"
const ROUNDS_WON := "%s rounds won: %d of %d"


## Round intro thirds: ROUND N → READY → DUEL (UX §24); result and match
## end name the outcome from the human's side. Empty while fighting.
static func banner(snapshot: PresentationSnapshot, human_slot: int) -> String:
	match snapshot.phase:
		MatchPhase.Id.ROUND_INTRO:
			var third := maxi(floori(float(snapshot.intro_ticks) / 3.0), 1)
			if snapshot.phase_ticks < third:
				return ROUND % snapshot.round_number
			return READY if snapshot.phase_ticks < 2 * third else DUEL
		MatchPhase.Id.ROUND_RESULT:
			var outcome := _outcome(snapshot.round_winner, human_slot, ROUND_WON, ROUND_LOST, ROUND_DRAWN)
			return "%s · %s" % [TIME_UP, outcome] if snapshot.end_reason == MatchPhase.REASON_TIMEOUT else outcome
		MatchPhase.Id.MATCH_ENDED:
			return outcome_title(snapshot.match_winner, human_slot)
	return ""


static func outcome_title(winner: int, human_slot: int) -> String:
	return _outcome(winner, human_slot, VICTORY, DEFEAT, DRAW)


static func clock(ticks: int) -> String:
	return SimulationTimebase.format_clock(ticks)


static func _outcome(winner: int, human_slot: int, won: String, lost: String, drawn: String) -> String:
	if winner == human_slot:
		return won
	if winner == 1 - human_slot:
		return lost
	return drawn
