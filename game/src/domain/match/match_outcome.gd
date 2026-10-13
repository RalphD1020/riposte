class_name MatchOutcome
extends RefCounted

## Whether a set (one match) is decided once a round's score is in, and by
## whom: the single home of that rule. The simulation ends the match with it
## after the result beat; presentation reads the same answer through the
## snapshot the moment the deciding round ends, so the winner's showcase can
## begin without guessing — and without a second copy of the rule.
##
## Pure: scores, the round number, and the rules in; a slot out.
##
## See also: /docs/concepts/simulation.md


## The set's winner (0, 1, or `MatchPhase.DRAW`) once the scores so far decide
## it, else `MatchPhase.NO_WINNER` while another round is due.
static func set_winner(scores: PackedInt32Array, round_number: int, rules: DuelRules) -> int:
	if scores[0] >= rules.rounds_to_win or scores[1] >= rules.rounds_to_win:
		return 0 if scores[0] > scores[1] else 1
	if round_number >= rules.max_rounds:
		if scores[0] == scores[1]:
			return MatchPhase.DRAW
		return 0 if scores[0] > scores[1] else 1
	return MatchPhase.NO_WINNER


## Why a decided set ended: a fighter reached `rounds_to_win`, or the round
## limit ran out.
static func reason(scores: PackedInt32Array, rules: DuelRules) -> StringName:
	if scores[0] >= rules.rounds_to_win or scores[1] >= rules.rounds_to_win:
		return MatchPhase.REASON_SCORE
	return MatchPhase.REASON_ROUND_LIMIT
