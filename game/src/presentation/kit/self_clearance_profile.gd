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
	[&"Chest", 1.10, 1.43, 0.20, 0.164],
	[&"Spine", 0.84, 1.12, 0.205, 0.172],
	[&"Hips", 0.93, 0.99, 0.215, 0.181],
]
@export var head_bone: StringName = &"Head"
## The head proxy's centre height in rest space, and its radius (with hair).
@export var head_center_height: float = 1.63
@export var head_radius: float = 0.15

## Air a hand, a wrist, and a forearm keep from the torso.
@export var min_hand_gap: float = 0.02
@export var min_forearm_gap: float = 0.02
## Elbows keep visibly more: they support the hands from outside the ribs.
@export var min_elbow_gap: float = 0.03
## The weapon's blade, guard, and pommel keep clear of the torso and head.
@export var min_weapon_gap: float = 0.02
