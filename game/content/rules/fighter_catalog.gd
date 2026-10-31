class_name FighterCatalog
extends RefCounted

## Every fighter the game ships, keyed by identity (CONTENT-001). A rule set
## asks for a fighter by id; it never reaches in and assembles one.
##
## A shipped fighter is authored as explicit physical facts — height, mass,
## push and hurt geometry, hands, the lying body — plus three actuator scales
## relative to the reference duelist (Wolf, 1.0 each):
##
## ```text
## strength_scale       weapon drive          × the weapon's authored torques
## traction_scale       locomotion, braking and burst force   × Wolf's N
## turn_support_scale   heading turn torque                   × Wolf's N·m
## ```
##
## The scales are an authoring convenience only: `resolve_actuators` turns them
## into forces and torques when the definition is built, and the simulation
## reads only the resolved SI values (CONTENT-002). Strength is no longer
## inferred from size; a big fighter is strong only if it is authored strong.
##
## `prototype_at(size)` is the old size-derived generator, kept for scaling
## proofs and quick prototypes — geometry linear, mass cubic, force squared,
## torque cubic. It is never how a shipped fighter is defined.
##
## See also: /docs/concepts/content.md, /docs/concepts/combat.md

## The reference duelist's strength (scale 1.0). Forces in newtons and torques
## in newton-metres, never accelerations (PHYS-005): against the reference
## 80 kg these are the ~22 / ~30 / ~70 m/s² the duel was tuned at, but authored
## this way a heavier build pays for its own mass instead of being handed the
## same acceleration for free.
const LOCOMOTION_FORCE_N := 1760.0
const BRAKING_FORCE_N := 2400.0
const BURST_FORCE_N := 5600.0
const TURN_TORQUE_NM := 175.0
## The reference duelist lying on the floor: half his 1.70 m lying length
## through his centre of mass, and his torso's thickness.
const LYING_HALF_LENGTH_M := 0.85
const LYING_RADIUS_M := 0.18
## The resolved physique document `from_physique` reads. The keys are the
## resolver's (`tools/character_modeling/character_modeling/physique.py`).
const PHYSIQUE_SCHEMA := "riposte.physique"
const PHYSIQUE_VERSION := 1
const PHYSIQUE_BODY := "body"
const PHYSIQUE_APPLIED := "applied"
const PHYSIQUE_HEIGHT := "height_m"
const PHYSIQUE_MASS := "mass_kg"
const PHYSIQUE_STRENGTH := "strength_scale"
const PHYSIQUE_TRACTION := "traction_scale"
const PHYSIQUE_TURN_SUPPORT := "turn_support_scale"
const PHYSIQUE_HURT := "hurt_radius_m"
const PHYSIQUE_PUSH := "push_radius_m"
const PHYSIQUE_GRIP := "grip_radius_m"
const PHYSIQUE_HAND := "hand_radius_m"
const PHYSIQUE_LYING_HALF_LENGTH := "lying_half_length_m"
const PHYSIQUE_LYING_RADIUS := "lying_radius_m"
const PHYSIQUE_APPLIED_KEYS: Array[String] = [
	PHYSIQUE_MASS, PHYSIQUE_STRENGTH, PHYSIQUE_TRACTION, PHYSIQUE_TURN_SUPPORT,
	PHYSIQUE_HURT, PHYSIQUE_PUSH, PHYSIQUE_GRIP, PHYSIQUE_HAND,
	PHYSIQUE_LYING_HALF_LENGTH, PHYSIQUE_LYING_RADIUS,
]


static func of(id: StringName) -> FighterDefinition:
	if id == ContentIds.FIGHTER_DUELIST:
		return duelist()
	## Fail closed. An unknown id yields nothing rather than a plausible
	## substitute, and the loadout then refuses the match.
	return null


## The reference duelist, Wolf (COMBAT §2): the fighter every scale is 1.0 of.
static func duelist() -> FighterDefinition:
	var fighter := FighterDefinition.new()
	fighter.id = ContentIds.FIGHTER_DUELIST
	_author_body(
		fighter,
		PhysicalBaseline.FIGHTER_HEIGHT_M,
		PhysicalBaseline.FIGHTER_MASS_KG,
		PhysicalBaseline.FIGHTER_RADIUS_M,
		PhysicalBaseline.TORSO_HURT_RADIUS_M,
		PhysicalBaseline.HAND_PROXY_RADIUS_M,
		PhysicalBaseline.GRIP_RADIUS_M,
		LYING_HALF_LENGTH_M,
		LYING_RADIUS_M
	)
	resolve_actuators(fighter, 1.0, 1.0, 1.0)
	_semantics(fighter)
	fighter.precompute()
	return fighter


