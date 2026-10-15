extends SceneTree

## The V48 feel probe (Phase 0 and every later phase): consequence density on a
## small paired corpus, so a combat change is judged by what contact *does*.
## Scripted wander pilots, never the CPU (whose ladder statistics are read
## separately), each seed played twice with the pilots swapped between slots.
## Read-only; never a gate.
##
## Run: godot --headless --path game --script res://tools/feel_probe.gd
##      [-- --mu0]   the same corpus with every sword friction (and the blade-on-
##                   body friction it bounds) set to zero, the
##                   counterfactual that says whether friction is what holds a
##                   contact (V48B is only justified if it is)
##
## Prints one progress line per duel and one `FEEL_RESULT {json}` line:
## clashes, hits (body and hand), kills, parries (and the passive share —
## parries made by a resting guard), whiffs, clashes per hit, held-contact
## lifetimes (mean, p90, share of holds of 30+ ticks), friction saturation
## |Jt|/(μ·Jn) over held points, the threat-time advantage 0/10/20 ticks after
## a contact or whiff, and per swing against the opponent's hands: near misses
## (the blade's closest surface gap to a hand, sampled each tick, within
## `NEAR_MISS_M` and no hand wound) and saves by steel — a protective contact
## (the blade) met before any grip wound where the same free sweep, carried
## on from just before the contact at its own rates with nothing in the way,
## would have entered a hand within `FREE_SWEEP_TICKS`: the hand was safe
## because the steel was there. Parries are also read per released attack (the
## passive rate is the parry metric; the share of all parries is telemetry).
##
## Clean body strikes — a torso hit by an attack that met no protective steel
## since its release, not a graze — report how decisive a won line is: how many
## there are per kill, the share that were terminal, the share that left the
## target at a third of its health or less, and the damage they did (a share of
## full health), broken down by closing speed and contact kind — each bin with
## its decisive count (terminal, or a third of health or less left).
##
## With `-- --punish`, every PARRY and every whiff is also forked
## (`StateFork`) at the event and `PUNISH_DELAYS` ticks later, and each side's
## physical punish is measured from the fork (`StateFork.punish`: the fastest
## of an advancing cut, an angled advancing cut either side and a lunge, the
## other fighter idle, real contact included): who could land first after a
## parry (defender or attacker) and
## after a whiff (the other fighter or the whiffer). The first fork of each
## duel is checked against a re-simulation from the commands.
##
## Every hold of `LONG_HOLD_TICKS` or more is classified: whether it began on
## the blades (always, since rules 50), whether it ever held two points, whether it was
## *maintained* (a normal force of at least `PRESS_N` on most of its ticks) or
## merely resting, whether either fighter was driving (charging, swinging or
## holding the attack button) on most of its ticks, and whether the bodies were
## mostly closing, still or separating — so a long hold reads as pressure or as
## a wedge nobody is holding. Every held tick is also read as BIND, SLIDE or
## resting (PLANAR-BIND-001 readings, `_reading`), each end of a hold
## counts as a disengage, and any point with tangent impulse but no normal
## impulse is counted (`friction_without_normal`, a solver defect if ever > 0).
##
## See also: /docs/reference/testing.md

const SEEDS: Array[int] = [501, 502, 503, 504, 505, 506, 507, 508]
const MAX_TICKS := 3600
const LONG_HOLD_TICKS := 30
const SAMPLE_OFFSETS: Array[int] = [0, 10, 20]
const NEAR_MISS_M := 0.02
const FREE_SWEEP_TICKS := 6
const FREE_SWEEP_SAMPLES := 4
const PRESS_N := 1.0
const ROOT_STILL_MPS := 0.05
## Slip speed (m/s) above which a held point at its friction limit reads SLIDE.
const SLIDE_MPS := 0.05
const CLOSING_BINS: Array[float] = [2.0, 5.0, 10.0]
const PUNISH_DELAYS: Array[int] = [0, 10]
const PUNISH_TICKS := 45

var _rules: DuelRules
## Each fighter's x, y, heading, θ and their rates, just before this tick.
var _before := PackedFloat64Array()


