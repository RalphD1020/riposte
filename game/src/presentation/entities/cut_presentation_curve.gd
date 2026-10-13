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
## cut mirrors it. Together they read as the X.
##
## See also: /docs/concepts/presentation.md

## Cut angle keys (degrees) and, at each: blade pitch (degrees) and the hands'
## height above blade height (m).
## Seeds from the frozen landmark table: +12° entering the corridor (−20°), +5°
## at Long Guard, −8° cutting through (+30°), −15° at the inflection (+45°); a
## loaded cut's higher start (+65° → +35° by −75°) is the gathered load
## descending on top, by physical progress. Past centre the hands stay a
## little above the belt: the rules-40 track carries them in toward the
## centreline, and lower they fold the support forearm into the gambeson.
const KEYS: PackedFloat64Array = [-90.0, -20.0, 0.0, 30.0, 45.0]
const PITCH_DEGREES: PackedFloat64Array = [12.0, 12.0, 5.0, -8.0, -15.0]
const RAISE: PackedFloat64Array = [0.18, 0.19, 0.17, 0.10, 0.08]

## Out at either end the curve hands the sword back to the stance: deep on the
## load side (an uncharged swing from far back), and far past the opposite
## guard — no cut is mid-arc out there.
const LOAD_HANDOFF_START := -45.0
const LOAD_HANDOFF_END := -90.0
const FAR_HANDOFF_START := 80.0
const FAR_HANDOFF_END := 110.0

## The inflection: past `ENTER` with the blade still travelling into the
## opposite side, the cut starts rising into that guard, fully by `RISE_END`;
## it lets go only back inside `LEAVE`, so contact rattling the blade about one
## threshold never bobs the point.
const INFLECTION_ENTER := 45.0
const INFLECTION_LEAVE := 30.0
const INFLECTION_RISE_END := 80.0
## The least angular velocity (rad/s, into the cut's side) that counts as
## still travelling there.
const INFLECTION_MIN_SPEED := 0.5


## The hysteresis that commits a cut to its opposite-side recovery. One per
## proxy; it reads authoritative state and decides nothing.
class Inflection:
	extends RefCounted
	var committed: bool = false

	## Advance for this frame. `cut_angle` in degrees, `travel_speed` the
	## angular velocity along the cut's direction (rad/s). Out of a cut, call
	## `reset`.
	func update(cut_angle: float, travel_speed: float) -> bool:
		if committed:
			if cut_angle < INFLECTION_LEAVE:
				committed = false
		elif cut_angle > INFLECTION_ENTER and travel_speed > INFLECTION_MIN_SPEED:
			committed = true
		return committed

	func reset() -> void:
		committed = false


## The cut angle (degrees) for an authoritative `angle` (radians) on a cut
## launched in `cut_dir`.
static func cut_angle(angle: float, cut_dir: float) -> float:
	return rad_to_deg(angle) * (1.0 if cut_dir >= 0.0 else -1.0)


static func pitch(a: float) -> float:
	return deg_to_rad(CombatPresentationField.sample_keys(KEYS, PITCH_DEGREES, a))


## The hands' height above blade height at cut angle `a` (degrees).
static func raise(a: float) -> float:
	return CombatPresentationField.sample_keys(KEYS, RAISE, a)


## How much of the stance the cut defers to at cut angle `a`: the two ends
## where no cut is mid-arc, plus the committed rise into the opposite guard.
static func stance_share(a: float, committed: bool) -> float:
	var ends := maxf(smoothstep(-LOAD_HANDOFF_START, -LOAD_HANDOFF_END, -a), smoothstep(FAR_HANDOFF_START, FAR_HANDOFF_END, a))
	var rise := smoothstep(INFLECTION_ENTER, INFLECTION_RISE_END, a) if committed else 0.0
	return maxf(ends, rise)
