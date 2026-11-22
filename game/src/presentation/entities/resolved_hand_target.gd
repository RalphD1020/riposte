class_name ResolvedHandTarget
extends RefCounted

## One hand's resolved grip target for this update (PRES-GRIP-001): where the
## Hand bone belongs, as the weapon decides it, and what the arm pose already
## knows about reaching it. Resolved once per update by `CombatPoseModifier3D`
## from the displayed sword's grip frames (`T_hand = T_weapon · T_grip ·
## T_contact⁻¹`, built by `SwordGripFrame` at bind), before the IK; the IK
## reaches `target.origin` and `GripHandsModifier3D` turns the hand to
## `target.basis`. Nothing else decides where a hand goes or how it turns.
## Pure data, preallocated per hand, never written back to the weapon.
##
## See also: /docs/concepts/presentation.md

## Whether this update resolved the target (a body bound to a sword with its
## stance applied); until then consumers keep reading the grip frames.
var valid: bool = false
## The Hand bone's wanted global transform: origin = the wrist the IK reaches,
## basis = the hand's orientation on the handle.
var target := Transform3D.IDENTITY
## The elbow preference the IK bends toward (global): the authored pose's own
## elbow (`ElbowGuideField.clip_pole`) or the guide field's.
var elbow_pole := Vector3.ZERO
## How strongly the weapon holds this hand (1 locked … 0 released): the one
## grip-influence authority (`SwordRig3D.set_grip_influence`).
var influence: float = 1.0
## Shoulder → wrist distance over the arm chain's length; `feasible` when the
## chain can reach the wrist without stretching.
var reach: float = 0.0
var feasible: bool = true
## The wrist bend this target asks of the pose the arm arrives in (radians):
## the angle between the hand's long axis and the line from the pre-IK elbow
## to the wrist. Known before the IK; a large value means the authored pose,
## not the last pass, is wrong.
var predicted_wrist_bend: float = 0.0
## The rotation the hand pass applied on top of the IK's hand (radians): the
## contact being completed. Large values are investigated, never compensated.
var orientation_residual: float = 0.0
