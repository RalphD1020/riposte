class_name StateFork
extends RefCounted

## A probe's what-if: a fresh runner whose authoritative state is a deep copy
## of another's at this tick, so the copy can be driven with other commands
## while the original carries on. Every script variable is copied, nested
## state and arrays of state included, so a field added to the state later is
## forked too. Events and the replay record are not state and start empty.
##
## `is_faithful` re-simulates the original from its replay record and drives
## that and a fork side by side, comparing hashes, then checks the original
## was not touched: a probe that forks a corpus checks it before trusting it.
## (A scene built by writing state directly has no record to re-simulate.)
##
## Tools only; never a gate.


static func of(runner: SimRunner) -> SimRunner:
	var fork := SimRunner.create(runner.rules, runner.state.seed_value)
	copy(runner.state, fork.state)
	return fork


## How soon `slot` could physically punish from this state, the opponent
## standing idle: the fastest of four forks — a tap re-pressed every tick
## while advancing straight (`c`) or angling forward to either side (`l`, `r`;
## the step that takes a blade out of a bind), and a forward burst onto the
## point with no attack (`p`). `[ticks, region, verb]` for the first body hit
## `slot` lands within `window` ticks — region `t` torso or `h` hand — or
## `[-1, "", ""]`. Real physics: the opponent's sword is in the way if it is.
static func punish(runner: SimRunner, slot: int, window: int) -> Array:
	var best: Array = [-1, "", ""]
	for verb: String in ["c", "l", "r", "p"]:
		var landed := _punish_with(of(runner), slot, window, verb)
		if int(landed[0]) > 0 and (int(best[0]) < 0 or int(landed[0]) < int(best[0])):
			best = [landed[0], landed[1], verb]
	return best


static func _punish_with(runner: SimRunner, slot: int, window: int, verb: String) -> Array:
	var across := -0.7 if verb == "l" else (0.7 if verb == "r" else 0.0)
	var ahead := 0.7 if across != 0.0 else 1.0
	for t in range(1, window + 1):
		var tick := runner.state.tick
		var move := PlayerCommand.create(tick, 0.0, 1.0, false, false, false, true) if verb == "p" else PlayerCommand.create(tick, across, ahead, true, true)
		var seen := runner.events.size()
		if slot == 0:
			runner.push(move, PlayerCommand.idle(tick))
		else:
			runner.push(PlayerCommand.idle(tick), move)
		for e in range(seen, runner.events.size()):
			var event: DuelEvent = runner.events[e]
			if event.type == DuelEventTypes.BODY_HIT and event.actor == slot:
				return [t, "h" if event.text(DuelEventKeys.REGION) == DuelEventKeys.REGION_GRIP else "t"]
		if runner.state.phase != MatchPhase.Id.ROUND_ACTIVE:
			break
	return [-1, ""]


## Every script variable of `from` into `to`.
static func copy(from: Object, to: Object) -> void:
	for property: Dictionary in from.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var key := StringName(property["name"])
		to.set(key, _copied(from.get(key), to.get(key)))


## Never hands back `value` itself: a fork that shared one object with its
## original would drive the original too.
static func _copied(value: Variant, into: Variant) -> Variant:
	if value is Object:
		if value == null:
			return null
		var target: Object = into if into is Object and into != null and into != value else (value as Object).get_script().new()
		copy(value, target)
		return target
	if value is Array:
		var source: Array = value
		var target: Array = into if into is Array else []
		if target.size() != source.size():
			target = target.duplicate()
			target.resize(source.size())
		for i in source.size():
			target[i] = _copied(source[i], target[i])
		return target
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
		return value.duplicate()
	return value


## Whether `runner`'s state is exactly what its own commands produce — after
## a corpus has been forked, proof that no fork reached back into it.
static func is_untouched(runner: SimRunner) -> bool:
	var truth := SimRunner.create(runner.rules, runner.record.seed_value)
	for i in runner.record.tick_count():
		truth.push(runner.record.command_at(0, i), runner.record.command_at(1, i))
	return StateHasher.hash_state(truth.state) == StateHasher.hash_state(runner.state)


## Whether a fork of `runner` evolves exactly as the original re-simulated
## from its commands, over `ticks` ticks of both fighters attacking — the copy
## carried everything the next tick reads — and leaves the original untouched.
static func is_faithful(runner: SimRunner, ticks: int) -> bool:
	var before := StateHasher.hash_state(runner.state)
	var truth := SimRunner.create(runner.rules, runner.record.seed_value)
	for i in runner.record.tick_count():
		truth.push(runner.record.command_at(0, i), runner.record.command_at(1, i))
	var fork := of(runner)
	if StateHasher.hash_state(truth.state) != StateHasher.hash_state(fork.state):
		return false
	for _i in ticks:
		var swing := PlayerCommand.create(fork.state.tick, 0.0, 1.0, true, true)
		truth.push(swing, swing)
		fork.push(swing, swing)
		if StateHasher.hash_state(truth.state) != StateHasher.hash_state(fork.state):
			return false
	return StateHasher.hash_state(runner.state) == before
