class_name MovementGestureState
extends RefCounted

## Authoritative footwork-gesture state (COMBAT §25.2). A double tap in one
## duel direction launches a short burst of footwork; this is everything the
## simulation remembers about where in that gesture a fighter is.
##
## It lives in `FighterState` rather than in a controller because the burst is
## derived from the command stream itself. Human, CPU, replay, and any future
## server re-simulation therefore reach the identical burst, and no client can
## claim "I double-tapped".
##
## Implements: /spec/invariants.md#move-002
## See also: /docs/concepts/controls.md

## Duel-axis sectors. NONE means the stick is inside the neutral band.
enum Direction { NONE, FORWARD, BACK, RIGHT, LEFT }

enum Mode { NORMAL, BURST, RECOVERY }

enum BurstKind { NONE, FORWARD_DASH, BACK_DASH, RIGHT_STEP, LEFT_STEP }

## Sector the intent is currently latched into, under hysteresis.
var sector: Direction = Direction.NONE
## How long it has been latched there. A deflection held longer than the tap
## window is a walk, not a tap, and can never complete a gesture.
var sector_ticks: int = 0

## The sector of the pending first tap, and the tick it was made on.
var last_direction: Direction = Direction.NONE
var first_tap_tick: int = -1
var awaiting_second_tap: bool = false
## Whether the intent has actually come back to **rest** since the first tap.
##
## This is deliberately not the same question as "which sector am I in". A
## released key or a lifted thumb goes to zero; an intent merely *passing*
## through the neutral band on its way from one heading to another does not.
## Without the distinction, any controller that steers continuously — the CPU,
## or a player rolling a thumb around the stick — earns dashes it never asked
## for, and since a burst overrides intent that punishes whoever changes their
## mind most often. Reacting faster must not make a fighter worse.
var returned_to_neutral: bool = true

var mode: Mode = Mode.NORMAL
var burst_kind: BurstKind = BurstKind.NONE
var burst_ticks_remaining: int = 0
## World-space heading, frozen when the burst starts: a forward dash must not
## bend to follow an opponent who circles away mid-dash.
var burst_dir_x: float = 0.0
var burst_dir_y: float = 0.0
## Recovery state (MOVE-002). After a forward dash ends (hit or miss), the
## fighter enters recovery with progressively returning authority.
var recovery_ticks_remaining: int = 0
var recovery_ticks_total: int = 0


func reset() -> void:
	sector = Direction.NONE
	sector_ticks = 0
	clear_pending()
	end_burst()
	_end_recovery()


## Forget the pending first tap. Called when it ages out, when it turns out to
## have been a hold, and when it is consumed by a burst.
func clear_pending() -> void:
	last_direction = Direction.NONE
	first_tap_tick = -1
	awaiting_second_tap = false
	returned_to_neutral = true


func end_burst() -> void:
	mode = Mode.NORMAL
	burst_kind = BurstKind.NONE
	burst_ticks_remaining = 0
	burst_dir_x = 0.0
	burst_dir_y = 0.0


## End the burst and enter recovery. Only FORWARD_DASH enters recovery;
## lateral steps and back dashes return to NORMAL immediately.
func end_burst_into_recovery(recovery_ticks: int) -> void:
	var was_forward := burst_kind == BurstKind.FORWARD_DASH
	burst_kind = BurstKind.NONE
	burst_ticks_remaining = 0
	burst_dir_x = 0.0
	burst_dir_y = 0.0
	if was_forward and recovery_ticks > 0:
		mode = Mode.RECOVERY
		recovery_ticks_remaining = recovery_ticks
		recovery_ticks_total = recovery_ticks
	else:
		mode = Mode.NORMAL


func _end_recovery() -> void:
	if mode == Mode.RECOVERY:
		mode = Mode.NORMAL
	recovery_ticks_remaining = 0
	recovery_ticks_total = 0


func is_bursting() -> bool:
	return mode == Mode.BURST


func is_recovering() -> bool:
	return mode == Mode.RECOVERY


## Progress through recovery: 0.0 at start, 1.0 at end. Used for progressive
## authority restoration (MOVE-002).
func recovery_progress() -> float:
	if recovery_ticks_total <= 0:
		return 1.0
	return 1.0 - float(recovery_ticks_remaining) / float(recovery_ticks_total)


static func kind_for(direction: Direction) -> BurstKind:
	match direction:
		Direction.FORWARD:
			return BurstKind.FORWARD_DASH
		Direction.BACK:
			return BurstKind.BACK_DASH
		Direction.RIGHT:
			return BurstKind.RIGHT_STEP
		Direction.LEFT:
			return BurstKind.LEFT_STEP
	return BurstKind.NONE


## True for the two dashes along the line between the fighters, which are
## stronger than a lateral slide-step because the whole body drives them.
static func is_axial(kind: BurstKind) -> bool:
	return kind == BurstKind.FORWARD_DASH or kind == BurstKind.BACK_DASH
