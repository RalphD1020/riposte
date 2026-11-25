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


## A contact never moves a drawn sword: the same physical state drawn with its
## contact and with the contact removed is the same pose, bit for bit; the
## yaw stays the authoritative one; the effects' height sits between the two
## drawn blades at the contact.
func test_a_contact_never_moves_a_drawn_sword() -> void:
	## ARRANGE: two touching swords, and the same state with no contact flag.
	var state := _crossing(true)
	var touching := SnapshotProjector.project(state, _rules)
	var flagless := SnapshotProjector.project(state, _rules)
	flagless.contacts.clear()
	assert_true(touching.contacts.size() >= 1 and flagless.contacts.is_empty(), "fixture: one snapshot touches, the other does not")
	## ACT
	var with_contact := _mount(state)
	with_contact.presenter.push(touching, [] as Array[DuelEvent])
	with_contact.presenter.render(1.0, 1.0 / 60.0)
	var without := _mount(state)
	without.presenter.push(flagless, [] as Array[DuelEvent])
	without.presenter.render(1.0, 1.0 / 60.0)
	## ASSERT
	var height := with_contact.presenter.contact_height()
	assert_false(is_nan(height), "fixture: a contact's effects to place")
	assert_true(is_nan(without.presenter.contact_height()), "fixture: none without the flag")
	var contact := touching.contacts[0]
	var drawn_heights := 0.0
	for slot in 2:
		var proxy := with_contact.presenter.fighter_proxy(slot)
		assert_true(proxy.carriage().transform == without.presenter.fighter_proxy(slot).carriage().transform, "slot %d: the contact flag does not move the drawn sword" % slot)
		var fraction := contact.fraction_a if slot == 0 else contact.fraction_b
		drawn_heights += proxy.drawn_point(ContactPresentation.along(fraction, _rules.combatant(slot).weapon)).y
		var planar := proxy.authoritative_blade_points()
		var shown := proxy.blade_points()
		var yaw_plane := Vector2(planar[1].x - planar[0].x, planar[1].z - planar[0].z).normalized()
		var yaw_shown := Vector2(shown[1].x - shown[0].x, shown[1].z - shown[0].z).normalized()
		assert_near(yaw_plane.dot(yaw_shown), 1.0, 1e-9, "slot %d: the drawn yaw is the authoritative one" % slot)
	assert_near(height, drawn_heights * 0.5, 1e-6, "the effects sit between the two drawn blades at the contact")
	with_contact.dispose()
	without.dispose()


## A directed contact: fighter 1 at the origin facing 0 in a guard at `b_angle`; fighter 0 facing π with its sword
## at `a_angle` (`a_phase`, angular speed `a_speed`), placed so its station `r_a` touches fighter 1's steel by a
## millimetre at `along_b` / `across_b` on fighter 1's sword, coming from the side its blade lies on. The manifold —
## points, fractions, normals and each point's steel pair — is the real geometry's, as the sweep records it.
func _directed(a_angle: float, a_phase: CombatPhase.Id, a_speed: float, b_angle: float, r_a: float, along_b: float, across_b: float, depth: float) -> MatchState:
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var state := DuelSetup.new_state(_rules, 1)
	ContactFixture.arm(state.fighter(1), 0.0, 0.0, 0.0, b_angle, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var b := WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new())
	var u_b := Vector2(b.ux, b.uy)
	var perp_b := Vector2(-b.uy, b.ux)
	var a0 := WeaponKinematics.pose_at(0.0, 0.0, PI, a_angle, spec, BladePose.new())
	var u_a := Vector2(a0.ux, a0.uy)
	## Fighter 0's blade comes from the side of fighter 1's line it lies on.
	var side := -signf(u_a.dot(perp_b)) if absf(u_a.dot(perp_b)) > 1.0e-6 else 1.0
	var target := Vector2(b.origin_x, b.origin_y) + u_b * along_b + perp_b * across_b + perp_b * side * depth
	var station := Vector2(a0.point_x(r_a), a0.point_y(r_a))
	var at := target - station
	ContactFixture.arm(state.fighter(0), at.x, at.y, PI, a_angle, a_speed, a_phase, 0.0, weapon)
	_record(state)
	return state


