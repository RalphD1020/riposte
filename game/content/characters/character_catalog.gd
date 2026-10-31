class_name CharacterCatalog
extends RefCounted

## Loads the character art file once and compiles a physics spec from it.
## `FighterCatalog.prototype_at` is the only scale law. Scale 1.0 uses the
## shipped duelist so the reference match stays the baseline. The sword stays
## at length scale 1.0; a body scale whose hands cannot hold that sword fails
## closed. The simulation never calls this during a tick.
##
## See also: /docs/concepts/content.md
## Source: game/content/characters/wolf.character.json

const ART_PATH := "res://content/characters/wolf.character.json"
## Wolf's resolved physique, written by `tools/character_modeling` from the
## Model A profile. Regenerate with `python -m character_modeling.physique`.
const WOLF_PHYSIQUE_PATH := "res://content/characters/wolf.physique.json"

static var _cached: CharacterDefinition


static func wolf() -> CharacterDefinition:
	if _cached != null:
		return _cached
	if not FileAccess.file_exists(ART_PATH):
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(ART_PATH)) != OK:
		return null
	if typeof(parser.data) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = parser.data
	var scale := float(data.get("body_scale", 0.0))
	if not (scale > 0.0) or not is_finite(scale):
		return null
	var character := CharacterDefinition.new()
	character.id = StringName(str(data.get("id", "")))
	character.display_name = str(data.get("display_name", ""))
	character.body_scale = scale
	character.fighter_id = StringName(str(data.get("fighter_id", "")))
	character.weapon_id = StringName(str(data.get("weapon_id", "")))
	character.handling_id = StringName(str(data.get("handling_id", "")))
	if character.display_name == "" or character.fighter_id == &"":
		return null
	_cached = character
	return character


## The combat spec for a body scale. Null when the unchanged sword no longer
## fits the hands. Scale 1.0 is the shipped duelist, not a regenerated copy.
static func spec_at(scale: float) -> CombatantPhysicsSpec:
	if not (scale > 0.0) or not is_finite(scale):
		return null
	return _with_sword(FighterCatalog.duelist() if is_equal_approx(scale, 1.0) else FighterCatalog.prototype_at(scale))


## A resolved physique file (`riposte.physique`), parsed. Empty when the file
## is missing or is not a JSON object; `FighterCatalog.physique_problem` judges
## the contents.
static func physique(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	return parser.data


## The combat spec for a resolved physique holding the bastard sword at that
## body's grip. Null when the physique cannot author a fighter or the sword no
## longer fits the hands. The product match does not call this.
static func spec_from_physique(fighter_id: StringName, document: Dictionary) -> CombatantPhysicsSpec:
	var fighter := FighterCatalog.from_physique(fighter_id, document)
	return null if fighter == null else _with_sword(fighter)


static func _with_sword(fighter: FighterDefinition) -> CombatantPhysicsSpec:
	var weapon := WeaponCatalog.of(ContentIds.WEAPON_BASTARD_SWORD, fighter.grip_radius)
	if weapon == null or not weapon.is_valid():
		return null
	return LoadoutCatalog.assemble(fighter, weapon)
