extends SceneTree

## Contact-feel diagnostics: how swords respond to being met, measured over
## CPU-vs-CPU duels with the shipping rules. Read-only; changes nothing, reads
## no private solver state, and is never a gate.
##
## Run: godot --headless --path game --script res://tools/feel_report.gd
## (`-- --seeds=N` reads only the first N seeds of the corpus; `-- --mu=0`
## plays the same rules with every friction coefficient zeroed, the control
## that isolates what friction changed.)
##
## A win rate or a hit count says how often things happen; this says what a
## clash *does* to the swords and bodies, so a rules change that makes combat
## feel stickier or more staccato shows up as a number rather than a hunch.
## Per swinging sword at a blade contact (tick t):
##
## ```text
## kept       θ̇(t)·dir / |θ̇(t−1)|      speed the cut kept through the clash
## rebound    max(0, −kept)               reversal the clash produced
## redriven   θ̇(t+1)·dir / |θ̇(t−1)|    what is left after the next motor tick
## ```
##
## and per clash: ticks the pair stays in contact, how far the contact point
## migrates along both blades while it lasts, ticks until a new attack is
## released, how much the bodies' velocity changed, and whether a body hit
## followed within half a second — split by whether the met cut physically
## continued or was stopped/reversed, so "fewer interrupts" can be read as
## follow-through (good) or bulldozing (bad).
##
## Sword-on-torso contacts (a sword held on the opponent's hurt torso by the
## persistent constraint) are characterized physically, never just counted:
## per tick the tangential relative speed `v_t` at the contact, the physical
## normal pressure `J_n / dt` (velocity stage only), how far the contact point
## migrated (along the blade and around the torso), and whether the cut's
## motor was still driving. An episode is then
##
## ```text
## SLIDE  meaningful v_t or migration: a legitimate glance/sweep along the body
## STALL  tiny v_t, little migration, persistent pressure, motor still driving
## REST   tiny v_t, little pressure: a sword simply resting against the body
## ```
##
## Only STALL is a defect. Friction should turn STALLs into clean stops or
## releases without turning SLIDEs into sticks.
##
## See also: /docs/reference/testing.md

const SEEDS: Array[int] = [
	201, 202, 203, 204, 205, 206, 207, 208, 209, 210,
	211, 212, 213, 214, 215, 216, 217, 218, 219, 220,
	221, 222, 223, 224, 225, 226, 227, 228, 229, 230,
	231, 232, 233, 234, 235, 236, 237, 238, 239, 240,
]
const MAX_TICKS := 40000
const FOLLOW_TICKS := 30
## Older rules emitted a scripted bind; counted by name so this tool reads
## any rules version.
const LEGACY_BIND_STARTED := &"bind_started"
## Episode classification thresholds (diagnostic, not gameplay): a contact
## moving at least this fast along the body, or migrating at least this far,
## is sliding; one pressing at least this hard is loaded.
const SLIDE_SPEED := 0.3
const SLIDE_MIGRATION := 0.05
const LOADED_PRESSURE := 50.0
const LONG_EPISODE_TICKS := 10
## Health deficits (share of max health behind the opponent at any moment of
## a round) the comeback diagnostic reports win rates for.
const DEFICIT_BANDS: PackedFloat64Array = [0.25, 0.5, 0.75]


class Clash:
	var tick: int = 0
	var swinging: PackedByteArray = PackedByteArray([0, 0])
	var before: PackedFloat64Array = PackedFloat64Array([0.0, 0.0])
	var dir: PackedFloat64Array = PackedFloat64Array([0.0, 0.0])
	var after: PackedFloat64Array = PackedFloat64Array([0.0, 0.0])
	var redriven: PackedFloat64Array = PackedFloat64Array([0.0, 0.0])
	var body_dv: float = 0.0
	var contact_ticks: int = 0
	var free: bool = false
	var next_attack: int = -1
	var hit_followed: bool = false
	## Did each fighter land a body hit within the follow window?
	var hit_by: PackedByteArray = PackedByteArray([0, 0])
	var interrupted: int = 0
	var closing: float = 0.0
	var migration: float = 0.0
	var last_fraction: PackedFloat64Array = PackedFloat64Array([-1.0, -1.0])


