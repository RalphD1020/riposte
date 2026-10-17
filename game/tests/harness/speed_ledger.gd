class_name SpeedLedger
extends RefCounted

## The Combat Speed Ledger (docs/reference/combat-speed-ledger.md): every
## quantity that sets how fast a duel plays, read from the rules and, for the
## timings, measured by driving the real weapon motor (`WeaponRig`). RULES
## checks the committed page against `table()`; `tools/speed_ledger.gd`
## rewrites it.
##
## The abb6a27 column is a frozen historical record of rules 20 (the build
## whose feel the review compares against), copied from that commit's content
## files once; it is never recomputed.

const BEGIN := "<!-- speed-ledger:begin -->"
const END := "<!-- speed-ledger:end -->"
const DOC := "../docs/reference/combat-speed-ledger.md"

## Quantity → rules 20 value, as the old content authored it.
const RULES_20 := {
	"sim": "60",
	"swing_tap": "10.5",
	"swing_full": "20.0",
	"arc_tap": "90",
	"arc_full": "180",
	"domain": "270",
	"swing_torque": "128.7 / 148.5",
	"brake_torque": "217.8 / 148.5",
	"hold_torque": "39.6",
	"windup": "1.8 @ 59.4",
	"control_speed": "1.2",
	"recovery": "6 + authored up to 48 (commitment, overswing, displacement, facing, balance)",
	"bind": "scripted; loser +10 recovery",
	"buffer": "4",
	"turn_torque": "175.0",
	"turn_rate": "9.0",
	"commit_turn": "tracking floor 12 % (penalties 0.72, overswing 0.1)",
	"move_max": "4.2",
	"forces": "1760 / 2400 / 5600",
	"burst_speed": "8.4",
	"hurt": "whole body 0.27",
	## Key kept so the rules-20 column still resolves. The row is not a hurt shape.
	"grip": "—",
	"steel": "blade only",
	"exposure": "damage × 0.75–1.5",
	"tap_swing": "—",
	"tap_control": "—",
	"full_windback": "—",
	"full_swing": "—",
	"full_control": "—",
}


## The ledger's table rows for `rules` (the reference combatant in slot 0).
static func table(rules: DuelRules) -> String:
	var spec := rules.combatant(0)
	var weapon := spec.weapon
	var fighter := spec.fighter
	var combat := rules.combat
	var tap := _tap(rules)
	var full := _full(rules)
	var rows: Array = [
		["sim", "Simulation rate", "Hz", str(SimulationTimebase.TICK_RATE)],
		["swing_tap", "Tap swing speed cap", "rad/s", _n(weapon.swing_speed_tap, 1)],
		["swing_full", "Full swing speed cap", "rad/s", _n(weapon.swing_speed_full, 1)],
		["arc_tap", "Tap attack arc", "°", _n(rad_to_deg(weapon.arc(0.0)), 0)],
		["arc_full", "Full attack arc (ATTACK-ARC-001)", "°", _n(rad_to_deg(weapon.arc(1.0)), 0)],
		["domain", "Control domain", "°", _n(rad_to_deg(weapon.guard_limit * 2.0), 0)],
		["swing_torque", "Swing torque tap / full", "N·m", "%s / %s" % [_n(weapon.swing_torque_tap, 1), _n(weapon.swing_torque_full, 1)]],
		["brake_torque", "Attack brake tap / full", "N·m", "%s / %s" % [_n(weapon.brake_torque_tap, 1), _n(weapon.brake_torque_full, 1)]],
		["hold_torque", "Hold / reacquire torque", "N·m", _n(weapon.hold_torque, 1)],
		["windup", "Wind-back speed @ torque", "rad/s @ N·m", "%s @ %s" % [_n(weapon.windup_speed, 1), _n(weapon.windup_torque, 1)]],
		["control_speed", "Control speed (attack gate)", "rad/s", _n(weapon.control_speed, 1)],
		["recovery", "Recovery", "ticks", "floor %d, then the brake (RECOVERY-001)" % combat.recovery_min_ticks],
		["bind", "Bind", "—", "rigid contact, no winner"],
		["buffer", "Attack buffer", "ticks", str(weapon.buffer_ticks)],
		["turn_torque", "Healthy turn torque", "N·m", _n(fighter.turn_torque, 1)],
		["turn_rate", "Healthy turn-rate cap", "rad/s", _n(fighter.turn_speed_max, 1)],
		["commit_turn", "Full-commit turn share", "—", "torque %d %% / rate %d %%" % [roundi(combat.commit_turn_torque_curve * 100.0), roundi(combat.commit_turn_speed_curve * 100.0)]],
		["move_max", "Move speed", "m/s", _n(fighter.max_speed, 1)],
		["forces", "Locomotion / brake / burst force", "N", "%s / %s / %s" % [_n(fighter.locomotion_force, 0), _n(fighter.braking_force, 0), _n(fighter.burst_force, 0)]],
		["burst_speed", "Burst speed (axial)", "m/s", _n(fighter.burst_speed_axial, 1)],
		["hurt", "Hurt target radius", "m", "torso %s" % _n(fighter.hurt_radius, 3)],
		["grip", "Hand discs, presentation and self-clearance only", "m", "2 × %s; not a hurt shape" % _n(fighter.hand_radius, 3)],
		["steel", "Sword-vs-sword steel", "—", "blade only (STEEL-TOPOLOGY-001)"],
		["exposure", "Exposure in damage", "—", "reading only (PHYS-004)"],
		["tap_swing", "Tap from the guard: release → overswing", "ticks", str(tap[0])],
		["tap_control", "Tap whiff: release → under control", "ticks", str(tap[1])],
		["full_windback", "Full charge: press → fully wound", "ticks", str(full[2])],
		["full_swing", "Full charge: release → overswing", "ticks", str(full[0])],
		["full_control", "Full whiff: release → under control", "ticks", str(full[1])],
	]
	var lines := PackedStringArray(["| Quantity | Unit | Now (rules %d) | abb6a27 (rules 20) |" % rules.version, "| --- | --- | --- | --- |"])
	for row: Array in rows:
		lines.append("| %s | %s | %s | %s |" % [row[1], row[2], row[3], RULES_20[row[0]]])
	return "\n".join(lines)