func _initialize() -> void:
	_rules = DuelFixture.rules()
	var frictionless := OS.get_cmdline_user_args().has("--mu0")
	var punishing := OS.get_cmdline_user_args().has("--punish")
	var punish := {}
	if frictionless:
		_rules.combat.blade_friction = 0.0
		## A blade on a body may not grip harder than blade on blade.
		_rules.combat.blade_body_friction = 0.0
	if not _rules.is_valid():
		push_error("feel probe: the rules are invalid")
		quit(1)
		return
	var totals := {
		"clashes": 0, "body_hits": 0, "hand_hits": 0, "kills": 0, "parries": 0, "passive_parries": 0,
		"whiffs": 0, "holds": 0, "long_holds": 0, "near_misses": 0, "saved_by_steel": 0, "live_ticks": 0,
		"attacks": 0, "clean_hits": 0, "clean_terminal": 0, "clean_crippling": 0,
		"disengages": 0, "friction_without_normal": 0,
	}
	var readings := {}
	var spans: Array[int] = []
	var clean_damage: Array[float] = []
	var clean_bins := {}
	var taxonomy := {}
	var saturation_sum := 0.0
	var saturation_n := 0
	var saturated := 0
	var advantage := [0.0, 0.0, 0.0]
	var advantage_n := [0, 0, 0]
	for seed_value in SEEDS:
		for swap: bool in [false, true]:
			var runner := SimRunner.create(_rules, seed_value)
			var pilots: Array[Pilot] = [Pilot.wander(seed_value, 11), Pilot.wander(seed_value, 23)]
			if swap:
				pilots.reverse()
			var span := 0
			## The hold in progress: the pair it began on, its most points, and
			## its maintained, driven, closing and separating ticks.
			var hold_pair := ""
			var hold_points := 0
			var hold_pressed := 0
			var hold_driven := 0
			var hold_closing := 0
			var hold_separating := 0
			## Per slot, its current swing: closest hand gap, whether it wounded
			## a hand, whether steel already saved one.
			var swinging := [false, false]
			var closest := [INF, INF]
			var wounded := [false, false]
			var saved := [false, false]
			## Whether each slot's attack met protective steel since its release.
			var steel := [false, false]
			var samples: Array[int] = []
			var seen := 0
			var verified := false
			for _tick in MAX_TICKS:
				if runner.state.is_finished():
					break
				_capture(runner.state)
				runner.push(pilots[0].command(runner.state, 0), pilots[1].command(runner.state, 1))
				var state := runner.state
				if state.phase != MatchPhase.Id.ROUND_ACTIVE:
					continue
				totals["live_ticks"] += 1
				## Events of this tick.
				for k in range(seen, runner.events.size()):
					var event: DuelEvent = runner.events[k]
					match event.type:
						DuelEventTypes.BLADE_CONTACT:
							totals["clashes"] += 1
							samples.append(event.tick)
							for slot in 2:
								var protected := _steel_protects(state, slot)
								steel[slot] = steel[slot] or protected
								if swinging[slot] and not wounded[slot] and not saved[slot] and protected and _free_sweep_enters_hand(slot):
									saved[slot] = true
									totals["saved_by_steel"] += 1
						DuelEventTypes.ATTACK_WHIFFED:
							totals["whiffs"] += 1
							samples.append(event.tick)
						DuelEventTypes.ATTACK_RELEASED:
							totals["attacks"] += 1
							steel[event.actor] = false
						DuelEventTypes.BODY_HIT:
							if event.text(DuelEventKeys.REGION) == DuelEventKeys.REGION_GRIP:
								totals["hand_hits"] += 1
								wounded[event.actor] = true
							else:
								totals["body_hits"] += 1
								if not steel[event.actor] and event.text(DuelEventKeys.CONTACT_KIND) != "graze" and event.number(DuelEventKeys.CLOSING_SPEED) > 0.0:
									var full := _rules.spec_of(state.fighter(event.target)).fighter.max_health
									var left := event.number(DuelEventKeys.HEALTH)
									var share := event.number(DuelEventKeys.DAMAGE) / full
									var terminal := left <= 0.0 or bool(event.data.get(DuelEventKeys.LETHAL, false))
									totals["clean_hits"] += 1
									totals["clean_terminal"] += 1 if terminal else 0
									totals["clean_crippling"] += 1 if left <= full / 3.0 else 0
									clean_damage.append(share)
									_bin(clean_bins, _closing_bin(event.number(DuelEventKeys.CLOSING_SPEED)), terminal, share, terminal or left <= full / 3.0)
									_bin(clean_bins, "kind:" + event.text(DuelEventKeys.CONTACT_KIND), terminal, share, terminal or left <= full / 3.0)
						DuelEventTypes.FIGHTER_KILLED:
							totals["kills"] += 1
						DuelEventTypes.PARRY:
							totals["parries"] += 1
							if state.fighter(event.actor).weapon.phase == CombatPhase.Id.NEUTRAL:
								totals["passive_parries"] += 1
				if punishing:
					for k in range(seen, runner.events.size()):
						var event: DuelEvent = runner.events[k]
						var winner := -1
						var kind := ""
						if event.type == DuelEventTypes.PARRY:
							winner = event.actor
							kind = "parry"
						elif event.type == DuelEventTypes.ATTACK_WHIFFED:
							winner = 1 - event.actor
							kind = "whiff"
						if winner < 0 or not (state.fighter(0).is_alive() and state.fighter(1).is_alive()):
							continue
						if not verified:
							verified = true
							if not StateFork.is_faithful(runner, 30):
								push_error("feel probe: a fork diverged from its re-simulation (seed %d)" % seed_value)
								quit(1)
								return
						_punish_sample(punish, kind, runner, winner)
				seen = runner.events.size()
				## Held contacts: lifetime, friction saturation, and what holds them.
				var contact := state.blade_contact
				if contact.phase != SwordContactSet.Phase.SEPARATED:
					if span == 0:
						hold_pair = "BB" if contact.point_count > 0 else "--"
						hold_points = 0
						hold_pressed = 0
						hold_driven = 0
						hold_closing = 0
						hold_separating = 0
					span += 1
					hold_points = maxi(hold_points, contact.point_count)
					var reading := _reading(contact, _rules.combat)
					readings[reading] = int(readings.get(reading, 0)) + 1
					for i in contact.point_count:
						if contact.normal_impulse[i] <= 0.0 and absf(contact.tangent_impulse[i]) > 0.0:
							totals["friction_without_normal"] += 1
					var pressing := 0.0
					for i in contact.point_count:
						pressing += contact.hold_normal[i]
						var mu := _rules.combat.blade_friction
						var jn := contact.normal_impulse[i]
						if mu > 0.0 and jn > 1.0e-9:
							var ratio := absf(contact.tangent_impulse[i]) / (mu * jn)
							saturation_sum += ratio
							saturation_n += 1
							saturated += 1 if ratio >= 0.99 else 0
					hold_pressed += 1 if pressing / SimulationTimebase.TICK_SECONDS >= PRESS_N else 0
					var f0 := state.fighter(0)
					var f1 := state.fighter(1)
					hold_driven += 1 if _driving(f0) or _driving(f1) else 0
					var radial := _radial_speed(f0, f1)
					hold_closing += 1 if radial < -ROOT_STILL_MPS else 0
					hold_separating += 1 if radial > ROOT_STILL_MPS else 0
				elif span > 0:
					totals["disengages"] += 1
					spans.append(span)
					if span >= LONG_HOLD_TICKS:
						_classify(taxonomy, span, hold_pair, hold_points, hold_pressed, hold_driven, hold_closing, hold_separating)
					span = 0
				## Threat advantage after contacts and whiffs.
				var a := state.fighter(0)
				var b := state.fighter(1)
				if a.is_alive() and b.is_alive():
					for at in samples:
						for o in SAMPLE_OFFSETS.size():
							if state.tick - 1 == at + SAMPLE_OFFSETS[o]:
								advantage[o] += absf(InitiativeModel.time_to_threat(a, b, _rules) - InitiativeModel.time_to_threat(b, a, _rules))
								advantage_n[o] += 1
				## Per-swing hand approach: a near miss is scored as its swing ends.
				for slot in 2:
					var now := CombatPhase.is_swinging(state.fighter(slot).weapon.phase)
					if now and not swinging[slot]:
						closest[slot] = INF
						wounded[slot] = false
						saved[slot] = false
					var gap := _hand_gap(state.fighter(slot), state.opponent_of(slot))
					if now:
						closest[slot] = minf(closest[slot], gap)
					elif swinging[slot] and closest[slot] <= NEAR_MISS_M and not wounded[slot]:
						totals["near_misses"] += 1
					swinging[slot] = now
			if span > 0:
				spans.append(span)
				if span >= LONG_HOLD_TICKS:
					_classify(taxonomy, span, hold_pair, hold_points, hold_pressed, hold_driven, hold_closing, hold_separating)
			if punishing and not StateFork.is_untouched(runner):
				push_error("feel probe: forking changed the duel it forked (seed %d)" % seed_value)
				quit(1)
				return
			print("  · feel seed %d%s: %d clashes, %d hits" % [seed_value, " (swapped)" if swap else "", runner.count(DuelEventTypes.BLADE_CONTACT), runner.count(DuelEventTypes.BODY_HIT)])
	spans.sort()
	totals["holds"] = spans.size()
	for s in spans:
		totals["long_holds"] += 1 if s >= LONG_HOLD_TICKS else 0
	var hits: int = int(totals["body_hits"]) + int(totals["hand_hits"])
	var result := totals.duplicate()
	result["mu0"] = frictionless
	result["clashes_per_hit"] = float(totals["clashes"]) / float(maxi(hits, 1))
	result["passive_parry_share"] = float(totals["passive_parries"]) / float(maxi(int(totals["parries"]), 1))
	result["passive_parries_per_attack"] = float(totals["passive_parries"]) / float(maxi(int(totals["attacks"]), 1))
	result["saved_by_steel_per_attack"] = float(totals["saved_by_steel"]) / float(maxi(int(totals["attacks"]), 1))
	result["clean_hits_per_kill"] = float(totals["clean_hits"]) / float(maxi(int(totals["kills"]), 1))
	result["clean_terminal_share"] = float(totals["clean_terminal"]) / float(maxi(int(totals["clean_hits"]), 1))
	result["clean_crippling_share"] = float(totals["clean_crippling"]) / float(maxi(int(totals["clean_hits"]), 1))
	clean_damage.sort()
	result["clean_damage_share"] = [_mean_f(clean_damage), _quantile(clean_damage, 0.5), _quantile(clean_damage, 0.9)]
	var by := {}
	for key: String in clean_bins:
		var row: Array = clean_bins[key]
		var damages: Array[float] = []
		damages.assign(row[2])
		damages.sort()
		by[key] = {"hits": row[0], "terminal": row[1], "decisive": row[3], "median_damage": _quantile(damages, 0.5)}
	result["clean_by"] = by
	if punishing:
		result["punish"] = _punish_summary(punish)
	result["long_hold_taxonomy"] = taxonomy
	result["held_tick_readings"] = readings
	result["hold_mean_ticks"] = _mean(spans)
	result["hold_p90_ticks"] = spans[int(spans.size() * 0.9)] if spans.size() > 0 else 0
	result["long_hold_share"] = float(totals["long_holds"]) / float(maxi(spans.size(), 1))
	result["saturation_mean"] = saturation_sum / float(maxi(saturation_n, 1))
	result["saturated_share"] = float(saturated) / float(maxi(saturation_n, 1))
	result["advantage_s"] = [advantage[0] / maxf(advantage_n[0], 1), advantage[1] / maxf(advantage_n[1], 1), advantage[2] / maxf(advantage_n[2], 1)]
	print("FEEL_RESULT %s" % JSON.stringify(result))
	quit()


