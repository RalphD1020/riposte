extends SceneTree

## Dev capture for one known steel clash: the glance in
## `test_a_tap_glancing_off_a_guard_is_redirected_but_not_stopped`.
## A real `DuelSimulation` and the product `MatchPresenter` (the blades the
## match draws). This is not a boot of `main.tscn` — no HUD, no menu.
## Windowed, not `--headless`:
##
##   godot --path game --rendering-method gl_compatibility --resolution 1280x720 -s res://tools/capture_clash.gd [-- --out=<dir>]
##
## Alpha 0 and alpha 1 are the authoritative end poses around the contact
## tick. Alpha 0.5 is the chord `MatchPresenter._pose` draws between them
## when a display frame is not on a tick boundary. The sidecar records the gaps.


const FRAME := 1.0 / 60.0

var _simulation: DuelSimulation
var _rules: DuelRules
var _state: MatchState
var _presenter: MatchPresenter
var _camera: Camera3D
var _out: String = ""
var _geometry := SwordContactGeometry.new()
var _pose_a := BladePose.new()
var _pose_b := BladePose.new()
var _blade_width: float = 0.0
var _segment := SegmentContact.new()


func _init() -> void:
	_rules = StandardDuelRules.create()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	kits.match_loadout = RiposteKits.match_loadout(kits.arena)
	_blade_width = kits.weapon.blade_width
	_out = ProjectSettings.globalize_path("res://../.reports/clash")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)
	var rig := DuelCameraRig.new()
	world.add_child(rig)
	rig.configure(RiposteKits.camera_profile())
	_simulation = DuelSimulation.create(_rules)
	_state = _simulation.new_match(7)
	_presenter = MatchPresenter.create(kits, PresentationOptions.new(), rig, _rules.platform_radius, _rules.edge_warning_inset, SnapshotProjector.project(_state, _rules))
	world.add_child(_presenter)
	_camera = Camera3D.new()
	world.add_child(_camera)
	_camera.make_current()
	_run.call_deferred()


