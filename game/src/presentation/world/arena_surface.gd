class_name ArenaSurfaceState
extends Node3D

## The fighting disc. A flat sand top and a wooden side. It does not react to
## the fight, and it adds no collider.
##
## See also: /docs/concepts/presentation.md

const SIDE_DROP := 0.4
const SIDE_SEGMENTS := 64
## How much of the top, in from the combat edge, is the wooden rim.
const RIM_WIDTH := 0.35


static func create(platform_radius: float) -> ArenaSurfaceState:
	var surface := ArenaSurfaceState.new()
	surface.name = "SandSurface"
	surface._build(platform_radius)
	return surface


func _build(platform_radius: float) -> void:
	var sand_radius := maxf(platform_radius - RIM_WIDTH, 0.5)
	var top := MeshInstance3D.new()
	top.name = "Top"
	top.mesh = _disc_mesh(sand_radius)
	top.material_override = _flat(RiposteTheme.SAND, 1.0)
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(top)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = _annulus_mesh(sand_radius, platform_radius + 0.01)
	rim.material_override = _flat(RiposteTheme.WOOD, 0.9)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)
	var side := MeshInstance3D.new()
	side.name = "Side"
	side.mesh = _side_mesh(platform_radius)
	side.material_override = _flat(RiposteTheme.WOOD, 0.9)
	side.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(side)


func _flat(ink: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = ink
	material.roughness = roughness
	material.metallic = 0.0
	return material


func _disc_mesh(platform_radius: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3.ZERO
	for index: int in SIDE_SEGMENTS:
		var a0 := TAU * float(index) / float(SIDE_SEGMENTS)
		var a1 := TAU * float(index + 1) / float(SIDE_SEGMENTS)
		tool.add_vertex(center)
		tool.add_vertex(Vector3(cos(a0) * platform_radius, 0.0, sin(a0) * platform_radius))
		tool.add_vertex(Vector3(cos(a1) * platform_radius, 0.0, sin(a1) * platform_radius))
	tool.generate_normals()
	return tool.commit()


func _annulus_mesh(inner: float, outer: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in SIDE_SEGMENTS:
		var a0 := TAU * float(index) / float(SIDE_SEGMENTS)
		var a1 := TAU * float(index + 1) / float(SIDE_SEGMENTS)
		var i0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var i1 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		var o0 := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
		var o1 := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
		tool.add_vertex(i0)
		tool.add_vertex(o0)
		tool.add_vertex(i1)
		tool.add_vertex(i1)
		tool.add_vertex(o0)
		tool.add_vertex(o1)
	tool.generate_normals()
	return tool.commit()


func _side_mesh(platform_radius: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lip := platform_radius + 0.01
	for index: int in SIDE_SEGMENTS:
		var a0 := TAU * float(index) / float(SIDE_SEGMENTS)
		var a1 := TAU * float(index + 1) / float(SIDE_SEGMENTS)
		var p0 := Vector3(cos(a0) * lip, 0.0, sin(a0) * lip)
		var p1 := Vector3(cos(a1) * lip, 0.0, sin(a1) * lip)
		var q0 := Vector3(p0.x, -SIDE_DROP, p0.z)
		var q1 := Vector3(p1.x, -SIDE_DROP, p1.z)
		## Outward. The previous order faced the arena, so the rim you see was the sand.
		tool.add_vertex(p0)
		tool.add_vertex(p1)
		tool.add_vertex(q0)
		tool.add_vertex(p1)
		tool.add_vertex(q1)
		tool.add_vertex(q0)
	tool.generate_normals()
	return tool.commit()
