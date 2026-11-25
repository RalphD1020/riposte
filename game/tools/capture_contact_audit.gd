extends SceneTree

## WEAPON-PATH-CONSISTENCY audit (WEAPON-PATH-004 Stage 5): real dynamic sword contacts — Hard CPU against Hard CPU
## through the real `DuelSimulation`, the product `MatchPresenter` and the gameplay `DuelCameraRig` — read on the drawn
## swords at every contact tick (`ContactRenderAudit`): both swing origins, touches, glances, clashes, arrests,
## rebounds and binds, blade on blade and blade on guard. Pass 1 measures every manifold point; pass 2 replays the same
## seeds (deterministic) and shoots the first and the worst sample of each category through the gameplay camera with
## the probe overlay (the solver's planar steel at the contact height, the drawn steel axes, the solver point, the
## drawn stations) and a SKELETON-CAPTURE sidecar whose `extra` holds the readings. This is not a boot of
## `main.tscn` — no HUD, no menu. Windowed, not `--headless`:
##
##   godot --path game --rendering-method gl_compatibility --resolution 1280x720 -s res://tools/capture_contact_audit.gd [-- --out=<dir> --seeds=3,9,17 --ticks=3600]

const FRAME := 1.0 / 60.0
## A contact held this many ticks reads as a bind.
const BIND_TICKS := 6
const SOLVER_COLOR := Color(1.0, 0.85, 0.1)
const DRAWN_COLOR := Color(0.2, 0.9, 1.0)
const POINT_COLOR := Color(1.0, 0.2, 0.2)
const STATION_COLOR := Color(0.3, 1.0, 0.3)
const MARK := 0.025

var _rules: DuelRules
var _kits: DuelKits
var _out: String = ""
var _seeds := PackedInt32Array([3, 9, 17])
var _ticks: int = 3600
var _samples: Array[Dictionary] = []
var _shots_taken: Array[Dictionary] = []
var _geometry := SwordContactGeometry.new()


func _init() -> void:
	SkeletonCapture.watch(self)
	_rules = StandardDuelRules.create()
	_kits = DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	_kits.match_loadout = RiposteKits.match_loadout(_kits.arena)
	_out = ProjectSettings.globalize_path("res://../.reports/contact_audit")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--seeds="):
			_seeds = PackedInt32Array()
			for part in argument.trim_prefix("--seeds=").split(","):
				_seeds.append(int(part))
		elif argument.begins_with("--ticks="):
			_ticks = int(argument.trim_prefix("--ticks="))
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	for seed_value in _seeds:
		await _play(seed_value, {})
	var plan := _plan()
	var recorded := _samples.size()
	for seed_value in _seeds:
		if plan.has(seed_value):
			print("contact audit: seed %d shoots ticks %s" % [seed_value, str((plan[seed_value] as Dictionary).keys())])
			await _play(seed_value, plan[seed_value], false)
	print("contact audit: %d planned shots, %d taken (%d samples recorded in pass 1)" % [_count(plan), _shots_taken.size(), recorded])
	_write()
	quit()


## Play one seed. `shots` maps tick → [label, point] to shoot in this pass; `record` keeps the readings.
func _play(seed_value: int, shots: Dictionary, record: bool = true) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var rig := DuelCameraRig.new()
	world.add_child(rig)
	rig.configure(RiposteKits.camera_profile())
	var simulation := DuelSimulation.create(_rules)
	var state := simulation.new_match(seed_value)
	var presenter := MatchPresenter.create(_kits, PresentationOptions.new(), rig, _rules.platform_radius, _rules.edge_warning_inset, SnapshotProjector.project(state, _rules))
	world.add_child(presenter)
	var overlay := _overlay(world)
	var cpus := [CpuController.create(_rules, CpuProfile.hard(), seed_value, 0), CpuController.create(_rules, CpuProfile.hard(), seed_value, 1)]
	presenter.render(1.0, FRAME, FRAME)
	rig.camera().make_current()
	var before := ContactRenderAudit.weapons(presenter)
	for _tick in _ticks:
		if state.phase == MatchPhase.Id.MATCH_ENDED:
			break
		var events := simulation.step(state, (cpus[0] as CpuController).command_for(state, 0), (cpus[1] as CpuController).command_for(state, 1))
		presenter.push(SnapshotProjector.project(state, _rules), events)
		var contact := state.blade_contact
		var touching := contact.phase == SwordContactSet.Phase.CONTACTING and contact.is_touching()
		var snaps := {}
		if touching:
			## The first frame of the interval that begins a contact, against the last frame drawn (expected unmoved).
			presenter.render(0.0, 0.0, 0.0)
			for point in contact.point_count:
				if contact.age[point] == 0:
					snaps[point] = ContactRenderAudit.onset(presenter, state, _rules, rig.camera(), point, before)
		presenter.render(1.0, FRAME, FRAME)
		if touching:
			var impact := _impact(events)
			for point in contact.point_count:
				var reading := ContactRenderAudit.measure(presenter, state, _rules, rig.camera(), point, _geometry)
				if snaps.has(point):
					reading.merge(snaps[point])
				reading["seed"] = seed_value
				reading["tick"] = state.tick
				reading["point"] = point
				reading["category"] = _category(state, contact.age[point], impact)
				reading["pair_name"] = ["blades", "blade_on_guard", "guard_on_blade"][contact.pair[point]]
				if record:
					_samples.append(reading)
				if shots.has(state.tick) and int(shots[state.tick][1]) == point:
					await _shot(overlay, presenter, state, rig.camera(), point, String(shots[state.tick][0]), reading)
		before = ContactRenderAudit.weapons(presenter)
	world.queue_free()
	await process_frame


