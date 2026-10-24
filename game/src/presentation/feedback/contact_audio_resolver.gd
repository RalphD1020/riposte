class_name ContactAudioResolver
extends RefCounted

## How a contact sounds, read off the solver's own result (presentation only).
## Physics decides the contact; this only names a cue and a gain. It never
## writes state, never plays a stream, and never feeds the simulation.
##
## A pair is the two material ids, in either order. An unknown pair is no cue,
## so a missing profile is silence rather than a guessed sound. Gain follows
## the normal impulse the solver applied, as an amplitude against a provisional
## presentation reference — not a force, and not a combat constant. Zero
## impulse is no impact.
##
## A scrape is not decided here. Tangential impulse alone does not prove the
## point is sliding (`ContactScrape` needs the slip as well), and a structure
## event does not carry that slip. Blade scrape stays `ContactScrape`.
##
## See also: /docs/concepts/presentation.md

## Provisional. A representative wall stop, in N·s, that reads as a full
## impact. Tuned by listening, not by the combat rules.
const REFERENCE_IMPULSE := 8.0
const GAIN_QUIET_DB := -12.0
const GAIN_FULL_DB := 2.0


## The impact cue for these two surfaces, or empty when the pair has no
## profile. Order does not matter. Weapon on weapon is a row of this same
## table: steel on steel is the light, solid, and strong takes, and `band` is
## the contact class that picks among a row's takes. A row with one take
## ignores the band. A new weapon is another material id and another row, not
## a new solver path.
static func impact_cue(material_a: StringName, material_b: StringName, band: String = "") -> StringName:
	var row: Variant = _pairs().get(_pair_key(String(material_a), String(material_b)))
	if row == null:
		return &""
	var takes: Dictionary = row
	var asked := String(band)
	if takes.has(asked):
		return takes[asked]
	if takes.has(""):
		return takes[""]
	var light := String(ContactResolver.CLASS_LIGHT)
	if takes.has(light):
		return takes[light]
	return &""


static func _pair_key(first: String, second: String) -> String:
	if first > second:
		return second + "|" + first
	return first + "|" + second


## Material id × material id. The empty-string take is the only take. A banded
## row (steel on steel) has one take per contact class.
static func _pairs() -> Dictionary:
	var steel := String(MaterialCatalog.STEEL)
	var stone := String(MaterialCatalog.STONE)
	var wood := String(MaterialCatalog.WOOD)
	var light := String(ContactResolver.CLASS_LIGHT)
	var solid := String(ContactResolver.CLASS_SOLID)
	var strong := String(ContactResolver.CLASS_STRONG)
	return {
		_pair_key(steel, steel): {
			light: PresentationKit.CUE_BLADE_LIGHT,
			solid: PresentationKit.CUE_BLADE_SOLID,
			strong: PresentationKit.CUE_BLADE_STRONG,
		},
		_pair_key(steel, stone): {"": PresentationKit.CUE_IMPACT_STEEL_STONE},
		_pair_key(steel, wood): {"": PresentationKit.CUE_IMPACT_STEEL_WOOD},
	}


## Gain (dB) for a normal impulse (N·s). Zero impulse is the quiet floor; the
## curve is an amplitude, so twice the impulse is not twice as loud.
static func impact_db(impulse: float) -> float:
	var shaped := sqrt(clampf(absf(impulse) / REFERENCE_IMPULSE, 0.0, 1.0))
	return lerpf(GAIN_QUIET_DB, GAIN_FULL_DB, shaped)


static func has_impact(impulse: float) -> bool:
	return impulse > 0.0
