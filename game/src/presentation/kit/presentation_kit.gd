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
## They name physical states the snapshot already carries; the sword path is
## never one of them, because the blade is posed from the simulation.
const ANIM_IDLE := &"IDLE"
const ANIM_MOVE_FORWARD := &"MOVE_FORWARD"
const ANIM_MOVE_BACKWARD := &"MOVE_BACKWARD"
const ANIM_ORBIT_LEFT := &"ORBIT_LEFT"
const ANIM_ORBIT_RIGHT := &"ORBIT_RIGHT"
const ANIM_DASH_FORWARD := &"DASH_FORWARD"
const ANIM_DASH_BACK := &"DASH_BACK"
const ANIM_DASH_LEFT := &"DASH_LEFT"
const ANIM_DASH_RIGHT := &"DASH_RIGHT"
const ANIM_CHARGE := &"CHARGE"
const ANIM_SWING := &"SWING"
const ANIM_OVERSWING := &"OVERSWING"
const ANIM_RECOVERY := &"RECOVERY"
const ANIM_HURT := &"HURT"
const ANIM_STAGGER := &"STAGGER"
const ANIM_CRITICAL := &"CRITICAL"
const ANIM_DEATH := &"DEATH"
## Every semantic the proxy will ever ask for. A kit that maps a clip to
## anything else has authored a clip nobody plays, which is the kind of mistake
## that looks like a broken rig for an afternoon.
const ANIM_SEMANTICS: Array[StringName] = [
	ANIM_IDLE,
	ANIM_MOVE_FORWARD,
	ANIM_MOVE_BACKWARD,
	ANIM_ORBIT_LEFT,
	ANIM_ORBIT_RIGHT,
	ANIM_DASH_FORWARD,
	ANIM_DASH_BACK,
	ANIM_DASH_LEFT,
	ANIM_DASH_RIGHT,
	ANIM_CHARGE,
	ANIM_SWING,
	ANIM_OVERSWING,
	ANIM_RECOVERY,
	ANIM_HURT,
	ANIM_STAGGER,
	ANIM_CRITICAL,
	ANIM_DEATH,
]
## Semantics that loop while their state holds; every other clip plays once.
const LOOPING_SEMANTICS: Array[StringName] = [
	ANIM_IDLE, ANIM_MOVE_FORWARD, ANIM_MOVE_BACKWARD, ANIM_ORBIT_LEFT, ANIM_ORBIT_RIGHT, ANIM_CHARGE, ANIM_STAGGER
]

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
const CUE_ROUND_WIN := &"round.win"
## Footwork and falls are floor sounds, never blade sounds.
const CUE_DASH := &"dash"
const CUE_FALL := &"fall"
## Layer-only cues: played *with* a primary cue through `audio_layers`,
## never on their own, so a heavy contact is transient + body + tail rather
## than one pre-mixed file.
const CUE_IMPACT_LOW := &"layer.impact_low"
const CUE_METAL_TAIL := &"layer.metal_tail"
const CUE_LETHAL_ACCENT := &"layer.lethal_accent"
## Menu and HUD interaction, on the UI bus.
const CUE_UI_CONFIRM := &"ui.confirm"
const CUE_UI_BACK := &"ui.back"
const CUE_UI_HOVER := &"ui.hover"
const UI_CUES: Array[StringName] = [CUE_UI_CONFIRM, CUE_UI_BACK, CUE_UI_HOVER]
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
## Audio cue → AudioStream, or an Array of AudioStream variants. Missing cues
## are silent. Variants are picked deterministically from the event, so a
## replay hears the same takes in the same order.
@export var audio_cues: Dictionary = {}
## Primary cue → extra cues played with it from the same event (layering).
@export var audio_layers: Dictionary = {}
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
## Fighter kits: how this identity is announced and introduced. Optional.
@export var voice: FighterVoiceKit
@export var intro: FighterIntroProfile
## Fighter kits: DEFAULT/ALTERNATE material sets for the Wolf-vs-Wolf mirror.
## Optional; a skin's colorway overrides this one.
@export var colorway: SkinColorwayProfile
## Fighter kits: how a killing blow collapses this fighter. Optional; a kit
## without one uses the built-in death spread. Reached only on a killing blow.
@export var death: DeathPresentationProfile
@export var is_placeholder: bool = false


## The death style for a killing blow of this family and key. A kit without an
## authored profile falls back to the built-in spread, so every fighter dies
## with character even before deaths are authored.
func death_style(family: DeathPresentationProfile.Family, key: int) -> StringName:
	var profile := death if death != null else DeathPresentationProfile.new()
	return profile.style_for(family, key)


## The authored clip for a death style, or empty when the kit has none for it
## (the caller then falls back to the generic DEATH clip).
func death_clip(style: StringName) -> StringName:
	return death.clip_for(style) if death != null else &""


## The authored run-through the striker of a killing thrust holds, or empty.
func finisher_clip() -> StringName:
	return death.finisher_clip if death != null else &""


func has_audio(cue: StringName) -> bool:
	return variant_count(cue) > 0


func variant_count(cue: StringName) -> int:
	if not audio_cues.has(cue):
		return 0
	var value: Variant = audio_cues[cue]
	if value is AudioStream:
		return 1
	if value is Array:
		return _variants(value).size()
	return 0


## The variant for `key` (any integer derived from the event). The same key
## always picks the same take.
func stream_for(cue: StringName, key: int = 0) -> AudioStream:
	var value: Variant = audio_cues.get(cue)
	if value is AudioStream:
		return value
	if value is Array:
		var variants := _variants(value)
		if not variants.is_empty():
			return variants[posmod(key, variants.size())]
	return null


func layers_for(cue: StringName) -> Array[StringName]:
	var layers: Array[StringName] = []
	var value: Variant = audio_layers.get(cue)
	if value is Array:
		for layer: Variant in value:
			if has_audio(StringName(str(layer))):
				layers.append(StringName(str(layer)))
	return layers


static func _variants(value: Array) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for item: Variant in value:
		if item is AudioStream:
			streams.append(item)
	return streams


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
