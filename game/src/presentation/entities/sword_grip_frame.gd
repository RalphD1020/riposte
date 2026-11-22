class_name SwordGripFrame
extends RefCounted

## How one hand holds the handle, in the sword's own frame (PRES-GRIP-001).
## A grip is a position and an orientation: where the palm sits on the handle
## and how the hand is turned around it. The sword places the frame; the arm IK
## only reaches the wrist the frame implies; `GripHandsModifier3D` turns the
## hand to the frame. Pure and deterministic, built once when the sword binds.
##
## Sword frame (the displayed sword's mount): +Z down the handle toward the
## point, +X along the crossguard bar, +Y the flat's normal (up at rest).
##
## The common (handshake) grip, both hands: the fingers stack along the handle,
## so each hand's wide axis (its knuckle line) runs along the handle; the hand
## comes onto the handle from below and behind (`hand_axis`, wrist → palm) and
## the handle crosses the palm, never running down the hand's length. Left and
## right are two hands with their own measured axes, never one quaternion
## negated. The thumb grip is a different configuration and is not this one.
##
## See also: /docs/concepts/presentation.md

## Stable geometric labels of the sword frame. They name geometry only: which
## edge is the long (true) edge is a property of the grip that holds the sword
## (`SwordRig3D.cutting_edge`), never of an axis name.
const BLADE_AXIS := Vector3(0.0, 0.0, 1.0)
const CROSSGUARD_AXIS := Vector3(1.0, 0.0, 0.0)
const FLAT_NORMAL := Vector3(0.0, 1.0, 0.0)
enum Edge { A, B }


## The outward normal of `edge` in the sword frame: edge A on +X, edge B on −X.
static func edge_normal(edge: Edge) -> Vector3:
	return CROSSGUARD_AXIS if edge == Edge.A else -CROSSGUARD_AXIS


## Wrist → palm in the sword frame at bind, before any arm reads it: the hand
## hangs under the handle, 67° off it toward the point.
const COMMON_HAND_AXIS := Vector3(0.0, -0.92, 0.39)
## The common grip's range. The knuckle line stays on the handle always; within
## that the hand follows its arm (`aimed_hand_axis`): its tilt off the handle
## (the handle crosses the palm, never runs down the hand's length or square
## across the fingers) and its turn round the handle from hanging under it
## (never past the side onto the top: the inverted hand). A hand held rigid in
## the sword's frame measured 100–146° of wrist bend at the loads and sides.
const TILT_MIN := deg_to_rad(45.0)
const TILT_MAX := deg_to_rad(90.0)
const ROLL_LIMIT := deg_to_rad(100.0)
## Below this share of the arm off the handle's line its turn is undefined;
## the turn fades back to hanging under the handle.
const ROLL_FADE := Vector2(0.05, 0.25)


## The hand's orientation in the sword frame: the basis that carries the hand
## bone's local axes onto the grip. `hand_axis` is wrist → palm in the sword
## frame; `span_local` is the hand mesh's wide axis (its knuckle line) in the
## hand bone's own frame, perpendicular to the bone's +Y. The knuckle line is
## laid along the handle, toward the point.
static func hand_basis(hand_axis: Vector3, span_local: Vector3) -> Basis:
	var along := hand_axis.normalized()
	var span := (Vector3.BACK - along * along.dot(Vector3.BACK)).normalized()
	var target := Basis(span, along, span.cross(along))
	var local_span := (span_local - Vector3.UP * span_local.dot(Vector3.UP)).normalized()
	var local := Basis(local_span, Vector3.UP, local_span.cross(Vector3.UP))
	return (target * local.inverse()).orthonormalized()


## The grip's transform in the sword frame: the palm at `palm` on the handle,
## the hand turned by `hand_basis`. In this transform's own space the hand's
## local axes are the bone's, so the wrist sits at `wrist_offset`.
static func frame(palm: Vector3, hand_axis: Vector3, span_local: Vector3) -> Transform3D:
	return Transform3D(hand_basis(hand_axis, span_local), palm)


## Wrist → palm in the sword frame for an arm reaching along `arm` (shoulder →
## palm, sword frame): the arm's own direction, held inside the common grip's
## tilt and turn. Continuous in `arm`, so a sweeping sword never pops a hand.
static func aimed_hand_axis(arm: Vector3) -> Vector3:
	var reach := arm.normalized()
	var tilt := clampf(reach.angle_to(Vector3.BACK), TILT_MIN, TILT_MAX)
	var across := Vector3(reach.x, reach.y, 0.0)
	## Basis(+Z, r) carries straight down to (sin r, −cos r, 0).
	var roll := atan2(across.x, -across.y) * smoothstep(ROLL_FADE.x, ROLL_FADE.y, across.length())
	roll = clampf(roll, -ROLL_LIMIT, ROLL_LIMIT)
	var side := Basis(Vector3.BACK, roll) * Vector3.DOWN
	return (Vector3.BACK * cos(tilt) + side * sin(tilt)).normalized()


## Where the wrist sits in the grip's own space: one hand back down the hand.
## The legacy placement (a palm point assumed on the bone axis); an authored
## contact (`contact_target`) replaces it.
static func wrist_offset(hand_length: float) -> Vector3:
	return Vector3(0.0, -hand_length, 0.0)


## An authored hand contact (PRES-GRIP-001): the handle's own frame in the Hand
## bone's space — `edge` the weapon's edge axis (sword +X), `axis` the handle
## toward the point (sword +Z), `centre` where the handle's axis passes
## through the gripping hand. Right-handed: +Y is the flat's normal (Z × X).
static func contact_frame(axis: Vector3, edge: Vector3, centre: Vector3) -> Transform3D:
	var z := axis.normalized()
	var x := (edge - z * edge.dot(z)).normalized()
	return Transform3D(Basis(x, z.cross(x), z), centre)


## The Hand bone's transform in the sword frame for a grip station at
## `station` held through `contact` (T_hand = T_grip · T_contact⁻¹): the
## handle's frame lands on the station's (the sword's own axes), so the hand's
## orientation and its origin — the wrist the IK reaches — both come from the
## authored contact, applied once.
static func contact_target(station: Vector3, contact: Transform3D) -> Transform3D:
	return Transform3D(Basis.IDENTITY, station) * contact.affine_inverse()
