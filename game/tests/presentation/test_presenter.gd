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
	mount.presenter = MatchPresenter.create(kits, options, mount.camera, _rules.platform_radius, _rules.edge_warning_inset, SnapshotProjector.project(mount.state, _rules))
	mount.root.add_child(mount.presenter)
	mount.presenter.hitstop_requested.connect(func(seconds: float) -> void: mount.hitstops.append(seconds))
	return mount


func _kit_weapon() -> PresentationKit:
	return DuelKits.resolve(RiposteKits.build_catalog(), _rules).weapon


func _events(type: StringName, actor: int, target: int, data: Dictionary) -> Array[DuelEvent]:
	var events: Array[DuelEvent] = [DuelEvent.create(type, 1, actor, target, data)]
	return events


## The fixtures carry what the resolver carries, including the contact
## geometry: feedback is directional now, and a fixture that omitted the
## normal would be testing a contact that cannot physically occur.
func _blade(contact_class: StringName, intensity: float = 1.0) -> Array[DuelEvent]:
	return _events(
		DuelEventTypes.BLADE_CONTACT,
		0,
		1,
		{
			DuelEventKeys.X: 0.0,
			DuelEventKeys.Y: 0.0,
			DuelEventKeys.CONTACT_CLASS: String(contact_class),
			DuelEventKeys.INTENSITY: intensity,
			DuelEventKeys.NORMAL_X: 1.0,
			DuelEventKeys.NORMAL_Y: 0.0,
			DuelEventKeys.STRIKE_X: 0.0,
			DuelEventKeys.STRIKE_Y: 1.0,
		}
	)


func _body(damage: float, quality: float = 1.0, grade: SwingSemantics.Grade = SwingSemantics.Grade.HEAVY) -> Array[DuelEvent]:
	return _events(
		DuelEventTypes.BODY_HIT,
		0,
		1,
		{
			DuelEventKeys.X: 1.0,
			DuelEventKeys.Y: 0.0,
			DuelEventKeys.DAMAGE: damage,
			DuelEventKeys.QUALITY: quality,
			DuelEventKeys.GRADE: SwingSemantics.grade_label(grade),
			DuelEventKeys.NORMAL_X: 1.0,
			DuelEventKeys.NORMAL_Y: 0.0,
			DuelEventKeys.STRIKE_X: 0.0,
			DuelEventKeys.STRIKE_Y: 1.0,
			DuelEventKeys.PUSH: 2.0,
		}
	)


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
	assert_true(mount.camera.impulse_strength() <= CombatFeedbackDirector.IMPULSE_BLADE_MAX, "restrained: a clash is not an earthquake")
	mount.dispose()


func test_body_hit_flashes_the_target_and_scales_with_quality() -> void:
	var mount := _mount()
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _body(70.0, SwingSemantics.GRADE_DEVASTATING, SwingSemantics.Grade.DEVASTATING))
	assert_eq(mount.presenter.audio().last_cue, PresentationKit.CUE_BODY_HEAVY, "heavy body sound")
	var devastating := mount.hitstops[0]
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _body(4.0, 0.1, SwingSemantics.Grade.GRAZE))
	assert_eq(mount.presenter.audio().last_cue, PresentationKit.CUE_BODY_LIGHT, "light body sound")
	assert_true(devastating > mount.hitstops[1], "a devastating hit freezes longer than a scrape")
	assert_between(devastating, _kit_weapon().hitstop_devastating.x, _kit_weapon().hitstop_devastating.y, "inside the devastating band")
	assert_between(mount.hitstops[1], _kit_weapon().hitstop_body.x, _kit_weapon().hitstop_body.y, "and a graze inside the ordinary one")
	mount.dispose()


## The hard claim behind the whole impact ladder: it is sized by the physics,
## never by the label. A heavy swing that grazed must feel weaker than a light
## one that landed perfectly, because quality is what hitstop reads.
func test_a_heavy_graze_feels_weaker_than_a_perfect_light_hit() -> void:
	var mount := _mount()
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _body(40.0, 0.2, SwingSemantics.Grade.GRAZE))
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _body(6.0, 1.4, SwingSemantics.Grade.HEAVY))
	assert_true(mount.hitstops[1] > mount.hitstops[0], "the better-landed strike punctuates harder despite doing less damage")
	mount.dispose()


