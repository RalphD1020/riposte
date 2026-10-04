class_name ResultsScreen
extends ScreenBase

## Match results (UX §25): outcome from the player's side, the score, a few
## physically meaningful stats, then Rematch (primary) or the menu.
##
## See also: /docs/concepts/ux.md

var summary: MatchSummary


func build() -> void:
	var session := app.last_session
	if session == null:
		app.go_to(AppScreen.Id.MAIN_MENU)
		return
	summary = session.summary(session.config.human_slot)
	var title := UiKit.title(lead, HudCopy.outcome_title(session.state.match_winner, session.config.human_slot))
	title.accessibility_live = AccessibilityServer.LIVE_POLITE
	var score := UiKit.heading(lead, AppCopy.SCORE % [summary.score_self, summary.score_opponent])
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.body(body, AppCopy.RESULT_ROUNDS % summary.rounds, true)
	UiKit.body(body, AppCopy.RESULT_BEST % roundi(summary.best_strike), true)
	UiKit.body(body, AppCopy.RESULT_PARRIES % summary.parries, true)
	UiKit.body(body, AppCopy.RESULT_CHARGE % roundi(summary.average_charge * 100.0), true)
	set_primary(UiKit.button(body, AppCopy.REMATCH, app.rematch, &"PrimaryButton"))
	UiKit.button(body, AppCopy.RETURN_TO_MENU, back)
