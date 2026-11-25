class_name ContactPresentation
extends RefCounted

## Where a sword contact's effects are drawn in 3D (CONTACT-PRESENTATION-001):
## one pure mapping from the snapshot's authoritative contact points to a
## rendered height for the sparks, the highlight and the contact audio.
##
## The combat plane owns the contact: its XY on the arena plane, each sword's
## yaw θ and each grip's horizontal place `C(θ)`. The drawn swords never move
## for it: each stays on its own continuous projection (height, pitch, roll)
## through contact onset, contact and release, so the visible meeting is a
## declared approximation of the exact planar one. The effects sit between
## the two drawn blades, at
##
## ```text
## z_contact = mean over touching points of ½(z_free,a + z_free,b)
## ```
##
## `z_free` being each sword's drawn height at the contact along its own blade
## (its body's own drawing, `WeaponPoseEvaluator`). Nothing here reads
## presentation back into the simulation.
##
## Implements: /spec/invariants.md#contact-presentation-001
## See also: /docs/concepts/presentation.md

var _pose := BladePose.new()
var _context := WeaponActionContext.new()
## One evaluator per body's drawing (`WeaponPresentationConfig`), so a free
## height is the drawn sword's own, never a second projection.
var _evaluators := {}


## Distance from the pommel along the blade axis (m) of a contact at blade
## `fraction` (0 at the crossguard, 1 at the point) — where on the drawn sword
## the contact lies.
static func along(fraction: float, weapon: WeaponDefinition) -> float:
	return lerpf(weapon.blade_base_radius, weapon.tip_radius, clampf(fraction, 0.0, 1.0))


## Height above the platform (m) of `row`'s drawn sword `distance` from its
## pommel under its free lift — what the fencer would show with no contact —
## drawn as `config` declares (the shared drawing on its own carriage when null).
func free_height(row: PresentationFighter, distance: float, blade_height: float, config: WeaponPresentationConfig = null) -> float:
	WeaponKinematics.pose_at(0.0, 0.0, 0.0, row.weapon_angle, row.combatant_spec, _pose)
	_context.read(row, row.swing_progress, row.charge, false)
	return _evaluator(row.combatant_spec, config).evaluate(_pose, row.weapon_angle, blade_height, _context).station(distance).y


func _evaluator(spec: CombatantPhysicsSpec, config: WeaponPresentationConfig) -> WeaponPoseEvaluator:
	var key: Object = spec
	if config != null:
		key = config
	if not _evaluators.has(key):
		_evaluators[key] = WeaponPoseEvaluator.new(spec, config)
	return _evaluators[key]


## The shared rendered height of this tick's contact (m above the platform),
## or NAN when there is none to draw: no touching point, or a fighter no longer
## standing to hold one. `configs` are the two bodies' drawings, by slot.
func contact_height(snapshot: PresentationSnapshot, blade_height: float, configs: Array[WeaponPresentationConfig] = []) -> float:
	if snapshot.contacts.is_empty() or snapshot.fighters.size() < 2:
		return NAN
	var a := snapshot.fighter(0)
	var b := snapshot.fighter(1)
	if not a.is_alive() or not b.is_alive() or a.is_falling or b.is_falling:
		return NAN
	var total := 0.0
	for contact in snapshot.contacts:
		var free_a := free_height(a, along(contact.fraction_a, a.weapon_definition), blade_height, configs[0] if configs.size() == 2 else null)
		var free_b := free_height(b, along(contact.fraction_b, b.weapon_definition), blade_height, configs[1] if configs.size() == 2 else null)
		total += (free_a + free_b) * 0.5
	return total / float(snapshot.contacts.size())
