class_name WeaponPathDefinition
extends RefCounted

## The data of a weapon's 3D path (WEAPON-PATH-004): the angle-indexed X
## projection that maps the authoritative planar sword onto its drawn height,
## pitch and roll. Presentation data only — it lives with the weapon's
## presentation, never in `WeaponHandlingProfile` or any rules fingerprint, so
## changing it can never move a simulation result or a replay hash.
##
## Every table is keyed by physical angle (degrees), never by animation time:
## the guard keys by |θ|, the cut keys by the cut angle `a = θ × cut_dir`
## (−135 the full load behind the striking shoulder, 0 the centre, +45 the
## opposite guard), the high-guard keys by |θ| on the attack-origin side. One
## definition serves both attack origins: the left-origin path is the
## right-origin path reflected (`mirror_policy`), never authored twice; only
## the body's anatomy differs between the sides.
##
## Immutable once built. `reference_sword()` is the reference longsword's path:
## the numbers below, moved unchanged from where the presentation field and the
## cut curve held them.
##
## Implements: /spec/invariants.md#weapon-path-004
## See also: /docs/concepts/presentation.md

## How a left-origin pose follows from the right-origin one.
enum MirrorPolicy {
	## Only the weapon's geometry is reflected; the skeleton is not.
	WEAPON_GEOMETRY_ONLY,
}

## The reference sword's guard keys over |θ|: 0 Long Guard, 45 Ready, 90 the
## edge of the ready band, 135 wound fully round. Hands' height above blade
## height (m) and blade pitch (degrees).
const STANCE_DEGREES: PackedFloat64Array = [0.0, 45.0, 90.0, 135.0]
const STANCE_RAISE: PackedFloat64Array = [0.19, 0.17, 0.15, 0.18]
const STANCE_PITCH_DEGREES: PackedFloat64Array = [10.0, 12.0, 8.0, 4.0]
## The high shoulder load at full charge (the shared gather lift).
const LOAD_RAISE := 0.42
const LOAD_PITCH_DEGREES := 65.0
## Swing progress over which a swing leaves its guard lift for the cut, and over
## which a loaded sword comes down off the shoulder.
const LEAVE_STANCE_END := 0.3
const DESCENT_END := 0.55
## The shared X projection's normalized height on the attack-origin side:
## Ready 0.75, gather 0.88, full wind-back 1.00.
const X_HIGH_DEGREES: PackedFloat64Array = [45.0, 90.0, 135.0]
const X_HIGH_HEIGHT: PackedFloat64Array = [0.75, 0.88, 1.0]
## Crossguard roll toward the blade's side off centre (the shared guard roll).
const ROLL_DEGREES := 14.0
const ROLL_START := 20.0
const ROLL_END := 90.0
## The cut curve, keyed by cut angle: blade pitch (degrees) and the hands'
## height above blade height (m).
const CUT_KEYS: PackedFloat64Array = [-90.0, -20.0, 0.0, 30.0, 45.0]
const CUT_PITCH_DEGREES: PackedFloat64Array = [12.0, 12.0, 5.0, -8.0, -15.0]
const CUT_RAISE: PackedFloat64Array = [0.18, 0.19, 0.17, 0.10, 0.08]
## Where the cut hands the sword back to the stance: deep on the load side and
## far past the opposite guard.
const LOAD_HANDOFF_START := -45.0
const LOAD_HANDOFF_END := -90.0
const FAR_HANDOFF_START := 80.0
const FAR_HANDOFF_END := 110.0
## The follow-through inflection: past `ENTER` with the blade still travelling
## into the opposite side the cut rises into that guard, fully by `RISE_END`; it
## lets go only back inside `LEAVE`.
const INFLECTION_ENTER := 45.0
const INFLECTION_LEAVE := 30.0
const INFLECTION_RISE_END := 80.0
## The least angular velocity (rad/s, into the cut's side) that counts as still
## travelling there.
const INFLECTION_MIN_SPEED := 0.5

## Authoring landmarks on the cut angle (degrees): references for poses and
## tests, never gameplay events and never physical limits.
const LANDMARK_HIGH_LOAD := -135.0
const LANDMARK_EARLY_DESCENT := -90.0
const LANDMARK_CENTRE := 0.0
const LANDMARK_TURNOVER := 30.0
const LANDMARK_SETTLED_END := 45.0

## Handling contexts the path distinguishes, and the transitions between them.
enum Context { GUARD, CHARGE, SWING, RECOVERY, STAGGER, DEATH }
## Every transition the path must cross continuously (no pose jump: position and
## orientation continuous across the change, derivative jumps bounded). Directed
## `Context` pairs, flattened (from, to, from, to, …); a transition not listed
## here never occurs.
const TRANSITIONS: PackedInt32Array = [
	Context.GUARD, Context.CHARGE,
	Context.CHARGE, Context.GUARD,
	Context.GUARD, Context.RECOVERY,
	Context.CHARGE, Context.SWING,
	Context.GUARD, Context.SWING,
	Context.SWING, Context.RECOVERY,
	Context.RECOVERY, Context.GUARD,
	Context.CHARGE, Context.RECOVERY,
	Context.GUARD, Context.STAGGER,
	Context.CHARGE, Context.STAGGER,
	Context.SWING, Context.STAGGER,
	Context.RECOVERY, Context.STAGGER,
	Context.STAGGER, Context.GUARD,
	Context.GUARD, Context.DEATH,
	Context.CHARGE, Context.DEATH,
	Context.SWING, Context.DEATH,
	Context.RECOVERY, Context.DEATH,
	Context.STAGGER, Context.DEATH,
]
## Context changes the presentation does not blend across: it resets its
## interpolation history instead (a new round after a death, like a rematch or a
## teleport). Directed pairs, flattened.
const RESETS: PackedInt32Array = [
	Context.DEATH, Context.GUARD,
]

