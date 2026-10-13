extends SceneTree

## Calibration diagnostics (7B.8): how fast a cut actually moves at the forte,
## the centre of percussion and the tip, at tap, half and full charge, under
## the shipping rules — read against a human reference. Read-only; changes
## nothing and is never a gate.
##
## Run: godot --headless --path game --script res://tools/swing_speed_report.gd
##
## Each charge is a free cut (the opponent far away, the wielder standing):
## press, hold until the earned charge reaches the target, release, and sample
## every tick of the swing. Point speed is the authoritative point velocity
## (`WeaponKinematics.velocity_into`: θ̇ plus the hands travelling the hilt
## track), so the carriage's own motion is included.
##
## See also: /docs/concepts/combat.md

const CHARGES: PackedFloat64Array = [0.0, 0.5, 1.0]
const MAX_HOLD_TICKS := 240
const MAX_SWING_TICKS := 120
## Fastest measured longsword cuts are in the low-to-mid teens at the point
## (m/s); energy goes as v², so the ratio squared is how much more a cut here
## carries than its human counterpart.
const HUMAN_TIP_SPEED := 14.0


func _initialize() -> void:
	var rules := StandardDuelRules.create()
	var spec := rules.combatant(0)
	var weapon := spec.weapon
	var forte := weapon.hilt_radius + 0.25 * weapon.blade_length()
	var percussion := ContactMechanics.percussion_radius(weapon)
	print("\nSwing speeds, rules v%d (swing_speed_full %.1f rad/s; forte %.3f m, CoP %.3f m, tip %.3f m from the pommel)" % [rules.version, weapon.swing_speed_full, forte, percussion, weapon.tip_radius])
	print("  %-10s %10s %10s %10s %10s %10s %12s" % ["charge", "arc (deg)", "peak θ̇", "forte m/s", "CoP m/s", "tip m/s", "tip² / human²"])
	for target in CHARGES:
		var rig := WeaponRig.create(rules)
		rig.press()
		var held := 0
		if target > 0.0:
			while held < MAX_HOLD_TICKS and rig.fighter.weapon.charge < target:
				rig.step()
				held += 1
		rig.release()
		var released := rig.events_of(DuelEventTypes.ATTACK_RELEASED)
		var charge := released[0].number(DuelEventKeys.CHARGE) if not released.is_empty() else 0.0
		var arc := rad_to_deg(released[0].number(DuelEventKeys.ARC)) if not released.is_empty() else 0.0
		var peak := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
		var pose := BladePose.new()
		for _tick in MAX_SWING_TICKS:
			if not CombatPhase.is_swinging(rig.fighter.weapon.phase) and rig.fighter.weapon.phase != CombatPhase.Id.LAUNCH:
				break
			peak[0] = maxf(peak[0], absf(rig.fighter.weapon.speed))
			WeaponKinematics.pose_of(rig.fighter, spec, pose)
			var radii := [forte, percussion, weapon.tip_radius]
			for k in 3:
				var r: float = radii[k]
				var px := pose.point_x(r)
				var py := pose.point_y(r)
				WeaponKinematics.velocity_into(rig.fighter, pose, px, py)
				peak[k + 1] = maxf(peak[k + 1], SimMath.length(pose.vx, pose.vy))
			rig.step()
		print("  %-10.2f %10.0f %10.1f %10.2f %10.2f %10.2f %12.2f" % [charge, arc, peak[0], peak[1], peak[2], peak[3], peak[3] * peak[3] / (HUMAN_TIP_SPEED * HUMAN_TIP_SPEED)])
	quit(0)