func _run() -> void:
	while _state.phase == MatchPhase.Id.ROUND_INTRO:
		_step(PlayerCommand.idle(_state.tick))
		await _paint(1.0, FRAME)
	_place_glance()
	var none: Array[DuelEvent] = []
	_presenter.push(SnapshotProjector.project(_state, _rules), none)
	await _paint(1.0, 0.0)
	var lines: PackedStringArray = []
	lines.append("scenario: glance, human rest -guard_angle, opponent (2.0, -0.3) facing PI, weapon 1.2 rad, one tap")
	lines.append("presenter: MatchPresenter on a bare world. Not main.tscn.")
	lines.append("can_start_attack: %s" % WeaponSystem.can_start_attack(_state.fighter(0), _rules.combatant(0).weapon))
	lines.append("start surface gap: %.6f m" % _gap(_sample_state(), PackedInt32Array([SwordContactGeometry.GUARD_FREE, SwordContactGeometry.GUARD_FREE])))
	var contact: DuelEvent = null
	var before := {}
	var after := {}
	for i in 40:
		var command := PlayerCommand.create(_state.tick, 0.0, 0.0, true, true) if i == 0 else PlayerCommand.idle(_state.tick)
		before = _sample_state()
		var events := _step(command)
		after = _sample_state()
		for event in events:
			if contact == null and event.type == DuelEventTypes.BLADE_CONTACT:
				contact = event
		if contact != null:
			break
		await _paint(1.0, FRAME)
	if contact == null:
		lines.append("verdict: detection — no BLADE_CONTACT in 40 ticks")
		_write(lines)
		await _shot("no_contact_wide", _wide_from(), _wide_at(), 50.0)
		quit()
		return
	var mid := _blend(before, after, 0.5)
	var free := PackedInt32Array([SwordContactGeometry.GUARD_FREE, SwordContactGeometry.GUARD_FREE])
	var gap_before := _gap(before, free)
	var gap_mid := _gap(mid, free)
	var gap_after := _gap(after, _state.blade_contact.guard_mode)
	var centre_before := _centreline(before)
	var centre_mid := _centreline(mid)
	var centre_after := _centreline(after)
	await _paint(0.0, 0.0)
	await _shot("contact_a000_wide", _wide_from(), _wide_at(), 42.0)
	var drawn_before := _drawn_distance()
	await _shot("contact_a000_tight", _tight_from(contact), _blade_focus(), 28.0)
	await _paint(0.5, 0.0)
	await _shot("contact_a050_wide", _wide_from(), _wide_at(), 42.0)
	var drawn_mid := _drawn_distance()
	await _shot("contact_a050_tight", _tight_from(contact), _blade_focus(), 28.0)
	await _paint(1.0, 0.0)
	await _shot("contact_a100_wide", _wide_from(), _wide_at(), 42.0)
	var drawn_after := _drawn_distance()
	await _shot("contact_a100_tight", _tight_from(contact), _blade_focus(), 28.0)
	await _shot("contact_a100_above", _blade_focus() + Vector3(0.0, 1.15, 0.05), _blade_focus(), 34.0)
	var radius := _rules.combatant(0).weapon.blade_radius
	lines.append("contact tick: %d" % contact.tick)
	lines.append("state tick after the step: %d" % _state.tick)
	lines.append("weapon angle human: %.4f -> %.4f rad (chord %.4f)" % [before["angle0"], after["angle0"], mid["angle0"]])
	lines.append("weapon angle opponent: %.4f -> %.4f rad (chord %.4f)" % [before["angle1"], after["angle1"], mid["angle1"]])
	lines.append("phase human: %s -> %s" % [_phase_name(int(before["phase0"])), _phase_name(int(after["phase0"]))])
	lines.append("point: (%.4f, %.4f) normal (%.4f, %.4f)" % [contact.number(DuelEventKeys.X), contact.number(DuelEventKeys.Y), contact.number(DuelEventKeys.NORMAL_X), contact.number(DuelEventKeys.NORMAL_Y)])
	var control := _rules.combatant(0).weapon.control_speed
	lines.append("impulse: %.6f N·s  energy: %.6f J  class: %s  reading: %s  pair: %s  points: %s" % [contact.number(DuelEventKeys.IMPULSE), contact.number(DuelEventKeys.ENERGY), str(contact.data[DuelEventKeys.CONTACT_CLASS]), String(ContactReading.classify(contact, control, control)), str(contact.data[DuelEventKeys.STEEL_PAIR]), str(contact.data[DuelEventKeys.POINT_COUNT])])
	lines.append("class is the closing-speed band. reading is what the cut kept. energy is the kinetic-energy drop, floored at 0.")
	lines.append("delta_0: %.4f  arrested_0: %s  progress %.4f -> %.4f" % [float(contact.data[DuelEventKeys.DELTA_0]), str(contact.data[DuelEventKeys.ARRESTED_0]), contact.number(DuelEventKeys.PROGRESS_BEFORE), contact.number(DuelEventKeys.PROGRESS_AFTER)])
	lines.append("fractions: %.4f / %.4f" % [contact.number(DuelEventKeys.FRACTION_0), contact.number(DuelEventKeys.FRACTION_1)])
	lines.append("ccd_cap_hits: %d  contact_cap_hits: %d" % [_simulation.diagnostics.ccd_cap_hits, _simulation.diagnostics.contact_cap_hits])
	lines.append("blade radius: %.4f m  slop: %.4f m  max correction: %.4f m" % [radius, _rules.combat.contact_slop, _rules.combat.contact_max_correction])
	lines.append("drawn blade box width: %.4f m  outline width: %.4f m  collision diameter: %.4f m" % [_blade_width, _blade_width + 0.03, radius * 2.0])
	lines.append("surface gap m (negative = overlap): before %.6f  chord %.6f  after %.6f" % [gap_before, gap_mid, gap_after])
	lines.append("centreline distance m: before %.6f  chord %.6f  after %.6f" % [centre_before, centre_mid, centre_after])
	lines.append("drawn centreline distance m: alpha0 %.6f  alpha0.5 %.6f  alpha1 %.6f" % [drawn_before, drawn_mid, drawn_after])
	lines.append("two drawn radii: %.4f m" % (radius * 2.0))
	lines.append("guard mode after the contact: %s" % str(_state.blade_contact.guard_mode))
	if not CombatPhase.is_swinging(before["phase0"]) and not CombatPhase.is_swinging(after["phase0"]):
		lines.append("verdict: not the glance — the first blade contact is not on a human swing")
	else:
		lines.append("verdict: %s" % _verdict(contact, gap_before, gap_mid, gap_after, centre_before, centre_mid, centre_after, drawn_before, drawn_mid, drawn_after, radius))
	_write(lines)
	_step(PlayerCommand.idle(_state.tick))
	await _paint(1.0, FRAME)
	await _shot("after_wide", _wide_from(), _wide_at(), 42.0)
	quit()