## Hitstop and camera both ride the clash, continuously. There is no step at a
## class boundary because there is no class in the mapping.
func test_a_harder_clash_punctuates_harder() -> void:
	var mount := _mount()
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _blade(ContactResolver.CLASS_LIGHT, 0.1))
	var soft := mount.hitstops[0]
	var soft_impulse := mount.camera.impulse_strength()
	mount.dispose()
	var harder := _mount()
	harder.presenter.push(SnapshotProjector.project(harder.state, _rules), _blade(ContactResolver.CLASS_STRONG, 1.0))
	assert_true(harder.hitstops[0] > soft, "a full deflection freezes longer than a graze")
	assert_true(harder.camera.impulse_strength() > soft_impulse, "and moves the camera more")
	assert_between(harder.hitstops[0], 0.0, _kit_weapon().hitstop_blade.y, "never past the authored band")
	harder.dispose()


## Blade feedback is directional: the camera leans the way the blow went
## rather than rattling at random, and the direction comes from the resolver's
## own normal rather than from presentation reconstructing the contact.
func test_impact_feedback_follows_the_carried_contact_direction() -> void:
	var mount := _mount()
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _blade(ContactResolver.CLASS_STRONG, 1.0))
	var lane_normal := Vector3(1.0, 0.0, 0.0)
	assert_true(mount.camera.impulse_direction().is_equal_approx(lane_normal), "lane +x is world +x")
	mount.dispose()
	var other := _mount()
	var flipped := _blade(ContactResolver.CLASS_STRONG, 1.0)
	flipped[0].data[DuelEventKeys.NORMAL_X] = 0.0
	flipped[0].data[DuelEventKeys.NORMAL_Y] = 1.0
	other.presenter.push(SnapshotProjector.project(other.state, _rules), flipped)
	## Lane north is world `-z`, which is the one place a sign error would
	## silently send every impact the wrong way.
	assert_true(other.camera.impulse_direction().is_equal_approx(Vector3(0.0, 0.0, -1.0)), "lane +y is world -z")
	other.dispose()


## A bind is a situation, not a quiet clash. It gets its own sound and
## deliberately no hitstop: the simulation has already stopped both blades
## dead, and freezing on top of that reads as a hitch.
func test_a_bind_sounds_like_itself_and_does_not_freeze() -> void:
	var mount := _mount()
	mount.presenter.push(
		SnapshotProjector.project(mount.state, _rules),
		_events(DuelEventTypes.BIND_STARTED, DuelEvent.NONE, DuelEvent.NONE, {DuelEventKeys.X: 0.0, DuelEventKeys.Y: 0.0, DuelEventKeys.INTENSITY: 0.2})
	)
	assert_eq(mount.presenter.audio().last_cue, PresentationKit.CUE_BIND, "its own category")
	assert_eq(mount.hitstops.size(), 0, "and no freeze")
	mount.dispose()


## Recoil is shown at the scale the simulation applied, never beyond it: the
## streak reaches one tick of the actual push and no further.
func test_recoil_never_overstates_the_push_the_simulation_applied() -> void:
	var mount := _mount()
	var push := 2.0
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _body(30.0))
	var contact := ArenaTransform.to_world(1.0, 0.0, _kit_weapon().blade_height)
	var reach := 0.0
	for child in mount.presenter.vfx().get_children():
		reach = maxf(reach, contact.distance_to((child as MeshInstance3D).position) * 2.0)
	assert_true(reach > 0.0, "precondition: the recoil was drawn")
	assert_true(reach <= push * CombatFeedbackDirector.RECOIL_SECONDS + 1e-6 or reach <= CombatFeedbackDirector.RECOIL_MIN_LENGTH + 1e-6, "no further than the impulse carried it")
	mount.dispose()


