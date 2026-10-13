class_name ArmStructureProfile
extends Resource

## Where a fighter's elbows support their hands (PRES-ARMS-001), per landmark
## of the guard field. Each triple is a bulge off the shoulder→hand midpoint,
## in metres in the bladed stance frame: behind (away from the chest), outward,
## and below. `ElbowGuideField` blends the landmarks, projects the bulge
## perpendicular to that arm, and locks its sign away from the torso. Wolf
## tuning, judged by silhouette.
##
## See also: /docs/concepts/presentation.md

## Mid guard: moderate flex, elbows visibly wide.
@export var mid_behind: float = 0.08
@export var mid_outward: float = 0.22
@export var mid_below: float = 0.08
## Longpoint: the longest arms — less flex, less flare, still clear of the body.
@export var longpoint_behind: float = 0.08
@export var longpoint_outward: float = 0.09
@export var longpoint_below: float = 0.05
## High load: the attacking-side elbow flexes and opens outward to make room
## beside the shoulder; the support elbow flexes too, forward of the ribs.
@export var load_attack_behind: float = 0.14
@export var load_attack_outward: float = 0.2
@export var load_attack_below: float = 0.12
@export var load_support_behind: float = 0.1
@export var load_support_outward: float = 0.25
@export var load_support_below: float = 0.1
## Follow-through past centre, as the roles exchange.
@export var follow_behind: float = 0.12
@export var follow_outward: float = 0.13
@export var follow_below: float = 0.08
## The torso an elbow guide must keep clear of (stance frame, half-extents)
## and by how much.
@export var torso_half_width: float = 0.22
@export var torso_half_depth: float = 0.18
@export var elbow_clearance: float = 0.05
## How far past the guide the pole sits, along the guide's outward direction,
## so the pole plane stays well-conditioned even with the arm near straight.
@export var pole_reach: float = 0.3