## Where a first impact happened (the hilt-contact diagnosis): which region of
## each sword the named point lay on, how far apart the fighters stood, each
## sword's θ, who was swinging, where along the blades, how fast they closed.
class Impact:
	## 0 blade on blade, 1 blade on a hilt region (crossguard or handle), 2 a
	## hilt region on both swords.
	var region: int = 0
	var separation: float = 0.0
	var theta: PackedFloat64Array = PackedFloat64Array([0.0, 0.0])
	var swinging: int = 0
	var fraction: PackedFloat64Array = PackedFloat64Array([0.0, 0.0])
	var closing: float = 0.0


class TorsoEpisode:
	var ticks: int = 0
	var drive_ticks: int = 0
	var speed_sum: float = 0.0
	var pressure_sum: float = 0.0
	var migration: float = 0.0
	var progress: float = 0.0
	var last_fraction: float = -1.0
	var last_angle: float = 0.0
	var separated: bool = false

	func mean_speed() -> float:
		return speed_sum / maxf(float(ticks), 1.0)

	func mean_pressure() -> float:
		return pressure_sum / maxf(float(ticks), 1.0)

	func kind() -> String:
		if mean_speed() >= SLIDE_SPEED or migration >= SLIDE_MIGRATION:
			return "SLIDE"
		if mean_pressure() >= LOADED_PRESSURE and drive_ticks * 2 >= ticks:
			return "STALL"
		return "REST"


var _pose := BladePose.new()
var _frictionless := false
var _impacts: Array[Impact] = []
var _ranges := {}


func _initialize() -> void:
	var limit := SEEDS.size()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			limit = clampi(int(arg.trim_prefix("--seeds=")), 1, SEEDS.size())
		elif arg == "--mu=0":
			_frictionless = true
	var clashes: Array[Clash] = []
	var episodes: Array[TorsoEpisode] = []
	var totals := {"hits": 0, "kills": 0, "damage": 0.0, "binds": 0, "rounds": 0, "round_ticks": 0, "attacks": 0, "whiffs": 0, "whiffs_countered": 0, "first_hit_rounds": 0, "first_hit_wins": 0, "deficit_rounds": [0, 0, 0], "deficit_wins": [0, 0, 0], "creep_episodes": 0, "creep_ticks": 0, "creep_long": 0, "creep_longest": 0, "rules": 0, "pairs_first": {}, "pairs_held": {}, "dropped": 0, "pivot_caps": 0, "held_ticks": 0, "held_multi": 0, "most_points": 0}
	for index in limit:
		_duel(SEEDS[index], index % 2 == 1, clashes, episodes, totals)
	_print(clashes, episodes, totals, limit)
	quit(0)


