class_name FighterAnimationSelector
extends RefCounted

## Picks the one animation semantic a fighter body should show this frame,
## from facts the snapshot already carries. Pure: it chooses what to look
## like and never decides anything (PRES-001).
##
## Priority runs from what overrides the whole body to what only colours it:
## death, the ring fall, stagger, a fresh hurt, committed footwork (a burst), plain footwork
## whenever the body is actually moving, then — standing still — the weapon
## phases' support clips, then idle.
##
## Charging never replaces locomotion (PRES-LOCO-001): the weapon phases are
## an upper-body condition, which `CombatPoseModifier3D` supplies on top of
## whatever the legs are doing. So a fighter walking while charging keeps the
## gait (slower, because the rules slow them, and the clip follows actual
## speed), and the gait clip never restarts when the charge starts or ends —
## its phase runs straight through. The support clips carry the idle stance's
## legs, so a stationary charge is idle legs under a charged torso.
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
	if row.is_falling:
		return PresentationKit.ANIM_RING_FALL
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
	var footwork := footwork_semantic(row.vx, row.vy, row.facing)
	if footwork != PresentationKit.ANIM_IDLE:
		return footwork
	match row.phase:
		CombatPhase.Id.CHARGING:
			return PresentationKit.ANIM_CHARGE
		CombatPhase.Id.OVERSWING:
			return PresentationKit.ANIM_OVERSWING
		CombatPhase.Id.RECOVERY:
			return PresentationKit.ANIM_RECOVERY
	if CombatPhase.is_swinging(row.phase):
		return PresentationKit.ANIM_SWING
	return PresentationKit.ANIM_IDLE


## True for the semantics whose clip is a gait cycle, which plays at the
## fighter's actual ground speed.
static func is_locomotion(semantic: StringName) -> bool:
	match semantic:
		PresentationKit.ANIM_MOVE_FORWARD, PresentationKit.ANIM_MOVE_BACKWARD, PresentationKit.ANIM_ORBIT_LEFT, PresentationKit.ANIM_ORBIT_RIGHT:
			return true
		_:
			return false


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
