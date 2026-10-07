class_name SwordTrail3D
extends MeshInstance3D

## World-space ribbon behind a moving blade (UX §19). It is a *reading* of the
## swing rather than decoration: every sample carries the `swing_potential` the
## simulation computed at that instant, and the ribbon's silhouette thickness
## and opacity come from it. Thin while the swing is still gathering, thickest
## through the part of the arc that is genuinely most dangerous, tapering as the
## swing spends itself.
##
## Because potential is read from the blade and not from the input that produced
## it, the strongest part of the ribbon lands in a slightly different place every
## swing (COMBAT-009). There is nothing authored here to memorize, and nothing
## here is predictive: the ribbon says how dangerous this swing *is*, never what
## it would do to the other fighter.
##
## The percussion band of the blade is drawn as a separate, narrower rib
## floating just above the ribbon, so the sweet region reads as a distinct
## *shape* and not merely a tint. Colour only reinforces it (UX §54).
##
## One ImmediateMesh rebuilt per frame from a bounded sample ring: two fighters
## of at most sixteen samples each, so the whole effect is a few dozen vertices
## and no allocation per frame beyond the mesh surfaces themselves.
##
## Implements: /spec/invariants.md#combat-009
## See also: /docs/concepts/presentation.md, /docs/concepts/combat.md

const LIFETIME := 0.14
## The ribbon is fainter at the hilt than at the tip.
const HILT_ALPHA := 0.55
const TIP_ALPHA := 0.85
## Silhouette half-thickness (m) at zero and at full swing potential. The band
## is two parallel sheets this far either side of the sweep plane: from any
## angle but exactly edge-on, that spacing *is* its apparent thickness, and it
## costs one extra strip rather than a solid extruded volume.
const WIDTH_SPENT := 0.006
const WIDTH_FULL := 0.05
## The sweet rib floats this far above the band, is this much brighter, and is
## not drawn at all below this potential — a blade that threatens nobody has no
## sweet region worth pointing at.
const ACCENT_LIFT := 0.014
const ACCENT_LIGHTEN := 0.5
const ACCENT_ALPHA := 0.95
const ACCENT_MIN_POTENTIAL := 0.3

var _ribbon := ImmediateMesh.new()
var _capacity: int = 10
var _hilts := PackedVector3Array()
var _tips := PackedVector3Array()
## Full precision, unlike the ages beside it: an age is a presentation-local
## clock, but a potential is an authoritative reading being carried, and a
## carried value that arrives slightly altered has been invented.
var _potentials := PackedFloat64Array()
var _ages := PackedFloat32Array()
var _color: Color = Color.WHITE
var _strength: float = 1.0
var _sweet: float = 1.0


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


## How prominent the ribbon and the sweet rib are drawn. Accessibility may
## exaggerate both, and `trail` of zero removes the ribbon entirely — neither
## moves the sweet region or changes a single authoritative value (UX §54).
func set_strength(trail: float, sweet: float) -> void:
	_strength = maxf(trail, 0.0)
	_sweet = maxf(sweet, 0.0)


func add_sample(hilt: Vector3, tip: Vector3, potential: float, speed: float, min_speed: float) -> void:
	if speed < min_speed:
		return
	_hilts.append(hilt)
	_tips.append(tip)
	_potentials.append(clampf(potential, 0.0, 1.0))
	_ages.append(0.0)
	if _hilts.size() > _capacity:
		_hilts.remove_at(0)
		_tips.remove_at(0)
		_potentials.remove_at(0)
		_ages.remove_at(0)


func advance(delta: float) -> void:
	for i in range(_ages.size() - 1, -1, -1):
		_ages[i] += delta
		if _ages[i] > LIFETIME:
			_hilts.remove_at(i)
			_tips.remove_at(i)
			_potentials.remove_at(i)
			_ages.remove_at(i)
	_rebuild()


func clear_trail() -> void:
	_hilts.clear()
	_tips.clear()
	_potentials.clear()
	_ages.clear()
	_ribbon.clear_surfaces()


func sample_count() -> int:
	return _hilts.size()


func surface_count() -> int:
	return _ribbon.get_surface_count()


func potential_at(index: int) -> float:
	return _potentials[index]


## Half the ribbon's silhouette thickness at one sample (m). Exposed because it
## is the whole readability claim: a dangerous part of a swing is visibly
## thicker than a spent one.
func half_width_at(index: int) -> float:
	return lerpf(WIDTH_SPENT, WIDTH_FULL, _potentials[index]) * _strength


func _rebuild() -> void:
	if _hilts.size() < 2 or _strength <= 0.0:
		## A ribbon switched off is the cheapest thing on screen, not an empty
		## mesh cleared again every frame. Samples still accumulate and age, so
		## switching it back on is immediate.
		if _ribbon.get_surface_count() > 0:
			_ribbon.clear_surfaces()
		return
	_ribbon.clear_surfaces()
	_emit_sheet(1.0)
	_emit_sheet(-1.0)
	if _sweet > 0.0 and _peak_potential() >= ACCENT_MIN_POTENTIAL:
		_emit_sweet_rib()


## One face of the band, offset `side` × the sample's thickness from the sweep
## plane. Older samples fade out, and the ring is walked oldest-first so the
## strip runs with the swing.
func _emit_sheet(side: float) -> void:
	_ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _hilts.size():
		var fade := _fade(i)
		var lift := Vector3.UP * half_width_at(i) * side
		_ribbon.surface_set_color(Color(_color, HILT_ALPHA * fade))
		_ribbon.surface_add_vertex(_hilts[i] + lift)
		_ribbon.surface_set_color(Color(_color, TIP_ALPHA * fade))
		_ribbon.surface_add_vertex(_tips[i] + lift)
	_ribbon.surface_end()


## The percussion band, swept. Drawn as one continuous strip with per-sample
## alpha rather than as broken segments, so a swing passing in and out of
## danger reads as one shape that swells and subsides.
func _emit_sweet_rib() -> void:
	var color := _color.lightened(ACCENT_LIGHTEN)
	_ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _hilts.size():
		var span := _tips[i] - _hilts[i]
		var lift := Vector3.UP * (half_width_at(i) + ACCENT_LIFT * _sweet)
		var alpha := ACCENT_ALPHA * _fade(i) * _emphasis(i) * minf(_sweet, 1.0)
		_ribbon.surface_set_color(Color(color, alpha))
		_ribbon.surface_add_vertex(_hilts[i] + span * SwingSemantics.SWEET_REGION_MIN + lift)
		_ribbon.surface_set_color(Color(color, alpha))
		_ribbon.surface_add_vertex(_hilts[i] + span * SwingSemantics.SWEET_REGION_MAX + lift)
	_ribbon.surface_end()


## Recency times position in the ribbon: the newest sample, nearest the blade,
## is the strongest.
func _fade(index: int) -> float:
	return clampf(1.0 - _ages[index] / LIFETIME, 0.0, 1.0) * float(index + 1) / float(_hilts.size())


func _emphasis(index: int) -> float:
	return clampf((_potentials[index] - ACCENT_MIN_POTENTIAL) / (1.0 - ACCENT_MIN_POTENTIAL), 0.0, 1.0)


func _peak_potential() -> float:
	var peak := 0.0
	for potential in _potentials:
		peak = maxf(peak, potential)
	return peak
