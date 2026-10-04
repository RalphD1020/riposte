class_name FighterDefinition
extends RefCounted

## Immutable fighter body and footwork semantics. Every value is authored in
## content (StandardDuelRules); defaults here are neutral. Units: meters,
## seconds, radians. Treat instances as frozen after creation.
##
## See also: /docs/concepts/combat.md
## Source: game/content/rules/standard_duel_rules.gd

var id: StringName = &""
## Gameplay footprint radius. Presentation derives body size from this.
var body_radius: float = 0.0
var max_health: float = 0.0

## Footwork. Desired velocity = input × max_speed × direction multiplier.
var max_speed: float = 0.0
var move_accel: float = 0.0
var brake_accel: float = 0.0
var speed_forward: float = 0.0
var speed_lateral: float = 0.0
var speed_backward: float = 0.0

## Facing. Rotation is never snapped (COMBAT §9).
var turn_speed_max: float = 0.0
var turn_accel: float = 0.0
var track_gain: float = 0.0

## Commitment penalties (COMBAT §20, §62): multiplier = 1 - penalty × K.
var translation_commit_penalty: float = 0.0
var accel_commit_penalty: float = 0.0
var tracking_commit_penalty: float = 0.0
var overswing_tracking_penalty: float = 0.0
var min_tracking: float = 0.0

## Counter-rotation (COMBAT §26): tracking × (1 - k × K × O), O from orbit rate.
var counter_rotation_penalty: float = 0.0
var counter_rotation_reference_rate: float = 0.0

## Stability B (COMBAT §36), smoothed toward a target each tick.
var stability_floor: float = 0.0
var stability_rate: float = 0.0
var stability_accel_weight: float = 0.0
var stability_turn_weight: float = 0.0

## Stagger: translation and tracking multipliers while staggered.
var stagger_translation: float = 0.0
var stagger_tracking: float = 0.0


func is_valid() -> bool:
	return (
		body_radius > 0.0
		and max_health > 0.0
		and max_speed > 0.0
		and move_accel > 0.0
		and brake_accel > 0.0
		and turn_speed_max > 0.0
		and turn_accel > 0.0
		and track_gain > 0.0
	)