func _place_glance() -> void:
	var human := _state.fighter(0)
	var opponent := _state.fighter(1)
	human.x = 0.0
	human.y = 0.0
	human.vx = 0.0
	human.vy = 0.0
	human.facing = 0.0
	human.turn_rate = 0.0
	human.weapon.reset(-_rules.combatant(0).weapon.guard_angle)
	opponent.x = 2.0
	opponent.y = -0.3
	opponent.vx = 0.0
	opponent.vy = 0.0
	opponent.facing = PI
	opponent.turn_rate = 0.0
	opponent.weapon.reset(1.2)


func _step(command: PlayerCommand) -> Array[DuelEvent]:
	var events := _simulation.step(_state, command, PlayerCommand.idle(_state.tick))
	_presenter.push(SnapshotProjector.project(_state, _rules), events)
	return events


func _paint(alpha: float, delta: float) -> void:
	_presenter.render(alpha, delta, delta)
	await process_frame


func _shot(shot_name: String, from: Vector3, at: Vector3, fov: float) -> void:
	_camera.fov = fov
	_camera.look_at_from_position(from, at, Vector3.UP)
	_camera.make_current()
	for _i in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))


func _wide_at() -> Vector3:
	var a := ArenaTransform.to_world(_state.fighter(0).x, _state.fighter(0).y, 1.05)
	var b := ArenaTransform.to_world(_state.fighter(1).x, _state.fighter(1).y, 1.05)
	return (a + b) * 0.5


func _wide_from() -> Vector3:
	return _wide_at() + Vector3(0.35, 1.15, 3.6)


func _blade_focus() -> Vector3:
	var a := _presenter.fighter_proxy(0).blade_points()
	var b := _presenter.fighter_proxy(1).blade_points()
	return (a[0] + a[1] + b[0] + b[1]) * 0.25


func _tight_from(contact: DuelEvent) -> Vector3:
	var normal := Vector3(contact.number(DuelEventKeys.NORMAL_X), 0.0, -contact.number(DuelEventKeys.NORMAL_Y))
	if normal.length_squared() < 1.0e-8:
		normal = Vector3(0.0, 0.0, 1.0)
	return _blade_focus() + normal.normalized() * 0.48 + Vector3(0.0, 0.16, 0.0)


func _sample_state() -> Dictionary:
	var row := {}
	for slot in 2:
		var fighter := _state.fighter(slot)
		row["x%d" % slot] = fighter.x
		row["y%d" % slot] = fighter.y
		row["face%d" % slot] = fighter.facing
		row["angle%d" % slot] = fighter.weapon.angle
		row["phase%d" % slot] = int(fighter.weapon.phase)
	return row


## Same blend `_pose` uses: positions and weapon angle with `lerpf`, facing
## with `lerp_angle`. Weapon angle is not wrapped.
func _blend(from: Dictionary, to: Dictionary, weight: float) -> Dictionary:
	var row := {}
	for slot in 2:
		row["x%d" % slot] = lerpf(from["x%d" % slot], to["x%d" % slot], weight)
		row["y%d" % slot] = lerpf(from["y%d" % slot], to["y%d" % slot], weight)
		row["face%d" % slot] = lerp_angle(from["face%d" % slot], to["face%d" % slot], weight)
		row["angle%d" % slot] = lerpf(from["angle%d" % slot], to["angle%d" % slot], weight)
		row["phase%d" % slot] = to["phase%d" % slot]
	return row


