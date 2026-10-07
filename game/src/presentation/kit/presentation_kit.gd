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
## Every semantic the proxy will ever ask for. A kit that maps a clip to
## anything else has authored a clip nobody plays, which is the kind of mistake
## that looks like a broken rig for an afternoon.
const ANIM_SEMANTICS: Array[StringName] = [ANIM_IDLE, ANIM_MOVE, ANIM_CHARGE, ANIM_SWING, ANIM_HIT, ANIM_STAGGER, ANIM_DEATH]

## Audio cues the presenter may request.
const CUE_SWING := &"swing"
const CUE_CHARGE := &"charge"
const CUE_BLADE_LIGHT := &"blade.light"
const CUE_BLADE_SOLID := &"blade.solid"
const CUE_BLADE_STRONG := &"blade.strong"
## Blades pinned together rather than deflecting: its own category, because a
## bind is a different *situation* and not a quieter clash.
const CUE_BIND := &"blade.bind"
const CUE_BODY_LIGHT := &"body.light"
const CUE_BODY_HEAVY := &"body.heavy"
const CUE_CRITICAL := &"critical"
## Point-first body contact (COMBAT-010). Distinct from a slash so a poke's
## thinner impulse and a thrust's heavier commitment are sonically separate.
const CUE_BODY_POKE := &"body.poke"
const CUE_BODY_THRUST := &"body.thrust"
const CUE_ROUND := &"round"
## Arena ambience; looped on the Music bus while a duel is mounted.
const CUE_MUSIC := &"music"

## VFX cues the presenter may request.
## Where a resolved strike's quality saturates the body hitstop band. The
## grade ladder tops out here, so quality beyond it reads as devastating
## rather than as more and more hitstop.
const QUALITY_FULL := SwingSemantics.GRADE_DEVASTATING

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
## Weapon impact feel: hitstop **bands** in seconds, `x` at no intensity and
## `y` at full (COMBAT §67). Bands rather than one value per class name, so the
## ladder from a graze to a full deflection is a continuum of the physics and
## an awful heavy graze can never be made to feel stronger than a perfect tap
## riposte by picking a louder label (COMBAT-009). Wall-clock only; the
## simulation never freezes (HITSTOP-001).
@export var hitstop_blade := Vector2(0.0, 0.04)
@export var hitstop_body := Vector2(0.025, 0.065)
@export var hitstop_devastating := Vector2(0.06, 0.09)
@export var is_placeholder: bool = false


func has_audio(cue: StringName) -> bool:
	return audio_cues.has(cue) and audio_cues[cue] is AudioStream


func stream_for(cue: StringName) -> AudioStream:
	return audio_cues[cue] as AudioStream if has_audio(cue) else null


## Hitstop for a blade clash, from how hard the blades actually met. One curve
## covers glance, clash, and strong deflection; there is no class to switch on.
func hitstop_for_clash(intensity: float) -> float:
	return lerpf(hitstop_blade.x, hitstop_blade.y, clampf(intensity, 0.0, 1.0))


## Hitstop for a body strike, from the quality the resolver produced. A
## devastating strike moves to its own band rather than being allowed to grow
## without limit inside the ordinary one.
func hitstop_for_strike(quality: float, devastating: bool) -> float:
	var band := hitstop_devastating if devastating else hitstop_body
	return lerpf(band.x, band.y, clampf(quality / QUALITY_FULL, 0.0, 1.0))


func has_vfx(cue: StringName) -> bool:
	return vfx_cues.has(String(cue))


func clip_for(semantic: StringName) -> StringName:
	return StringName(str(animation_clips.get(semantic, &"")))


## Mapped keys that are not semantics the proxy asks for. Reported rather than
## repaired: guessing which semantic an author meant would hide the typo.
func unknown_clip_semantics() -> PackedStringArray:
	var unknown := PackedStringArray()
	for semantic: Variant in animation_clips:
		if not ANIM_SEMANTICS.has(StringName(str(semantic))):
			unknown.append(str(semantic))
	return unknown


static func missing(primitive_kind: StringName) -> PresentationKit:
	var kit := PresentationKit.new()
	kit.id = &"missing"
	kit.primitive = primitive_kind
	kit.is_placeholder = true
	return kit
