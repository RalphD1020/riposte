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
## Presentation only. -1 keeps the mirror colorway rule. 0 is Main, 1 is Alternate.
var palette_slot: PackedInt32Array = PackedInt32Array([-1, -1])
## The stage this match was started on. A rematch rebuilds from it, so its
## identity, rules, kit, crowd, and basin come back together. Training has none.
var stage: StageDefinition
var stage_id: StringName:
	get:
		return stage.stage_id if stage != null else &""
## Presentation. A crowd stage can omit the ambient bed.
var crowd_bed: bool:
	get:
		return stage == null or stage.has_crowd_bed
## Presentation. NONE keeps a ring-out on the ballistic fall. WATER holds the body at basin_height.
var basin: StageDefinition.Basin:
	get:
		return stage.basin if stage != null else StageDefinition.Basin.NONE
var basin_height: float:
	get:
		return stage.basin_height if stage != null else 0.0


## The version-58 open disc on the Arena kit, mirror colorways.
static func quick_play(difficulty: Difficulty, match_seed: int) -> MatchConfig:
	var config := MatchConfig.new()
	config.mode = Mode.QUICK_PLAY_CPU
	config.stage = StageCatalog.open_disc()
	config.rules = config.stage.rules()
	config.seed_value = match_seed & SEED_LIMIT
	config.cpu_difficulty = difficulty
	return config


## The product pit. Same controllers as quick play, closed edge, Main versus Alternate.
static func arena(difficulty: Difficulty, match_seed: int) -> MatchConfig:
	return for_stage(StageCatalog.arena(), difficulty, match_seed)


## Rules, crowd, and basin come from the stage. An unknown stage does not start.
static func for_stage(chosen: StageDefinition, difficulty: Difficulty, match_seed: int) -> MatchConfig:
	var config := quick_play(difficulty, match_seed)
	if chosen == null or chosen.problem() != "":
		config.rules = null
		return config
	config.stage = chosen
	config.rules = chosen.rules()
	config.palette_slot = PackedInt32Array([0, 1])
	return config


static func training(match_seed: int) -> MatchConfig:
	var config := MatchConfig.new()
	config.mode = Mode.TRAINING
	config.rules = StandardDuelRules.training()
	config.seed_value = match_seed & SEED_LIMIT
	config.controllers = [ControllerKind.HUMAN, ControllerKind.TRAINING_DUMMY]
	return config


## Rematch: same stage, same palettes, fresh seed, fresh rules instance. The
## stage decides the rules; the live rules are never read back.
func rematch(match_seed: int) -> MatchConfig:
	if mode == Mode.TRAINING:
		return training(match_seed)
	var next := for_stage(stage, cpu_difficulty, match_seed)
	next.palette_slot = palette_slot.duplicate()
	return next


static func difficulty_label(difficulty: Difficulty) -> String:
	match difficulty:
		Difficulty.EASY:
			return "Easy"
		Difficulty.HARD:
			return "Hard"
	return "Medium"
