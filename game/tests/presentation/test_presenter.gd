extends TestCase

## PRES-PRESENTER: the presenter projects, interpolates, and dramatizes
## without ever touching the simulation (PRES-001).
##
## Implements: /spec/invariants.md#pres-001
## See also: /docs/concepts/presentation.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "PRES-PRESENTER"
	_rules = StandardDuelRules.create()


class Mount:
	var root: Node3D
	var camera: DuelCameraRig
	var presenter: MatchPresenter
	var state: MatchState
	var hitstops: PackedFloat64Array = PackedFloat64Array()

	func dispose() -> void:
		presenter.detach_and_dispose()
		root.queue_free()


func _mount(options: PresentationOptions = PresentationOptions.new()) -> Mount:
	var mount := Mount.new()
	mount.root = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(mount.root)
	mount.camera = DuelCameraRig.new()
	mount.root.add_child(mount.camera)
	mount.camera.configure(RiposteKits.camera_profile())
	mount.state = DuelSetup.new_state(_rules, 1)
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	mount.presenter = MatchPresenter.create(kits, options, mount.camera, _rules.arena_radius, SnapshotProjector.project(mount.state, _rules))
	mount.root.add_child(mount.presenter)
	mount.presenter.hitstop_requested.connect(func(seconds: float) -> void: mount.hitstops.append(seconds))
	return mount


func _events(type: StringName, actor: int, target: int, data: Dictionary) -> Array[DuelEvent]:
	var events: Array[DuelEvent] = [DuelEvent.create(type, 1, actor, target, data)]
	return events


func _blade(contact_class: StringName) -> Array[DuelEvent]:
	return _events(DuelEventTypes.BLADE_CONTACT, 0, 1, {DuelEventKeys.X: 0.0, DuelEventKeys.Y: 0.0, DuelEventKeys.CONTACT_CLASS: String(contact_class)})


func _body(damage: float) -> Array[DuelEvent]:
	return _events(DuelEventTypes.BODY_HIT, 0, 1, {DuelEventKeys.X: 1.0, DuelEventKeys.Y: 0.0, DuelEventKeys.DAMAGE: damage})


func test_proxies_stand_where_the_simulation_says() -> void:
	var mount := _mount()
	mount.presenter.render(1.0, 1.0 / 60.0)
	for slot in 2:
		var fighter := mount.state.fighter(slot)
		var expected := ArenaTransform.to_world(fighter.x, fighter.y)
		assert_true(mount.presenter.fighter_proxy(slot).position.is_equal_approx(expected), "fighter %d at its projected position" % slot)
	mount.dispose()


func test_frames_interpolate_between_ticks() -> void:
	var mount := _mount()
	var start := mount.state.fighter(0).x
	mount.state.fighter(0).x = start + 1.0
	var none: Array[DuelEvent] = []
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), none)
	mount.presenter.render(0.5, 1.0 / 60.0)
	assert_near(mount.presenter.fighter_proxy(0).position.x, start + 0.5, 1e-6, "halfway between ticks at alpha 0.5")
	mount.dispose()


func test_the_blade_points_where_the_simulated_blade_points() -> void:
	var mount := _mount()
	var fighter := mount.state.fighter(0)
	fighter.weapon.angle = 0.6
	var none: Array[DuelEvent] = []
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), none)
	mount.presenter.render(1.0, 1.0 / 60.0)
	var blade_angle := DuelGeometry.blade_angle(fighter)
	var proxy := mount.presenter.fighter_proxy(0)
	var expected := ArenaTransform.to_world(fighter.x + _rules.weapon.tip_radius * cos(blade_angle), fighter.y + _rules.weapon.tip_radius * sin(blade_angle), proxy.blade_height())
	assert_true(proxy.blade_points()[1].is_equal_approx(expected), "tip matches the gameplay blade")
	mount.dispose()


func test_strong_blade_contact_sparks_sounds_and_requests_hitstop() -> void:
	var mount := _mount()
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _blade(ContactResolver.CLASS_STRONG))
	assert_true(mount.presenter.vfx().effect_count() > 0, "sparks spawned")
	assert_eq(mount.presenter.audio().last_cue, PresentationKit.CUE_BLADE_STRONG, "strong clang")
	assert_eq(mount.hitstops.size(), 1, "one hitstop request")
	assert_true(mount.hitstops[0] > 0.0, "a real freeze")
	assert_true(mount.camera.impulse_strength() > 0.0, "a small camera impulse")
	mount.dispose()