var mirror_policy: MirrorPolicy = MirrorPolicy.WEAPON_GEOMETRY_ONLY
var stance_degrees: PackedFloat64Array
var stance_raise: PackedFloat64Array
var stance_pitch_degrees: PackedFloat64Array
var load_raise: float
var load_pitch_degrees: float
var leave_stance_end: float
var descent_end: float
var x_high_degrees: PackedFloat64Array
var x_high_height: PackedFloat64Array
var roll_degrees: float
var roll_start: float
var roll_end: float
var cut_keys: PackedFloat64Array
var cut_pitch_degrees: PackedFloat64Array
var cut_raise: PackedFloat64Array
var load_handoff_start: float
var load_handoff_end: float
var far_handoff_start: float
var far_handoff_end: float
var inflection_enter: float
var inflection_leave: float
var inflection_rise_end: float
var inflection_min_speed: float

static var _reference: WeaponPathDefinition = null


## The reference longsword's path (shared, immutable: callers never write it).
static func reference_sword() -> WeaponPathDefinition:
	if _reference == null:
		var path := WeaponPathDefinition.new()
		path.stance_degrees = STANCE_DEGREES
		path.stance_raise = STANCE_RAISE
		path.stance_pitch_degrees = STANCE_PITCH_DEGREES
		path.load_raise = LOAD_RAISE
		path.load_pitch_degrees = LOAD_PITCH_DEGREES
		path.leave_stance_end = LEAVE_STANCE_END
		path.descent_end = DESCENT_END
		path.x_high_degrees = X_HIGH_DEGREES
		path.x_high_height = X_HIGH_HEIGHT
		path.roll_degrees = ROLL_DEGREES
		path.roll_start = ROLL_START
		path.roll_end = ROLL_END
		path.cut_keys = CUT_KEYS
		path.cut_pitch_degrees = CUT_PITCH_DEGREES
		path.cut_raise = CUT_RAISE
		path.load_handoff_start = LOAD_HANDOFF_START
		path.load_handoff_end = LOAD_HANDOFF_END
		path.far_handoff_start = FAR_HANDOFF_START
		path.far_handoff_end = FAR_HANDOFF_END
		path.inflection_enter = INFLECTION_ENTER
		path.inflection_leave = INFLECTION_LEAVE
		path.inflection_rise_end = INFLECTION_RISE_END
		path.inflection_min_speed = INFLECTION_MIN_SPEED
		_reference = path
	return _reference


## An independent copy (tables duplicated) for building a variant path.
func copy() -> WeaponPathDefinition:
	var out := WeaponPathDefinition.new()
	out.mirror_policy = mirror_policy
	for property: String in ["stance_degrees", "stance_raise", "stance_pitch_degrees", "x_high_degrees", "x_high_height", "cut_keys", "cut_pitch_degrees", "cut_raise"]:
		out.set(property, (get(property) as PackedFloat64Array).duplicate())
	for property: String in ["load_raise", "load_pitch_degrees", "leave_stance_end", "descent_end", "roll_degrees", "roll_start", "roll_end", "load_handoff_start", "load_handoff_end", "far_handoff_start", "far_handoff_end", "inflection_enter", "inflection_leave", "inflection_rise_end", "inflection_min_speed"]:
		out.set(property, get(property))
	return out


## Contract problems (empty when valid): every key table strictly increasing with
## a value per key, hand-offs and inflection thresholds ordered, the landmarks in
## cut order.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	for table: Array in [["stance", stance_degrees, [stance_raise, stance_pitch_degrees]], ["x_high", x_high_degrees, [x_high_height]], ["cut", cut_keys, [cut_raise, cut_pitch_degrees]]]:
		var keys: PackedFloat64Array = table[1]
		for i in range(1, keys.size()):
			if keys[i] <= keys[i - 1]:
				out.append("%s keys must increase" % table[0])
		for values: PackedFloat64Array in table[2]:
			if values.size() != keys.size():
				out.append("%s table needs one value per key" % table[0])
	if not (load_handoff_end < load_handoff_start and far_handoff_start < far_handoff_end):
		out.append("hand-offs must open outward")
	if not (inflection_leave < inflection_enter and inflection_enter < inflection_rise_end):
		out.append("inflection leave < enter < rise end")
	if not (LANDMARK_HIGH_LOAD < LANDMARK_EARLY_DESCENT and LANDMARK_EARLY_DESCENT < LANDMARK_CENTRE and LANDMARK_CENTRE < LANDMARK_TURNOVER and LANDMARK_TURNOVER < LANDMARK_SETTLED_END):
		out.append("landmarks must follow the cut")
	return out


## Whether the path declares the continuous transition `from` → `to` (directed).
static func allows(from: Context, to: Context) -> bool:
	return _listed(TRANSITIONS, from, to)


## Whether `from` → `to` is a declared reset (interpolation history restarts).
static func resets(from: Context, to: Context) -> bool:
	return _listed(RESETS, from, to)


static func _listed(pairs: PackedInt32Array, from: Context, to: Context) -> bool:
	for index in range(0, pairs.size(), 2):
		if pairs[index] == from and pairs[index + 1] == to:
			return true
	return false
