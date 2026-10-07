class_name DebugOverlay
extends PanelContainer

## Combat diagnostics (COMBAT §76) for debug builds, toggled with F3:
## spacing, closing speed, orbit, each fighter's phase/charge/commitment/
## stability/time-to-threat, and the last contact. Text only, updated only
## while visible.
##
## See also: /docs/concepts/combat.md

const NONE := "none"
## Below the HUD's top plates.
const TOP := 96.0

var _label: Label
var _last_contact: String = NONE
var _profile: PackedStringArray = PackedStringArray()


static func create() -> DebugOverlay:
	var overlay := DebugOverlay.new()
	overlay.name = "DebugOverlay"
	overlay.theme_type_variation = &"HudPlate"
	overlay.mouse_filter = MOUSE_FILTER_IGNORE
	overlay.position = Vector2(RiposteTheme.HUD_EDGE, TOP)
	overlay._label = Label.new()
	overlay._label.theme_type_variation = &"HudCaptionLabel"
	overlay.add_child(overlay._label)
	overlay.visible = false
	return overlay


## Record the match's physical profile (COMBAT §41). Shown because almost
## every surprise in tuning turns out to be a derived quantity disagreeing
## with the authored one: a sluggish fighter is usually carrying more inertia
## than anyone intended. Seeing `I` and `α = τ/I` beside the mass and torque
## they came from is what makes that visible instead of mysterious.
##
## Captured once, since definitions are immutable for the life of the match.
func describe(fighter: FighterDefinition, weapon: WeaponDefinition) -> void:
	_profile = PackedStringArray([
		(
			"body %.2f m · %.1f kg (×%.2f) · I %.2f kg·m² · move %.0f N (%.1f m/s²) · turn %.0f N·m (%.1f rad/s²)"
			% [
				fighter.height,
				fighter.mass,
				fighter.mass_ratio(),
				fighter.moment_of_inertia(),
				fighter.locomotion_force,
				fighter.move_accel(),
				fighter.turn_torque,
				fighter.turn_accel(),
			]
		),
		(
			"blade %.2f m · %.2f kg (×%.2f) · I %.2f kg·m² (×%.2f) · swing %.0f N·m · tip %.1f m/s"
			% [
				weapon.length(),
				weapon.mass,
				weapon.mass_ratio(),
				weapon.moment_of_inertia(),
				weapon.inertia_ratio(),
				weapon.swing_torque_full,
				weapon.swing_speed_full * weapon.tip_radius,
			]
		),
	])


func observe(events: Array[DuelEvent]) -> void:
	for event in events:
		match event.type:
			DuelEventTypes.BLADE_CONTACT:
				_last_contact = "blade %s · impulse %.2f · closing %.1f m/s" % [event.text(DuelEventKeys.CONTACT_CLASS), event.number(DuelEventKeys.IMPULSE), event.number(DuelEventKeys.CLOSING_SPEED)]
			DuelEventTypes.BODY_HIT:
				_last_contact = "body %.1f dmg · quality %.2f · exposure %.2f" % [event.number(DuelEventKeys.DAMAGE), event.number(DuelEventKeys.QUALITY), event.number(DuelEventKeys.EXPOSURE)]
			DuelEventTypes.PARRY:
				_last_contact = "parry · margin %.2f s" % event.number(DuelEventKeys.MARGIN)
			DuelEventTypes.BIND_STARTED:
				_last_contact = "bind"


func update(snapshot: PresentationSnapshot, fps: float) -> void:
	if not visible or snapshot == null:
		return
	var lines := _profile.duplicate()
	lines.append("tick %d · %d fps" % [snapshot.tick, roundi(fps)])
	lines.append("distance %.2f m · closing %.2f m/s · orbit %.2f rad/s" % [snapshot.distance, snapshot.closing_speed, snapshot.orbit_rate])
	for fighter in snapshot.fighters:
		lines.append("P%d %s · charge %.2f · commit %.2f · stability %.2f · threat %.2f s" % [
			fighter.slot,
			CombatPhase.label(fighter.phase),
			fighter.charge,
			fighter.commitment,
			fighter.stability,
			fighter.threat_time,
		])
	lines.append("last contact: %s" % _last_contact)
	_label.text = "\n".join(lines)


func text() -> String:
	return _label.text
