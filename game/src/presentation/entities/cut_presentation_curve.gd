class_name CutPresentationCurve
extends RefCounted

## The lift of a cut in flight: Riposte's diagonal X-slash, drawn over one
## horizontal combat plane (PRES-CARRIAGE-001). Only height and pitch — where
## the sword is on the plane is the authoritative orbit's (WEAPON-ORBIT-005).
## Pure and stateless apart from `Inflection`, which only carries hysteresis.
##
## The curve is keyed by the **cut angle** `a = angle × cut_dir`: the
## authoritative sword angle measured along the direction the cut was launched
## in, so −135° is a full load behind the striking shoulder, 0° the centreline,
## and +45° the opposite guard. Keying by angle — never by animation time — is
## what keeps the picture honest: a cut stopped at 35% of its travel shows 35%
## of a cut, a rebound runs the curve backward, a bind holds it where the blades
## are. Landmarks (Meyer: Wrath Guard → Longpoint halfway → the opposite guard):
##
##   a ≤ −45°   descending from the load (the field blends the gathered load
##              in on top, by physical progress)
##   a = 0°     Long Guard / contact corridor: blade near level, so the drawn
##              blade's ground projection is the simulated blade's here, where
##              contact happens (the orbit carries the hands forward)
##   a = +30°   cutting through, point below horizontal
##   a = +50°   follow-through low (−15°), never a chop at the floor
##   a ≥ +45°   the pitch inflection, once the blade is committed into the
##              opposite side: it stops descending and rises into that guard
##
## A right→left cut (cut_dir +1) traces upper-right → lower-left; a left→right
## cut mirrors it. Together they read as the X. The numbers are the weapon's
## path data (`WeaponPathDefinition`; the reference sword's by default): +12°
## entering the corridor (−20°), +5° at Long Guard, −8° cutting through (+30°),
## −15° at the inflection (+45°), hands a little above the belt past centre.
##
## See also: /docs/concepts/presentation.md


## The hysteresis that commits a cut to its opposite-side recovery. One per
## proxy; it reads authoritative state and decides nothing.
class Inflection:
	extends RefCounted
	var committed: bool = false
	var path: WeaponPathDefinition = WeaponPathDefinition.reference_sword()

	## Advance for this frame. `cut_angle` in degrees, `travel_speed` the
	## angular velocity along the cut's direction (rad/s). Out of a cut, call
	## `reset`.
	func update(cut_angle: float, travel_speed: float) -> bool:
		if committed:
			if cut_angle < path.inflection_leave:
				committed = false
		elif cut_angle > path.inflection_enter and travel_speed > path.inflection_min_speed:
			committed = true
		return committed

	func reset() -> void:
		committed = false


## The cut angle (degrees) for an authoritative `angle` (radians) on a cut
## launched in `cut_dir`.
static func cut_angle(angle: float, cut_dir: float) -> float:
	return rad_to_deg(angle) * (1.0 if cut_dir >= 0.0 else -1.0)


## The blade's pitch (radians) at cut angle `a` (degrees).
static func pitch(a: float, path: WeaponPathDefinition = null) -> float:
	var p := path if path != null else WeaponPathDefinition.reference_sword()
	return deg_to_rad(CombatPresentationField.sample_keys(p.cut_keys, p.cut_pitch_degrees, a))


## The hands' height above blade height at cut angle `a` (degrees).
static func raise(a: float, path: WeaponPathDefinition = null) -> float:
	var p := path if path != null else WeaponPathDefinition.reference_sword()
	return CombatPresentationField.sample_keys(p.cut_keys, p.cut_raise, a)


## How much of the stance the cut defers to at cut angle `a`: the two ends
## where no cut is mid-arc, plus the committed rise into the opposite guard.
static func stance_share(a: float, committed: bool, path: WeaponPathDefinition = null) -> float:
	var p := path if path != null else WeaponPathDefinition.reference_sword()
	var ends := maxf(smoothstep(-p.load_handoff_start, -p.load_handoff_end, -a), smoothstep(p.far_handoff_start, p.far_handoff_end, a))
	var rise := smoothstep(p.inflection_enter, p.inflection_rise_end, a) if committed else 0.0
	return maxf(ends, rise)
