class_name SoundCaptions
extends RefCounted

## Captions for the combat sounds that carry gameplay (COMBAT-READABILITY-001,
## UX-001): a player with the sound off reads the cue the mixer plays, from
## the same audio requests, so a caption can never disagree with what is
## heard. At most one per tick — the most significant sound by a fixed order —
## so a hit's layered takes or a clash's metal tail never stack text, and the
## physical hierarchy holds in words too: a tap reads smaller than a heavy
## clash, a heavy clash smaller than a hit.
##
## Swings, the charge's tension, footwork and decorative layers are not
## captioned: each is either already seen on the body or would be noise.
##
## Implements: /spec/invariants.md#combat-readability-001
## See also: /docs/concepts/presentation.md

## Seconds a caption stays up; the next one replaces it.
const HOLD_SECONDS := 1.2

## Lower is more significant. A cut's lead and trail takes share a rank, so the
## lead — appended first — names the hit.
const RANK := {
	PresentationKit.CUE_CRITICAL: 0,
	PresentationKit.CUE_BODY_HEAVY: 1,
	PresentationKit.CUE_BODY_LIGHT: 1,
	PresentationKit.CUE_BODY_THRUST: 2,
	PresentationKit.CUE_BODY_POKE: 3,
	PresentationKit.CUE_BLADE_STRONG: 4,
	PresentationKit.CUE_BLADE_SOLID: 5,
	PresentationKit.CUE_BLADE_LIGHT: 6,
	PresentationKit.CUE_FALL: 7,
	PresentationKit.CUE_WHIFF: 8,
}


## The caption for one tick's sounds, or "" when none of them is captioned.
static func pick(requests: Array[AudioCueRequest]) -> String:
	var best := -1
	var best_rank := RANK.size()
	for index in requests.size():
		var rank: int = RANK.get(requests[index].cue, RANK.size())
		if rank < best_rank:
			best_rank = rank
			best = index
	return "" if best < 0 else HudCopy.sound_caption(requests[best].cue)