func test_reduced_motion_disables_camera_impulses() -> void:
	var options := PresentationOptions.new()
	options.reduced_motion = true
	var mount := _mount(options)
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _blade(ContactResolver.CLASS_STRONG))
	assert_eq(mount.camera.impulse_strength(), 0.0, "no shake under Reduced Motion")
	assert_eq(mount.hitstops.size(), 1, "hitstop still conveys the impact")
	mount.dispose()


## The arena marks its own north-south axis, so the duel's orientation is
## legible without the HUD. Each end gets a different *shape*, because side is
## never communicated by colour alone (SIDE-001).
func test_the_arena_marks_both_home_ends_distinguishably() -> void:
	var mount := _mount()
	var arena := mount.presenter.get_node("Arena")
	var light := arena.get_node("HomeLight") as MeshInstance3D
	var dark := arena.get_node("HomeDark") as MeshInstance3D
	assert_true(light != null and dark != null, "both ends are marked")
	assert_near(light.position.x, 0.0, 1e-6, "marks sit on the centre line")
	assert_near(dark.position.x, 0.0, 1e-6, "both of them")
	assert_true(light.position.z * dark.position.z < 0.0, "at opposite ends of the arena")
	var south := ArenaTransform.to_world(0.0, DuelSide.spawn_y(DuelSide.Id.LIGHT_SOUTH, _rules.spawn_offset))
	assert_near(light.position.z, south.z, 1e-6, "Light's mark is at Light's spawn")
	assert_false(light.mesh.get_class() == dark.mesh.get_class(), "and the two ends are different shapes, not just tints")
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
	var spawn := ArenaTransform.to_world(0.0, DuelSide.spawn_y(mount.state.fighter(0).side, _rules.spawn_offset))
	assert_near(mount.presenter.fighter_proxy(0).position.distance_to(spawn), 0.0, 1e-6, "teleported to spawn, not interpolated")
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


## ───────────────────────── SWING READABILITY ─────────────────────────


func _ribbon(potentials: PackedFloat64Array) -> SwordTrail3D:
	var trail := SwordTrail3D.create(Color.WHITE, 16)
	for i in potentials.size():
		trail.add_sample(Vector3(float(i), 1.0, 0.0), Vector3(float(i), 1.0, 1.0), potentials[i], 10.0, 1.0)
	trail.advance(0.0)
	return trail


## The ribbon is a reading, not a decoration: its thickness comes from the
## potential the simulation computed, so a dangerous part of a swing is
## visibly heavier than a spent one (COMBAT-009).
func test_the_ribbon_is_thicker_where_the_swing_is_more_dangerous() -> void:
	var trail := _ribbon(PackedFloat64Array([0.0, 0.5, 1.0]))
	assert_near(trail.half_width_at(0), SwordTrail3D.WIDTH_SPENT, 1e-9, "a spent blade draws its thinnest line")
	assert_near(trail.half_width_at(2), SwordTrail3D.WIDTH_FULL, 1e-9, "a fully dangerous one its heaviest")
	assert_true(trail.half_width_at(1) > trail.half_width_at(0), "and the middle is between them")
	assert_true(trail.half_width_at(1) < trail.half_width_at(2), "monotonically")
	trail.queue_free()


## Potential is carried, never recomputed. Presentation may exaggerate an
## authoritative value; it may not invent one, so anything out of range is
## clamped rather than believed.
func test_the_ribbon_records_the_potential_it_was_given() -> void:
	var trail := _ribbon(PackedFloat64Array([0.4, 2.0, -1.0]))
	assert_eq(trail.potential_at(0), 0.4, "what the simulation said")
	assert_eq(trail.potential_at(1), 1.0, "clamped above")
	assert_eq(trail.potential_at(2), 0.0, "and below")
	trail.queue_free()


## The sweet region is a distinct *shape* — its own rib above the band — so it
## survives for a player who cannot separate the two tints (UX §54).
func test_the_sweet_region_is_drawn_as_its_own_shape() -> void:
	var dull := _ribbon(PackedFloat64Array([0.05, 0.1]))
	assert_eq(dull.surface_count(), 2, "a harmless swing is just the band")
	var keen := _ribbon(PackedFloat64Array([0.05, 0.9]))
	assert_eq(keen.surface_count(), 3, "a dangerous one adds the percussion rib")
	dull.queue_free()
	keen.queue_free()


