class_name FighterCatalog
extends RefCounted

## Every fighter the game ships, keyed by identity (CONTENT-001). A rule set
## asks for a fighter by id; it never reaches in and assembles one.
##
## The entries are written as a *size* plus a set of baseline quantities, not
## as a column of magic numbers. That is the whole point of CONTENT-002: a
## second build is a different scale, and the scaling laws — geometry linear,
## mass cubic, force squared, torque cubic — then produce its physics. Nobody
## hand-writes "and this one accelerates a bit less".
##
## Mass is the one default that content is expected to override. Volumetric
## mass assumes the same density throughout, which is a reasonable *starting*
## guess for a human body and a poor final answer for any particular one, so a
## lean or heavy build simply assigns `mass` after the frame is laid down and
## the derived accelerations follow (PHYS-005).
##
## See also: /docs/concepts/content.md, /docs/concepts/combat.md

## The baseline duelist's strength, measured at `size_scale = 1.0`. Forces in
## newtons and torques in newton-metres, never accelerations (PHYS-005):
## against the baseline 80 kg these are the ~22 / ~30 / ~70 m/s² the duel was
## tuned at, but authored this way a heavier build pays for its own mass
## instead of being handed the same acceleration for free.
const LOCOMOTION_FORCE_N := 1760.0
const BRAKING_FORCE_N := 2400.0
const BURST_FORCE_N := 5600.0
const TURN_TORQUE_NM := 175.0


static func of(id: StringName) -> FighterDefinition:
	if id == ContentIds.FIGHTER_DUELIST:
		return duelist()
	## Fail closed. An unknown id yields nothing rather than a plausible
	## substitute, and `DuelRules.is_valid()` then refuses the match.
	return null


## The normalized duelist (COMBAT §2): the fighter `scale = 1.0` means.
static func duelist() -> FighterDefinition:
	return duelist_at(1.0)


## The duelist at an arbitrary size. Shipping content is this at 1.0; the
## parameter is here because it is what makes the scaling laws real rather than
## decorative, and it is the surface the scaling proofs exercise.
static func duelist_at(size_scale: float) -> FighterDefinition:
	var fighter := FighterDefinition.new()
	fighter.id = ContentIds.FIGHTER_DUELIST

	fighter.height = PhysicalBaseline.fighter_height(size_scale)
	fighter.body_radius = PhysicalBaseline.fighter_radius(size_scale)
	fighter.mass = PhysicalBaseline.volumetric_mass(PhysicalBaseline.FIGHTER_MASS_KG, size_scale)
	## Solid cylinder about its own axis — a shape fact, so it does not scale.
	## With the baseline mass and footprint `moment_of_inertia()` is
	## ~2.92 kg·m², the scale `TURN_TORQUE_NM` is authored against.
	fighter.body_inertia_coefficient = 0.5

	fighter.locomotion_force = PhysicalBaseline.structural_scale(LOCOMOTION_FORCE_N, size_scale)
	fighter.braking_force = PhysicalBaseline.structural_scale(BRAKING_FORCE_N, size_scale)
	fighter.burst_force = PhysicalBaseline.structural_scale(BURST_FORCE_N, size_scale)
	## `α = τ / I_body` works out to ~60 rad/s² at the baseline.
	fighter.turn_torque = PhysicalBaseline.torque_scale(TURN_TORQUE_NM, size_scale)
	## How hard this fighter drives *any* weapon. A longer, stronger arm
	## applies more torque to the same sword; the sword never changes.
	fighter.weapon_torque_scale = PhysicalBaseline.torque_scale(1.0, size_scale)

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
	fighter.base_stamina = 100.0
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
	fighter.tracking_commit_penalty = 0.72
	fighter.overswing_tracking_penalty = 0.1
	fighter.min_move_authority = 0.25
	fighter.min_tracking = 0.12
	fighter.counter_rotation_penalty = 0.5
	fighter.counter_rotation_reference_rate = 3.0
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
