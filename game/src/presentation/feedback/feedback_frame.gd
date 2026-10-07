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


func has_requests() -> bool:
	return (
		camera_requests.size() > 0 or hitstop_requests.size() > 0 or
		audio_requests.size() > 0 or vfx_requests.size() > 0 or
		fighter_requests.size() > 0 or weapon_requests.size() > 0
	)