func _pose(row: Dictionary, slot: int) -> BladePose:
	var out := _pose_a if slot == 0 else _pose_b
	return WeaponKinematics.pose_at(row["x%d" % slot], row["y%d" % slot], row["face%d" % slot], row["angle%d" % slot], _rules.combatant(slot), out)


func _gap(row: Dictionary, modes: PackedInt32Array) -> float:
	var a := _pose(row, 0)
	var origin_ax := a.origin_x
	var origin_ay := a.origin_y
	var uax := a.ux
	var uay := a.uy
	var b := _pose(row, 1)
	return _geometry.measure(row["x0"], row["y0"], origin_ax, origin_ay, uax, uay, b.origin_x, b.origin_y, b.ux, b.uy, _rules.combatant(0).weapon, _rules.combatant(1).weapon, modes)


func _centreline(row: Dictionary) -> float:
	var a := _pose(row, 0)
	var ax0 := a.point_x(_rules.combatant(0).weapon.guard_root_apex_radius())
	var ay0 := a.point_y(_rules.combatant(0).weapon.guard_root_apex_radius())
	var ax1 := a.point_x(_rules.combatant(0).weapon.tip_radius)
	var ay1 := a.point_y(_rules.combatant(0).weapon.tip_radius)
	var b := _pose(row, 1)
	var weapon_b := _rules.combatant(1).weapon
	SimMath.closest_segments(ax0, ay0, ax1, ay1, b.point_x(weapon_b.guard_root_apex_radius()), b.point_y(weapon_b.guard_root_apex_radius()), b.point_x(weapon_b.tip_radius), b.point_y(weapon_b.tip_radius), _segment)
	return _segment.distance


## Distance between the two drawn blade axes (what the meshes follow).
func _drawn_distance() -> float:
	var a := _presenter.fighter_proxy(0).blade_points()
	var b := _presenter.fighter_proxy(1).blade_points()
	return _segment_distance(a[0], a[1], b[0], b[1])


func _segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1.0e-12 and e <= 1.0e-12:
		return r.length()
	if a <= 1.0e-12:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1.0e-12:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = 0.0 if denom <= 1.0e-12 else clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


func _phase_name(phase: int) -> String:
	var names := CombatPhase.Id.keys()
	return names[phase] if phase >= 0 and phase < names.size() else str(phase)


func _verdict(contact: DuelEvent, gap_before: float, gap_mid: float, gap_after: float, centre_before: float, centre_mid: float, centre_after: float, drawn_before: float, drawn_mid: float, drawn_after: float, radius: float) -> String:
	if contact.number(DuelEventKeys.IMPULSE) <= 0.0:
		return "detection — a blade event fired with no solved impulse"
	var slop := _rules.combat.contact_slop
	var deep := _rules.combat.contact_max_correction
	var volumes := radius * 2.0
	if gap_after < -deep or gap_before < -deep:
		return "resolution — an authoritative end pose overlaps deeper than the correction bound"
	if gap_after < -slop or gap_before < -slop:
		return "resolution — an authoritative end pose overlaps past the contact slop"
	if gap_mid < -slop or centre_mid + slop < volumes:
		return "presentation — the authoritative ends are within slop and the interpolated chord overlaps"
	if drawn_before + slop < centre_before or drawn_mid + slop < centre_mid or drawn_after + slop < centre_after:
		return "presentation — a drawn blade axis is closer than the authoritative centreline"
	return "clear — authoritative ends and the chord stay within slop or apart, and the drawn axes match the planar blades"


func _write(lines: PackedStringArray) -> void:
	var text := "\n".join(lines)
	print(text)
	var file := FileAccess.open(_out.path_join("clash_report.txt"), FileAccess.WRITE)
	file.store_string(text + "\n")
	file.close()