## Accessibility strengthens the cue and never the mechanic. Turning the
## sweet-spot cue off or up changes what is drawn; `SwingSemantics` still
## decides where the region is, and the band is still there to read.
func test_the_sweet_spot_cue_scales_the_drawing_not_the_region() -> void:
	var trail := _ribbon(PackedFloat64Array([0.9, 0.9]))
	var band := trail.half_width_at(0)
	trail.set_strength(1.0, 0.0)
	trail.advance(0.0)
	assert_eq(trail.surface_count(), 2, "Off removes the rib")
	trail.set_strength(1.0, 2.0)
	trail.advance(0.0)
	assert_eq(trail.surface_count(), 3, "Strong draws it")
	assert_eq(trail.half_width_at(0), band, "and neither touched the band")
	assert_eq(trail.potential_at(0), 0.9, "nor the reading it is drawn from")
	trail.queue_free()


## Trail Strength off is allowed to remove the ribbon entirely, and must do so
## without losing a single sample: the duel is still fully described.
func test_trail_strength_off_draws_nothing_and_loses_nothing() -> void:
	var trail := _ribbon(PackedFloat64Array([0.9, 0.9, 0.9]))
	trail.set_strength(0.0, 1.0)
	trail.advance(0.0)
	assert_eq(trail.surface_count(), 0, "nothing is drawn")
	assert_eq(trail.sample_count(), 3, "but the swing is still sampled")
	trail.queue_free()


## The wiring. What reaches the ribbon is the projected `swing_potential`, not
## some presentation-local notion of how hard the swing looked.
func test_the_ribbon_is_fed_the_simulated_swing_potential() -> void:
	var mount := _mount()
	var weapon := mount.state.fighter(0).weapon
	weapon.set_phase(CombatPhase.Id.ACTIVE_THREAT)
	weapon.speed = 15.0
	weapon.launch_readiness = 1.0
	var snapshot := SnapshotProjector.project(mount.state, _rules)
	var none: Array[DuelEvent] = []
	mount.presenter.push(snapshot, none)
	mount.presenter.render(1.0, 1.0 / 60.0)
	var trail := mount.presenter.trail(0)
	assert_true(trail.sample_count() >= 1, "precondition: the swing left a sample")
	assert_true(snapshot.fighter(0).swing_potential > 0.0, "precondition: the swing is a real threat")
	assert_eq(trail.potential_at(trail.sample_count() - 1), snapshot.fighter(0).swing_potential, "the ribbon carries the projected potential")
	mount.dispose()


## Wind-back needs no invented glow — the blade physically travels backwards.
## Audio only tightens behind it, and it lets go the moment the wind-back ends.
func test_the_wind_back_tightens_an_audio_layer_and_then_lets_go() -> void:
	var mount := _mount()
	var weapon := mount.state.fighter(0).weapon
	var audio := mount.presenter.audio()
	var none: Array[DuelEvent] = []
	weapon.set_phase(CombatPhase.Id.CHARGING)
	weapon.charge = 0.2
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), none)
	mount.presenter.render(1.0, 1.0 / 60.0)
	assert_true(audio.is_tension_held(0), "a wind-back holds the layer")
	var early := audio.tension_pitch(0)
	weapon.charge = 1.0
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), none)
	mount.presenter.render(1.0, 1.0 / 60.0)
	assert_true(audio.tension_pitch(0) > early, "and tightens as more wind-back is earned")
	assert_near(audio.tension_pitch(0), AudioDirector.TENSION_PITCH_FULL, 1e-6, "plateauing where no more is reachable")
	assert_false(audio.is_tension_held(1), "the other fighter is not charging")
	weapon.set_phase(CombatPhase.Id.ACTIVE_THREAT)
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), none)
	mount.presenter.render(1.0, 1.0 / 60.0)
	assert_false(audio.is_tension_held(0), "releasing the swing releases the tension")
	mount.dispose()


