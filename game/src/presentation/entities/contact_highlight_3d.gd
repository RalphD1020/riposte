class_name ContactHighlight3D
extends Node3D

## Optional accessibility cue: a ring on every point where the swords actually
## touch (CONTACT-PRESENTATION-001), at the shared rendered contact height,
## so a bind, a slide or a two-point lock reads without sound, sparks or a
## sharp eye. It draws the snapshot's contact set and nothing else — never a
## prediction, never a nearest-approach guess.
##
## A dark ring around a light one reads on any background, and it is a shape,
## not a colour (UX-001). Drawn over the blades (no depth test) because the
## point is usually where both blades hide it. The pool is the contact set's
## own capacity, built once; a switched-off highlight is never created.
##
## See also: /docs/concepts/presentation.md

const OUTER_RADIUS := 0.055
const INNER_RADIUS := 0.038
const RING_THICKNESS := 0.012

var _markers: Array[Node3D] = []
var _shown: int = 0


static func create() -> ContactHighlight3D:
	var highlight := ContactHighlight3D.new()
	highlight.name = "ContactHighlight"
	var outer := _ring_mesh(OUTER_RADIUS, RiposteTheme.STEEL_900, 0)
	var inner := _ring_mesh(INNER_RADIUS, RiposteTheme.TEXT_ON_DARK, 1)
	for index in SwordContactSet.CAPACITY:
		var point := Node3D.new()
		point.name = "Contact%d" % index
		point.visible = false
		for mesh: Mesh in [outer, inner]:
			var ring := MeshInstance3D.new()
			ring.mesh = mesh
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			point.add_child(ring)
		highlight.add_child(point)
		highlight._markers.append(point)
	return highlight


## Show one ring per touching point at `height` (m above the platform).
func show_contacts(contacts: Array[PresentationContact], height: float) -> void:
	var count := mini(contacts.size(), _markers.size())
	for index in count:
		_markers[index].position = ArenaTransform.to_world(contacts[index].x, contacts[index].y, height)
		_markers[index].visible = true
	for index in range(count, _shown):
		_markers[index].visible = false
	_shown = count


func shown_count() -> int:
	return _shown


func marker(index: int) -> Node3D:
	return _markers[index]


static func _ring_mesh(radius: float, color: Color, priority: int) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - RING_THICKNESS
	mesh.outer_radius = radius
	mesh.rings = 24
	mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	material.render_priority = priority
	mesh.material = material
	return mesh
