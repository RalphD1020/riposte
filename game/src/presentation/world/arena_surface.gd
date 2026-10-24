class_name ArenaSurfaceState
extends Node3D

## The fighting floor. One sand surface at `y = 0`, the same twelve-sided
## interior as the wall, tucked under the first course. One colour. No
## prints. It adds no collider. The wall is the bowl.
##
## See also: /docs/concepts/presentation.md

const SIDE_SEGMENTS := 64
## `arena_masonry._pit_bay` sets the first course this far outside the
## combat radius, so a block corner stays out of the disc.
const STONE_FACE_OUTSET := 0.08
## How far the sand continues under that course. The flats sit past the
## stone face. The corners stay inside the wall's outer radius.
const SAND_UNDERLAP := 0.16

var _sides := 0
var _apothem := 0.0
var _angular_zero := 0.0


static func face_distance(wall_inner: float) -> float:
	return wall_inner + STONE_FACE_OUTSET + SAND_UNDERLAP


## Corner radius of the twelve-sided floor. The sword ground uses these
## same points, so the two outlines cannot drift.
static func corner_radius(apothem: float, sides: int) -> float:
	return apothem / cos(PI / float(sides))


static func rim_points(sides: int, apothem: float, angular_zero: float) -> PackedVector3Array:
	var reach := corner_radius(apothem, sides)
	var points := PackedVector3Array()
	for index: int in sides:
		var angle := angular_zero + TAU * (float(index) + 0.5) / float(sides)
		points.append(Vector3(cos(angle) * reach, 0.0, sin(angle) * reach))
	return points


static func create(platform_radius: float, layout: ArenaSection = null) -> ArenaSurfaceState:
	var surface := ArenaSurfaceState.new()
	surface.name = "SandSurface"
	if layout != null and layout.pit and layout.bay_count >= 3 and layout.issues().is_empty():
		surface._sides = layout.bay_count
		surface._apothem = face_distance(layout.wall_inner)
		surface._angular_zero = layout.angular_zero
		surface._build_shell(layout.bay_count, face_distance(layout.wall_inner), layout.angular_zero)
	else:
		surface._build_disc(platform_radius)
	return surface


func _build_shell(sides: int, apothem: float, angular_zero: float) -> void:
	var top := MeshInstance3D.new()
	top.name = "Top"
	top.mesh = _shell_mesh(sides, apothem, angular_zero)
	top.material_override = _flat(RiposteTheme.SAND, 1.0)
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(top)


func _build_disc(radius: float) -> void:
	var top := MeshInstance3D.new()
	top.name = "Top"
	top.mesh = _disc_mesh(radius)
	top.material_override = _flat(RiposteTheme.SAND, 1.0)
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(top)


func _flat(ink: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = ink
	material.roughness = roughness
	material.metallic = 0.0
	return material


## Flats face each bay. Godot's front face is clockwise, so the fan follows
## the bay angle and the lit side is the top.
func _shell_mesh(sides: int, apothem: float, angular_zero: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3.ZERO
	var rim := rim_points(sides, apothem, angular_zero)
	for index: int in sides:
		var a0: Vector3 = rim[index]
		var a1: Vector3 = rim[(index + 1) % sides]
		tool.add_vertex(center)
		tool.add_vertex(a0)
		tool.add_vertex(a1)
	tool.generate_normals()
	return tool.commit()


func _disc_mesh(radius: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3.ZERO
	for index: int in SIDE_SEGMENTS:
		var a0 := TAU * float(index) / float(SIDE_SEGMENTS)
		var a1 := TAU * float(index + 1) / float(SIDE_SEGMENTS)
		tool.add_vertex(center)
		tool.add_vertex(Vector3(cos(a0) * radius, 0.0, sin(a0) * radius))
		tool.add_vertex(Vector3(cos(a1) * radius, 0.0, sin(a1) * radius))
	tool.generate_normals()
	return tool.commit()
