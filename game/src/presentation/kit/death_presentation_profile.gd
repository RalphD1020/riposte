class_name DeathPresentationProfile
extends Resource

## How a fighter's death reads, chosen by what killed them. A killing cut and a
## killing thrust collapse differently, so the profile holds a set of styles per
## contact family and picks one deterministically from the killing blow's event
## key — the same death plays the same way in every replay.
##
## This is presentation only, and it is reached only on a killing blow: a death
## is the one state the simulation hands over whole (the fighter is already not
## alive), so nothing here can lock a living player. A non-lethal stab never
## selects a style because it never kills (PRES-001).
##
## Styles are named poses the proxy knows how to carry out (procedural while the
## Wolf has no authored death clips; an authored DEATH clip, if the kit maps
## one, still wins). The vocabulary is fixed so a kit cannot author a style the
## proxy cannot play.
##
## See also: /docs/concepts/presentation.md

enum Family { SLASH, STAB }

## Slash deaths: struck down by a cut.
const STYLE_DEAD_DROP := &"dead_drop"
const STYLE_KNEES_FLOP := &"knees_flop"
const STYLE_GROUND_WRITHE := &"ground_writhe"
## Stab deaths: run through by a killing thrust.
const STYLE_STAB_CRUMPLE := &"stab_crumple"
const STYLE_STAB_PITCH := &"stab_pitch"

const SLASH_STYLES: Array[StringName] = [STYLE_DEAD_DROP, STYLE_KNEES_FLOP, STYLE_GROUND_WRITHE]
const STAB_STYLES: Array[StringName] = [STYLE_STAB_CRUMPLE, STYLE_STAB_PITCH]

## Per-family style lists. Empty falls back to the family's built-in set, so a
## kit that authors nothing still gets the full spread of deaths.
@export var slash_styles: Array[StringName] = []
@export var stab_styles: Array[StringName] = []
## Death style → authored clip in the fighter scene. A style with no clip here
## falls back to the kit's generic DEATH clip, then to the procedural collapse,
## so an authored fighter can gain a style one clip at a time.
@export var style_clips: Dictionary = {}
## The clip the striker of a killing thrust holds for the run-through. Empty
## falls back to the dash-forward lunge (which returns to guard on its own).
@export var finisher_clip: StringName = &""
## Death style → `DeathStyleTiming`. A style with none uses
## `default_weapon_release`.
@export var style_timings: Dictionary = {}
## When the dead hand lets go for a style with no authored timing
## (presentation-scaled seconds from the killing blow).
@export var default_weapon_release: float = DEFAULT_WEAPON_RELEASE
## The shared timeline of a killing thrust (striker withdrawal, victim
## collapse, the victim's release). Null uses the built-in beats. Every stab
## style is timed by it, never by a per-style release.
@export var stab_finisher: StabFinisherProfile
## Authored flails for a ring-out, picked deterministically from the fall's
## event key so a replay falls the same way. Empty: none authored.
@export var ring_fall_clips: Array[StringName] = []

## The built-in release beat: the hand goes slack as the collapse begins.
const DEFAULT_WEAPON_RELEASE := 0.12


## The whole death for a killing blow, resolved once: style, clip, timings.
func resolve(family: Family, key: int) -> DeathStyleSpec:
	var spec := DeathStyleSpec.new()
	spec.style = style_for(family, key)
	spec.clip = clip_for(spec.style)
	var timing := style_timings.get(spec.style) as DeathStyleTiming
	spec.weapon_release_time = timing.weapon_release_time if timing != null else default_weapon_release
	spec.ragdoll_handoff_time = timing.ragdoll_handoff_time if timing != null else -1.0
	if family == Family.STAB:
		var finisher := stab_timeline()
		spec.collapse_delay = finisher.victim_collapse_start
		spec.weapon_release_time = finisher.victim_weapon_release
		spec.finisher = finisher
	return spec


## The killing thrust's shared timeline: the authored one, or the built-in.
func stab_timeline() -> StabFinisherProfile:
	return stab_finisher if stab_finisher != null else StabFinisherProfile.new()


## The ring-fall flail for a fall with event `key`, or empty.
func ring_fall_clip(key: int) -> StringName:
	if ring_fall_clips.is_empty():
		return &""
	return ring_fall_clips[absi(key) % ring_fall_clips.size()]


## The authored clip for a style, or empty when this profile has none.
func clip_for(style: StringName) -> StringName:
	return StringName(str(style_clips.get(style, &"")))


## The family a contact kind reads as. A thrust or poke runs the body through
## (stab); a slash or graze cuts it down. Point families only ever reach here on
## a killing blow, which is the invariant the caller enforces.
static func family_of(contact_kind: String) -> Family:
	match contact_kind:
		"thrust", "poke":
			return Family.STAB
		_:
			return Family.SLASH


## The family a death style belongs to (a style outside the stab set is a cut).
static func family_of_style(style: StringName) -> Family:
	return Family.STAB if STAB_STYLES.has(style) else Family.SLASH


## The death style for a killing blow: deterministic from the family and the
## event key, so a replay dies the same way. Never empty — an unauthored family
## falls back to its built-in styles.
func style_for(family: Family, key: int) -> StringName:
	var styles := _styles(family)
	return styles[absi(key) % styles.size()]


func _styles(family: Family) -> Array[StringName]:
	if family == Family.STAB:
		return stab_styles if not stab_styles.is_empty() else STAB_STYLES
	return slash_styles if not slash_styles.is_empty() else SLASH_STYLES