## Footwork writes on the floor; swings write in the air. A dash and a swing
## must never be confusable at a glance, so the dust stays at ankle height and
## scuffs away *opposite* the heading the simulation froze (UX §19).
func test_a_burst_kicks_dust_along_the_floor_behind_the_fighter() -> void:
	var mount := _mount()
	var burst := _events(
		DuelEventTypes.BURST_STARTED,
		0,
		DuelEvent.NONE,
		{
			DuelEventKeys.BURST: int(MovementGestureState.BurstKind.FORWARD_DASH),
			DuelEventKeys.HEADING_X: 0.0,
			DuelEventKeys.HEADING_Y: 1.0,
		}
	)
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), burst)
	var vfx := mount.presenter.vfx()
	assert_true(vfx.effect_count() > 0, "the dash is visible")
	var start := Vector3.ZERO
	for child in vfx.get_children():
		var puff := child as MeshInstance3D
		assert_true(puff.position.y < _rules.weapon.tip_radius, "dust stays well below blade height")
		assert_near(puff.position.y, VfxDirector.DUST_HEIGHT, 1e-6, "it is on the floor")
		start += puff.position
	mount.presenter.render(1.0, 0.1)
	var moved := Vector3.ZERO
	for child in vfx.get_children():
		moved += (child as MeshInstance3D).position
	## Heading `+y` is world `-z`, so the dust must drift towards `+z`.
	assert_true(moved.z > start.z, "and it scuffs backwards, away from where the fighter went")
	mount.dispose()


## Victim reaction comes from the simulation first. The proxy stands exactly
## where the state says even on the frame it is struck — there is no recoil
## overlay that could throw the target further than the impulse did.
func test_a_struck_fighter_stands_exactly_where_the_simulation_says() -> void:
	var mount := _mount()
	var target := mount.state.fighter(1)
	target.vx = 3.0
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _body(40.0))
	mount.presenter.render(1.0, 1.0 / 60.0)
	var expected := ArenaTransform.to_world(target.x, target.y)
	assert_true(mount.presenter.fighter_proxy(1).position.is_equal_approx(expected), "no recoil overlay displaces the body")
	assert_eq(mount.presenter.fighter_proxy(1).current_semantic(), PresentationKit.ANIM_HIT, "the flinch is animation only")
	mount.dispose()


## A miss is information, not a non-event: the swing follows through, the
## recovery pose is there to read, and crucially nothing *punctuates* it. No
## freeze and no impact sound, so a whiff can never be mistaken for a touch.
func test_a_whiff_is_never_punctuated_like_a_hit() -> void:
	var mount := _mount()
	var audio := mount.presenter.audio()
	var before := audio.last_cue
	mount.presenter.push(
		SnapshotProjector.project(mount.state, _rules),
		_events(DuelEventTypes.ATTACK_WHIFFED, 0, DuelEvent.NONE, {DuelEventKeys.ARC: 1.2})
	)
	assert_eq(mount.hitstops.size(), 0, "a miss does not stop time")
	assert_eq(audio.last_cue, before, "and makes no contact sound")
	assert_eq(mount.presenter.vfx().effect_count(), 0, "nor a spark")
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


## -- ACCESSIBILITY AND DIAGNOSTICS --


func test_the_debug_vectors_draw_only_when_asked() -> void:
	var mount := _mount()
	var vectors := mount.presenter.debug_vectors()
	mount.presenter.render(1.0, 1.0 / 60.0)
	assert_false(vectors.visible, "hidden by default: this is a diagnostic, not a feature")
	assert_eq(vectors.line_count(), 0, "and it costs nothing while hidden")
	vectors.visible = true
	mount.presenter.render(1.0, 1.0 / 60.0)
	assert_eq(vectors.line_count(), 1, "one line surface once shown")
	mount.dispose()