func _duel(match_seed: int, swap: bool, clashes: Array[Clash], episodes: Array[TorsoEpisode], totals: Dictionary) -> void:
	var levels: Array[MatchConfig.Difficulty] = [MatchConfig.Difficulty.MEDIUM, MatchConfig.Difficulty.HARD]
	if swap:
		levels = [MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.MEDIUM]
	var config := MatchConfig.quick_play(levels[0], match_seed)
	if _frictionless:
		config.rules.combat.blade_friction = 0.0
		config.rules.combat.blade_body_friction = 0.0
		config.rules.combat.guard_friction = 0.0
	totals.rules = config.rules.version
	var controllers: Array[FighterController] = []
	for slot in 2:
		controllers.append(CpuController.create(config.rules, CpuProfile.for_difficulty(levels[slot]), match_seed, slot))
	if _ranges.is_empty():
		var scale := WeaponKinematics.strike_reach(config.rules.combatant(0), config.rules.combatant(1)) / CpuController.calibration_reach()
		_ranges["strike reach"] = WeaponKinematics.strike_reach(config.rules.combatant(0), config.rules.combatant(1))
		for level: MatchConfig.Difficulty in [MatchConfig.Difficulty.MEDIUM, MatchConfig.Difficulty.HARD]:
			var profile := CpuProfile.for_difficulty(level)
			var name := "medium" if level == MatchConfig.Difficulty.MEDIUM else "hard"
			_ranges["%s tap" % name] = profile.tap_range * scale
			_ranges["%s smothered" % name] = profile.tap_range * scale - CpuController.SMOTHERED_MARGIN
			_ranges["%s engage" % name] = profile.engage_range * scale
			_ranges["%s charge" % name] = profile.charge_range * scale
	var session := MatchSession.create(config, controllers)
	var open: Array[Clash] = []
	var round_start := 0
	var creeping := PackedInt32Array([0, 0])
	var torso: Array[TorsoEpisode] = [null, null]
	## Whiff → counter: the tick each fighter's latest physical whiff ended
	## (−1 when none is open). Round outcome diagnostics: who landed the
	## round's first body hit, and the worst health deficit each fighter faced.
	var whiffed_at := PackedInt32Array([-1, -1])
	var first_hitter := -1
	var worst_deficit := PackedFloat64Array([0.0, 0.0])
	var max_health := config.rules.combatant(0).fighter.max_health
	for _tick in MAX_TICKS:
		if session.is_finished():
			break
		var state := session.state
		var speed_before := PackedFloat64Array([state.fighter(0).weapon.speed, state.fighter(1).weapon.speed])
		var body_before := PackedFloat64Array([state.fighter(0).vx, state.fighter(0).vy, state.fighter(1).vx, state.fighter(1).vy])
		var swinging := PackedByteArray([
			1 if CombatPhase.is_swinging(state.fighter(0).weapon.phase) else 0,
			1 if CombatPhase.is_swinging(state.fighter(1).weapon.phase) else 0,
		])
		var dirs := PackedFloat64Array([state.fighter(0).weapon.swing_dir, state.fighter(1).weapon.swing_dir])
		var events := session.step()
		state = session.state
		var contact := state.blade_contact
		var held := contact.hold_count()
		for row in held:
			_tally(totals.pairs_held, contact.hold_feature_a[row], contact.hold_feature_b[row])
		if held > 0:
			totals.held_ticks += 1
			if held > SwordContactSet.POINTS_PER_PAIR:
				totals.held_multi += 1
		for slot in 2:
			var lifecycle := state.weapon_body_contacts[slot]
			var on_torso := lifecycle.phase == WeaponBodyContact.Phase.CONSTRAINING
			## A cut still live while its sword rests on the opponent's torso.
			if on_torso and CombatPhase.is_swinging(state.fighter(slot).weapon.phase):
				creeping[slot] += 1
			elif creeping[slot] > 0:
				totals.creep_episodes += 1
				totals.creep_ticks += creeping[slot]
				totals.creep_longest = maxi(int(totals.creep_longest), creeping[slot])
				if creeping[slot] >= LONG_EPISODE_TICKS:
					totals.creep_long += 1
				creeping[slot] = 0
			if on_torso:
				if torso[slot] == null:
					torso[slot] = TorsoEpisode.new()
				_sample_torso(torso[slot], state, slot, config.rules)
			elif torso[slot] != null:
				torso[slot].separated = lifecycle.phase == WeaponBodyContact.Phase.EXITING or lifecycle.phase == WeaponBodyContact.Phase.OUTSIDE
				episodes.append(torso[slot])
				torso[slot] = null
		for clash in open:
			_follow(clash, state, events)
		open = open.filter(func(c: Clash) -> bool: return session.state.tick - c.tick <= FOLLOW_TICKS)
		for event in events:
			match event.type:
				DuelEventTypes.BLADE_CONTACT:
					var clash := Clash.new()
					clash.tick = event.tick
					clash.closing = event.number(DuelEventKeys.CLOSING_SPEED)
					clash.swinging = swinging.duplicate()
					clash.dir = dirs.duplicate()
					clash.before = speed_before.duplicate()
					for slot in 2:
						clash.after[slot] = state.fighter(slot).weapon.speed
						if swinging[slot] == 1 and not CombatPhase.is_swinging(state.fighter(slot).weapon.phase):
							clash.interrupted += 1
					clash.body_dv = maxf(
						SimMath.length(state.fighter(0).vx - body_before[0], state.fighter(0).vy - body_before[1]),
						SimMath.length(state.fighter(1).vx - body_before[2], state.fighter(1).vy - body_before[3])
					)
					clash.last_fraction[0] = state.blade_contact.fraction_a[0]
					clash.last_fraction[1] = state.blade_contact.fraction_b[0]
					for point in state.blade_contact.point_count:
						_tally(totals.pairs_first, state.blade_contact.feature_a[point], state.blade_contact.feature_b[point])
					_impacts.append(_impact(event, state, swinging))
					clashes.append(clash)
					open.append(clash)
				DuelEventTypes.BODY_HIT:
					totals.hits += 1
					totals.damage += event.number(DuelEventKeys.DAMAGE)
					if event.actor == 0 or event.actor == 1:
						if first_hitter < 0:
							first_hitter = event.actor
						var whiffer := 1 - event.actor
						if whiffed_at[whiffer] >= 0 and event.tick - whiffed_at[whiffer] <= FOLLOW_TICKS:
							totals.whiffs_countered += 1
						whiffed_at[whiffer] = -1
				DuelEventTypes.FIGHTER_KILLED:
					totals.kills += 1
				DuelEventTypes.ATTACK_RELEASED:
					totals.attacks += 1
				DuelEventTypes.ATTACK_WHIFFED:
					totals.whiffs += 1
					if event.actor == 0 or event.actor == 1:
						whiffed_at[event.actor] = event.tick
				DuelEventTypes.ROUND_STARTED:
					round_start = event.tick
					whiffed_at = PackedInt32Array([-1, -1])
					first_hitter = -1
					worst_deficit = PackedFloat64Array([0.0, 0.0])
				DuelEventTypes.ROUND_ENDED:
					totals.rounds += 1
					totals.round_ticks += event.tick - round_start
					var winner := int(event.number(DuelEventKeys.WINNER))
					if first_hitter >= 0:
						totals.first_hit_rounds += 1
						if winner == first_hitter:
							totals.first_hit_wins += 1
					for slot in 2:
						for band in DEFICIT_BANDS.size():
							if worst_deficit[slot] >= DEFICIT_BANDS[band]:
								totals.deficit_rounds[band] += 1
								if winner == slot:
									totals.deficit_wins[band] += 1
				LEGACY_BIND_STARTED:
					totals.binds += 1
		if state.phase == MatchPhase.Id.ROUND_ACTIVE and max_health > 0.0:
			for slot in 2:
				var deficit := (state.fighter(1 - slot).health - state.fighter(slot).health) / max_health
				worst_deficit[slot] = maxf(worst_deficit[slot], deficit)
	var counters := session.simulation.diagnostics
	totals.dropped += counters.meaningful_contacts_dropped
	totals.pivot_caps += counters.pivot_cap_hits
	totals.most_points = maxi(int(totals.most_points), counters.max_manifold_points)