## Fork the duel at this event and `PUNISH_DELAYS` ticks later and measure
## who could physically land first: `winner` (the parrying defender, or the
## fighter who was whiffed at) against the other.
static func _punish_sample(punish: Dictionary, kind: String, runner: SimRunner, winner: int) -> void:
	var fork := StateFork.of(runner)
	var waited := 0
	for delay in PUNISH_DELAYS:
		for _i in delay - waited:
			fork.push(PlayerCommand.idle(fork.state.tick), PlayerCommand.idle(fork.state.tick))
		waited = delay
		if fork.state.phase != MatchPhase.Id.ROUND_ACTIVE:
			return
		var won: Array = StateFork.punish(fork, winner, PUNISH_TICKS)
		var lost: Array = StateFork.punish(fork, 1 - winner, PUNISH_TICKS)
		var key := "%s+%d" % [kind, delay]
		var row: Dictionary = punish.get(key, {"n": 0, "winner_first": 0, "other_first": 0, "tie": 0, "neither": 0, "winner_ticks": [], "other_ticks": [], "winner_verbs": {}})
		row["n"] += 1
		var w := int(won[0])
		var o := int(lost[0])
		if w > 0:
			(row["winner_ticks"] as Array).append(w)
			var verbs: Dictionary = row["winner_verbs"]
			verbs[won[2]] = int(verbs.get(won[2], 0)) + 1
		if o > 0:
			(row["other_ticks"] as Array).append(o)
		if w < 0 and o < 0:
			row["neither"] += 1
		elif o < 0 or (w > 0 and w < o):
			row["winner_first"] += 1
		elif w < 0 or o < w:
			row["other_first"] += 1
		else:
			row["tie"] += 1
		punish[key] = row


