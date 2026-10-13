class_name FighterStanceProfile
extends Resource

## How a fighter's body stands against the combat frame (PRES-STANCE-001).
## Simulation facing stays exactly opponent-forward and owns movement, the
## ±135° sword angle, and every contact; presentation turns the *body* into a
## bladed fighting stance on top of it:
##
##   visual body yaw = combat facing + stance blade + transient coil
##
## and counter-rotates the head back onto the opponent. The sword angle is
## never re-measured against the bladed chest — the sword is posed in the
## combat frame (`C(θ)`, yaw θ) — so blading the body cannot move the attack
## window or any threshold.
##
## Wolf: a fixed right-foot lead, deliberately normalized for a competitive
## game (historical German longsword often changes the lead with the side of
## the guard; Riposte does not — gathering-step footwork keeps the lead, and
## an attack can reverse as fast as its physics does). Positive yaw turns the
## body toward the fighter's left, bringing the right shoulder forward.
##
## See also: /docs/concepts/presentation.md

enum LeadSide { RIGHT, LEFT }

@export var lead_side: LeadSide = LeadSide.RIGHT
## The pelvis's blade relative to combat-forward (degrees).
@export var hip_yaw_degrees: float = 12.0
## The shoulder line's blade relative to combat-forward (degrees, total).
@export var chest_yaw_degrees: float = 22.5
## The most the sword may turn the chest off that blade in a settled guard
## (degrees, either side): wherever the sword rests in its arc the torso stays
## bladed, never squaring up behind it. The bigger coils are a charge's and a
## cut's.
@export var guard_coil_degrees: float = 2.5
## The most extra coil a charged load adds toward each side (degrees of chest
## yaw). The lead-side load gathers through the shoulders and elbows more than
## the torso; the rear-side load turns a little more.
@export var lead_load_coil_degrees: float = 10.0
@export var rear_load_coil_degrees: float = 14.0
## Where each foot's toe points relative to combat-forward (degrees, the same
## sign as the blade). The lead toe points mostly down the line into the
## fight; the rear foot opens outward. Each foot turns at its ankle, so the
## clip's foot placement and stance width are untouched (STANCE-FOOT-001).
@export var lead_foot_yaw_degrees: float = 8.0
@export var rear_foot_yaw_degrees: float = 25.0
## Where the elbows support the hands (PRES-ARMS-001). Null uses the built-in
## structure.
@export var arms: ArmStructureProfile


func arm_structure() -> ArmStructureProfile:
	return arms if arms != null else ArmStructureProfile.new()


## The fighter's own-body clearance proxies and gaps (PRES-POSE-001). Null
## uses the built-in (baseline fencer) proxies.
@export var clearance: SelfClearanceProfile


func self_clearance() -> SelfClearanceProfile:
	return clearance if clearance != null else SelfClearanceProfile.new()


## The shoulder line's total signed blade (radians): the torso's forward,
## which the elbow guides are built in.
func chest_yaw() -> float:
	return _signed(chest_yaw_degrees)


## The signed blade of the pelvis (radians; + turns toward the fighter's left).
func hip_yaw() -> float:
	return _signed(hip_yaw_degrees)


## The blade the spine and chest add above the pelvis (radians).
func upper_yaw() -> float:
	return _signed(chest_yaw_degrees - hip_yaw_degrees)


## The settled-guard coil cap, either side (radians).
func guard_coil() -> float:
	return deg_to_rad(guard_coil_degrees)


## How far the lead foot turns at its ankle off the pelvis's blade (signed
## radians), so its toe points `lead_foot_yaw_degrees` off combat-forward.
func lead_foot_turn() -> float:
	return _signed(lead_foot_yaw_degrees - hip_yaw_degrees)


## The same for the rear foot.
func rear_foot_turn() -> float:
	return _signed(rear_foot_yaw_degrees - hip_yaw_degrees)


## The held-load coil cap toward the side `sword_side` (−1 right, +1 left).
func load_coil(sword_side: float) -> float:
	var lead := -1.0 if lead_side == LeadSide.RIGHT else 1.0
	return deg_to_rad(lead_load_coil_degrees if sword_side * lead > 0.0 else rear_load_coil_degrees)


func _signed(degrees: float) -> float:
	return deg_to_rad(degrees) * (1.0 if lead_side == LeadSide.RIGHT else -1.0)
