class_name ProductEvents
extends RefCounted

## Product (UX) event names and their property keys, separate from duel
## events (UX §89, PLAN Phase 19). Product events describe how people use
## the app; duel events describe what happened in a fight. They never mix.
## Properties carry ids and enums only, never personal data.
##
## See also: /docs/concepts/telemetry.md

const GAME_LOADED := &"game_loaded"
const QUICK_PLAY_CLICKED := &"quick_play_clicked"
const DIFFICULTY_CHANGED := &"difficulty_changed"
const TUTORIAL_STARTED := &"tutorial_started"
const TUTORIAL_COMPLETED := &"tutorial_completed"
const SETTINGS_OPENED := &"settings_opened"
const MATCH_STARTED := &"match_started"
const MATCH_FINISHED := &"match_finished"
const MATCH_EXITED := &"match_exited"
const REMATCH_CLICKED := &"rematch_clicked"
const COMMUNITY_CLICKED := &"community_clicked"
const ORIENTATION_PROMPT_SEEN := &"orientation_prompt_seen"
const FULLSCREEN_ENTERED := &"fullscreen_entered"

## Property keys.
const PROP_MODE := "mode"
const PROP_DIFFICULTY := "difficulty"
const PROP_OUTCOME := "outcome"
const PROP_ROUNDS := "rounds"
const PROP_DESTINATION := "destination"
