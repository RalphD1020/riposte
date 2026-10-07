class_name DebugVectors3D
extends MeshInstance3D

## The physical quantities a duel is made of, drawn in the world (UX §54). A
## development and training aid rather than a feature: the text overlay tells
## you a number, and this tells you where it points.
##
## Each fighter gets their body velocity, the direction their blade tip is
## actually travelling, and a mark at the percussion band of the blade. All
## three are read straight off `PresentationSnapshot` — this draws
## authoritative quantities and derives nothing, which is exactly why it can
## be trusted as a debugging tool at all (PRES-001).
##
## One ImmediateMesh of line primitives, rebuilt only while visible.
##
## Implements: /spec/invariants.md#combat-009
## See also: /docs/concepts/presentation.md, /docs/concepts/ux.md

## Metres drawn per m/s, so a vector's length is a readable speed rather than
## an arbitrary arrow.
const VELOCITY_SCALE := 0.25
const TIP_SCALE := 0.06
## Height the body vectors are drawn at, clear of the floor markings.
const BODY_HEIGHT := 0.12
## Half-length of the cross marking the sweet region.
const SWEET_MARK := 0.07

var _lines := ImmediateMesh.new()
var _blade_height: float = 1.0


static func create(blade_height: float) -> DebugVectors3D:
	var vectors := DebugVectors3D.new()
	vectors.name = "DebugVectors"
	vectors.mesh = vectors._lines
	vectors._blade_height = blade_height
	vectors.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vectors.visible = false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	vectors.material_override = material
	return vectors


func update(snapshot: PresentationSnapshot) -> void:
	if not visible or snapshot == null:
		## Hidden is the normal case and must cost nothing. Clearing an
		## already-empty mesh every frame is work whose only result is the
		## state it was already in.
		if _lines.get_surface_count() > 0:
			_lines.clear_surfaces()
		return
	_rebuild(snapshot)


func line_count() -> int:
	return _lines.get_surface_count()


func _rebuild(snapshot: PresentationSnapshot) -> void:
	_lines.clear_surfaces()
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for slot in 2:
		var row := snapshot.fighter(slot)
		var body := ArenaTransform.to_world(row.x, row.y, BODY_HEIGHT)
		## Where the body is going, at a scale where a walk and a dash are
		## visibly different lengths.
		_segment(body, body + Vector3(row.vx, 0.0, -row.vy) * VELOCITY_SCALE, RiposteTheme.SPARK)
		var hilt := ArenaTransform.to_world(row.x, row.y, _blade_height)
		var tip := ArenaTransform.to_world(
			row.x + row.tip_radius * cos(row.weapon_angle), row.y + row.tip_radius * sin(row.weapon_angle), _blade_height
		)
		## The tip's own travel: perpendicular to the blade, signed by which
		## way it is swinging. This is the vector that decides everything at
		## contact, and the one players most often guess wrong.
		var along := (tip - hilt).normalized()
		var across := along.rotated(Vector3.UP, PI * 0.5) * row.swing_dir
		_segment(tip, tip + across * row.tip_speed * TIP_SCALE, RiposteTheme.CRITICAL)
		## And the percussion band, as a cross on the blade itself.
		var mid := hilt.lerp(tip, (SwingSemantics.SWEET_REGION_MIN + SwingSemantics.SWEET_REGION_MAX) * 0.5)
		_segment(mid - across * SWEET_MARK, mid + across * SWEET_MARK, RiposteTheme.BODY_IMPACT)
	_lines.surface_end()


func _segment(from: Vector3, to: Vector3, color: Color) -> void:
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(from)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(to)
