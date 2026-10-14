extends SceneTree

## The lost-line probe: how long a physical advantage lasts
## (DEFLECTION-CONSEQUENCE-001). Hand-built scenes on the shipped rules.
## Read-only; never a gate.
##
## Run: godot --headless --path game --script res://tools/reacquisition_probe.gd
##
## Scenes:
##   displaced  fighter 1's Long Guard knocked 20° / 45° / 90° off the line, at
##              rest or still turning outward (6 rad/s); fighter 0 composed.
##   cut        fighter 0 cuts into fighter 1's Long Guard (tap / half / full
##              charge, on the line or 20 cm to either side); sampled from the
##              first blade contact.
##   whiff      a full cut thrown from just out of measure, so it meets nothing;
##              sampled from its release.
##
## Two readings per sample tick `k` after the event:
##
## - The estimate: each fighter's `InitiativeModel` time to threat on the other
##   (THREAT-001), with θ, θ̇ and the phase of both swords. It ignores the
##   opponent's sword and counts hands, so in a bind both may read a tick or
##   two; it is shown, not trusted.
## - The punish (`hit0` / `hit1`, `StateFork.punish`): the scene forked at `k`,
##   then that fighter alone punishes — the fastest of a tap re-pressed every
##   tick while advancing straight (`c`) or angling forward left / right (`l`,
##   `r`), and a forward burst onto the point (`p`) — and
##   the other stays idle. The ticks until it lands a body hit (`t` torso, `h`
##   hand) through whatever steel is physically in the way, or `--` if none
##   lands within `PUNISH_TICKS`. Real physics, the opponent's sword included.
##   `adv` is hit0 − hit1: positive means fighter 1 punishes sooner.
##
## The scene's labels (PARRY, the contact's deflection flags) are printed so a
## row can be read against what the classification called it.
##
## See also: /docs/reference/testing.md

const SAMPLES: Array[int] = [0, 3, 5, 10, 15, 20]
const SEARCH_TICKS := 90
const PUNISH_TICKS := 45

var _rules: DuelRules


func _initialize() -> void:
	_rules = DuelFixture.rules()
	for degrees: float in [20.0, 45.0, 90.0]:
		for outward: float in [0.0, 6.0]:
			_report("displaced %2.0f° %s" % [degrees, "turning" if outward > 0.0 else "at rest"], _displaced.bind(degrees, outward), StringName())
	for charge: float in [0.0, 0.5, 1.0]:
		for offset: float in [0.0, -0.2, 0.2]:
			_report("cut c=%.1f x=%+.1f" % [charge, offset], _cut.bind(charge, offset, 2.2), DuelEventTypes.BLADE_CONTACT)
	## A whiff on the line needs the defender far out of measure; one beside
	## the cut's start (a side-step against its direction) can be close.
	for charge: float in [0.0, 1.0]:
		for offset: float in [0.0, -0.6, -1.0]:
			var clear := _whiff_distance(charge, offset)
			_report("whiff c=%.1f x=%+.1f at %.2f m" % [charge, offset, clear], _cut.bind(charge, offset, clear), DuelEventTypes.ATTACK_RELEASED)
	quit()


