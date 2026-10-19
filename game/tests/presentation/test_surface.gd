extends TestCase

## PRES-SURFACE: the sand mask is presentation. Stamps read the snapshot and
## the events. Rounds keep the marks. A new presenter starts covered.
##
## See also: /docs/concepts/presentation.md


func _init() -> void:
	suite_name = "PRES-SURFACE"


func test_a_fresh_mask_is_covered_and_a_stamp_wears_it_down() -> void:
	var surface := ArenaSurfaceState.create(8.27)
	assert_eq(surface.resolution(), ArenaSurfaceState.RESOLUTION, "the fighting mask is 256")
	assert_eq(surface.coverage_sim(0.0, 0.0), 255, "the arena starts under sand")
	assert_eq(surface.update_count(), 0, "building the texture is not a stamp upload")
	assert_true(surface.stamp_circle(Vector2(1.0, 0.5), 0.4, 80.0), "a stamp on the disc changes coverage")
	var center := surface.coverage_sim(1.0, 0.5)
	var edge := surface.coverage_sim(1.0 + 0.32, 0.5)
	assert_true(center < edge, "the middle of a stamp wears more than its rim")
	assert_true(center > 0, "one stamp does not clear the wood")
	surface.stamp_circle(Vector2(1.0, 0.5), 0.4, 80.0)
	surface.flush()
	assert_eq(surface.update_count(), 1, "several stamps in one tick upload once")
	var worn := surface.coverage_sim(1.0, 0.5)
	for _step: int in 6:
		surface.stamp_circle(Vector2(1.0, 0.5), 0.4, 255.0)
	surface.flush()
	assert_eq(surface.coverage_sim(1.0, 0.5), 0, "coverage clamps at bare wood")
	assert_true(worn >= surface.coverage_sim(1.0, 0.5), "another stamp never puts sand back")
	var before := surface.update_count()
	assert_false(surface.stamp_circle(Vector2(30.0, 0.0), 0.5, 255.0), "a stamp outside the disc does nothing")
	surface.flush()
	assert_eq(surface.update_count(), before, "a no-op stamp does not upload")
	surface.free()


func test_a_known_sim_point_lands_on_its_cell() -> void:
	var surface := ArenaSurfaceState.create(8.27)
	surface.stamp_circle(Vector2(4.0, 0.0), 0.25, 90.0)
	surface.flush()
	assert_true(surface.coverage_sim(4.0, 0.0) < 255, "sim +x wears the east cell")
	assert_eq(surface.coverage_sim(0.0, 4.0), 255, "the north cell is a different place")
	var coarse := ArenaSurfaceState.create(8.27, 128)
	assert_eq(coarse.resolution(), 128, "the comparison mask is the coarser grid")
	coarse.free()
	surface.free()


func test_walking_waits_for_a_stride_and_a_burst_does_not_add_a_step() -> void:
	var surface := ArenaSurfaceState.create(8.27)
	var still := _fighter(0, 0.0, 0.0, 0.0, 0.0)
	for _step: int in 30:
		surface.consume(_pair(still), [])
	assert_eq(surface.coverage_sim(0.0, 0.0), 255, "a stationary fighter leaves no print")
	assert_eq(surface.update_count(), 0, "and does not upload")
	var walker := _fighter(0, 0.0, 0.0, 2.0, 0.0)
	var ticks := int(ceil(ArenaSurfaceState.STRIDE / (2.0 * SimulationTimebase.TICK_SECONDS)))
	for _step: int in ticks:
		surface.consume(_pair(walker), [])
	assert_true(surface.coverage_sim(0.0, -ArenaSurfaceState.FOOT_OFFSET) < 255, "a stride plants one foot")
	assert_eq(surface.update_count(), 1, "that plant uploads once")
	var dead := _fighter(0, 0.0, 0.0, 4.0, 0.0)
	dead.health = 0.0
	var fallen := _fighter(0, 1.0, 0.0, 4.0, 0.0)
	fallen.is_falling = true
	var outside := _fighter(0, 9.0, 0.0, 4.0, 0.0)
	for _step: int in ticks:
		surface.consume(_pair(dead), [])
		surface.consume(_pair(fallen), [])
		surface.consume(_pair(outside), [])
	assert_eq(surface.update_count(), 1, "a dead, falling, or outside fighter does not keep walking")
	var burst := _fighter(0, 1.2, 0.3, 0.0, 0.0)
	var events: Array[DuelEvent] = [DuelEvent.create(DuelEventTypes.BURST_STARTED, 1, 0, DuelEvent.NONE, {
		DuelEventKeys.HEADING_X: 1.0,
		DuelEventKeys.HEADING_Y: 0.0,
	})]
	surface.consume(_pair(burst), events)
	assert_true(surface.coverage_sim(1.2, 0.3) < 255, "a burst scuffs along its heading")
	var after_burst := surface.update_count()
	var quiet: Array[DuelEvent] = []
	surface.consume(_pair(burst), quiet)
	assert_eq(surface.update_count(), after_burst, "a still fighter does not add a walking step after the burst")
	var other := _fighter(1, -1.0, 0.4, 0.0, 0.0)
	var both := _pair(burst)
	both.fighters[1] = other
	var pair_events: Array[DuelEvent] = [
		DuelEvent.create(DuelEventTypes.BURST_STARTED, 2, 0, DuelEvent.NONE, {DuelEventKeys.HEADING_X: 1.0, DuelEventKeys.HEADING_Y: 0.0}),
		DuelEvent.create(DuelEventTypes.BURST_STARTED, 2, 1, DuelEvent.NONE, {DuelEventKeys.HEADING_X: 0.0, DuelEventKeys.HEADING_Y: 1.0}),
	]
	var before_pair := surface.update_count()
	surface.consume(both, pair_events)
	assert_true(surface.coverage_sim(1.2, 0.3) < 255 and surface.coverage_sim(-1.0, 0.4) < 255, "both fighters mark the same mask")
	assert_eq(surface.update_count(), before_pair + 1, "one tick uploads once")
	surface.free()


