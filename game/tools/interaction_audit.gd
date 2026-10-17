extends SceneTree

## The interaction audit (review 15): evidence for the line game and the
## threat predictor, from real physics. Read-only; never a gate.
##
## Run: godot --headless --path game --script res://tools/interaction_audit.gd
##      [-- line | agreement | capitalize]   one section (default: all three)
##
## - **line** — the line-change matrix (ATTACK-SIDE-001, LINE-CHANGE-001):
##   inside strike reach, a planted tap from rest at a defender who walks
##   behind the blade (origin side), into it (end side) or stands, over
##   distance × timing. Per cell: what the tap met (body / grip / steel /
##   none), and who lands the first body hit afterwards when the defender walks
##   straight in pressing whenever its sword is free and the attacker is then a
##   Hard CPU. `LINE_RESULT {json}`.
## - **agreement** — `THREAT-AGREEMENT-AUDIT`: at states sampled from
##   Hard–Medium duels, the steel-aware route prediction of the direct line
##   (`InitiativeModel.estimate`, ROUTE, the true current bodies) against a
##   fork of the same state rolled on with the same continuation (the fighter
##   walks the line pressing its tap as soon as it can; the opponent gives no
##   input, so its sword follows the law of its phase). A confusion matrix of
##   BODY / GRIP / STEEL / NONE, split by whether the blades started bound.
##   `AGREEMENT_RESULT {json}`.
## - **capitalize** — CPU-008 conversion: Hard–Medium duels, each seed in both
##   slot orders; capitalize starts, and how many are followed by the
##   capitalizer's body hit within `CONVERT_TICKS`. `CAPITALIZE_RESULT {json}`.
##
## See also: /docs/reference/testing.md, /docs/concepts/cpu.md

const DISTANCES: Array[float] = [1.35, 1.5, 1.65, 1.8]
## Ticks before the press the defender starts its walk (early → late).
const LEADS: Array[int] = [-6, -4, -2]
const WALK_TICKS := 6
const LINE_TICKS := 240
const AUDIT_SEEDS: Array[int] = [201, 202, 203, 204, 205, 206]
const SAMPLE_EVERY := 30
const ROLLOUT_TICKS := 30
const CONVERT_TICKS := 30

var _rules: DuelRules


func _initialize() -> void:
	_rules = StandardDuelRules.create()
	var args := OS.get_cmdline_user_args()
	var only := args[0] if args.size() > 0 else ""
	if only == "" or only == "line":
		_line()
	if only == "" or only == "agreement":
		_agreement()
	if only == "" or only == "capitalize":
		_capitalize()
	quit()


# ── line ──────────────────────────────────────────────────────────────────────


func _line() -> void:
	var cells := {}
	for d0 in DISTANCES:
		for lead in LEADS:
			for side: String in ["origin", "none", "end"]:
				var run := _line_run(d0, lead, side)
				var key := "%s" % side
				var cell: Dictionary = cells.get(key, {"runs": 0, "body": 0, "grip": 0, "steel": 0, "none": 0, "defender_first": 0, "attacker_first": 0})
				cell["runs"] += 1
				cell[run[0]] += 1
				if run[1] != "":
					cell[run[1] + "_first"] += 1
				cells[key] = cell
		print("  · line d0 %.2f" % d0)
	print("LINE_RESULT " + JSON.stringify(cells))


