class_name SelfClearanceProfile
extends Resource

## A fighter's own-body clearance proxies and the gaps a pose must keep
## (PRES-POSE-001). Simple primitives in the rig's rest space, carried by their
## bones, a little larger than the visible clothes: they exist only to validate
## presentation poses — never combat geometry, never physics bodies.
##
## Torso shells are elliptic prisms (bone, bottom, top, half-width,
## half-depth); the head is a sphere on its bone. Gaps are metres of air from
## the proxy surface to a limb sample on its bone axis (the limb's own block
## half-thickness is part of the gap), or to the weapon's centre line.
##
## See also: /docs/concepts/presentation.md

## Wolf's clothing shells as `build_wolf.py` builds them: chest gambeson,
## lower gambeson, belt.
@export var torso_shells: Array = [
	[&"Chest", 1.19, 1.43, 0.22, 0.180],
	[&"Spine", 0.95, 1.21, 0.22, 0.185],
	[&"Hips", 0.95, 1.03, 0.20, 0.168],
]
@export var head_bone: StringName = &"Head"
## The head proxy's centre height in rest space, and its radius (skull plus a
## little air; the dome sits on this sphere). Tracks `body.head_z` 1.375 and
## `head_radius` 0.16 on a 0.24 m face tube: centre is the skull midpoint.
@export var head_center_height: float = 1.625
@export var head_radius: float = 0.175

## Air a hand, a wrist, and a forearm keep from the torso.
@export var min_hand_gap: float = 0.02
@export var min_forearm_gap: float = 0.02
## Elbows keep visibly more: they support the hands from outside the ribs.
@export var min_elbow_gap: float = 0.03
## The weapon's blade, guard, and pommel keep clear of the torso and head.
@export var min_weapon_gap: float = 0.02