func test_a_kill_stamps_once_and_a_round_keeps_the_mask() -> void:
	var surface := ArenaSurfaceState.create(8.27)
	var body := _fighter(0, 0.0, 0.0, 0.0, 0.0)
	body.health = 0.0
	var kill := DuelEvent.create(DuelEventTypes.FIGHTER_KILLED, 4, 1, 0, {DuelEventKeys.X: 2.0, DuelEventKeys.Y: 0.4})
	var events: Array[DuelEvent] = [kill]
	surface.consume(_pair(body), events)
	var center := surface.coverage_sim(2.0, 0.4)
	var rim := surface.coverage_sim(2.0 + ArenaSurfaceState.KILL_RADIUS * 0.85, 0.4)
	assert_true(center < rim, "the kill wears the middle more than the feather")
	assert_true(center < 255 - 100, "the kill is one deep stamp")
	var marked := center
	var again: Array[DuelEvent] = []
	var intro := _pair(body)
	intro.phase = MatchPhase.Id.ROUND_INTRO
	surface.consume(intro, again)
	assert_eq(surface.coverage_sim(2.0, 0.4), marked, "the next round keeps the mark")
	var fresh := ArenaSurfaceState.create(8.27)
	assert_eq(fresh.coverage_sim(2.0, 0.4), 255, "a new presenter starts covered")
	fresh.free()
	surface.free()


func test_the_presenter_stamps_a_kill_through_push() -> void:
	var rules := StandardDuelRules.create()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	var rig := DuelCameraRig.new()
	var state := DuelSetup.new_state(rules, 3)
	var presenter := MatchPresenter.create(kits, PresentationOptions.new(), rig, rules.platform_radius, rules.edge_warning_inset, SnapshotProjector.project(state, rules))
	var kill := DuelEvent.create(DuelEventTypes.FIGHTER_KILLED, state.tick, 1, 0, {DuelEventKeys.X: 1.5, DuelEventKeys.Y: -0.2})
	var events: Array[DuelEvent] = [kill]
	presenter.push(SnapshotProjector.project(state, rules), events)
	var surface := (presenter.get_node("Arena") as ArenaScaffold).surface()
	assert_true(surface.coverage_sim(1.5, -0.2) < 255, "push sends the kill through the surface")
	var marked := surface.coverage_sim(1.5, -0.2)
	var intro := SnapshotProjector.project(state, rules)
	intro.phase = MatchPhase.Id.ROUND_INTRO
	var none: Array[DuelEvent] = []
	presenter.push(intro, none)
	assert_eq(surface.coverage_sim(1.5, -0.2), marked, "a round intro does not clear the mask")
	var rematch := MatchPresenter.create(kits, PresentationOptions.new(), rig, rules.platform_radius, rules.edge_warning_inset, SnapshotProjector.project(state, rules))
	assert_eq((rematch.get_node("Arena") as ArenaScaffold).surface().coverage_sim(1.5, -0.2), 255, "a rematch presenter starts covered")
	var top := surface.get_node("Top") as MeshInstance3D
	var material := top.material_override as ShaderMaterial
	var texture := material.get_shader_parameter("coverage") as Texture2D
	assert_eq(texture.get_width(), ArenaSurfaceState.RESOLUTION, "the shader reads the mask")
	presenter.free()
	rematch.free()
	rig.free()


func _fighter(slot: int, sim_x: float, sim_y: float, vx: float, vy: float) -> PresentationFighter:
	var row := PresentationFighter.new()
	row.slot = slot
	row.health = 1.0
	row.x = sim_x
	row.y = sim_y
	row.vx = vx
	row.vy = vy
	return row


func _pair(mover: PresentationFighter) -> PresentationSnapshot:
	var snap := PresentationSnapshot.new()
	snap.phase = MatchPhase.Id.ROUND_ACTIVE
	var other := _fighter(1 if mover.slot == 0 else 0, 0.0, 2.0, 0.0, 0.0)
	if mover.slot == 0:
		snap.fighters = [mover, other]
	else:
		snap.fighters = [other, mover]
	return snap