## A fighter authored from a resolved physique (`riposte.physique`, written by
## `tools/character_modeling` from a profile's height, frame build and
## muscularity). The resolver is the only formula: this reads its applied
## values and passes them through the same body facts and `resolve_actuators`
## every fighter uses. Proposed values (stamina) and readings are never read.
## Null when the document is malformed or breaks `0 < hurt <= push`; the
## reason is `physique_problem`. Nothing is clamped.
static func from_physique(id: StringName, physique: Dictionary) -> FighterDefinition:
	if physique_problem(physique) != "":
		return null
	var body: Dictionary = physique[PHYSIQUE_BODY]
	var applied: Dictionary = physique[PHYSIQUE_APPLIED]
	var fighter := FighterDefinition.new()
	fighter.id = id
	_author_body(
		fighter,
		float(body[PHYSIQUE_HEIGHT]),
		float(applied[PHYSIQUE_MASS]),
		float(applied[PHYSIQUE_PUSH]),
		float(applied[PHYSIQUE_HURT]),
		float(applied[PHYSIQUE_HAND]),
		float(applied[PHYSIQUE_GRIP]),
		float(applied[PHYSIQUE_LYING_HALF_LENGTH]),
		float(applied[PHYSIQUE_LYING_RADIUS])
	)
	resolve_actuators(fighter, float(applied[PHYSIQUE_STRENGTH]), float(applied[PHYSIQUE_TRACTION]), float(applied[PHYSIQUE_TURN_SUPPORT]))
	_semantics(fighter)
	fighter.precompute()
	return fighter


## Why a physique document cannot author a fighter, or "" when it can.
static func physique_problem(physique: Dictionary) -> String:
	if physique.get("schema") != PHYSIQUE_SCHEMA or int(physique.get("version", -1)) != PHYSIQUE_VERSION:
		return "a physique must be %s version %d" % [PHYSIQUE_SCHEMA, PHYSIQUE_VERSION]
	if typeof(physique.get(PHYSIQUE_BODY)) != TYPE_DICTIONARY or typeof(physique.get(PHYSIQUE_APPLIED)) != TYPE_DICTIONARY:
		return "a physique needs its body and applied values"
	var body: Dictionary = physique[PHYSIQUE_BODY]
	var applied: Dictionary = physique[PHYSIQUE_APPLIED]
	if not _positive_finite(body.get(PHYSIQUE_HEIGHT)):
		return "body.%s must be a positive number" % PHYSIQUE_HEIGHT
	for key: String in PHYSIQUE_APPLIED_KEYS:
		if not _positive_finite(applied.get(key)):
			return "applied.%s must be a positive number" % key
	if float(applied[PHYSIQUE_HURT]) > float(applied[PHYSIQUE_PUSH]):
		return "hurt_radius must not exceed push_radius"
	return ""


static func _positive_finite(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value)) and float(value) > 0.0


## The body facts every fighter states, in one place: geometry, mass, the hands
## and the lying body. Hand mass follows body mass by the reference share.
static func _author_body(fighter: FighterDefinition, height: float, mass: float, push_radius: float, hurt_radius: float, hand_radius: float, grip_radius: float, lying_half_length: float, lying_radius: float) -> void:
	fighter.height = height
	fighter.push_radius = push_radius
	fighter.hurt_radius = hurt_radius
	fighter.hand_radius = hand_radius
	fighter.grip_radius = grip_radius
	fighter.mass = mass
	fighter.hand_mass = mass * PhysicalBaseline.HAND_REFLECTED_MASS_SHARE
	## Solid cylinder about its own axis. With the reference mass and footprint
	## `moment_of_inertia()` is ~2.92 kg·m², the scale `TURN_TORQUE_NM` is
	## authored against.
	fighter.body_inertia_coefficient = 0.5
	fighter.lying_half_length = lying_half_length
	fighter.lying_radius = lying_radius
	fighter.material = MaterialCatalog.flesh()


