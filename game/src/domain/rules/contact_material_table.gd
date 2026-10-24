class_name ContactMaterialTable
extends RefCounted

## How two materials meet (CONTACT-MATERIAL-001). Rules content: the same two
## surfaces may grip differently in another rule set, and a change here is a
## rules change (version bump). Resolution is for setup only — the rules cache
## each pair they need (`DuelRules`), keyed to `revision`.
##
## A pair with an entry uses it. Each entry may author friction, restitution,
## or both; what it leaves as NAN falls back:
##
## ```text
## friction     same surface: its own μ. Different: √(μ_a·μ_b) (Box2D's rule).
## restitution  the less elastic of the two, each at its own threshold.
## ```
##
## The geometric mean cannot hold steel–steel 0.20, steel–flesh 0.05 and
## flesh–flesh 0.30 at once, so today's pairs are entries and the mix is only
## for pairs nobody has authored yet.
##
## See also: /docs/concepts/combat.md

## Bumped by every authored change, so a cached pair is never stale.
var revision: int = 0
var _a := PackedStringArray()
var _b := PackedStringArray()
var _friction := PackedFloat64Array()
var _restitution := PackedFloat64Array()
## The first pair authored more than once, for `problem()`. Defining a pair
## twice is an authoring mistake — the second would silently win — so it fails
## closed rather than coalescing. Updating a pair's friction (`set_friction`)
## is not a redefinition and never trips this.
var _duplicate: String = ""


## Author how `a` meets `b` (either order). NAN leaves that term to the default.
## Authoring the same pair twice is a mistake the table remembers for
## `problem()`; it does not quietly let the last one win.
func define_pair(a: StringName, b: StringName, friction: float = NAN, restitution: float = NAN) -> void:
	if _find(a, b) >= 0 and _duplicate == "":
		_duplicate = "%s–%s" % [a, b]
	_upsert(a, b, friction, restitution)


## Author only the friction of `a` on `b`, keeping any authored restitution.
## Updating an existing pair is not a redefinition.
func set_friction(a: StringName, b: StringName, friction: float) -> void:
	var at := _find(a, b)
	_upsert(a, b, friction, _restitution[at] if at >= 0 else NAN)


## Write a pair's terms, appending it if new, overwriting it if present.
func _upsert(a: StringName, b: StringName, friction: float, restitution: float) -> void:
	var at := _find(a, b)
	if at < 0:
		_a.append(String(a))
		_b.append(String(b))
		_friction.append(friction)
		_restitution.append(restitution)
	else:
		_friction[at] = friction
		_restitution[at] = restitution
	revision += 1


func pair_count() -> int:
	return _a.size()


## The pair `a` meets `b` as. Allocates: setup only.
func resolve(a: ContactMaterial, b: ContactMaterial) -> ContactPair:
	var pair := ContactPair.new()
	pair.a = a
	pair.b = b
	if a.id == b.id:
		pair.friction = a.friction
	else:
		pair.friction = sqrt(a.friction * b.friction)
	var at := _find(a.id, b.id)
	if at >= 0:
		if not is_nan(_friction[at]):
			pair.friction = _friction[at]
		pair.restitution_override = _restitution[at]
	return pair


## Every authored entry, in authored order, for the rules' world fingerprint.
func digest(ints: PackedInt64Array, floats: PackedFloat64Array, names: PackedStringArray) -> void:
	ints.append(_a.size())
	for i in _a.size():
		names.append(_a[i])
		names.append(_b[i])
		floats.append(_friction[i])
		floats.append(_restitution[i])


## Why the table cannot run a duel, or "".
func problem() -> String:
	if _duplicate != "":
		return "the %s material pair is defined more than once" % _duplicate
	for i in _a.size():
		if _a[i] == "" or _b[i] == "":
			return "a material pair names no material"
		if not is_nan(_friction[i]) and (not is_finite(_friction[i]) or _friction[i] < 0.0 or _friction[i] > 1.0):
			return "the %s–%s friction is not in [0, 1]" % [_a[i], _b[i]]
		if not is_nan(_restitution[i]) and (not is_finite(_restitution[i]) or _restitution[i] < 0.0 or _restitution[i] > 1.0):
			return "the %s–%s restitution is not in [0, 1]" % [_a[i], _b[i]]
	return ""


func _find(a: StringName, b: StringName) -> int:
	var sa := String(a)
	var sb := String(b)
	for i in _a.size():
		if (_a[i] == sa and _b[i] == sb) or (_a[i] == sb and _b[i] == sa):
			return i
	return -1