static func _punish_summary(punish: Dictionary) -> Dictionary:
	var out := {}
	for key: String in punish:
		var row: Dictionary = punish[key]
		var mine: Array[int] = []
		mine.assign(row["winner_ticks"])
		mine.sort()
		var theirs: Array[int] = []
		theirs.assign(row["other_ticks"])
		theirs.sort()
		out[key] = {
			"n": row["n"], "winner_first": row["winner_first"], "other_first": row["other_first"], "tie": row["tie"], "neither": row["neither"],
			"winner_lands": mine.size(), "winner_median_ticks": mine[int(mine.size() * 0.5)] if mine.size() > 0 else -1, "winner_verbs": row["winner_verbs"],
			"other_lands": theirs.size(), "other_median_ticks": theirs[int(theirs.size() * 0.5)] if theirs.size() > 0 else -1,
		}
	return out


## The surface gap (m) from `attacker`'s blade to the nearer of `defender`'s
## hands — the hand discs at its grip markers, as the sweep measures them.
func _hand_gap(attacker: FighterState, defender: FighterState) -> float:
	var attacking := _rules.spec_of(attacker)
	var defending := _rules.spec_of(defender)
	var blade := WeaponKinematics.pose_of(attacker, attacking, BladePose.new())
	var grip := WeaponKinematics.pose_of(defender, defending, BladePose.new())
	var hx := blade.point_x(attacking.weapon.blade_base_radius)
	var hy := blade.point_y(attacking.weapon.blade_base_radius)
	var tx := blade.point_x(attacking.weapon.tip_radius)
	var ty := blade.point_y(attacking.weapon.tip_radius)
	var reach := defending.fighter.hand_radius + attacking.weapon.blade_radius
	var gap := INF
	for radius: float in [defending.weapon.offhand_grip_radius, defending.weapon.dominant_grip_radius]:
		var gx := grip.point_x(radius)
		var gy := grip.point_y(radius)
		var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, gx, gy)
		gap = minf(gap, SimMath.length(SimMath.mix(hx, tx, t) - gx, SimMath.mix(hy, ty, t) - gy) - reach)
	return gap