func _record(state: MatchState) -> void:
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var a := WeaponKinematics.pose_of(state.fighter(0), spec, BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new())
	var geometry := SwordContactGeometry.new()
	var gap := geometry.measure(state.fighter(0).x, state.fighter(0).y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, weapon, weapon)
	var manifold := state.blade_contact
	manifold.begin_search()
	var index := 0
	for point in geometry.count:
		if geometry.point_gap[point] > 0.0:
			continue
		manifold.record_point(index, (geometry.point_ax[point] + geometry.point_bx[point]) * 0.5, (geometry.point_ay[point] + geometry.point_by[point]) * 0.5, geometry.point_fraction_a[point], geometry.point_fraction_b[point], geometry.point_nx[point], geometry.point_ny[point], geometry.point_pair[point])
		index += 1
	manifold.observe(gap, 0.0, _rules.combat.separation_epsilon)


## The worst horizontal miss of a drawn blade station against rigid foreshortening of the authoritative centreline:
## the drawn station at `along` must project onto the planar blade line, `(along − carriage)·cos p` from the carriage.
func _station_miss(mount: Mount, state: MatchState, slot: int, along: float) -> float:
	var proxy := mount.presenter.fighter_proxy(slot)
	var spec := _rules.combatant(slot)
	var planar := WeaponKinematics.pose_of(state.fighter(slot), spec, BladePose.new())
	var shown := proxy.blade_points()
	var axis := shown[1] - shown[0]
	var cos_pitch := Vector2(axis.x, axis.z).length() / axis.length()
	var carriage := spec.handling.carriage_radius
	var expected := Vector2(planar.point_x(carriage), planar.point_y(carriage)).lerp(Vector2(planar.point_x(along), planar.point_y(along)), cos_pitch)
	var world := ArenaTransform.to_world(expected.x, expected.y, 0.0)
	var drawn := proxy.drawn_point(along)
	return Vector2(drawn.x - world.x, drawn.z - world.z).length()


## Directed blade clashes, both origins: the solver's own feature (blade on blade), each drawn station exactly the
## rigidly foreshortened authoritative station, the contact never moving a drawn sword, and the mirrored clash the same
## physical picture — the same drawn heights and misses — with each fighter's own hands.
func test_directed_blade_clashes_mirror_with_exact_stations() -> void:
	## ARRANGE: a right-origin cut at −30° (travelling +) meeting a guard at +40°, and its mirror image.
	var weapon := _rules.combatant(0).weapon
	var near_tip := weapon.tip_radius - 0.03
	var right := _directed(deg_to_rad(-30.0), CombatPhase.Id.ACTIVE_THREAT, 8.0, deg_to_rad(40.0), near_tip, 0.6, 0.0, 2.0 * weapon.blade_radius - 0.001)
	var left := _directed(deg_to_rad(30.0), CombatPhase.Id.ACTIVE_THREAT, -8.0, deg_to_rad(-40.0), near_tip, 0.6, 0.0, 2.0 * weapon.blade_radius - 0.001)
	var readings: Array[PackedFloat64Array] = []
	for state: MatchState in [right, left]:
		assert_true(state.blade_contact.point_count >= 1 and state.blade_contact.pair[0] == SwordContactSet.PAIR_BLADES, "fixture: a blade-on-blade contact (%d points)" % state.blade_contact.point_count)
		## ACT
		var mount := _mount(state)
		mount.presenter.push(SnapshotProjector.project(state, _rules), [] as Array[DuelEvent])
		mount.presenter.render(1.0, 1.0 / 60.0)
		## ASSERT: each drawn station is the authoritative one, rigidly foreshortened.
		var reading := PackedFloat64Array()
		for slot in 2:
			var fraction := state.blade_contact.fraction_a[0] if slot == 0 else state.blade_contact.fraction_b[0]
			var along := ContactPresentation.along(fraction, weapon)
			var miss := _station_miss(mount, state, slot, along)
			assert_true(miss < 1.0e-3, "slot %d: the drawn station is the authoritative one, foreshortened (miss %.5f m)" % [slot, miss])
			reading.append(mount.presenter.fighter_proxy(slot).drawn_point(along).y)
		readings.append(reading)
		mount.dispose()
	## ASSERT: the mirrored clash draws the same physical picture.
	for slot in 2:
		assert_near(readings[1][slot], readings[0][slot], 1.0e-5, "slot %d: the mirrored clash draws its station at the same height" % slot)


