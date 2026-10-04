class_name PresentationKit
extends Resource

## Immutable audio-visual manifest for one content identity (a fighter, a
## weapon, an arena). It is the ONE place to change how something looks,
## animates, sounds, and feels: replacing the primitive cylinder with a Blender
## model, adding clips, or swapping a sound edits a kit (an authored .tres),
## never MatchPresenter, the directors, or gameplay.
##
## Kits are shared and frozen during a match; per-entity playback state lives
## on the presenters. A missing optional cue is silent; a missing clip falls
## back to the procedural primitive motion.
##
## Implements: /spec/invariants.md#pres-kit-001
## See also: /docs/concepts/presentation.md

const PRIMITIVE_FIGHTER := &"FIGHTER"
const PRIMITIVE_BLADE := &"BLADE"
const PRIMITIVE_ARENA := &"ARENA"

## Animation semantics a fighter scene may provide (clip names via animation_clips).
const ANIM_IDLE := &"IDLE"
const ANIM_MOVE := &"MOVE"
const ANIM_CHARGE := &"CHARGE"
const ANIM_SWING := &"SWING"
const ANIM_HIT := &"HIT"
const ANIM_STAGGER := &"STAGGER"
const ANIM_DEATH := &"DEATH"

## Audio cues the presenter may request.
const CUE_SWING := &"swing"
const CUE_CHARGE := &"charge"
const CUE_BLADE_LIGHT := &"blade.light"
const CUE_BLADE_SOLID := &"blade.solid"
const CUE_BLADE_STRONG := &"blade.strong"
const CUE_BODY_LIGHT := &"body.light"
const CUE_BODY_HEAVY := &"body.heavy"
const CUE_CRITICAL := &"critical"
const CUE_ROUND := &"round"
## Arena ambience; looped on the Music bus while a duel is mounted.
const CUE_MUSIC := &"music"

## VFX cues the presenter may request.
const VFX_TRAIL := &"trail"
const VFX_SPARK := &"spark"
const VFX_IMPACT := &"impact"

@export var id: StringName = &""
@export var primitive: StringName = PRIMITIVE_FIGHTER
## Optional authored scene (e.g. a wrapper around a Blender .glb). When set it
## replaces the primitive; nodes named in color_targets receive combatant color.
@export var scene: PackedScene
@export var color_targets: PackedStringArray = PackedStringArray()
@export var visual_transform: Transform3D = Transform3D.IDENTITY
## Primitive fighter: visual height (m). Footprint radius comes from the rules.
@export var body_height: float = 1.4
## Primitive blade: thickness (m) and hand height above the ground (m).
@export var blade_width: float = 0.05
@export var blade_height: float = 1.0
## Animation semantic → clip name in the scene's AnimationPlayer.
@export var animation_clips: Dictionary = {}
## Audio cue → AudioStream. Missing cues are silent.
@export var audio_cues: Dictionary = {}
@export var vfx_cues: PackedStringArray = PackedStringArray()
## Weapon trail: samples kept and the angular speed (rad/s) that draws it.
@export var trail_samples: int = 10
@export var trail_min_speed: float = 4.0
## Weapon impact feel: hitstop seconds by contact class (COMBAT §67).
@export var hitstop_blade_light: float = 0.015
@export var hitstop_blade_solid: float = 0.03
@export var hitstop_blade_strong: float = 0.045
@export var hitstop_body_light: float = 0.04
@export var hitstop_body_heavy: float = 0.07
@export var hitstop_devastating: float = 0.09
@export var is_placeholder: bool = false


func has_audio(cue: StringName) -> bool:
	return audio_cues.has(cue) and audio_cues[cue] is AudioStream


func stream_for(cue: StringName) -> AudioStream:
	return audio_cues[cue] as AudioStream if has_audio(cue) else null


func has_vfx(cue: StringName) -> bool:
	return vfx_cues.has(String(cue))


func clip_for(semantic: StringName) -> StringName:
	return StringName(str(animation_clips.get(semantic, &"")))


static func missing(primitive_kind: StringName) -> PresentationKit:
	var kit := PresentationKit.new()
	kit.id = &"missing"
	kit.primitive = primitive_kind
	kit.is_placeholder = true
	return kit
