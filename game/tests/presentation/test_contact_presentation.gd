extends TestCase

## PRES-CONTACT: the drawn swords meet where the simulation says they touch
## (CONTACT-PRESENTATION-001). The combat plane owns the contact's XY, each
## sword's yaw and grip; presentation adds one shared height. A contacted sword
## is level at that height, so it passes through the authoritative contact
## point; apart, each sword keeps its free lift; leaving a contact eases back.
## Sparks and the grind sit at the same rendered contact. Presentation never
## writes back.
##
## Implements: /spec/invariants.md#contact-presentation-001
## See also: /docs/concepts/presentation.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "PRES-CONTACT"
	_rules = StandardDuelRules.create()


class Mount:
	var root: Node3D
	var presenter: MatchPresenter

	func dispose() -> void:
		presenter.detach_and_dispose()
		root.queue_free()


func _mount(state: MatchState, options: PresentationOptions = PresentationOptions.new()) -> Mount:
	var mount := Mount.new()
	mount.root = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(mount.root)
	var camera := DuelCameraRig.new()
	mount.root.add_child(camera)
	camera.configure(RiposteKits.camera_profile())
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	mount.presenter = MatchPresenter.create(kits, options, camera, _rules.platform_radius, _rules.edge_warning_inset, SnapshotProjector.project(state, _rules))
	mount.root.add_child(mount.presenter)
	return mount