## A blade meeting a guard root from its protected side: the solver's feature is the guard (blade on guard), and the
## whole drawn guard root is the authoritative one moved only by the drawn sword's own rigid rotation — each corner
## within the chord `2·|k|·sin(α/2)` of the sword's rotation α away from level, never anywhere else.
func test_a_directed_guard_contact_corresponds_to_the_whole_guard_root() -> void:
	## ARRANGE: fighter 0's tip laid back along fighter 1's blade onto the bar near its end, from the point's side.
	var weapon := _rules.combatant(0).weapon
	var b_angle := deg_to_rad(30.0)
	var a_angle := b_angle
	var state := _directed(a_angle, CombatPhase.Id.ACTIVE_LATE, 2.0, b_angle, weapon.tip_radius - 0.005, weapon.crossguard_centre_radius + weapon.crossguard_radius + weapon.blade_radius - 0.001, 0.6 * weapon.crossguard_half_span, 0.0)
	var pairs := PackedInt32Array()
	for point in state.blade_contact.point_count:
		pairs.append(state.blade_contact.pair[point])
	assert_true(pairs.has(SwordContactSet.PAIR_BLADE_ON_GUARD), "fixture: fighter 0's blade meets fighter 1's guard root (pairs %s)" % str(pairs))
	## ACT
	var mount := _mount(state)
	mount.presenter.push(SnapshotProjector.project(state, _rules), [] as Array[DuelEvent])
	mount.presenter.render(1.0, 1.0 / 60.0)
	## ASSERT
	var proxy := mount.presenter.fighter_proxy(1)
	var into_world := proxy.visual_root().global_transform
	var drawn := proxy.weapon_pose().weapon
	var planar := WeaponKinematics.pose_of(state.fighter(1), _rules.combatant(1), BladePose.new())
	var root := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	assert_true(SwordContactGeometry.place_guard(planar.origin_x, planar.origin_y, planar.ux, planar.uy, weapon, root), "fixture: the sword has a guard root")
	var world_basis := into_world.basis * drawn.basis
	var level := Basis(Vector3.UP, world_basis.get_euler(EULER_ORDER_YXZ).y)
	var alpha := (level.inverse() * world_basis).get_rotation_quaternion().get_angle()
	var carriage := _rules.combatant(1).handling.carriage_radius
	var drawn_corners := proxy.weapon_pose().guard_root_corners()
	var solver_corners := [Vector2(root[0], root[1]), Vector2(root[2], root[3]), Vector2(root[4], root[5])]
	for corner in drawn_corners:
		var world := into_world * corner
		var on_plane := Vector2(world.x, world.z)
		var nearest := INF
		var reach := 0.0
		for solver: Vector2 in solver_corners:
			var at := ArenaTransform.to_world(solver.x, solver.y, 0.0)
			var distance := on_plane.distance_to(Vector2(at.x, at.z))
			if distance < nearest:
				nearest = distance
				reach = (drawn.affine_inverse() * corner - Vector3(0.0, 0.0, carriage)).length()
		var bound := 2.0 * reach * sin(alpha * 0.5) + 1.0e-3
		assert_true(nearest <= bound, "the drawn guard-root corner is the authoritative one, rigidly turned (%.4f m within %.4f m)" % [nearest, bound])
	mount.dispose()