## One planted tap at `d0`; the defender walks toward `side` from `lead` ticks
## before the press for WALK_TICKS, then walks in pressing whenever free.
## [what the tap met, who landed the first body hit after it].
func _line_run(d0: float, lead: int, side: String) -> Array:
	var runner := SimRunner.create(_rules, 5)
	runner.skip_intro()
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, d0, 0.0, PI)
	var cpu := CpuController.create(_rules, CpuProfile.hard(), 5, 0)
	var press := runner.state.tick + 8
	var start := press + lead
	var dir := Vector2.ZERO
	var met := ""
	var first := ""
	var tap_over := false
	for _t in LINE_TICKS:
		var state := runner.state
		if state.phase != MatchPhase.Id.ROUND_ACTIVE:
			break
		var tick := state.tick
		var ca := cpu.command_for(state, 0) if tap_over else PlayerCommand.create(tick, 0.0, 0.0, tick == press, tick == press)
		if tick == start and side != "none":
			dir = CutGeometry.origin_side(a) if side == "origin" else CutGeometry.end_side(a)
		var cb := PlayerCommand.idle(tick)
		if tick >= start and tick < start + WALK_TICKS and side != "none":
			var step := CutGeometry.step_intent(b, a, dir)
			cb = PlayerCommand.create(tick, step.x, step.y)
		elif tick >= start + WALK_TICKS and met != "":
			var inward := CutGeometry.step_intent(b, a, Vector2(a.x - b.x, a.y - b.y).normalized())
			var free := b.weapon.phase == CombatPhase.Id.NEUTRAL
			cb = PlayerCommand.create(tick, inward.x, inward.y, free, free)
		var seen := runner.events.size()
		runner.push(ca, cb)
		for i in range(seen, runner.events.size()):
			var event: DuelEvent = runner.events[i]
			if met == "":
				if event.type == DuelEventTypes.BODY_HIT and event.actor == 0:
					met = "body"
					## The tap itself landed first.
					first = "attacker"
				elif event.type == DuelEventTypes.BLADE_CONTACT:
					met = "steel"
				elif event.type == DuelEventTypes.ATTACK_WHIFFED and event.actor == 0:
					met = "none"
			elif event.type == DuelEventTypes.BODY_HIT and first == "":
				first = "defender" if event.actor == 1 else "attacker"
		if not tap_over and tick > press and a.weapon.phase != CombatPhase.Id.LAUNCH and not CombatPhase.is_swinging(a.weapon.phase):
			tap_over = true
		if first != "":
			break
	return [met if met != "" else "none", first]


# ── agreement ─────────────────────────────────────────────────────────────────


func _agreement() -> void:
	var matrix := {}
	var sensitivity := {}
	var samples := 0
	for seed_value in AUDIT_SEEDS:
		var duel := CpuLadder.session(MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.MEDIUM, seed_value)
		while not duel.is_finished() and duel.state.tick < CpuLadder.MAX_TICKS:
			duel.step()
			if duel.state.phase != MatchPhase.Id.ROUND_ACTIVE or duel.state.tick % SAMPLE_EVERY != 0:
				continue
			for slot in 2:
				var me := duel.state.fighter(slot)
				var them := duel.state.opponent_of(slot)
				if not WeaponSystem.can_start_attack(me, _rules.spec_of(me).weapon):
					continue
				var line := Vector2(them.x - me.x, them.y - me.y).normalized()
				var predicted := InitiativeModel.estimate(me, _rules.spec_of(me), them, _rules.spec_of(them), _rules.combat, ThreatEstimate.new(), ThreatContinuation.route(line.x, line.y))
				var actual := _rolled(duel, slot, line, true)
				var key := "%s %s->%s" % ["bound" if predicted.starts_bound else "free", _name(predicted.first_contact), actual.split(" ")[0]]
				matrix[key] = int(matrix.get(key, 0)) + 1
				## Continuation sensitivity, never predictor error: the same
				## prediction against an opponent that stops giving input.
				var idle := _rolled(duel, slot, line, false)
				var idle_key := "sensitivity %s %s->%s" % ["bound" if predicted.starts_bound else "free", _name(predicted.first_contact), idle.split(" ")[0]]
				sensitivity[idle_key] = int(sensitivity.get(idle_key, 0)) + 1
				## The dangerous disagreement, by mechanism: the opponent's phase
				## and the features that actually met.
				var flesh := predicted.first_contact == ThreatEstimate.BODY
				if flesh and not predicted.starts_bound and actual.begins_with("STEEL"):
					var why := "false_clear opp=%s predicted=%s %s seed=%d tick=%d slot=%d" % [CombatPhase.label(them.weapon.phase), _name(predicted.first_contact), actual.substr(6), seed_value, duel.state.tick, slot]
					matrix[why] = int(matrix.get(why, 0)) + 1
				samples += 1
		print("  · agreement seed %d (%d samples)" % [seed_value, samples])
	print("AGREEMENT_RESULT " + JSON.stringify({"samples": samples, "matrix": matrix}))
	print("CONTINUATION_SENSITIVITY " + JSON.stringify(sensitivity))


