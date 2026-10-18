class_name LocalMatchHost
extends RefCounted

## The local Quick Play authority. It is the only object the match screen
## asks to advance the duel. Leaving it drops the session; a later step does
## not keep simulating. This is not a remote host and it does not open a socket.
##
## See also: /docs/concepts/simulation.md

var session: MatchSession
var left: bool = false


static func attach(match: MatchSession) -> LocalMatchHost:
	var host := LocalMatchHost.new()
	host.session = match
	return host


func step() -> Array[DuelEvent]:
	if left or session == null:
		var none: Array[DuelEvent] = []
		return none
	return session.step()


func leave() -> void:
	left = true
	session = null
