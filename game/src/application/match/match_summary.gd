class_name MatchSummary
extends RefCounted

## Post-match facts for one fighter (UX §25): outcome, score, and a few
## physically meaningful stats drawn from the event log.
##
## See also: /docs/concepts/ux.md

const VICTORY := &"victory"
const DEFEAT := &"defeat"
const DRAW := &"draw"

var slot: int = 0
var outcome: StringName = DRAW
var score_self: int = 0
var score_opponent: int = 0
var rounds: int = 0
var hits_landed: int = 0
var best_strike: float = 0.0
var parries: int = 0
var criticals: int = 0
var attacks: int = 0
var average_charge: float = 0.0


static func from_session(session: MatchSession, fighter_slot: int) -> MatchSummary:
	var summary := MatchSummary.new()
	var state := session.state
	summary.slot = fighter_slot
	summary.score_self = state.scores[fighter_slot]
	summary.score_opponent = state.scores[1 - fighter_slot]
	summary.rounds = state.round_number
	if state.match_winner == fighter_slot:
		summary.outcome = VICTORY
	elif state.match_winner == 1 - fighter_slot:
		summary.outcome = DEFEAT
	var charge_total := 0.0
	for event in session.events:
		if event.actor != fighter_slot:
			continue
		match event.type:
			DuelEventTypes.BODY_HIT:
				summary.hits_landed += 1
				summary.best_strike = maxf(summary.best_strike, event.number(DuelEventKeys.DAMAGE))
			DuelEventTypes.PARRY:
				summary.parries += 1
			DuelEventTypes.CRITICAL_HIT:
				summary.criticals += 1
			DuelEventTypes.ATTACK_RELEASED:
				summary.attacks += 1
				charge_total += event.number(DuelEventKeys.CHARGE)
	if summary.attacks > 0:
		summary.average_charge = charge_total / float(summary.attacks)
	return summary