func _impact(event: DuelEvent, state: MatchState, swinging: PackedByteArray) -> Impact:
	var impact := Impact.new()
	var hilt_a := int(event.number(DuelEventKeys.FEATURE_0)) != SwordContactSet.Feature.BLADE
	var hilt_b := int(event.number(DuelEventKeys.FEATURE_1)) != SwordContactSet.Feature.BLADE
	impact.region = int(hilt_a) + int(hilt_b)
	impact.separation = DuelGeometry.distance(state.fighter(0), state.fighter(1))
	for slot in 2:
		impact.theta[slot] = absf(rad_to_deg(state.fighter(slot).weapon.angle))
	impact.swinging = swinging[0] + swinging[1]
	impact.fraction[0] = event.number(DuelEventKeys.FRACTION_0)
	impact.fraction[1] = event.number(DuelEventKeys.FRACTION_1)
	impact.closing = event.number(DuelEventKeys.CLOSING_SPEED)
	return impact


## Diagnostic only: do hilt-region first impacts happen at legitimately closed
## (inside-sword) range — CPU spacing — or at fencing distance, where the hilt
## geometry or candidates would be suspect? Read against the CPUs' own
## preferred distances.
func _hilt_diagnosis() -> void:
	print("\n  first impacts by region (named point)        blade/blade  blade/hilt   hilt/hilt")
	var by_region: Array = [[], [], []]
	for impact in _impacts:
		by_region[impact.region].append(impact)
	var counts := ""
	for region in 3:
		counts += " %11d" % by_region[region].size()
	print("  %-44s%s" % ["count", counts])
	for metric: String in ["separation (m) p10", "separation (m) median", "separation (m) p90", "|θ| either sword (deg) median", "swinging swords (mean)", "blade fraction median", "closing speed (m/s) median"]:
		var row := ""
		for region in 3:
			var values := PackedFloat64Array()
			for impact: Impact in by_region[region]:
				match metric:
					"separation (m) p10", "separation (m) median", "separation (m) p90":
						values.append(impact.separation)
					"|θ| either sword (deg) median":
						values.append(impact.theta[0])
						values.append(impact.theta[1])
					"swinging swords (mean)":
						values.append(float(impact.swinging))
					"blade fraction median":
						values.append(impact.fraction[0])
						values.append(impact.fraction[1])
					_:
						values.append(impact.closing)
			var stat := _mean(values) if metric.ends_with("(mean)") else _percentile(values, 0.1 if metric.ends_with("p10") else (0.9 if metric.ends_with("p90") else 0.5))
			row += " %11.2f" % stat
		print("  %-44s%s" % [metric, row])
	var inside := PackedInt32Array([0, 0, 0])
	var smothered := minf(float(_ranges.get("medium smothered", 0.0)), float(_ranges.get("hard smothered", 0.0)))
	for impact in _impacts:
		if impact.separation < smothered:
			inside[impact.region] += 1
	print("  %-44s %10.0f%% %10.0f%% %10.0f%%" % ["closer than the CPUs' smothered measure", _pct(inside[0], by_region[0].size()), _pct(inside[1], by_region[1].size()), _pct(inside[2], by_region[2].size())])
	var reference := ""
	for key: String in _ranges:
		reference += "%s %.2f  " % [key, float(_ranges[key])]
	print("  CPU distances (m): %s" % reference)