func test_the_debug_vectors_follow_the_simulated_swing_direction() -> void:
	var mount := _mount()
	var vectors := mount.presenter.debug_vectors()
	vectors.visible = true
	var fighter := mount.state.fighter(0)
	ContactFixture.arm(fighter, 0.0, 0.0, 0.0, 0.0, 9.0, CombatPhase.Id.ACTIVE_THREAT, 0.8, _rules.weapon)
	var forward := SnapshotProjector.project(mount.state, _rules)
	assert_eq(forward.fighter(0).swing_dir, 1.0, "precondition: swinging one way")
	mount.presenter.push(forward, ([] as Array[DuelEvent]))
	fighter.weapon.speed = -9.0
	var back := SnapshotProjector.project(mount.state, _rules)
	assert_eq(back.fighter(0).swing_dir, -1.0, "and the other way once the blade reverses")
	assert_eq(back.fighter(0).tip_speed, forward.fighter(0).tip_speed, "a speed is a magnitude; only the sign changed")
	mount.dispose()


func test_combat_stays_legible_with_every_motion_cue_switched_off() -> void:
	var options := PresentationOptions.new()
	options.screen_shake = false
	options.reduced_motion = true
	options.trail_strength = 0.0
	options.sweet_spot_cue = 0.0
	var mount := _mount(options)
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _body(12.0))
	assert_eq(mount.camera.impulse_strength(), 0.0, "no shake, as asked")
	assert_true(mount.presenter.trail(0).surface_count() == 0, "no ribbon, as asked")
	assert_true(mount.presenter.vfx().effect_count() > 0, "but the hit is still marked in the world")
	assert_true(mount.presenter.audio().last_cue != &"", "and still heard")
	assert_eq(mount.hitstops.size(), 1, "and still felt in the pacing")
	assert_true(mount.presenter.vfx().effect_count() >= MatchPresenter.SPARK_COUNT_MIN, "with the full spark fan, which is where the hit came from")
	assert_eq(SwingSemantics.SWEET_REGION_MIN, 0.55, "and the region itself is untouched by any of this")
	mount.dispose()


## ───────────────────────── POINT-STRIKE CUES ─────────────────────────


func _poke_event() -> Array[DuelEvent]:
	return _events(
		DuelEventTypes.BODY_POKE,
		0,
		1,
		{
			DuelEventKeys.X: 1.0,
			DuelEventKeys.Y: 0.0,
			DuelEventKeys.THRUST_ALIGNMENT: 0.5,
			DuelEventKeys.INCIDENCE_QUALITY: 0.6,
			DuelEventKeys.CONTACT_KIND: "poke",
		}
	)


func _thrust_event() -> Array[DuelEvent]:
	return _events(
		DuelEventTypes.BODY_THRUST,
		0,
		1,
		{
			DuelEventKeys.X: 1.0,
			DuelEventKeys.Y: 0.0,
			DuelEventKeys.THRUST_ALIGNMENT: 0.9,
			DuelEventKeys.INCIDENCE_QUALITY: 0.8,
			DuelEventKeys.CONTACT_KIND: "thrust",
		}
	)


## Point strikes play their own audio cue so the player hears the contact
## kind — a poke is a different situation from a slash.
func test_a_poke_plays_its_own_audio_cue() -> void:
	var mount := _mount()
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _poke_event())
	assert_eq(mount.presenter.audio().last_cue, PresentationKit.CUE_BODY_POKE, "poke has its own sound")
	mount.dispose()


func test_a_thrust_plays_its_own_audio_cue() -> void:
	var mount := _mount()
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _thrust_event())
	assert_eq(mount.presenter.audio().last_cue, PresentationKit.CUE_BODY_THRUST, "thrust has its own sound")
	mount.dispose()


## Point strikes are companion events alongside BODY_HIT, so they do not add
## their own hitstop — the hit already sized it from the physics.
func test_point_strikes_do_not_add_hitstop() -> void:
	var mount := _mount()
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _poke_event())
	assert_eq(mount.hitstops.size(), 0, "a poke-only event does not freeze (the BODY_HIT handles it)")
	mount.presenter.push(SnapshotProjector.project(mount.state, _rules), _thrust_event())
	assert_eq(mount.hitstops.size(), 0, "a thrust-only event does not freeze either")
	mount.dispose()