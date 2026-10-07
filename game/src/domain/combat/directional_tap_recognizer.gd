class_name DirectionalTapRecognizer
extends RefCounted

## Reads double-tap footwork gestures straight out of the command stream
## (COMBAT §25.2). Pure: given the gesture state and this tick's intent, it
## advances the state machine and reports the burst that just became due.
##
## Direction is read in **duel axes**, so the gesture is semantic rather than
## literal: a thumbstick pushed into the forward sector and released back to
## neutral, twice, is the same gesture as `W → neutral → W`. Godot's
## `InputEventScreenTouch.double_tap` is deliberately unused, because the
## mechanic is "the same direction twice", not "the same screen point twice".
##
## Implements: /spec/invariants.md#move-002
## See also: /docs/concepts/controls.md


## Advance the gesture machine one tick. Returns the burst to launch, or
## `BurstKind.NONE`.
static func observe(
	gesture: MovementGestureState, intent_x: float, intent_y: float, tick: int, definition: FighterDefinition
) -> MovementGestureState.BurstKind:
	var next := _sector(gesture.sector, intent_x, intent_y, definition)
	if SimMath.length(intent_x, intent_y) <= definition.burst_rest_deflection:
		gesture.returned_to_neutral = true
	if next == gesture.sector:
		gesture.sector_ticks += 1
		## A deflection held past the tap window is a walk. Dropping the
		## pending tap here is what stops "hold W, then tap W" from dashing.
		if gesture.sector != MovementGestureState.Direction.NONE and gesture.sector_ticks > definition.tap_window_ticks:
			gesture.clear_pending()
		_expire(gesture, tick, definition)
		return MovementGestureState.BurstKind.NONE
	gesture.sector = next
	gesture.sector_ticks = 0
	if next == MovementGestureState.Direction.NONE:
		_expire(gesture, tick, definition)
		return MovementGestureState.BurstKind.NONE
	## A rising edge, and only a rising edge: the intent had to leave the
	## sector to get here, so key repeat and held input can never produce one.
	## It also had to come genuinely to rest in between, which is what
	## separates a deliberate tap from a controller steering through neutral.
	if (
		gesture.awaiting_second_tap
		and gesture.last_direction == next
		and gesture.returned_to_neutral
		and tick - gesture.first_tap_tick <= definition.double_tap_window_ticks
	):
		gesture.clear_pending()
		return MovementGestureState.kind_for(next)
	gesture.last_direction = next
	gesture.first_tap_tick = tick
	gesture.awaiting_second_tap = true
	gesture.returned_to_neutral = false
	return MovementGestureState.BurstKind.NONE


## Small windows on purpose. A long buffer fires a dash after the player has
## mentally moved on, which reads as the game moving on its own.
static func _expire(gesture: MovementGestureState, tick: int, definition: FighterDefinition) -> void:
	if gesture.awaiting_second_tap and tick - gesture.first_tap_tick > definition.double_tap_window_ticks:
		gesture.clear_pending()


## Which cardinal sector the intent is in, with hysteresis: a clear deflection
## is needed to enter one and a near-centred stick to leave it. Without the
## gap, an intent hovering on a boundary would chatter between sectors and
## manufacture gestures nobody made.
static func _sector(
	current: MovementGestureState.Direction, intent_x: float, intent_y: float, definition: FighterDefinition
) -> MovementGestureState.Direction:
	var magnitude := SimMath.length(intent_x, intent_y)
	if magnitude <= definition.burst_neutral_deflection:
		return MovementGestureState.Direction.NONE
	if magnitude < definition.burst_enter_deflection:
		return current
	if absf(intent_y) >= absf(intent_x):
		return MovementGestureState.Direction.FORWARD if intent_y > 0.0 else MovementGestureState.Direction.BACK
	return MovementGestureState.Direction.RIGHT if intent_x > 0.0 else MovementGestureState.Direction.LEFT


## The world heading a burst commits to, from the fighter's duel axis.
static func heading(fighter: FighterState, kind: MovementGestureState.BurstKind) -> PackedFloat64Array:
	match kind:
		MovementGestureState.BurstKind.FORWARD_DASH:
			return DuelGeometry.to_world(0.0, 1.0, fighter.duel_forward_x, fighter.duel_forward_y)
		MovementGestureState.BurstKind.BACK_DASH:
			return DuelGeometry.to_world(0.0, -1.0, fighter.duel_forward_x, fighter.duel_forward_y)
		MovementGestureState.BurstKind.RIGHT_STEP:
			return DuelGeometry.to_world(1.0, 0.0, fighter.duel_forward_x, fighter.duel_forward_y)
		MovementGestureState.BurstKind.LEFT_STEP:
			return DuelGeometry.to_world(-1.0, 0.0, fighter.duel_forward_x, fighter.duel_forward_y)
	return PackedFloat64Array([0.0, 0.0])
