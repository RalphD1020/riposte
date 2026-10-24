class_name StagePresentationProfile
extends Resource

## What an arena kit's stage looks like around the duel: which ground the
## scaffold builds, which sky, whether the home marks are drawn, and how the
## key light's shadow is spent. Presentation only. The support circle, the
## edge, and any wall are rules (ARENA-001, ARENA-002); this never moves them.
##
## See also: /docs/concepts/presentation.md

## PIT: the sand floor and the bowl. DECK: the kit's own scene on a flat
## outline, nothing else.
enum Ground { PIT, DECK }
enum Backdrop { OUTDOOR, VOID }

@export var ground: Ground = Ground.PIT
@export var backdrop: Backdrop = Backdrop.OUTDOOR
## The audience this stage seats in the pit's bowl, or none. The Arena seats
## its Roman crowd; The End seats nobody. A deck never seats one.
@export var crowd: CrowdProfile
## Surfaces a fighter can be seen against. The check does not name a stage.
@export var readability_surfaces: PackedStringArray = PackedStringArray(["floor", "inner_wall", "shadow_band"])
## Spawn discs. Side is also told by the fighters, their facing, and the HUD (SIDE-001).
@export var home_marks: bool = true
## The warm key casts one directional shadow map. The rim never does.
@export var key_shadow: bool = true
## Whether the stage's own scene casts into that map (the Arena wall). A deck
## only receives.
@export var stage_casts: bool = true
## DECK only: the visible outline in plan, a regular polygon with clipped
## corners. `deck_flat` is the distance to each flat, `deck_corner` the
## distance to each clipped corner (equal to the vertex distance for none).
## Flats face the arena axes. The sword floor and the fall's ledge use it.
@export var deck_sides: int = 8
@export var deck_flat: float = 0.0
@export var deck_corner: float = 0.0


## The deck's visible outline on the world XZ plane, counter-clockwise. Empty
## for a pit or an unauthored deck.
func deck_outline() -> PackedVector2Array:
	var outline := PackedVector2Array()
	if ground != Ground.DECK or deck_sides < 3 or deck_flat <= 0.0:
		return outline
	var half := PI / float(deck_sides)
	var vertex := deck_flat / cos(half)
	var clip := clampf(deck_corner, deck_flat, vertex) if deck_corner > 0.0 else vertex
	for side in deck_sides:
		var normal := TAU * float(side) / float(deck_sides)
		var corner := normal + half
		if clip >= vertex - 1.0e-6:
			outline.append(Vector2(cos(corner), sin(corner)) * vertex)
			continue
		## The clip line meets this flat at `along` from the flat's centre.
		var along := (clip - deck_flat * cos(half)) / sin(half)
		var flat_normal := Vector2(cos(normal), sin(normal))
		var flat_tangent := Vector2(-flat_normal.y, flat_normal.x)
		outline.append(flat_normal * deck_flat + flat_tangent * along)
		var next := Vector2(cos(normal + 2.0 * half), sin(normal + 2.0 * half))
		var next_tangent := Vector2(-next.y, next.x)
		outline.append(next * deck_flat - next_tangent * along)
	return outline


func problem() -> String:
	if readability_surfaces.is_empty():
		return "a stage names the surfaces behind a fighter"
	if ground == Ground.DECK and deck_outline().size() < 3:
		return "a deck needs an outline"
	if crowd != null and ground == Ground.DECK:
		return "a deck has no bowl to seat a crowd in"
	if crowd != null:
		return crowd.problem()
	return ""