## Two swords crossing at mid-blade, fighter 0's blade descending across
## fighter 1's Long Guard, touching by a millimetre and recorded on the
## manifold as the sweep would. `touching` false winds fighter 0 clear.
func _crossing(touching: bool) -> MatchState:
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var state := DuelSetup.new_state(_rules, 1)
	ContactFixture.arm(state.fighter(1), 0.0, 0.0, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, spec, BladePose.new())
	var r := (weapon.blade_base_radius + weapon.tip_radius) * 0.5
	var direction := deg_to_rad(-120.0)
	var reach := WeaponKinematics.pose_at(0.0, 0.0, direction, 0.0, spec, BladePose.new())
	var lift := 2.0 * weapon.blade_radius - 0.001 if touching else 0.6
	var x := pose.point_x(r) - reach.point_x(r)
	var y := pose.point_y(r) + lift - reach.point_y(r)
	ContactFixture.arm(state.fighter(0), x, y, direction, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var a := WeaponKinematics.pose_of(state.fighter(0), spec, BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new())
	var geometry := SwordContactGeometry.new()
	var gap := geometry.measure(state.fighter(0).x, state.fighter(0).y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, weapon, weapon)
	var manifold := state.blade_contact
	manifold.begin_search()
	for point in geometry.count:
		if geometry.point_gap[point] > 0.0:
			continue
		manifold.record_point(point, (geometry.point_ax[point] + geometry.point_bx[point]) * 0.5, (geometry.point_ay[point] + geometry.point_by[point]) * 0.5, geometry.point_fraction_a[point], geometry.point_fraction_b[point], geometry.point_nx[point], geometry.point_ny[point])
	manifold.observe(gap, 0.0, _rules.combat.separation_epsilon)
	return state


func _proxy_pitch(mount: Mount, slot: int) -> float:
	return mount.presenter.fighter_proxy(slot).carriage().pitch


func test_the_snapshot_carries_every_touching_point_read_only() -> void:
	var state := _crossing(true)
	assert_true(state.blade_contact.point_count >= 1, "fixture: the swords touch")
	var before := StateHasher.hash_state(state)
	var snapshot := SnapshotProjector.project(state, _rules)
	assert_eq(snapshot.contacts.size(), state.blade_contact.point_count, "every touching point is projected")
	var contact := snapshot.contacts[0]
	assert_eq(contact.contact_id, state.blade_contact.contact_id[0], "with its stable identity")
	assert_near(contact.fraction_a, state.blade_contact.fraction_a[0], 0.0, "and its place on each blade")
	assert_near(contact.fraction_b, state.blade_contact.fraction_b[0], 0.0, "on both")
	var mount := _mount(state)
	mount.presenter.push(snapshot, [] as Array[DuelEvent])
	mount.presenter.render(1.0, 1.0 / 60.0)
	assert_eq(StateHasher.hash_state(state), before, "projecting and drawing a contact never touches the simulation")
	mount.dispose()
	var apart := SnapshotProjector.project(_crossing(false), _rules)
	assert_eq(apart.contacts.size(), 0, "apart, there is nothing to draw")


## The core parity: both drawn swords level, at one height, through the
## authoritative contact; grip and yaw stay where the plane put them.
func test_contacted_swords_are_level_and_meet_at_the_authoritative_point() -> void:
	var state := _crossing(true)
	var snapshot := SnapshotProjector.project(state, _rules)
	var mount := _mount(state)
	mount.presenter.push(snapshot, [] as Array[DuelEvent])
	mount.presenter.render(1.0, 1.0 / 60.0)
	var height := mount.presenter.contact_height()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	assert_false(is_nan(height), "fixture: a contact to draw")
	assert_near(height, ContactPresentation.new().contact_height(snapshot, kits.weapon.blade_height), 1e-12, "the presenter draws the one shared height")
	var contact := snapshot.contacts[0]
	var world := ArenaTransform.to_world(contact.x, contact.y, height)
	for slot in 2:
		var proxy := mount.presenter.fighter_proxy(slot)
		assert_true(proxy.is_contact_anchored(), "slot %d: the sword is anchored at the contact" % slot)
		assert_near(_proxy_pitch(mount, slot), 0.0, 1e-12, "slot %d: and level" % slot)
		var fraction := contact.fraction_a if slot == 0 else contact.fraction_b
		var drawn := proxy.drawn_point(ContactPresentation.along(fraction, _rules.combatant(0).weapon))
		assert_near(drawn.y, height, 1e-6, "slot %d: at the shared height" % slot)
		var across := Vector2(drawn.x - world.x, drawn.z - world.z).length()
		assert_true(across <= _rules.combatant(0).weapon.blade_radius + 0.002, "slot %d: its axis passes the contact within the blade's own radius (%.4f m)" % [slot, across])
		var planar := proxy.authoritative_blade_points()
		var shown := proxy.blade_points()
		var yaw_plane := Vector2(planar[1].x - planar[0].x, planar[1].z - planar[0].z).normalized()
		var yaw_shown := Vector2(shown[1].x - shown[0].x, shown[1].z - shown[0].z).normalized()
		assert_near(yaw_plane.dot(yaw_shown), 1.0, 1e-9, "slot %d: the drawn yaw is the authoritative one" % slot)
	mount.dispose()


func test_apart_swords_keep_their_free_lift() -> void:
	var state := _crossing(false)
	var mount := _mount(state)
	mount.presenter.push(SnapshotProjector.project(state, _rules), [] as Array[DuelEvent])
	mount.presenter.render(1.0, 1.0 / 60.0)
	assert_true(is_nan(mount.presenter.contact_height()), "fixture: no contact")
	for slot in 2:
		assert_false(mount.presenter.fighter_proxy(slot).is_contact_anchored(), "slot %d: not anchored" % slot)
	assert_true(absf(_proxy_pitch(mount, 1)) > deg_to_rad(5.0), "Long Guard keeps its free point lift (%.1f°)" % rad_to_deg(_proxy_pitch(mount, 1)))
	mount.dispose()


## Anchoring is exact at once; release eases back to the free lift rather than
## popping.
func test_leaving_a_contact_eases_back_without_a_pop() -> void:
	var held := _crossing(true)
	var mount := _mount(held)
	mount.presenter.push(SnapshotProjector.project(held, _rules), [] as Array[DuelEvent])
	mount.presenter.render(1.0, 1.0 / 60.0)
	assert_near(_proxy_pitch(mount, 1), 0.0, 1e-12, "fixture: anchored level")
	var apart := _crossing(false)
	mount.presenter.push(SnapshotProjector.project(apart, _rules), [] as Array[DuelEvent])
	mount.presenter.render(1.0, 1.0 / 240.0)
	var free := deg_to_rad(CombatPresentationField.STANCE_PITCH_DEGREES[0])
	var first := _proxy_pitch(mount, 1)
	assert_true(first < 0.5 * free, "one short frame after release the sword has not jumped to its free pitch (%.2f° of %.2f°)" % [rad_to_deg(first), rad_to_deg(free)])
	for _frame in 60:
		mount.presenter.render(1.0, 1.0 / 60.0)
	assert_near(_proxy_pitch(mount, 1), free, deg_to_rad(0.1), "and it settles into the free lift")
	mount.dispose()


func test_clash_sparks_sound_where_the_swords_are_drawn() -> void:
	var state := _crossing(true)
	var snapshot := SnapshotProjector.project(state, _rules)
	var contact := snapshot.contacts[0]
	var mount := _mount(state)
	var events: Array[DuelEvent] = [DuelEvent.create(DuelEventTypes.BLADE_CONTACT, 1, 0, 1, {
		DuelEventKeys.X: contact.x,
		DuelEventKeys.Y: contact.y,
		DuelEventKeys.INTENSITY: 1.0,
		DuelEventKeys.CONTACT_CLASS: String(ContactResolver.CLASS_STRONG),
		DuelEventKeys.NORMAL_X: contact.normal_x,
		DuelEventKeys.NORMAL_Y: contact.normal_y,
		DuelEventKeys.STRIKE_X: 1.0,
		DuelEventKeys.STRIKE_Y: 0.0,
	})]
	mount.presenter.push(snapshot, events)
	var height := mount.presenter.contact_height()
	var frame := mount.presenter.last_frame()
	assert_true(frame.vfx_requests.size() > 0 and frame.audio_requests.size() > 0, "fixture: the clash sparks and sounds")
	for request in frame.vfx_requests:
		assert_near(request.world_position.y, height, 1e-6, "sparks at the rendered contact height (Vector3 is single precision)")
	assert_near(frame.audio_requests[0].world_position.y, height, 1e-6, "and the clang too")
	assert_true(absf(height - mount.presenter.duel_kits().weapon.blade_height) > 1e-3, "fixture: the rendered height is not the bare blade plane (%.3f m)" % height)
	mount.dispose()


## The optional contact highlight marks exactly the authoritative touching
## points, at the one rendered contact height, and goes when they part. Off,
## it is never built.
func test_the_contact_highlight_marks_every_touching_point() -> void:
	var state := _crossing(true)
	var snapshot := SnapshotProjector.project(state, _rules)
	assert_true(snapshot.contacts.size() >= 1, "fixture: the swords touch")
	var plain := _mount(state)
	assert_true(plain.presenter.contact_highlight() == null, "off by default, and then it does not exist")
	plain.dispose()
	var options := PresentationOptions.new()
	options.contact_highlight = true
	var mount := _mount(state, options)
	var before := StateHasher.hash_state(state)
	mount.presenter.push(snapshot, [] as Array[DuelEvent])
	mount.presenter.render(1.0, 1.0 / 60.0)
	var highlight := mount.presenter.contact_highlight()
	assert_eq(highlight.shown_count(), snapshot.contacts.size(), "one ring per touching point")
	var height := mount.presenter.contact_height()
	for index in snapshot.contacts.size():
		var contact := snapshot.contacts[index]
		var expected := ArenaTransform.to_world(contact.x, contact.y, height)
		assert_true(highlight.marker(index).global_position.distance_to(expected) < 1e-5, "ring %d sits on the authoritative point at the drawn height" % index)
	assert_false(highlight.marker(snapshot.contacts.size()).visible, "and no ring where nothing touches")
	assert_eq(StateHasher.hash_state(state), before, "drawing it never touches the simulation")
	mount.presenter.push(SnapshotProjector.project(_crossing(false), _rules), [] as Array[DuelEvent])
	assert_eq(highlight.shown_count(), 0, "apart, the rings go")
	assert_false(highlight.marker(0).visible, "all of them")
	mount.dispose()


## A scrape is captioned once when it becomes audible: not while the blade is
## pressed still, not again every tick it lasts, and again for a new contact.
func test_a_scrape_is_captioned_once_per_contact() -> void:
	var state := _crossing(true)
	var options := PresentationOptions.new()
	options.sound_captions = true
	var mount := _mount(state, options)
	var heard: Array[String] = []
	mount.presenter.sound_caption_requested.connect(func(text: String, _seconds: float) -> void: heard.append(text))
	var still := SnapshotProjector.project(state, _rules)
	still.contacts[0].age = 3
	still.contacts[0].slip = 0.0
	mount.presenter.push(still, [] as Array[DuelEvent])
	assert_eq(heard.size(), 0, "a blade pressed still is silent, so nothing is captioned")
	for _tick in 3:
		var sliding := SnapshotProjector.project(state, _rules)
		sliding.contacts[0].age = 4
		sliding.contacts[0].slip = 0.4
		sliding.contacts[0].tangent_impulse = 0.5
		mount.presenter.push(sliding, [] as Array[DuelEvent])
	assert_eq(heard, [HudCopy.SOUND_SCRAPE] as Array[String], "sliding, the scrape is captioned once however long it lasts")
	var fresh := SnapshotProjector.project(state, _rules)
	fresh.contacts[0].age = 2
	fresh.contacts[0].slip = 0.4
	fresh.contacts[0].tangent_impulse = 0.5
	fresh.contacts[0].contact_id += 7
	mount.presenter.push(fresh, [] as Array[DuelEvent])
	assert_eq(heard.size(), 2, "a new contact is a new scrape")
	mount.dispose()