## Near-parallel blades have no well-determined closest station: the drawn picture never infers one. The effects sit
## at the solver's own point and stations (its fractions), the drawn stations are the authoritative ones foreshortened,
## and a persistent hold neither moves a sword nor repeats an impact: no new spark or clang while it lasts.
func test_a_near_parallel_bind_uses_the_solvers_stations_and_never_repeats_an_impact() -> void:
	## ARRANGE: two blades within 5° of antiparallel, side by side along their middles.
	var weapon := _rules.combatant(0).weapon
	var b_angle := deg_to_rad(20.0)
	var middle := (weapon.blade_base_radius + weapon.tip_radius) * 0.5
	var state := _directed(deg_to_rad(25.0), CombatPhase.Id.NEUTRAL, 0.0, b_angle, middle, middle, 0.0, 2.0 * weapon.blade_radius - 0.001)
	var a := WeaponKinematics.pose_of(state.fighter(0), _rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), _rules.combatant(1), BladePose.new())
	var sine := absf(a.ux * b.uy - a.uy * b.ux)
	assert_true(sine < 0.2, "fixture: the blades are near parallel (|sin| %.3f)" % sine)
	assert_true(state.blade_contact.point_count >= 1, "fixture: they touch")
	var mount := _mount(state)
	var held := 0
	for tick in 5:
		## PERTURB: the same hold, older each tick, with no impact event.
		var snapshot := SnapshotProjector.project(state, _rules)
		snapshot.tick = tick + 1
		for contact in snapshot.contacts:
			contact.age = tick
		## ACT
		mount.presenter.push(snapshot, [] as Array[DuelEvent])
		mount.presenter.render(1.0, 1.0 / 60.0)
		var frame := mount.presenter.last_frame()
		## ASSERT
		assert_eq(frame.vfx_requests.size(), 0, "tick %d: a held contact never re-fires an impact spark" % tick)
		assert_eq(frame.audio_requests.size(), 0, "tick %d: nor a clang" % tick)
		var heights := 0.0
		for slot in 2:
			var fraction := snapshot.contacts[0].fraction_a if slot == 0 else snapshot.contacts[0].fraction_b
			var along := ContactPresentation.along(fraction, weapon)
			assert_true(_station_miss(mount, state, slot, along) < 1.0e-3, "tick %d slot %d: the drawn station is the solver's own, foreshortened" % [tick, slot])
			heights += mount.presenter.fighter_proxy(slot).drawn_point(along).y
		var contacts := snapshot.contacts.size()
		var effects := 0.0
		for contact in snapshot.contacts:
			for slot in 2:
				effects += mount.presenter.fighter_proxy(slot).drawn_point(ContactPresentation.along(contact.fraction_a if slot == 0 else contact.fraction_b, weapon)).y
		assert_near(mount.presenter.contact_height(), effects / float(2 * contacts), 1.0e-6, "tick %d: the effects sit between the drawn blades at the solver's own stations" % tick)
		held += 1
		assert_true(heights > 0.0, "fixture: drawn")
	assert_eq(held, 5, "every held tick was drawn")
	mount.dispose()


