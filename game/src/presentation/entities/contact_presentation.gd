class_name ContactPresentation
extends RefCounted

## Where a sword contact is drawn in 3D (CONTACT-PRESENTATION-001): one pure
## mapping from the snapshot's authoritative contact points to a rendered
## height, shared by the drawn swords, the sparks and the contact audio so all
## three meet at one place.
##
## The combat plane owns the contact: its XY on the arena plane, each sword's
## yaw θ and each grip's horizontal place `C(θ)`. Presentation adds only a
## height. A pitched blade's ground projection is shorter than the blade
## (`d·cos p`), so a sword can pass through the authoritative contact point
## only while it is level there. So:
##
## ```text
## no contact   each sword at its own free lift (height, pitch, roll)
## contact      grip XY and yaw unchanged (authority)
##              pitch → 0 on each contacted sword
##              both swords at one shared height
##                  z_contact = mean over touching points of
##                              ½(z_free,a + z_free,b)
##              roll stays presentation (it never moves the centreline)
## ```
##
## `z_free` is each sword's height at the contact along its own blade under
## its free lift. Both swords at one height meet edge to edge exactly as the
## plane says they touch, so there is no over/under to decide. The swords are
## anchored at once; the bodies follow through the arm IK, and leaving a
## contact eases back to the free lift (the proxy's inertialization). Nothing
## here reads presentation back into the simulation.
##
## Implements: /spec/invariants.md#contact-presentation-001
## See also: /docs/concepts/presentation.md

var _field := CombatPresentationField.new()
var _pose := BladePose.new()


## Distance from the pommel along the blade axis (m) of a contact at blade
## `fraction` (0 at the crossguard, 1 at the point) — where on the drawn sword
## the contact lies.
static func along(fraction: float, weapon: WeaponDefinition) -> float:
	return lerpf(weapon.blade_base_radius, weapon.tip_radius, clampf(fraction, 0.0, 1.0))


## Height above the platform (m) of `row`'s drawn sword `distance` from its
## pommel under its free lift — what the fencer would show with no contact.
func free_height(row: PresentationFighter, distance: float, blade_height: float) -> float:
	WeaponKinematics.pose_at(0.0, 0.0, 0.0, row.weapon_angle, row.combatant_spec, _pose)
	_field.carriage_radius = row.combatant_spec.handling.carriage_radius
	_field.sample(row.weapon_angle, _pose.carriage_y, _pose.carriage_x, row.phase, row.swing_progress, row.charge, row.swing_charge, blade_height, row.cut_dir)
	return (_field.transform * Vector3(0.0, 0.0, distance)).y


## The shared rendered height of this tick's contact (m above the platform),
## or NAN when there is none to draw: no touching point, or a fighter no longer
## standing to hold one.
func contact_height(snapshot: PresentationSnapshot, blade_height: float) -> float:
	if snapshot.contacts.is_empty() or snapshot.fighters.size() < 2:
		return NAN
	var a := snapshot.fighter(0)
	var b := snapshot.fighter(1)
	if not a.is_alive() or not b.is_alive() or a.is_falling or b.is_falling:
		return NAN
	var total := 0.0
	for contact in snapshot.contacts:
		var free_a := free_height(a, along(contact.fraction_a, a.weapon_definition), blade_height)
		var free_b := free_height(b, along(contact.fraction_b, b.weapon_definition), blade_height)
		total += (free_a + free_b) * 0.5
	return total / float(snapshot.contacts.size())
