class_name FighterAnimationSelector
extends RefCounted

## Picks the one animation semantic a fighter body should show this frame,
## from facts the snapshot already carries. Pure: it chooses what to look
## like and never decides anything (PRES-001).
##
## Priority runs from what overrides the whole body to what only colours it:
## death, stagger, a fresh hurt, committed footwork (a burst), the weapon
## phases, then plain footwork resolved into the body's own frame, then idle.
##
## See also: /docs/concepts/presentation.md, /docs/reference/godot.md

## Ground speed (m/s) below which footwork reads as standing.
const MOVE_SPEED := 0.6


## `hurt` / `critical` are the proxy's own flinch timers (presentation-only).
## `finishing` holds the striker of a killing thrust in the run-through: the
## forward-burst lunge, held, until authored stab clips exist. Only ever true
## after a kill, so it can never freeze a living exchange.
static func select(row: PresentationFighter, hurt: bool, critical: bool, finishing: bool = false) -> StringName:
	if not row.is_alive():
		return PresentationKit.ANIM_DEATH
	if row.phase == CombatPhase.Id.STAGGER:
		return PresentationKit.ANIM_STAGGER
	if finishing:
		return PresentationKit.ANIM_DASH_FORWARD
	if critical:
		return PresentationKit.ANIM_CRITICAL
	if hurt:
		return PresentationKit.ANIM_HURT
	var dash := dash_semantic(row.burst)
	if dash != &"":
		return dash
	match row.phase:
		CombatPhase.Id.CHARGING, CombatPhase.Id.BIND:
			return PresentationKit.ANIM_CHARGE
		CombatPhase.Id.OVERSWING:
			return PresentationKit.ANIM_OVERSWING
		CombatPhase.Id.RECOVERY:
			return PresentationKit.ANIM_RECOVERY
	if CombatPhase.is_swinging(row.phase):
		return PresentationKit.ANIM_SWING
	return footwork_semantic(row.vx, row.vy, row.facing)


static func dash_semantic(kind: MovementGestureState.BurstKind) -> StringName:
	match kind:
		MovementGestureState.BurstKind.FORWARD_DASH:
			return PresentationKit.ANIM_DASH_FORWARD
		MovementGestureState.BurstKind.BACK_DASH:
			return PresentationKit.ANIM_DASH_BACK
		MovementGestureState.BurstKind.LEFT_STEP:
			return PresentationKit.ANIM_DASH_LEFT
		MovementGestureState.BurstKind.RIGHT_STEP:
			return PresentationKit.ANIM_DASH_RIGHT
	return &""


## Carried body velocity in the fighter's own frame: the larger of the
## forward and lateral components names the step. Gameplay facing `θ` points
## along `(cos θ, sin θ)`; the body's right is `(sin θ, −cos θ)`.
static func footwork_semantic(vx: float, vy: float, facing: float) -> StringName:
	if vx * vx + vy * vy < MOVE_SPEED * MOVE_SPEED:
		return PresentationKit.ANIM_IDLE
	var forward := vx * cos(facing) + vy * sin(facing)
	var right := vx * sin(facing) - vy * cos(facing)
	if absf(forward) >= absf(right):
		return PresentationKit.ANIM_MOVE_FORWARD if forward > 0.0 else PresentationKit.ANIM_MOVE_BACKWARD
	return PresentationKit.ANIM_ORBIT_RIGHT if right > 0.0 else PresentationKit.ANIM_ORBIT_LEFT
