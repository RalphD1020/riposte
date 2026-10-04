class_name SwordTrail3D
extends MeshInstance3D

## World-space ribbon behind a moving blade (UX §19): length follows angular
## speed (samples are only added while the blade is fast), opacity follows
## recency. One ImmediateMesh rebuilt per frame from a bounded sample ring.
##
## See also: /docs/concepts/presentation.md

const LIFETIME := 0.14
## The ribbon is fainter at the hilt than at the tip.
const HILT_ALPHA := 0.55
const TIP_ALPHA := 0.85

var _ribbon := ImmediateMesh.new()
var _capacity: int = 10
var _hilts := PackedVector3Array()
var _tips := PackedVector3Array()
var _ages := PackedFloat32Array()
var _color: Color = Color.WHITE


static func create(color: Color, capacity: int) -> SwordTrail3D:
	var trail := SwordTrail3D.new()
	trail.name = "SwordTrail"
	trail._color = color
	trail._capacity = maxi(capacity, 2)
	trail.mesh = trail._ribbon
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail.material_override = material
	return trail


func add_sample(hilt: Vector3, tip: Vector3, speed: float, min_speed: float) -> void:
	if speed < min_speed:
		return
	_hilts.append(hilt)
	_tips.append(tip)
	_ages.append(0.0)
	if _hilts.size() > _capacity:
		_hilts.remove_at(0)
		_tips.remove_at(0)
		_ages.remove_at(0)


func advance(delta: float) -> void:
	for i in range(_ages.size() - 1, -1, -1):
		_ages[i] += delta
		if _ages[i] > LIFETIME:
			_hilts.remove_at(i)
			_tips.remove_at(i)
			_ages.remove_at(i)
	_rebuild()


func clear_trail() -> void:
	_hilts.clear()
	_tips.clear()
	_ages.clear()
	_ribbon.clear_surfaces()


func sample_count() -> int:
	return _hilts.size()


func _rebuild() -> void:
	_ribbon.clear_surfaces()
	if _hilts.size() < 2:
		return
	_ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _hilts.size():
		var fade := clampf(1.0 - _ages[i] / LIFETIME, 0.0, 1.0) * float(i + 1) / float(_hilts.size())
		_ribbon.surface_set_color(Color(_color, HILT_ALPHA * fade))
		_ribbon.surface_add_vertex(_hilts[i])
		_ribbon.surface_set_color(Color(_color, TIP_ALPHA * fade))
		_ribbon.surface_add_vertex(_tips[i])
	_ribbon.surface_end()