## The first blade contact event this tick, if any.
func _impact(events: Array[DuelEvent]) -> DuelEvent:
	for event in events:
		if event.type == DuelEventTypes.BLADE_CONTACT:
			return event
	return null


## kind / origin: a first touch by what the cut kept (touch / glance / clash), arrested, or rebounding; a contact held
## `BIND_TICKS` a bind; the origin side of the swing(s) in it.
func _category(state: MatchState, age: int, impact: DuelEvent) -> String:
	var kind := "held"
	if age >= BIND_TICKS:
		kind = "bind"
	elif age == 0 and impact != null:
		var control := _rules.combatant(0).weapon.control_speed
		kind = String(ContactReading.classify(impact, control, _rules.combatant(1).weapon.control_speed))
		if impact.data.has(DuelEventKeys.PROGRESS_AFTER) and impact.number(DuelEventKeys.PROGRESS_AFTER) < 0.0:
			kind = "rebound"
		elif bool(impact.data.get(DuelEventKeys.ARRESTED_0, false)) or bool(impact.data.get(DuelEventKeys.ARRESTED_1, false)):
			kind = "arrest"
	var origins := PackedStringArray()
	for slot in 2:
		var weapon := state.fighter(slot).weapon
		if CombatPresentationField.is_swing(weapon.phase) or weapon.phase == CombatPhase.Id.RECOVERY:
			origins.append("right" if weapon.swing_dir > 0.0 else "left")
	var origin := "guard" if origins.is_empty() else ("both" if origins.size() == 2 else origins[0])
	return "%s/%s" % [kind, origin]


## Per category, the first sample and the worst by screen discrepancy: seed → {tick: [label, point]}.
func _plan() -> Dictionary:
	var chosen := {}
	for sample in _samples:
		var category: String = sample["category"]
		var px := float(sample.get("witness_px", 0.0))
		if not chosen.has(category):
			chosen[category] = {"first": sample, "worst": sample, "worst_px": px}
		elif px > float(chosen[category]["worst_px"]):
			chosen[category]["worst"] = sample
			chosen[category]["worst_px"] = px
	var plan := {}
	for category: String in chosen:
		for which: String in ["first", "worst"]:
			var sample: Dictionary = chosen[category][which]
			var seed_value := int(sample["seed"])
			if not plan.has(seed_value):
				plan[seed_value] = {}
			plan[seed_value][int(sample["tick"])] = ["%s_%s" % [category.replace("/", "_"), which], int(sample["point"])]
	return plan


func _count(plan: Dictionary) -> int:
	var total := 0
	for seed_value: int in plan:
		total += (plan[seed_value] as Dictionary).size()
	return total