## Record both fighters' kinematics before the tick is stepped.
func _capture(state: MatchState) -> void:
	_before.resize(16)
	for slot in 2:
		var fighter := state.fighter(slot)
		var row := slot * 8
		_before[row] = fighter.x
		_before[row + 1] = fighter.y
		_before[row + 2] = fighter.facing
		_before[row + 3] = fighter.weapon.angle
		_before[row + 4] = fighter.vx
		_before[row + 5] = fighter.vy
		_before[row + 6] = fighter.turn_rate
		_before[row + 7] = fighter.weapon.speed


## Whether `attacker`'s sweep, carried on from just before this tick at its own
## rates (and the opponent's at theirs) with nothing to stop it, would enter one
## of the opponent's hands within `FREE_SWEEP_TICKS`.
func _free_sweep_enters_hand(attacker: int) -> bool:
	var attacking := _rules.combatant(attacker)
	var defending := _rules.combatant(1 - attacker)
	var blade := BladePose.new()
	var grip := BladePose.new()
	var reach := defending.fighter.hand_radius + attacking.weapon.blade_radius
	var a := attacker * 8
	var d := (1 - attacker) * 8
	var dt := SimulationTimebase.TICK_SECONDS / float(FREE_SWEEP_SAMPLES)
	for k in range(1, FREE_SWEEP_TICKS * FREE_SWEEP_SAMPLES + 1):
		var t := dt * float(k)
		WeaponKinematics.pose_at(_before[a] + _before[a + 4] * t, _before[a + 1] + _before[a + 5] * t, _before[a + 2] + _before[a + 6] * t, _before[a + 3] + _before[a + 7] * t, attacking, blade)
		WeaponKinematics.pose_at(_before[d] + _before[d + 4] * t, _before[d + 1] + _before[d + 5] * t, _before[d + 2] + _before[d + 6] * t, _before[d + 3] + _before[d + 7] * t, defending, grip)
		var hx := blade.point_x(attacking.weapon.blade_base_radius)
		var hy := blade.point_y(attacking.weapon.blade_base_radius)
		var tx := blade.point_x(attacking.weapon.tip_radius)
		var ty := blade.point_y(attacking.weapon.tip_radius)
		for radius: float in [defending.weapon.offhand_grip_radius, defending.weapon.dominant_grip_radius]:
			var gx := grip.point_x(radius)
			var gy := grip.point_y(radius)
			var along := SimMath.closest_param_on_segment(hx, hy, tx, ty, gx, gy)
			if SimMath.length(SimMath.mix(hx, tx, along) - gx, SimMath.mix(hy, ty, along) - gy) <= reach:
				return true
	return false