## Resolve authored actuator scales into the forces and torques the
## simulation reads. The one place a scale ever multiplies a reference value.
static func resolve_actuators(fighter: FighterDefinition, strength_scale: float, traction_scale: float, turn_support_scale: float) -> void:
	fighter.locomotion_force = LOCOMOTION_FORCE_N * traction_scale
	fighter.braking_force = BRAKING_FORCE_N * traction_scale
	fighter.burst_force = BURST_FORCE_N * traction_scale
	## `α = τ / I_body` works out to ~60 rad/s² for the reference duelist.
	fighter.turn_torque = TURN_TORQUE_NM * turn_support_scale
	## How hard this fighter drives *any* weapon. A stronger arm applies more
	## torque to the same sword; the sword never changes.
	fighter.weapon_torque_scale = strength_scale


## A prototype duelist at an arbitrary size: the reference body scaled by the
## CONTENT-002 laws, with strength, traction and turn support derived from
## size (`torque_scale` / `structural_scale`). For scaling proofs and
## prototypes only — a fighter that ships authors its own body and scales.
static func prototype_at(size_scale: float) -> FighterDefinition:
	var fighter := FighterDefinition.new()
	fighter.id = ContentIds.FIGHTER_DUELIST
	_author_body(
		fighter,
		PhysicalBaseline.fighter_height(size_scale),
		PhysicalBaseline.volumetric_mass(PhysicalBaseline.FIGHTER_MASS_KG, size_scale),
		PhysicalBaseline.fighter_radius(size_scale),
		PhysicalBaseline.torso_hurt_radius(size_scale),
		PhysicalBaseline.hand_proxy_radius(size_scale),
		PhysicalBaseline.fighter_grip(size_scale),
		LYING_HALF_LENGTH_M * size_scale,
		LYING_RADIUS_M * size_scale
	)
	resolve_actuators(
		fighter,
		PhysicalBaseline.torque_scale(1.0, size_scale),
		PhysicalBaseline.structural_scale(1.0, size_scale),
		PhysicalBaseline.torque_scale(1.0, size_scale)
	)
	_semantics(fighter)
	fighter.precompute()
	return fighter


## Everything that is a decision about how this fighter *fights* rather than
## how large they are. None of it scales: size changes physical inputs, and
## the physical equations produce the gameplay outputs (COMBAT §46). Reaction,
## timing windows, and tracking in particular must never move with size
## (PHYS-005) — a bigger fighter is not a dimmer one.
static func _semantics(fighter: FighterDefinition) -> void:
	fighter.max_health = 100.0
	fighter.max_speed = 4.2
	fighter.speed_forward = 1.0
	fighter.speed_lateral = 0.92
	fighter.speed_backward = 0.78
	fighter.turn_speed_max = 9.0
	fighter.track_gain = 14.0
	## Commitment buys positional debt by spending authority, never speed: a
	## fully committed fighter keeps whatever stride they had and loses two
	## thirds of their ability to change it.
	fighter.accel_commit_penalty = 0.66
	## A fully committed cut keeps ~18 % of its turning authority: a side-step
	## outside its heading stays outside long enough to punish (HEADING-001).
	fighter.min_move_authority = 0.25
	fighter.stability_floor = 0.35
	fighter.stability_rate = 3.0
	fighter.stability_accel_weight = 0.35
	fighter.stability_turn_weight = 0.25
	fighter.stagger_translation = 0.55
	fighter.stagger_tracking = 0.35
	## Burst footwork. The windows are small on purpose: ~150 ms to get the
	## second tap in, and a deflection held past ~150 ms is read as walking.
	fighter.burst_enter_deflection = 0.75
	fighter.burst_neutral_deflection = 0.25
	## A released key and a lifted thumb are both exactly zero, so this only
	## has to be forgiving enough for a thumb resting near the stick centre.
	fighter.burst_rest_deflection = 0.1
	fighter.tap_window_ticks = 9
	fighter.double_tap_window_ticks = 13
	## A sixth of a second of hard push. Long enough to change the measure,
	## short enough that it cannot be used to run a duel.
	fighter.burst_ticks = 10
	fighter.burst_speed_axial = 8.4
	fighter.burst_speed_lateral = 6.6
	fighter.dash_recovery_ticks = 6
