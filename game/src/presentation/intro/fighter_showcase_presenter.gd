class_name FighterShowcasePresenter
extends Node3D

## A display-only fighter for the set introduction. It reuses the combatant's
## body scene (or the primitive body) but is *not* FighterPresentation3D: no
## simulation pose drives it, and the sword it holds is a display sword that
## performs an authored flourish. Nothing here can collide or score — the
## combat invariant (the blade belongs to the simulation) only begins when
## the duel does.
##
## See also: /docs/concepts/presentation.md

## Primitive flourish: the display blade sweeps from a high wind-back through
## a cut and settles in guard, in shot-relative time [0, 1].
const FLOURISH_FROM := -2.2
const FLOURISH_TO := 0.6
const FLOURISH_GUARD := 0.78
const PRIMITIVE_HEIGHT := 1.4

var _pivot: Node3D
var _animation: AnimationPlayer
var _clip: StringName = &""
var _played: bool = false
var _rig: SwordRig3D


static func create(combatant: CombatantPresentationKit, side: DuelSide.Id, intro: FighterIntroProfile, body_radius: float, hilt: float, tip: float) -> FighterShowcasePresenter:
	var showcase := FighterShowcasePresenter.new()
	showcase.name = "Showcase"
	var scene := combatant.body_scene()
	if scene != null:
		var model := scene.instantiate()
		showcase.add_child(model)
		if combatant.fighter_skin != null:
			combatant.fighter_skin.apply(model)
		showcase._animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		for target in combatant.fighter.color_targets:
			var mesh := model.find_child(target, true, false) as MeshInstance3D
			if mesh != null:
				mesh.material_override = _material(RiposteTheme.accent_for(side))
	else:
		var body := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = body_radius
		cylinder.bottom_radius = body_radius
		cylinder.height = PRIMITIVE_HEIGHT
		body.mesh = cylinder
		body.material_override = _material(RiposteTheme.body_for(side))
		body.position.y = PRIMITIVE_HEIGHT * 0.5
		showcase.add_child(body)
	showcase._pivot = Node3D.new()
	showcase._pivot.name = "DisplaySword"
	showcase._pivot.position.y = combatant.weapon.blade_height
	showcase.add_child(showcase._pivot)
	var weapon_scene := combatant.weapon_scene()
	var weapon_model: Node = null
	if weapon_scene != null:
		weapon_model = weapon_scene.instantiate()
		showcase._pivot.add_child(weapon_model)
		if combatant.weapon_skin != null:
			combatant.weapon_skin.apply(weapon_model)
	else:
		var blade := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(combatant.weapon.blade_width, 0.035, tip - hilt)
		blade.mesh = box
		blade.material_override = _material(RiposteTheme.blade_for(side))
		blade.position.z = hilt + (tip - hilt) * 0.5
		showcase._pivot.add_child(blade)
	if intro != null and showcase._animation != null and showcase._animation.has_animation(intro.intro_clip):
		showcase._clip = intro.intro_clip
	if scene != null:
		showcase._rig = showcase.get_child(0) as SwordRig3D
		if showcase._rig != null:
			showcase._rig.bind_sword(showcase._pivot, weapon_model)
	return showcase


## Advance the flourish to `t01` of its shot. The display sword sweeps from a
## wind-back through a cut and settles in guard; an authored body clip plays
## once alongside, and the rig's hands follow the display sword.
func flourish(t01: float) -> void:
	if _clip != &"" and not _played:
		_animation.play(_clip)
		_played = true
	var t := clampf(t01, 0.0, 1.0)
	var settle := smoothstep(0.55, 1.0, t)
	var cut := lerpf(FLOURISH_FROM, FLOURISH_TO, smoothstep(0.0, 0.55, t))
	_pivot.rotation.y = lerpf(cut, FLOURISH_GUARD, settle)
	if _rig != null:
		_rig.pose_sword(_pivot.rotation.y)


func display_sword_angle() -> float:
	return _pivot.rotation.y


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material