static func _percentile(values: PackedFloat64Array, share: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(share * float(sorted.size() - 1)), 0, sorted.size() - 1)]


static func _mean(values: PackedFloat64Array) -> float:
	var sum := 0.0
	for value in values:
		sum += value
	return sum / maxf(float(values.size()), 1.0)


## Unordered feature-pair label (BLADE/GUARD and GUARD/BLADE are one row).
const _FEATURE_NAMES := ["BLADE", "GUARD", "HILT"]


static func _tally(into: Dictionary, a: int, b: int) -> void:
	var low := mini(a, b)
	var high := maxi(a, b)
	var label := "%s/%s" % [_FEATURE_NAMES[low], _FEATURE_NAMES[high]]
	into[label] = int(into.get(label, 0)) + 1


## One tick of a sword held on the opponent's torso: where the contact is,
## how fast it slides, how hard it presses, whether the cut is still driven.
func _sample_torso(episode: TorsoEpisode, state: MatchState, slot: int, rules: DuelRules) -> void:
	var weapon := rules.spec_of(state.fighter(slot)).weapon
	var wielder := state.fighter(slot)
	var target := state.opponent_of(slot)
	WeaponKinematics.pose_of(wielder, rules.spec_of(wielder), _pose)
	var hx := _pose.point_x(weapon.hilt_radius)
	var hy := _pose.point_y(weapon.hilt_radius)
	var tx := _pose.point_x(weapon.tip_radius)
	var ty := _pose.point_y(weapon.tip_radius)
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, target.x, target.y)
	var px := SimMath.mix(hx, tx, t)
	var py := SimMath.mix(hy, ty, t)
	var nx := px - target.x
	var ny := py - target.y
	var distance := SimMath.length(nx, ny)
	if distance > SimMath.EPSILON:
		nx /= distance
		ny /= distance
	WeaponKinematics.velocity_into(wielder, _pose, px, py)
	var slide := absf((_pose.vx - target.vx) * -ny + (_pose.vy - target.vy) * nx)
	var angle := SimMath.arctan2(ny, nx)
	if episode.last_fraction >= 0.0:
		episode.migration += absf(t - episode.last_fraction) * weapon.blade_length()
		episode.migration += absf(SimMath.wrap_angle(angle - episode.last_angle)) * rules.spec_of(target).fighter.hurt_radius
	episode.last_fraction = t
	episode.last_angle = angle
	episode.ticks += 1
	episode.speed_sum += slide
	episode.pressure_sum += state.weapon_body_contacts[slot].normal_impulse / SimulationTimebase.TICK_SECONDS
	if CombatPhase.is_swinging(wielder.weapon.phase):
		episode.drive_ticks += 1
		episode.progress += rad_to_deg(wielder.weapon.speed * wielder.weapon.swing_dir) * SimulationTimebase.TICK_SECONDS