## The committed page's table, between its markers; empty if unreadable. Read
## with LF line endings, whatever the checkout wrote.
static func committed() -> String:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join(DOC)).replace("\r\n", "\n")
	var from := text.find(BEGIN)
	var to := text.find(END)
	if from < 0 or to < from:
		return ""
	return text.substr(from + BEGIN.length(), to - from - BEGIN.length()).strip_edges()


## The page with its table replaced by `table(rules)`, in the page's own line
## endings, so a CRLF checkout is never left with mixed ones.
static func rewritten(rules: DuelRules) -> String:
	var path := ProjectSettings.globalize_path("res://").path_join(DOC)
	var text := FileAccess.get_file_as_string(path)
	var eol := "\r\n" if text.contains("\r\n") else "\n"
	var from := text.find(BEGIN)
	var to := text.find(END)
	var block := (eol + eol + table(rules) + eol + eol).replace("\r\n", "\n").replace("\n", eol)
	return text.substr(0, from + BEGIN.length()) + block + text.substr(to)


## A tap from the right guard, idle: [release → overswing, release → neutral].
static func _tap(rules: DuelRules) -> PackedInt32Array:
	var rig := WeaponRig.create(rules)
	rig.step(true, true)
	var released := rig.tick
	rig.step_until_phase(CombatPhase.Id.OVERSWING)
	var swing := rig.tick - released
	rig.step_until_phase(CombatPhase.Id.NEUTRAL)
	return PackedInt32Array([swing, rig.tick - released])


## A full charge from the right guard, idle: [release → overswing,
## release → neutral, press → full charge].
static func _full(rules: DuelRules) -> PackedInt32Array:
	var rig := WeaponRig.create(rules)
	rig.press()
	var pressed := rig.tick
	while rig.fighter.weapon.charge < 1.0 and rig.tick - pressed < 600:
		rig.hold(1)
	var wound := rig.tick - pressed
	rig.release()
	var released := rig.tick
	rig.step_until_phase(CombatPhase.Id.OVERSWING)
	var swing := rig.tick - released
	rig.step_until_phase(CombatPhase.Id.NEUTRAL)
	return PackedInt32Array([swing, rig.tick - released, wound])


static func _n(value: float, places: int) -> String:
	return ("%." + str(places) + "f") % value