## Whether the sword contact `attacker` just met is on steel that defends its
## opponent (DEFENSE-ROLE-001: the blade, the only steel there is).
func _steel_protects(state: MatchState, attacker: int) -> bool:
	return state.blade_contact.point_count > 0 and _rules.spec_of(state.opponent_of(attacker)).weapon.blade_protects


## Whether `fighter` is driving its sword: charging, swinging, or holding the
## attack button.
static func _driving(fighter: FighterState) -> bool:
	return fighter.attack_held or fighter.weapon.phase == CombatPhase.Id.CHARGING or CombatPhase.is_swinging(fighter.weapon.phase)


## How fast the bodies are separating along the line between them (m/s;
## negative = closing).
static func _radial_speed(a: FighterState, b: FighterState) -> float:
	var dx := b.x - a.x
	var dy := b.y - a.y
	var apart := maxf(SimMath.length(dx, dy), SimMath.EPSILON)
	return ((b.vx - a.vx) * dx + (b.vy - a.vy) * dy) / apart


## What one held tick of the manifold reads as (PLANAR-BIND-001), a
## description only: SLIDE — a point sliding at the friction limit; BIND —
## normal pressure on the blades; RESTING — touching, nothing pressing.
static func _reading(contact: SwordContactSet, combat: CombatTuning) -> String:
	var pressed := false
	var sliding := false
	var mu := combat.blade_friction
	for i in contact.hold_count():
		var jn := contact.hold_normal[i]
		pressed = pressed or jn / SimulationTimebase.TICK_SECONDS >= PRESS_N
		sliding = sliding or (contact.hold_slip[i] >= SLIDE_MPS and mu > 0.0 and absf(contact.hold_tangent[i]) >= 0.99 * mu * jn and jn > 0.0)
	if sliding:
		return "slide"
	if pressed:
		return "bind"
	return "resting"


## Count one long hold into each of its classes.
static func _classify(taxonomy: Dictionary, span: int, pair: String, points: int, pressed: int, driven: int, closing: int, separating: int) -> void:
	var still := span - closing - separating
	var motion := "still"
	if closing >= maxi(separating, still):
		motion = "closing"
	elif separating >= still:
		motion = "separating"
	var maintained := "maintained" if pressed * 2 >= span else "resting"
	var drive := "driven" if driven * 2 >= span else "undriven"
	var points_key := "2+" if points >= 2 else "1"
	for key: String in ["pair:" + pair, "points:" + points_key, "root:" + motion, maintained + "/" + drive]:
		taxonomy[key] = int(taxonomy.get(key, 0)) + 1


func _closing_bin(closing: float) -> String:
	for edge in CLOSING_BINS:
		if closing < edge:
			return "closing<%.0f" % edge
	return "closing>=%.0f" % CLOSING_BINS[CLOSING_BINS.size() - 1]


static func _bin(bins: Dictionary, key: String, terminal: bool, share: float, decisive: bool) -> void:
	var row: Array = bins.get(key, [0, 0, [], 0])
	row[0] = int(row[0]) + 1
	row[1] = int(row[1]) + (1 if terminal else 0)
	var damages: Array = row[2]
	damages.append(share)
	row[3] = int(row[3]) + (1 if decisive else 0)
	bins[key] = row


static func _quantile(sorted: Array[float], q: float) -> float:
	return sorted[int(sorted.size() * q)] if sorted.size() > 0 else 0.0


func _mean_f(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / float(maxi(values.size(), 1))


func _mean(values: Array[int]) -> float:
	var total := 0
	for v in values:
		total += v
	return float(total) / float(maxi(values.size(), 1))