func _follow(clash: Clash, state: MatchState, events: Array[DuelEvent]) -> void:
	var age := state.tick - 1 - clash.tick
	if age == 1:
		for slot in 2:
			clash.redriven[slot] = state.fighter(slot).weapon.speed
	if not clash.free:
		if state.blade_contact.phase == SwordContactSet.Phase.SEPARATED:
			clash.free = true
		else:
			clash.contact_ticks += 1
			if state.blade_contact.point_count > 0:
				var blade := state.blade_contact
				clash.migration += absf(blade.fraction_a[0] - clash.last_fraction[0]) + absf(blade.fraction_b[0] - clash.last_fraction[1])
				clash.last_fraction[0] = blade.fraction_a[0]
				clash.last_fraction[1] = blade.fraction_b[0]
	for event in events:
		if event.type == DuelEventTypes.ATTACK_RELEASED and clash.next_attack < 0:
			clash.next_attack = age
		elif event.type == DuelEventTypes.BODY_HIT:
			clash.hit_followed = true
			if event.actor == 0 or event.actor == 1:
				clash.hit_by[event.actor] = 1


func _print(clashes: Array[Clash], episodes: Array[TorsoEpisode], totals: Dictionary, duels: int) -> void:
	var kept := PackedFloat64Array()
	var rebound := PackedFloat64Array()
	var redriven := PackedFloat64Array()
	var contact := PackedFloat64Array()
	var migration := PackedFloat64Array()
	var to_attack := PackedFloat64Array()
	var body := PackedFloat64Array()
	var closing := PackedFloat64Array()
	var followed := 0
	var interrupted := 0
	var swords := 0
	## [cut continued, cut stopped or reversed] × [swords, own hit, opponent hit]
	var split := PackedInt32Array([0, 0, 0, 0, 0, 0])
	for clash in clashes:
		contact.append(float(clash.contact_ticks))
		migration.append(clash.migration)
		body.append(clash.body_dv)
		closing.append(clash.closing)
		if clash.next_attack >= 0:
			to_attack.append(float(clash.next_attack))
		if clash.hit_followed:
			followed += 1
		interrupted += clash.interrupted
		for slot in 2:
			var start := absf(clash.before[slot])
			if clash.swinging[slot] == 0 or start < 1.0:
				continue
			swords += 1
			var k := clash.after[slot] * clash.dir[slot] / start
			kept.append(k)
			rebound.append(maxf(0.0, -k))
			redriven.append(clash.redriven[slot] * clash.dir[slot] / start)
			var row := 0 if k > 0.0 else 3
			split[row] += 1
			split[row + 1] += clash.hit_by[slot]
			split[row + 2] += clash.hit_by[1 - slot]
	print("\nContact feel over %d duels (Medium vs Hard, sides alternating), rules v%d%s" % [duels, totals.rules, " with μ = 0 (control)" if _frictionless else ""])
	print("  clashes %d | binds %d | hits %d | kills %d | damage %.0f | attacks %d | whiffs %d | avg round %.1fs" % [
		clashes.size(), totals.binds, totals.hits, totals.kills, totals.damage, totals.attacks, totals.whiffs,
		SimulationTimebase.ticks_to_seconds(totals.round_ticks) / maxf(float(totals.rounds), 1.0),
	])
	print("  swinging swords met: %d | interrupted at the clash: %d | clash → body hit within 0.5 s: %.1f%%" % [
		swords, interrupted, 100.0 * float(followed) / maxf(float(clashes.size()), 1.0),
	])
	print("  met cut CONTINUED: %d swords | its wielder hit within 0.5 s %.1f%% | opponent hit %.1f%%" % [
		split[0], _pct(split[1], split[0]), _pct(split[2], split[0]),
	])
	print("  met cut STOPPED/REVERSED: %d swords | its wielder hit within 0.5 s %.1f%% | opponent hit %.1f%%" % [
		split[3], _pct(split[4], split[3]), _pct(split[5], split[3]),
	])
	print("  whiff → opponent body hit within 0.5 s: %d of %d whiffs (%.1f%%)" % [
		totals.whiffs_countered, totals.whiffs, _pct(totals.whiffs_countered, totals.whiffs),
	])
	var deficits := ""
	for band in DEFICIT_BANDS.size():
		deficits += " | ≥ %d%% behind: won %d of %d (%.1f%%)" % [
			roundi(DEFICIT_BANDS[band] * 100.0), totals.deficit_wins[band], totals.deficit_rounds[band], _pct(totals.deficit_wins[band], totals.deficit_rounds[band]),
		]
	print("  first-hit fighter won the round: %d of %d (%.1f%%)%s" % [
		totals.first_hit_wins, totals.first_hit_rounds, _pct(totals.first_hit_wins, totals.first_hit_rounds), deficits,
	])
	print("  cut live on a torso: %d episodes, %d ≥ %d ticks, longest %d ticks, %.1f ticks mean" % [
		totals.creep_episodes, totals.creep_long, LONG_EPISODE_TICKS, totals.creep_longest, float(totals.creep_ticks) / maxf(float(totals.creep_episodes), 1.0),
	])
	print("  %-38s %8s %8s %8s %8s" % ["", "p10", "median", "p90", "mean"])
	_row("closing speed at clash (m/s)", closing)
	_row("speed kept through clash", kept)
	_row("rebound (reversal share)", rebound)
	_row("speed after next motor tick", redriven)
	_row("ticks in contact (≤ 30)", contact)
	_row("blade contact migration (fractions)", migration)
	_row("ticks to next attack (≤ 30)", to_attack)
	_row("body |Δv| at clash (m/s)", body)
	_pairs(totals)
	_hilt_diagnosis()
	_torso(episodes)