## Fighter 0 at the origin facing +y, composed in Long Guard; fighter 1 2.3 m
## up facing it (clear of fighter 0's sword: inside about 2.15 m two Long
## Guards start inside each other), its Long Guard knocked `degrees` off the
## line, turning outward at `outward` rad/s.
func _displaced(degrees: float, outward: float) -> SimRunner:
	var weapon := _rules.combatant(0).weapon
	var runner := SimRunner.create(_rules, 1)
	runner.skip_intro()
	var state := runner.state
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	ContactFixture.arm(state.fighter(1), 0.0, 2.3, -PI / 2.0, deg_to_rad(degrees), outward, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	return runner


## Fighter 0 cutting from its wound-back guard into fighter 1's Long Guard
## `distance` metres up and `offset` metres across, at `charge`.
func _cut(charge: float, offset: float, distance: float) -> SimRunner:
	var weapon := _rules.combatant(0).weapon
	var runner := SimRunner.create(_rules, 1)
	runner.skip_intro()
	var state := runner.state
	var speed := weapon.achievable_swing_speed(charge, 1.0)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, PI / 2.0, -weapon.guard_angle - weapon.arc(charge) * 0.25, speed, CombatPhase.Id.ACTIVE_THREAT, charge, weapon)
	state.fighter(0).weapon.swing_dir = 1.0
	ContactFixture.arm(state.fighter(1), offset, distance, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	return runner


## The nearest distance (cm steps from 2 m) at which the cut at `charge`,
## thrown with fighter 1 offset `offset` m across, meets nothing at all — a
## whiff, not a clash or a hit.
func _whiff_distance(charge: float, offset: float) -> float:
	var distance := 2.2
	while distance < 4.0:
		if _whiffs(_cut(charge, offset, distance)):
			return distance
		distance += 0.01
	return distance


static func _whiffs(runner: SimRunner) -> bool:
	for _i in SEARCH_TICKS:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
		if runner.count(DuelEventTypes.BLADE_CONTACT) > 0 or runner.count(DuelEventTypes.BODY_HIT) > 0:
			return false
		if runner.count(DuelEventTypes.ATTACK_WHIFFED) > 0:
			return true
	return false


## Build the scene and step idle to its event (`type`, or the start for an
## empty type); null if the event never comes.
func _at_event(build: Callable, type: StringName) -> SimRunner:
	var runner: SimRunner = build.call()
	if type == StringName():
		return runner
	if type == DuelEventTypes.ATTACK_RELEASED:
		return runner
	for _i in SEARCH_TICKS:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
		if runner.count(type) > 0:
			return runner
	return null


func _idle(runner: SimRunner, ticks: int) -> void:
	for _i in ticks:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))


func _report(label: String, build: Callable, type: StringName) -> void:
	var base := _at_event(build, type)
	if base == null:
		print("%-24s no %s within %d ticks" % [label, type, SEARCH_TICKS])
		return
	var tags := ""
	if type == DuelEventTypes.BLADE_CONTACT:
		var contact := base.first(DuelEventTypes.BLADE_CONTACT)
		tags = "parry=%d arrested0=%s arrested1=%s impulse=%.2f" % [base.count(DuelEventTypes.PARRY), str(contact.data.get(DuelEventKeys.ARRESTED_0, false)), str(contact.data.get(DuelEventKeys.ARRESTED_1, false)), contact.number(DuelEventKeys.IMPULSE)]
	print("%s  %s" % [label, tags])
	print("   k   θ0°    θ̇0   ph0  θ1°    θ̇1   ph1  ttt0   ttt1   hit0   hit1   adv")
	var sampled := 0
	for k in SAMPLES:
		_idle(base, k - sampled)
		sampled = k
		var a := base.state.fighter(0)
		var b := base.state.fighter(1)
		var hit0 := StateFork.punish(base, 0, PUNISH_TICKS)
		var hit1 := StateFork.punish(base, 1, PUNISH_TICKS)
		var adv := "  -"
		if int(hit0[0]) > 0 and int(hit1[0]) > 0:
			adv = "%+3d" % (int(hit0[0]) - int(hit1[0]))
		elif int(hit1[0]) > 0:
			adv = " 1+"
		elif int(hit0[0]) > 0:
			adv = " 0+"
		print("  %2d %6.1f %6.2f %4s %6.1f %6.2f %4s  %.3f  %.3f  %5s  %5s  %s" % [
			k,
			rad_to_deg(a.weapon.angle), a.weapon.speed, _phase(a.weapon.phase),
			rad_to_deg(b.weapon.angle), b.weapon.speed, _phase(b.weapon.phase),
			InitiativeModel.time_to_threat(a, b, _rules), InitiativeModel.time_to_threat(b, a, _rules),
			_hit(hit0), _hit(hit1), adv,
		])


static func _hit(result: Array) -> String:
	return "%d%s%s" % [result[0], result[1], result[2]] if int(result[0]) > 0 else "--"


static func _phase(phase: CombatPhase.Id) -> String:
	match phase:
		CombatPhase.Id.NEUTRAL:
			return "N"
		CombatPhase.Id.RECOVERY:
			return "R"
		CombatPhase.Id.OVERSWING:
			return "O"
		CombatPhase.Id.STAGGER:
			return "S"
		CombatPhase.Id.CHARGING:
			return "C"
		CombatPhase.Id.DEAD:
			return "D"
	return "A"
