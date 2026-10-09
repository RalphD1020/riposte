class_name VfxRequest
extends RefCounted

## A typed instruction to spawn a visual effect. The director decides what
## kind, where, and how intense; VfxPresenter draws it.
##
## See also: /docs/architecture/presentation-feedback.md

enum Kind {
	SPARKS,
	RING,
	STREAK,
	DUST,
	## A narrow, fast spray along one axis: a point strike's line.
	AXIAL,
	## The lethal accent: a bright expanding ring plus hot sparks.
	FLASH,
}

var kind: Kind = Kind.SPARKS
var world_position: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.ZERO
var color: Color = Color.WHITE
var count: int = 0
var speed: float = 0.0
var size: float = 0.0
var flash_scale: float = 1.0


static func sparks(pos: Vector3, dir: Vector3, col: Color, cnt: int, spd: float, flash: float) -> VfxRequest:
	var req := VfxRequest.new()
	req.kind = Kind.SPARKS
	req.world_position = pos
	req.direction = dir
	req.color = col
	req.count = cnt
	req.speed = spd
	req.flash_scale = flash
	return req


static func ring(pos: Vector3, col: Color, sz: float, flash: float) -> VfxRequest:
	var req := VfxRequest.new()
	req.kind = Kind.RING
	req.world_position = pos
	req.color = col
	req.size = sz
	req.flash_scale = flash
	return req


static func streak(start: Vector3, endpoint: Vector3, col: Color, flash: float) -> VfxRequest:
	var req := VfxRequest.new()
	req.kind = Kind.STREAK
	req.world_position = start
	req.direction = endpoint
	req.color = col
	req.flash_scale = flash
	return req


static func dust(pos: Vector3, heading: Vector3, col: Color, cnt: int, spd: float, flash: float) -> VfxRequest:
	var req := VfxRequest.new()
	req.kind = Kind.DUST
	req.world_position = pos
	req.direction = heading
	req.color = col
	req.count = cnt
	req.speed = spd
	req.flash_scale = flash
	return req


static func axial(pos: Vector3, dir: Vector3, col: Color, cnt: int, spd: float, length: float, flash: float) -> VfxRequest:
	var req := sparks(pos, dir, col, cnt, spd, flash)
	req.kind = Kind.AXIAL
	req.size = length
	return req


static func lethal_flash(pos: Vector3, dir: Vector3, col: Color, sz: float, cnt: int, flash: float) -> VfxRequest:
	var req := VfxRequest.new()
	req.kind = Kind.FLASH
	req.world_position = pos
	req.direction = dir
	req.color = col
	req.size = sz
	req.count = cnt
	req.flash_scale = flash
	return req
