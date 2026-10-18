extends TestCase

## FRIEND: a host-authoritative casual match over a fake link. The guest does
## not step the duel. Disconnect abandons the session. This is not Steam and
## not a ranked result.
##
## See also: /docs/concepts/simulation.md


func _init() -> void:
	suite_name = "FRIEND"


func _authority() -> FriendAuthority:
	return FriendAuthority.open(StandardDuelRules.create(), 9)


func _join(authority: FriendAuthority) -> int:
	var note := MatchNote.join(authority.rules.version, MatchNote.BUILD_ID)
	var accepted := authority.accept_join(note)
	assert_true(accepted != null, "fixture: the join is accepted")
	return accepted.slot


func test_two_slots_share_one_authority_and_cannot_write_each_other() -> void:
	var authority := _authority()
	var first := _join(authority)
	var second := _join(authority)
	assert_eq(first, 0, "the host assigns the first slot")
	assert_eq(second, 1, "and the second")
	var stolen := MatchNote.pack(authority.session_id, 0, 1, PlayerCommand.create(authority.state.tick, 0.0, 1.0, true))
	assert_false(authority.submit(1, stolen), "slot 1 cannot submit slot 0's command")
	var own := MatchNote.pack(authority.session_id, 1, 1, PlayerCommand.create(authority.state.tick, 0.0, 1.0, true))
	assert_true(authority.submit(1, own), "slot 1 can submit its own")
	var snapshot := authority.tick()
	assert_eq(snapshot.extra, MatchNote.RESULT_LIVE, "the match is still live")
	assert_eq(ReplayVerifier.verify(authority.record, authority.rules), ReplayVerifier.VERIFIED, "the accepted log replays")


func test_a_missing_command_holds_the_move_and_adds_no_edge() -> void:
	var authority := _authority()
	_join(authority)
	_join(authority)
	var press := MatchNote.pack(authority.session_id, 0, 1, PlayerCommand.create(authority.state.tick, 0.0, 1.0))
	assert_true(authority.submit(0, press), "fixture: the move is accepted")
	authority.tick()
	var before := authority.record.tick_count()
	authority.tick()
	var held := authority.record.command_at(0, before)
	assert_eq(held.move_y, PlayerCommand.AXIS_MAX, "the last move is held")
	assert_false(held.attack_pressed or held.attack_released, "and no attack edge is invented")


func test_a_late_or_duplicate_command_is_refused() -> void:
	var authority := _authority()
	_join(authority)
	var stale := MatchNote.pack(authority.session_id, 0, 1, PlayerCommand.create(authority.state.tick - MatchNote.ACCEPT_WINDOW - 1, 1.0, 0.0, true))
	assert_false(authority.submit(0, stale), "a command outside the window is refused")
	var fresh := MatchNote.pack(authority.session_id, 0, 1, PlayerCommand.create(authority.state.tick, 1.0, 0.0, true))
	assert_true(authority.submit(0, fresh), "fixture: the next sequence is accepted")
	var again := MatchNote.pack(authority.session_id, 0, 1, PlayerCommand.create(authority.state.tick, 0.0, 0.0))
	assert_false(authority.submit(0, again), "the same sequence is not accepted twice")


func test_disconnect_abandons_without_a_winner_or_a_further_step() -> void:
	var authority := _authority()
	_join(authority)
	_join(authority)
	authority.tick()
	var before := StateHasher.hash_state(authority.state)
	authority.end_session(1)
	var snapshot := authority.tick()
	assert_eq(snapshot.extra, MatchNote.RESULT_ABANDONED, "the session is abandoned")
	assert_eq(snapshot.slot, FriendAuthority.NO_WINNER, "nobody is awarded the match")
	assert_eq(StateHasher.hash_state(authority.state), before, "the duel does not take another tick")
	var late := MatchNote.pack(authority.session_id, 0, 1, PlayerCommand.create(authority.state.tick, 0.0, 1.0, true))
	assert_false(authority.submit(0, late), "a finished session ignores new commands")


func test_the_wire_rejects_a_bad_size_or_version_and_the_link_can_delay() -> void:
	assert_true(MatchNote.from_bytes(PackedByteArray()) == null, "an empty packet is refused")
	var note := MatchNote.join(1, MatchNote.BUILD_ID)
	var raw := note.to_bytes()
	raw[1] = 0
	assert_true(MatchNote.from_bytes(raw) == null, "the wrong protocol version is refused")
	var authority := _authority()
	var other := MatchNote.join(authority.rules.version + 1, MatchNote.BUILD_ID)
	assert_true(authority.accept_join(other) == null, "a different rules version is refused")
	var link := FakeLink.new()
	link.delay = 2
	link.send(MatchNote.join(authority.rules.version, MatchNote.BUILD_ID))
	assert_eq(link.take().size(), 0, "a delayed note is not ready")
	link.advance(2)
	assert_eq(link.take().size(), 1, "it arrives after the delay")
	link.drop_remaining = 1
	link.send(MatchNote.join(authority.rules.version, MatchNote.BUILD_ID))
	link.advance(1)
	assert_eq(link.take().size(), 0, "a dropped note does not arrive")
	_join(authority)
	var ordered := FakeLink.new()
	ordered.send(MatchNote.pack(authority.session_id, 0, 1, PlayerCommand.idle(0)))
	ordered.send(MatchNote.pack(authority.session_id, 0, 2, PlayerCommand.idle(1)))
	var reversed := ordered.take_reversed()
	assert_eq(reversed[0].seq, 2, "fixture: the later note is delivered first")
	assert_false(authority.submit(0, reversed[0]), "sequence 2 cannot pass sequence 1")
	assert_true(authority.submit(0, reversed[1]), "sequence 1 is still the next command")


func test_leaving_the_local_host_stops_the_session() -> void:
	var session := MatchComposer.compose(MatchConfig.quick_play(MatchConfig.Difficulty.EASY, 3), HumanController.new())
	var host := LocalMatchHost.attach(session)
	var tick := session.state.tick
	host.step()
	assert_eq(session.state.tick, tick + 1, "the host advances the local duel")
	host.leave()
	var stopped := session.state.tick
	var events := host.step()
	assert_eq(events.size(), 0, "a left host does not step")
	assert_eq(session.state.tick, stopped, "and the duel stays where it was")
	assert_true(host.session == null, "the session is released")