## Diagnostic only (not gated): which features meet — first-impact points and
## held-contact row ticks — how often a held contact needs more rows than one
## feature pair could hold, and whether any real constraint was dropped.
func _pairs(totals: Dictionary) -> void:
	print("\n  feature pairs %-24s %10s %10s" % ["", "first", "held ticks"])
	for label: String in ["BLADE/BLADE", "BLADE/GUARD", "BLADE/HILT", "GUARD/GUARD", "GUARD/HILT", "HILT/HILT"]:
		print("  %-38s %10d %10d" % [label, int(totals.pairs_first.get(label, 0)), int(totals.pairs_held.get(label, 0))])
	print("  held ticks %d | with more than %d rows %d (%.1f%%) | most points at once %d" % [
		totals.held_ticks, SwordContactSet.POINTS_PER_PAIR, totals.held_multi, _pct(totals.held_multi, totals.held_ticks), totals.most_points,
	])
	print("  meaningful contacts dropped: %d | pivot cap hits: %d" % [totals.dropped, totals.pivot_caps])


func _torso(episodes: Array[TorsoEpisode]) -> void:
	var kinds := {"SLIDE": 0, "STALL": 0, "REST": 0}
	var long_kinds := {"SLIDE": 0, "STALL": 0, "REST": 0}
	var separated := 0
	var ticks := PackedFloat64Array()
	var speed := PackedFloat64Array()
	var pressure := PackedFloat64Array()
	var moved := PackedFloat64Array()
	var progress := PackedFloat64Array()
	var stall_ticks := PackedFloat64Array()
	for episode in episodes:
		var kind := episode.kind()
		kinds[kind] += 1
		if episode.ticks >= LONG_EPISODE_TICKS:
			long_kinds[kind] += 1
			ticks.append(float(episode.ticks))
			speed.append(episode.mean_speed())
			pressure.append(episode.mean_pressure())
			moved.append(episode.migration)
			progress.append(episode.progress)
			if kind == "STALL":
				stall_ticks.append(float(episode.ticks))
		if episode.separated:
			separated += 1
	print("\n  sword held on a torso: %d episodes (SLIDE %d | STALL %d | REST %d), %d end separated" % [
		episodes.size(), kinds.SLIDE, kinds.STALL, kinds.REST, separated,
	])
	print("  of which ≥ %d ticks: SLIDE %d | STALL %d | REST %d" % [LONG_EPISODE_TICKS, long_kinds.SLIDE, long_kinds.STALL, long_kinds.REST])
	print("  (SLIDE: mean |v_t| ≥ %.2f m/s or migration ≥ %.2f m; STALL: else, mean J_n/dt ≥ %.0f N and the cut still driven ≥ half the episode)" % [SLIDE_SPEED, SLIDE_MIGRATION, LOADED_PRESSURE])
	print("  long episodes %-25s %8s %8s %8s %8s" % ["", "p10", "median", "p90", "mean"])
	_row("duration (ticks)", ticks)
	_row("mean |v_t| (m/s)", speed)
	_row("mean J_n / dt (N)", pressure)
	_row("contact migration (m)", moved)
	_row("cut progress while held (deg)", progress)
	_row("STALL duration (ticks)", stall_ticks)


static func _pct(part: int, whole: int) -> float:
	return 100.0 * float(part) / maxf(float(whole), 1.0)


func _row(label: String, values: PackedFloat64Array) -> void:
	if values.is_empty():
		print("  %-38s %8s" % [label, "—"])
		return
	var sorted := values.duplicate()
	sorted.sort()
	var mean := 0.0
	for value in sorted:
		mean += value
	mean /= float(sorted.size())
	print("  %-38s %8.2f %8.2f %8.2f %8.2f" % [label, _pick(sorted, 0.1), _pick(sorted, 0.5), _pick(sorted, 0.9), mean])


static func _pick(sorted: PackedFloat64Array, q: float) -> float:
	return sorted[clampi(int(q * float(sorted.size() - 1)), 0, sorted.size() - 1)]
