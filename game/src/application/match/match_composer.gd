class_name MatchComposer
extends RefCounted

## The one place a MatchConfig becomes controllers and a MatchSession.
##
## See also: /docs/concepts/simulation.md


static func compose(config: MatchConfig, human: HumanController, sink: TelemetrySink = null) -> MatchSession:
	var controllers: Array[FighterController] = []
	for slot in 2:
		match config.controllers[slot]:
			MatchConfig.ControllerKind.HUMAN:
				controllers.append(human)
			MatchConfig.ControllerKind.CPU:
				controllers.append(CpuController.create(config.rules, CpuProfile.for_difficulty(config.cpu_difficulty), config.seed_value, slot))
			MatchConfig.ControllerKind.TRAINING_DUMMY:
				controllers.append(TrainingDummyController.create(config.rules))
	return MatchSession.create(config, controllers, sink)
