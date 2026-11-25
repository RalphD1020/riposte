class_name WeaponStationTopology
extends RefCounted
## WEAPON-PATH-004 Stage 4: which parts of a weapon are which, read from the
## weapon's own definition — never from where they are drawn. Where each
## region is comes from `WeaponPoseEvaluator`; what it is comes from here,
## and both are fixed by `WeaponDefinition` (STEEL-TOPOLOGY-001,
## GUARD-PROTECTION-001, DEFENSE-ROLE-001). Nothing here decides a contact:
## the planar solver keeps its own geometry and its own side reading; this
## only names the same regions so presentation can draw and audit them.
##
## Radii are metres from the pommel down the blade (the sword frame's +Z).
##
## See also: /docs/concepts/presentation.md

enum Kind { HANDLE, GUARD_ROOT, BLADE }


## One region of the weapon along its axis.
class Region:
	extends RefCounted
	var kind: Kind
	var from_radius: float
	var to_radius: float
	## Steel the solver holds against another sword (the handle never is).
	var steel: bool
	## Steel only against a blade from the point's side of the bar (the guard
	## root); the blade's own steel holds from either side.
	var protected_side_only: bool
	## Whether a contact on it can be a successful defense of its wielder.
	var protects: bool

	func _init(region_kind: Kind, start: float, end: float, is_steel: bool, one_sided: bool, defends: bool) -> void:
		kind = region_kind
		from_radius = start
		to_radius = end
		steel = is_steel
		protected_side_only = one_sided
		protects = defends


## The weapon's regions in order from the pommel: the handle (grip hurt
## geometry, both hands on it, never steel); the guard root from the bar to
## its apex (steel on its protected side, absent for a sword with no
## crossguard); the blade from the apex to the point (steel from either side).
static func regions(weapon: WeaponDefinition) -> Array[Region]:
	var out: Array[Region] = []
	var bar := weapon.crossguard_centre_radius if weapon.crossguard_half_span > 0.0 else weapon.blade_base_radius
	out.append(Region.new(Kind.HANDLE, 0.0, bar, false, false, false))
	var apex := weapon.guard_root_apex_radius()
	if weapon.crossguard_half_span > 0.0:
		out.append(Region.new(Kind.GUARD_ROOT, weapon.crossguard_centre_radius, apex, true, true, weapon.crossguard_protects))
	out.append(Region.new(Kind.BLADE, apex, weapon.tip_radius, true, false, weapon.blade_protects))
	return out


## The region holding the station `radius` down the blade (the last one that
## starts at or before it).
static func region_at(weapon: WeaponDefinition, radius: float) -> Region:
	var found: Region = null
	for region in regions(weapon):
		if radius >= region.from_radius:
			found = region
	return found


## The grip stations from the weapon's definition, dominant (right) first: both
## on the handle, the dominant hand nearer the guard.
static func grip_radii(weapon: WeaponDefinition) -> PackedFloat64Array:
	return PackedFloat64Array([weapon.dominant_grip_radius, weapon.offhand_grip_radius])