## Tangential deflection, live: a cut stepped by the real simulation into a guard and on through the contact. Every
## frame the drawn sword's yaw is the authoritative blade's, and the drawn pose is exactly the contact-free one — the
## visible weapon follows the solver's response and nothing else.
func test_a_deflected_cut_is_drawn_as_the_solver_moves_it() -> void:
	## ARRANGE: the right-origin clash, live, the attacker still driving.
	var weapon := _rules.combatant(0).weapon
	var state := _directed(deg_to_rad(-30.0), CombatPhase.Id.ACTIVE_THREAT, 8.0, deg_to_rad(40.0), weapon.tip_radius - 0.03, 0.6, 0.0, 2.0 * weapon.blade_radius - 0.001)
	state.set_phase(MatchPhase.Id.ROUND_ACTIVE)
	var simulation := DuelSimulation.create(_rules)
	var contacted := _mount(state)
	var free := _mount(state)
	var touched := 0
	var moved := 0.0
	var start := state.fighter(0).weapon.angle
	for _tick in 8:
		## ACT: the solver steps the duel; the same snapshot is drawn with and without its contact flag.
		var events := simulation.step(state, PlayerCommand.idle(state.tick), PlayerCommand.idle(state.tick))
		var flagged := SnapshotProjector.project(state, _rules)
		var flagless := SnapshotProjector.project(state, _rules)
		flagless.contacts.clear()
		touched += 1 if not flagged.contacts.is_empty() else 0
		contacted.presenter.push(flagged, events)
		free.presenter.push(flagless, [] as Array[DuelEvent])
		for weight: float in [0.5, 1.0]:
			contacted.presenter.render(weight, 1.0 / 120.0)
			free.presenter.render(weight, 1.0 / 120.0)
			## ASSERT
			for slot in 2:
				var proxy := contacted.presenter.fighter_proxy(slot)
				assert_true(proxy.carriage().transform == free.presenter.fighter_proxy(slot).carriage().transform, "slot %d: the contact flag never moves the drawn sword" % slot)
				var planar := proxy.authoritative_blade_points()
				var shown := proxy.blade_points()
				var yaw_plane := Vector2(planar[1].x - planar[0].x, planar[1].z - planar[0].z).normalized()
				var yaw_shown := Vector2(shown[1].x - shown[0].x, shown[1].z - shown[0].z).normalized()
				assert_near(yaw_plane.dot(yaw_shown), 1.0, 1.0e-6, "slot %d: the drawn yaw follows the solver's blade" % slot)
	moved = absf(angle_difference(start, state.fighter(0).weapon.angle))
	assert_true(touched >= 1, "fixture: the cut met the guard (%d touching ticks)" % touched)
	assert_true(moved > deg_to_rad(1.0), "fixture: and the solver moved it on (%.1f°)" % rad_to_deg(moved))
	contacted.dispose()
	free.dispose()


func test_apart_swords_keep_their_free_lift() -> void:
	var state := _crossing(false)
	var mount := _mount(state)
	mount.presenter.push(SnapshotProjector.project(state, _rules), [] as Array[DuelEvent])
	mount.presenter.render(1.0, 1.0 / 60.0)
	assert_true(is_nan(mount.presenter.contact_height()), "fixture: no contact")
	assert_true(absf(_proxy_pitch(mount, 1)) > deg_to_rad(5.0), "Long Guard keeps its free point lift (%.1f°)" % rad_to_deg(_proxy_pitch(mount, 1)))
	mount.dispose()


## Contact onset, hold and release draw exactly the contact-free sequence: at
## every rendered instant of free → touching → touching → free over the same
## physical states, each drawn sword is the pose the presenter draws with no
## contact flag at all — no onset snap, no release ease, no hold drift.
func test_contact_onset_hold_and_release_never_move_the_swords() -> void:
	## ARRANGE: one physical state; the contact flag on for the middle ticks only.
	var state := _crossing(true)
	var flags := [false, true, true, true, false, false]
	var contacted := _mount(state)
	var free := _mount(state)
	var compared := 0
	var onset := 0
	for index in flags.size():
		state.tick = index + 1
		var flagged := SnapshotProjector.project(state, _rules)
		var flagless := SnapshotProjector.project(state, _rules)
		flagless.contacts.clear()
		if not flags[index]:
			flagged.contacts.clear()
		## ACT: the same snapshot sequence, with and without the contact flag.
		contacted.presenter.push(flagged, [] as Array[DuelEvent])
		free.presenter.push(flagless, [] as Array[DuelEvent])
		if flags[index] and (index == 0 or not flags[index - 1]):
			onset += 1
		for weight: float in [0.0, 0.25, 0.5, 1.0]:
			contacted.presenter.render(weight, 1.0 / 240.0)
			free.presenter.render(weight, 1.0 / 240.0)
			## ASSERT: the same drawn swords, bit for bit.
			for slot in 2:
				assert_true(contacted.presenter.fighter_proxy(slot).carriage().transform == free.presenter.fighter_proxy(slot).carriage().transform, "tick %d α %.2f slot %d: the contact flag never moves the sword" % [index, weight, slot])
			compared += 1
	assert_eq(onset, 1, "fixture: one contact onset and one release")
	assert_eq(compared, flags.size() * 4, "every instant compared")
	contacted.dispose()
	free.dispose()


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
