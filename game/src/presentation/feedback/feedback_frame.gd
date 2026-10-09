class_name FeedbackFrame
extends RefCounted

## One tick's worth of presentation requests, produced by CombatFeedbackDirector.
## Value-like: the director fills it, presenters consume it. No SceneTree
## dependency, no node references.
##
## Implements: /spec/invariants.md#pres-002
## See also: /docs/architecture/presentation-feedback.md

var camera_requests: Array[CameraShakeRequest] = []
var hitstop_requests: Array[HitstopRequest] = []
var audio_requests: Array[AudioCueRequest] = []
var vfx_requests: Array[VfxRequest] = []
var fighter_requests: Array[FighterCueRequest] = []
var weapon_requests: Array[WeaponCueRequest] = []
var slow_motion_requests: Array[SlowMotionRequest] = []
## Killing blows only: one per fighter the tick left not alive.
var death_requests: Array[DeathPresentationRequest] = []
## Ring-outs: one per fighter that crossed the edge this tick.
var fall_requests: Array[FallPresentationRequest] = []
## Swords leaving the hands: one per killing blow or ring-out this tick.
var weapon_drop_requests: Array[WeaponDropRequest] = []


func has_requests() -> bool:
	return (
		camera_requests.size() > 0 or hitstop_requests.size() > 0 or
		audio_requests.size() > 0 or vfx_requests.size() > 0 or
		fighter_requests.size() > 0 or weapon_requests.size() > 0 or
		slow_motion_requests.size() > 0 or death_requests.size() > 0 or
		fall_requests.size() > 0 or weapon_drop_requests.size() > 0
	)
