class_name VfxDirector
extends Node3D

## Short, capped impact effects (UX §20–§22): directional sparks for blade
## contact, an expanding ring for body impacts and parries, a streak for
## criticals. Effects shrink to nothing instead of fading, so every effect of
## one kind shares a single material. Never hides blade geometry; Reduced
## Flash scales size and count down. Cosmetic randomness only.
##
## See also: /docs/concepts/presentation.md

const MAX_EFFECTS := 48
const SPARK_SIZE := 0.07
const SPARK_LIFE := 0.22
## Sparks fan ±SPARK_SPREAD rad around the contact normal, rise up to
## SPARK_LIFT, and launch at 50–100% of the requested speed.
const SPARK_SPREAD := 1.1
const SPARK_LIFT := 0.6
const SPARK_SPEED_MIN := 0.5
const RING_LIFE := 0.2
const RING_INNER := 0.3
const RING_OUTER := 0.36
## Rings grow from RING_START to RING_END times their requested size.
const RING_START := 0.4
const RING_END := 1.6
## Burst dust: flat puffs that stay on the floor and spread *backwards* from
## the heading, growing as they settle. Deliberately ground-bound and slow, so
## footwork and a blade ribbon can never share a silhouette (UX §19).
const DUST_LIFE := 0.34
const DUST_HEIGHT := 0.02
const DUST_SIZE := 0.16
const DUST_END_SCALE := 2.1
const DUST_SPREAD := 0.8
const DUST_SPEED_MIN := 0.35
const DUST_ALPHA := 0.4
const STREAK_LIFE := 0.16
const STREAK_WIDTH := 0.05
const STREAK_THICKNESS := 0.02
const STREAK_MIN_LENGTH := 0.01
## Effects draw over the world, after blades (which use priorities 0–1).
const RENDER_PRIORITY := 2
## Godot rejects a zero scale basis; shrink to this instead.
const MIN_SCALE := 0.0001
const COSMETIC_SEED := 7


class Effect:
	var node: MeshInstance3D
	var velocity: Vector3
	var life: float
	var max_life: float
	var start_scale: float
	var end_scale: float


var last_cue: StringName = &""
var _effects: Array[Effect] = []
var _random := RandomNumberGenerator.new()
var _spark_mesh := QuadMesh.new()
var _dust_mesh := QuadMesh.new()
var _ring_mesh := TorusMesh.new()
var _materials: Dictionary = {}


func _init() -> void:
	name = "Vfx"
	_random.seed = COSMETIC_SEED
	_spark_mesh.size = Vector2(SPARK_SIZE, SPARK_SIZE)
	_dust_mesh.size = Vector2(DUST_SIZE, DUST_SIZE)
	_ring_mesh.inner_radius = RING_INNER
	_ring_mesh.outer_radius = RING_OUTER
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 4


## Burst of sparks spraying along `normal` (world, horizontal).
func sparks(world: Vector3, normal: Vector3, color: Color, count: int, speed: float, flash_scale: float) -> void:
	last_cue = PresentationKit.VFX_SPARK
	var total := maxi(1, roundi(float(count) * flash_scale))
	for _i in total:
		var spread := normal.rotated(Vector3.UP, _random.randf_range(-SPARK_SPREAD, SPARK_SPREAD))
		var lift := Vector3.UP * _random.randf_range(0.0, SPARK_LIFT)
		var velocity := (spread + lift).normalized() * speed * _random.randf_range(SPARK_SPEED_MIN, 1.0)
		_spawn(_spark_mesh, _billboard(color), world, velocity, SPARK_LIFE, 1.0, 0.0)


## Floor dust kicked up by a burst of footwork, spraying opposite `heading`
## (world, horizontal) from the fighter's feet.
func dust(world: Vector3, heading: Vector3, color: Color, count: int, speed: float, flash_scale: float) -> void:
	last_cue = PresentationKit.VFX_IMPACT
	var away := -heading
	if away.length_squared() < MIN_SCALE:
		away = Vector3.FORWARD
	away = away.normalized()
	var ground := Vector3(world.x, DUST_HEIGHT, world.z)
	var total := maxi(1, roundi(float(count) * flash_scale))
	for _i in total:
		var spread := away.rotated(Vector3.UP, _random.randf_range(-DUST_SPREAD, DUST_SPREAD))
		var velocity := spread * speed * _random.randf_range(DUST_SPEED_MIN, 1.0)
		var puff := _spawn(_dust_mesh, _flat(Color(color, DUST_ALPHA)), ground, velocity, DUST_LIFE, flash_scale, DUST_END_SCALE * flash_scale)
		## Laid flat on the floor rather than billboarded, so it reads as
		## ground scuff instead of as another airborne spark.
		puff.node.basis = Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0))


func ring(world: Vector3, color: Color, size: float, flash_scale: float) -> void:
	last_cue = PresentationKit.VFX_IMPACT
	_spawn(_ring_mesh, _flat(color), world, Vector3.ZERO, RING_LIFE, RING_START * size * flash_scale, RING_END * size * flash_scale)


func streak(from: Vector3, to: Vector3, color: Color, flash_scale: float) -> void:
	var length := from.distance_to(to)
	if length < STREAK_MIN_LENGTH:
		return
	last_cue = PresentationKit.VFX_IMPACT
	var mesh := BoxMesh.new()
	mesh.size = Vector3(STREAK_WIDTH, STREAK_THICKNESS, length)
	var effect := _spawn(mesh, _flat(color), (from + to) * 0.5, Vector3.ZERO, STREAK_LIFE, flash_scale, 0.0)
	effect.node.basis = Basis.looking_at(to - from, Vector3.UP) * Basis.from_scale(Vector3.ONE * flash_scale)


func advance(delta: float) -> void:
	for i in range(_effects.size() - 1, -1, -1):
		var effect := _effects[i]
		effect.life -= delta
		if effect.life <= 0.0:
			effect.node.queue_free()
			_effects.remove_at(i)
			continue
		effect.node.position += effect.velocity * delta
		var size := lerpf(effect.start_scale, effect.end_scale, 1.0 - effect.life / effect.max_life)
		effect.node.scale = Vector3.ONE * maxf(size, MIN_SCALE)


func clear_all() -> void:
	for effect in _effects:
		effect.node.queue_free()
	_effects.clear()


func effect_count() -> int:
	return _effects.size()


func _spawn(mesh: Mesh, material: Material, world: Vector3, velocity: Vector3, life: float, start_scale: float, end_scale: float) -> Effect:
	if _effects.size() >= MAX_EFFECTS:
		var oldest: Effect = _effects.pop_front()
		oldest.node.queue_free()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = world
	node.scale = Vector3.ONE * maxf(start_scale, MIN_SCALE)
	add_child(node)
	var effect := Effect.new()
	effect.node = node
	effect.velocity = velocity
	effect.life = life
	effect.max_life = life
	effect.start_scale = start_scale
	effect.end_scale = end_scale
	_effects.append(effect)
	return effect


func _billboard(color: Color) -> StandardMaterial3D:
	return _shared(color, true)


func _flat(color: Color) -> StandardMaterial3D:
	return _shared(color, false)


func _shared(color: Color, billboard: bool) -> StandardMaterial3D:
	var key := "%s:%s" % [color.to_html(), str(billboard)]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.no_depth_test = true
		material.render_priority = RENDER_PRIORITY
		if color.a < 1.0:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if billboard:
			material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_materials[key] = material
	return _materials[key]