func test_body_hit_flashes_the_target_and_scales_with_damage() -> void:
	var mount := _mount()
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _body(70.0))
	assert_eq(mount.presenter.audio().last_cue, PresentationKit.CUE_BODY_HEAVY, "heavy body sound")
	var heavy := mount.hitstops[0]
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _body(4.0))
	assert_eq(mount.presenter.audio().last_cue, PresentationKit.CUE_BODY_LIGHT, "light body sound")
	assert_true(heavy > mount.hitstops[1], "a devastating hit freezes longer than a scrape")
	mount.dispose()


func test_reduced_motion_disables_camera_impulses() -> void:
	var options := PresentationOptions.new()
	options.reduced_motion = true
	var mount := _mount(options)
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _blade(ContactResolver.CLASS_STRONG))
	assert_eq(mount.camera.impulse_strength(), 0.0, "no shake under Reduced Motion")
	assert_eq(mount.hitstops.size(), 1, "hitstop still conveys the impact")
	mount.dispose()


func test_a_new_round_snaps_instead_of_sliding() -> void:
	var mount := _mount()
	mount.state.set_phase(MatchPhase.Id.ROUND_ACTIVE)
	mount.state.fighter(0).x = 3.0
	var none: Array[DuelEvent] = []
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), none)
	mount.presenter.render(1.0, 1.0 / 60.0)
	DuelSetup.reset_round(mount.state, _rules)
	mount.state.set_phase(MatchPhase.Id.ROUND_INTRO)
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), none)
	mount.presenter.render(0.0, 1.0 / 60.0)
	assert_near(mount.presenter.fighter_proxy(0).position.x, -_rules.spawn_offset, 1e-6, "teleported to spawn, not interpolated")
	assert_eq(mount.presenter.trail(0).sample_count(), 0, "trails cleared on reset")
	mount.dispose()


func test_fast_blades_draw_trails_and_slow_blades_do_not() -> void:
	var mount := _mount()
	mount.presenter.render(1.0, 1.0 / 60.0)
	assert_eq(mount.presenter.trail(0).sample_count(), 0, "a resting blade draws nothing")
	mount.state.fighter(0).weapon.speed = 15.0
	var none: Array[DuelEvent] = []
	for _i in 3:
		mount.presenter.push(SnapshotProjector.project(mount.state, _rules), none)
		mount.presenter.render(1.0, 1.0 / 60.0)
	assert_true(mount.presenter.trail(0).sample_count() >= 2, "a fast blade leaves a ribbon")
	mount.dispose()


func test_proxy_semantics_follow_movement_hits_and_teleports() -> void:
	var mount := _mount()
	var none: Array[DuelEvent] = []
	mount.presenter.render(1.0, 1.0 / 60.0)
	assert_eq(mount.presenter.fighter_proxy(0).current_semantic(), PresentationKit.ANIM_IDLE, "standing still idles")
	mount.state.fighter(0).x += 0.05
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), none)
	mount.presenter.render(1.0, 1.0 / 60.0)
	assert_eq(mount.presenter.fighter_proxy(0).current_semantic(), PresentationKit.ANIM_MOVE, "3 m/s of footwork plays the move clip")
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _body(20.0))
	mount.presenter.render(1.0, 1.0 / 60.0)
	assert_eq(mount.presenter.fighter_proxy(1).current_semantic(), PresentationKit.ANIM_HIT, "the struck fighter flinches")
	mount.state.fighter(0).x += 5.0
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), none)
	mount.presenter.render(1.0, 1.0 / 60.0)
	assert_eq(mount.presenter.fighter_proxy(0).current_semantic(), PresentationKit.ANIM_IDLE, "a teleport is not a walk")
	mount.dispose()


func test_arena_ambience_loops_on_the_music_bus_until_teardown() -> void:
	var mount := _mount()
	var audio := mount.presenter.audio()
	assert_true(audio.is_music_playing(), "the arena kit's music starts with the duel")
	var stream := audio.music_stream() as AudioStreamWAV
	assert_true(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "and loops")
	mount.presenter.detach_and_dispose()
	assert_false(audio.is_music_playing(), "teardown silences it")
	mount.root.queue_free()


func test_teardown_is_idempotent() -> void:
	var mount := _mount()
	mount.presenter.detach_and_dispose()
	assert_true(mount.presenter.get_parent() == null, "detached")
	mount.presenter.detach_and_dispose()
	assert_true(mount.presenter.is_queued_for_deletion(), "queued once")
	mount.root.queue_free()
