class_name ElbowDebugOverlay3D
extends MeshInstance3D

## The elbow solve and the fighter's orientation, drawn on the fighter
## (PRES-ARMS-001, HEADING-001). One diagnostic with the world vectors:
## shoulder → actual elbow → hand, a cross at the guide the pole was built
## from, a tick out to the pole, the torso / head clearance proxies, and on the
## ground the target bearing τ (red), the combat heading φ (blue) and the
## bladed stance's heading (green), with the authoritative sword (white) on its
## plane — so a lagging heading or a drawn sword off its truth is visible.
## Hidden is the normal case and rebuilds nothing.
##
## See also: /docs/concepts/presentation.md

const CROSS := 0.035
const ELLIPSE_STEPS := 12
const HEADING_HEIGHT := 0.05
const HEADING_LENGTH := 0.9

var _lines := ImmediateMesh.new()


static func create() -> ElbowDebugOverlay3D:
	var overlay := ElbowDebugOverlay3D.new()
	overlay.name = "ElbowDebug"
	overlay.mesh = overlay._lines
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.visible = false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	overlay.material_override = material
	return overlay


func line_count() -> int:
	return _lines.get_surface_count()


func clear() -> void:
	if _lines.get_surface_count() > 0:
		_lines.clear_surfaces()


## Redraw from the proxy's last solved pose. Cheap while hidden.
func redraw(proxy: FighterPresentation3D) -> void:
	if not visible:
		clear()
		return
	var rig := proxy.rig()
	if rig == null or not rig.is_bound():
		clear()
		return
	var skel := rig.skeleton()
	var guides := proxy.elbow_guides()
	var root := proxy.visual_root()
	var into := proxy.global_transform.affine_inverse()
	_lines.clear_surfaces()
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for arm in 2:
		var tag := "R" if arm == 0 else "L"
		var shoulder := _bone(skel, into, "UpperArm." + tag)
		var elbow := _bone(skel, into, "Forearm." + tag)
		var hand := _bone(skel, into, "Hand." + tag)
		if not shoulder.is_empty() and not elbow.is_empty() and not hand.is_empty():
			_segment(shoulder[0], elbow[0], RiposteTheme.SPARK)
			_segment(elbow[0], hand[0], RiposteTheme.SPARK)
		if guides == null or root == null:
			continue
		var guide := into * (root.global_transform * guides.guides[arm])
		var pole := into * (root.global_transform * guides.poles[arm])
		_cross(guide, RiposteTheme.CRITICAL)
		_segment(guide, pole, RiposteTheme.GRIND)
	var stance := proxy.combatant_kit().fighter.stance
	if stance != null:
		_proxies(skel, into, stance.self_clearance())
	_headings(proxy, rig, into)
	_lines.surface_end()


## φ is the proxy's own forward; τ and the stance are turned off it.
func _headings(proxy: FighterPresentation3D, rig: SwordRig3D, into: Transform3D) -> void:
	var foot := Vector3(0.0, HEADING_HEIGHT, 0.0)
	_segment(foot, foot + _yawed(0.0) * HEADING_LENGTH, RiposteTheme.DEBUG_COMBAT_HEADING)
	_segment(foot, foot + _yawed(proxy.look_offset()) * HEADING_LENGTH, RiposteTheme.DEBUG_TARGET_BEARING)
	_segment(foot, foot + _yawed(rig.rotation.y) * HEADING_LENGTH * 0.6, RiposteTheme.DEBUG_STANCE)
	var blade := proxy.authoritative_blade_points()
	_segment(into * blade[0], into * blade[1], RiposteTheme.DEBUG_SWORD)


## Local +Z turned by `yaw` (+ toward the fighter's left, +X).
static func _yawed(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


func _bone(skel: Skeleton3D, into: Transform3D, bone_name: String) -> PackedVector3Array:
	var index := skel.find_bone(bone_name)
	if index < 0:
		return PackedVector3Array()
	return PackedVector3Array([into * (skel.global_transform * skel.get_bone_global_pose(index).origin)])


func _proxies(skel: Skeleton3D, into: Transform3D, profile: SelfClearanceProfile) -> void:
	for shell: Array in profile.torso_shells:
		var bone := skel.find_bone(String(shell[0]))
		if bone < 0:
			continue
		var y := (float(shell[1]) + float(shell[2])) * 0.5
		_ellipse(skel, into, bone, y, float(shell[3]), float(shell[4]), RiposteTheme.WORLD_RIM)
	var head := skel.find_bone(String(profile.head_bone))
	if head < 0:
		return
	var rest := skel.get_bone_global_rest(head)
	var centre_rest := Vector3(rest.origin.x, profile.head_center_height, rest.origin.z)
	var centre := skel.get_bone_global_pose(head) * (rest.affine_inverse() * centre_rest)
	_circle(into * (skel.global_transform * centre), profile.head_radius, RiposteTheme.WORLD_RIM)


func _ellipse(skel: Skeleton3D, into: Transform3D, bone: int, y: float, half_width: float, half_depth: float, color: Color) -> void:
	var rest := skel.get_bone_global_rest(bone)
	var pose := skel.get_bone_global_pose(bone)
	var carry := skel.global_transform * pose * rest.affine_inverse()
	var previous := Vector3.ZERO
	for step in ELLIPSE_STEPS + 1:
		var turns := TAU * float(step) / float(ELLIPSE_STEPS)
		var at := into * (carry * Vector3(half_width * cos(turns), y, half_depth * sin(turns)))
		if step > 0:
			_segment(previous, at, color)
		previous = at


func _circle(centre: Vector3, radius: float, color: Color) -> void:
	var previous := Vector3.ZERO
	for step in ELLIPSE_STEPS + 1:
		var turns := TAU * float(step) / float(ELLIPSE_STEPS)
		var at := centre + Vector3(radius * cos(turns), 0.0, radius * sin(turns))
		if step > 0:
			_segment(previous, at, color)
		previous = at


func _cross(at: Vector3, color: Color) -> void:
	_segment(at + Vector3(-CROSS, 0.0, -CROSS), at + Vector3(CROSS, 0.0, CROSS), color)
	_segment(at + Vector3(-CROSS, 0.0, CROSS), at + Vector3(CROSS, 0.0, -CROSS), color)


func _segment(from: Vector3, to: Vector3, color: Color) -> void:
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(from)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(to)
