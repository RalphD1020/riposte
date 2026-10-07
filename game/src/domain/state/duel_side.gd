class_name DuelSide
extends RefCounted

## Which end of the arena a fighter belongs to. The world has exactly one
## permanently locked orientation — **north is `+y`, south is `-y`** — and the
## simulation never rotates for anyone's benefit.
##
## Side is a first-class identity, not a consequence. It decides canonical
## spawn, initial facing, presentation identity, and the local camera
## orientation. Nothing may infer it from slot number, spawn position, colour,
## or camera yaw; those are all downstream of it. Keeping the arrow pointing
## that way is what lets two networked players look at opposite perspectives
## of one authoritative world without the world itself having a "front".
##
## Implements: /spec/invariants.md#side-001
## See also: /docs/concepts/combat.md

enum Id { LIGHT_SOUTH, DARK_NORTH }

## Facing is measured like a heading: 0 is `+x`, counter-clockwise positive.
## So looking north is a quarter turn, and looking south is the negative of
## it — which is also exactly how each side's spawn faces its opponent.
const NORTH_FACING := PI * 0.5
const SOUTH_FACING := -PI * 0.5


## Signed `y` direction of a side's home end: Light is south (negative),
## Dark is north (positive).
static func home_sign(side: Id) -> float:
	return 1.0 if side == Id.DARK_NORTH else -1.0


## Where a side spawns, `spawn_offset` metres out from the centre along the
## north-south line. Spawns are cardinal so the duel always begins on the
## same axis the camera is built around.
static func spawn_y(side: Id, spawn_offset: float) -> float:
	return home_sign(side) * spawn_offset


## Initial facing: each fighter starts looking across the arena at the other.
static func facing(side: Id) -> float:
	return SOUTH_FACING if side == Id.DARK_NORTH else NORTH_FACING


static func other(side: Id) -> Id:
	return Id.LIGHT_SOUTH if side == Id.DARK_NORTH else Id.DARK_NORTH


static func label(side: Id) -> String:
	return "Dark" if side == Id.DARK_NORTH else "Light"