## Fork the duel's state; `slot` walks `line` and presses its tap whenever it
## can. With `matched` the opponent continues as the predictor assumes — it
## keeps its current velocity (its stick held along that velocity, at its
## share of top speed), its heading and sword following their own laws; without
## it the opponent gives no input and brakes (continuation sensitivity). What
## `slot`'s strike meets first, or DIVERGED when the matched opponent's held
## stick started a burst (it stopped continuing at its velocity).
func _rolled(duel: MatchSession, slot: int, line: Vector2, matched: bool) -> String:
	var fork := SimRunner.create(duel.config.rules, duel.state.seed_value)
	StateFork.copy(duel.state, fork.state)
	var launched := false
	var start := fork.state.opponent_of(slot)
	var drift := Vector2(start.vx, start.vy)
	var drift_share := clampf(drift.length() / maxf(fork.rules.spec_of(start).fighter.max_speed, SimMath.EPSILON), 0.0, 1.0)
	## What the strike did, which is what the prediction answers: flesh struck
	## (even after grazing steel that did not stop it), steel only, or nothing.
	var touched_steel := ""
	for _t in ROLLOUT_TICKS:
		var tick := fork.state.tick
		var me := fork.state.fighter(slot)
		var them := fork.state.opponent_of(slot)
		var step := CutGeometry.step_intent(me, them, line)
		var press := not launched and WeaponSystem.can_start_attack(me, fork.rules.spec_of(me).weapon)
		var mine := PlayerCommand.create(tick, step.x, step.y, press, press)
		var theirs := PlayerCommand.idle(tick)
		if matched and drift_share > 0.0:
			var keep := CutGeometry.step_intent(them, me, drift.normalized()) * drift_share
			theirs = PlayerCommand.create(tick, keep.x, keep.y)
		var seen := fork.events.size()
		if slot == 0:
			fork.push(mine, theirs)
		else:
			fork.push(theirs, mine)
		launched = launched or CombatPhase.is_swinging(me.weapon.phase) or me.weapon.phase == CombatPhase.Id.LAUNCH
		for i in range(seen, fork.events.size()):
			var event: DuelEvent = fork.events[i]
			## The held stick read as a gesture: the opponent no longer
			## continues at its velocity, so this roll answers a different
			## question than the prediction asked. Its own bucket, never an error.
			if matched and event.type == DuelEventTypes.BURST_STARTED and event.actor != slot:
				return "DIVERGED"
			if event.type == DuelEventTypes.BLADE_CONTACT and launched and touched_steel == "":
				touched_steel = "STEEL at=%d" % (tick - duel.state.tick)
			if event.type == DuelEventTypes.BODY_HIT and event.actor == slot:
				return "BODY"
		## Steel that stopped the strike: it is over, and no flesh was struck.
		if touched_steel != "" and launched and not CombatPhase.is_swinging(me.weapon.phase) and me.weapon.phase != CombatPhase.Id.LAUNCH:
			return touched_steel
		if fork.state.phase != MatchPhase.Id.ROUND_ACTIVE:
			break
	return touched_steel if touched_steel != "" else "NONE"


static func _name(contact: int) -> String:
	if contact == ThreatEstimate.BODY:
		return "BODY"
	if contact == ThreatEstimate.STEEL:
		return "STEEL"
	return "NONE"


# ── capitalize ────────────────────────────────────────────────────────────────


func _capitalize() -> void:
	var starts := 0
	var converted := 0
	var duels := 0
	for seed_value in AUDIT_SEEDS:
		for order: int in 2:
			var first := MatchConfig.Difficulty.HARD if order == 0 else MatchConfig.Difficulty.MEDIUM
			var second := MatchConfig.Difficulty.MEDIUM if order == 0 else MatchConfig.Difficulty.HARD
			var duel := CpuLadder.session(first, second, seed_value)
			var was := [false, false]
			var pending := [-1, -1]
			while not duel.is_finished() and duel.state.tick < CpuLadder.MAX_TICKS:
				var events := duel.step()
				for slot in 2:
					var cpu := duel.controllers[slot] as CpuController
					if cpu._capitalizing and not was[slot]:
						starts += 1
						pending[slot] = duel.state.tick
					was[slot] = cpu._capitalizing
				for event in events:
					if event.type == DuelEventTypes.BODY_HIT and pending[event.actor] >= 0 and event.tick - pending[event.actor] <= CONVERT_TICKS:
						converted += 1
						pending[event.actor] = -1
			duels += 1
		print("  · capitalize seed %d" % seed_value)
	print("CAPITALIZE_RESULT " + JSON.stringify({"duels": duels, "starts": starts, "converted": converted}))
