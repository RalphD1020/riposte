class_name MatchConfig
extends RefCounted

## Everything needed to compose one match (PLAN Phase 13.3). Modes are
## configuration, never separate simulations: Quick Play and Training run the
## same DuelSimulation with different controllers and rules content.
##
## See also: /docs/concepts/simulation.md

## Future: SHARED_LINK, MATCHMAKING, PRIVATE_MATCH, RANKED.
enum Mode { QUICK_PLAY_CPU, TRAINING }
enum Difficulty { EASY, MEDIUM, HARD }
enum ControllerKind { HUMAN, CPU, TRAINING_DUMMY }

const SEED_LIMIT := 0x7fffffff

var mode: Mode = Mode.QUICK_PLAY_CPU
var rules: DuelRules
var seed_value: int = 0
var human_slot: int = 0
var controllers: Array[ControllerKind] = [ControllerKind.HUMAN, ControllerKind.CPU]
var cpu_difficulty: Difficulty = Difficulty.MEDIUM


static func quick_play(difficulty: Difficulty, match_seed: int) -> MatchConfig:
	var config := MatchConfig.new()
	config.mode = Mode.QUICK_PLAY_CPU
	config.rules = StandardDuelRules.create()
	config.seed_value = match_seed & SEED_LIMIT
	config.cpu_difficulty = difficulty
	return config


static func training(match_seed: int) -> MatchConfig:
	var config := MatchConfig.new()
	config.mode = Mode.TRAINING
	config.rules = StandardDuelRules.training()
	config.seed_value = match_seed & SEED_LIMIT
	config.controllers = [ControllerKind.HUMAN, ControllerKind.TRAINING_DUMMY]
	return config


## Rematch: same configuration, fresh seed, fresh rules instance.
func rematch(match_seed: int) -> MatchConfig:
	if mode == Mode.TRAINING:
		return training(match_seed)
	return quick_play(cpu_difficulty, match_seed)


static func difficulty_label(difficulty: Difficulty) -> String:
	match difficulty:
		Difficulty.EASY:
			return "Easy"
		Difficulty.HARD:
			return "Hard"
	return "Medium"
