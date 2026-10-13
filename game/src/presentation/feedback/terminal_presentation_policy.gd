class_name TerminalPresentationPolicy
extends RefCounted

## One terminal presentation per fighter, decided by authority, never by which
## request happened to be emitted first (PRES-TERMINAL-001). The simulation has
## already ordered a same-tick kill and ring-out (COMBAT-014) and the snapshot
## carries the result as `terminal_cause`; this filter keeps only the requests
## that agree with it:
##
## - KILLED   → the death presentation (and, through it, the death release);
## - RING_OUT → the fall trajectory and the airborne release;
## - both fighters out → each keeps their own.
##
## Pure: no nodes, no state.
##
## Implements: /spec/invariants.md#pres-terminal-001
## See also: /docs/concepts/presentation.md


## Drop every terminal request in `frame` that contradicts the authoritative
## cause in `snapshot`. Order-independent: shuffling the requests or the
## events behind them cannot change what survives.
static func filter(frame: FeedbackFrame, snapshot: PresentationSnapshot) -> void:
	var deaths: Array[DeathPresentationRequest] = []
	for request in frame.death_requests:
		if cause(snapshot, request.slot) == FighterState.Terminal.KILLED:
			deaths.append(request)
	frame.death_requests = deaths
	var falls: Array[FallPresentationRequest] = []
	for request in frame.fall_requests:
		if cause(snapshot, request.slot) == FighterState.Terminal.RING_OUT:
			falls.append(request)
	frame.fall_requests = falls
	## Death releases are queued with the death; the frame only ever carries the
	## airborne release of a ring-out.
	var drops: Array[WeaponDropRequest] = []
	for request in frame.weapon_drop_requests:
		if cause(snapshot, request.slot) == FighterState.Terminal.RING_OUT:
			drops.append(request)
	frame.weapon_drop_requests = drops


static func cause(snapshot: PresentationSnapshot, slot: int) -> FighterState.Terminal:
	return snapshot.fighter(slot).terminal_cause