func _overlay(world: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "ContactAuditOverlay"
	node.mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	node.material_override = material
	node.visible = false
	world.add_child(node)
	return node


func _shot(overlay: MeshInstance3D, presenter: MatchPresenter, state: MatchState, camera: Camera3D, point: int, label: String, reading: Dictionary) -> void:
	var mesh := overlay.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var height := presenter.contact_height()
	var contact := state.blade_contact
	var weapons := {}
	for slot in 2:
		var spec := _rules.combatant(slot)
		var planar := WeaponKinematics.pose_of(state.fighter(slot), spec, BladePose.new())
		var steel := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
		SwordContactGeometry.place(planar.origin_x, planar.origin_y, planar.ux, planar.uy, spec.weapon, steel)
		if not is_nan(height):
			_line(mesh, ArenaTransform.to_world(steel[0], steel[1], height), ArenaTransform.to_world(steel[2], steel[3], height), SOLVER_COLOR)
		var proxy := presenter.fighter_proxy(slot)
		var into_world := proxy.visual_root().global_transform
		var pose := proxy.weapon_pose()
		var drawn_from := into_world * pose.station(spec.weapon.guard_root_apex_radius())
		var drawn_to := into_world * pose.tip()
		_line(mesh, drawn_from, drawn_to, DRAWN_COLOR)
		var fraction := contact.fraction_a[point] if slot == 0 else contact.fraction_b[point]
		var station := into_world * pose.station(ContactPresentation.along(fraction, spec.weapon))
		_cross(mesh, station, STATION_COLOR)
		weapons["slot_%d" % slot] = {"steel_from": _vector(drawn_from), "steel_to": _vector(drawn_to), "station": _vector(station),
			"steel_from_px": _pixel(camera, drawn_from), "steel_to_px": _pixel(camera, drawn_to), "station_px": _pixel(camera, station)}
	if not is_nan(height):
		var solver := ArenaTransform.to_world(contact.point_x[point], contact.point_y[point], height)
		_cross(mesh, solver, POINT_COLOR)
		weapons["solver_point"] = _vector(solver)
		weapons["solver_point_px"] = _pixel(camera, solver)
	mesh.surface_end()
	overlay.visible = true
	for _i in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := _out.path_join(label + ".png")
	SkeletonCapture.save(root, path, "capture_contact_audit", {"contact_audit": reading, "weapons": weapons, "viewport": [root.size.x, root.size.y]})
	_shots_taken.append({"label": label, "file": path.get_file(), "seed": reading["seed"], "tick": reading["tick"]})
	overlay.visible = false


func _line(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to)


func _cross(mesh: ImmediateMesh, at: Vector3, color: Color) -> void:
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_line(mesh, at - axis * MARK, at + axis * MARK, color)


func _pixel(camera: Camera3D, at: Vector3) -> Array:
	var pixel := camera.unproject_position(at)
	return [snappedf(pixel.x, 0.01), snappedf(pixel.y, 0.01)]


func _vector(v: Vector3) -> Array:
	return [snappedf(v.x, 0.00001), snappedf(v.y, 0.00001), snappedf(v.z, 0.00001)]


## The readings (one JSON line per manifold point), per-category percentiles and the shot list.
func _write() -> void:
	var lines := PackedStringArray()
	for sample in _samples:
		lines.append(JSON.stringify(sample))
	var samples_file := FileAccess.open(_out.path_join("contact_audit_samples.jsonl"), FileAccess.WRITE)
	samples_file.store_string("\n".join(lines) + "\n")
	samples_file.close()
	var by_category := {}
	for sample in _samples:
		var category: String = "%s %s" % [sample["category"], sample["pair_name"]]
		if not by_category.has(category):
			by_category[category] = []
		(by_category[category] as Array).append(sample)
	var report := PackedStringArray()
	report.append("contact render audit: seeds %s, up to %d ticks each, Hard CPU vs Hard CPU, viewport %dx%d, gameplay DuelCameraRig" % [str(_seeds), _ticks, root.size.x, root.size.y])
	report.append("samples: %d manifold points" % _samples.size())
	report.append("all %s" % _stats(_samples))
	var names := by_category.keys()
	names.sort()
	for category: String in names:
		report.append("%s (n %d): %s" % [category, (by_category[category] as Array).size(), _stats(by_category[category])])
	report.append("shots:")
	for shot in _shots_taken:
		report.append("  %s seed %d tick %d" % [shot["file"], shot["seed"], shot["tick"]])
	var text := "\n".join(report)
	print(text)
	var file := FileAccess.open(_out.path_join("contact_audit_report.txt"), FileAccess.WRITE)
	file.store_string(text + "\n")
	file.close()


func _stats(samples: Array) -> String:
	var parts := PackedStringArray()
	var features := 0
	var ambiguous := 0
	for sample: Dictionary in samples:
		if bool(sample.get("feature", false)):
			features += 1
		if bool(sample.get("ambiguous", false)):
			ambiguous += 1
	parts.append("solver feature found %d/%d, near-parallel (station ambiguous) %d" % [features, samples.size(), ambiguous])
	for field: String in ContactRenderAudit.FIELDS:
		var values := PackedFloat64Array()
		for sample: Dictionary in samples:
			if sample.has(field):
				values.append(float(sample[field]))
		if values.is_empty():
			continue
		values.sort()
		parts.append("%s p50 %.4f p95 %.4f max %.4f" % [field, values[int(0.5 * (values.size() - 1))], values[int(0.95 * (values.size() - 1))], values[values.size() - 1]])
	return "; ".join(parts)
