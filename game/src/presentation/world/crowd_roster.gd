class_name CrowdRoster
extends RefCounted

## One seated assignment. Seed plus seat index, on separate streams, so a new
## hair shape does not reshuffle skin. Neighbors do not share skin, role, and
## hair. The imperial household is not in this draw.
##
## See also: /docs/concepts/presentation.md

const STREAM_SKIN := 1
const STREAM_ROLE := 2
const STREAM_HAIR := 3
const STREAM_HAIR_COLOR := 4
const STREAM_CLOTH := 5
## `skin_01`–`skin_10` in pairs: 18, 24, 24, 20, 14. The everyday role takes
## the leftover tenth so the draw sums to 100 (50 / 20 / 15 / 15).
const SKIN_WEIGHTS: Array[int] = [9, 9, 12, 12, 12, 12, 10, 10, 7, 7]
const ROLE_WEIGHTS: Array[int] = [50, 20, 15, 15]
const HAIR_SHAPES := 2
const ROLE_EVERYDAY := 0
const ROLE_LONG := 1
const ROLE_TRAVELER := 2
const ROLE_PROSPEROUS := 3

var skin: int = 0
var role: int = 0
var hair: int = 0
var hair_color: int = 0
var cloth: int = 0


static func assign(seed_value: int, seat: int, previous: CrowdRoster = null) -> CrowdRoster:
	var row := CrowdRoster.new()
	row.skin = _weighted(_mix(seed_value, seat, STREAM_SKIN), SKIN_WEIGHTS)
	row.role = _weighted(_mix(seed_value, seat, STREAM_ROLE), ROLE_WEIGHTS)
	row.hair = _mix(seed_value, seat, STREAM_HAIR) % HAIR_SHAPES
	row.hair_color = _mix(seed_value, seat, STREAM_HAIR_COLOR) % 4
	row.cloth = _mix(seed_value, seat, STREAM_CLOTH) % 5
	if previous != null and previous.skin == row.skin and previous.role == row.role and previous.hair == row.hair:
		row.hair = (row.hair + 1) % HAIR_SHAPES
	return row


static func _weighted(roll: int, weights: Array[int]) -> int:
	var cursor := roll % 100
	var total := 0
	for index: int in weights.size():
		total += weights[index]
		if cursor < total:
			return index
	return weights.size() - 1


static func _mix(seed_value: int, seat: int, stream: int) -> int:
	var mixed := seed_value * 13 + seat * 131 + stream * 17 + 0x9e3779b1
	mixed = (mixed ^ (mixed >> 16)) * 0x7feb352d
	mixed = (mixed ^ (mixed >> 15)) * 0x846ca68b
	mixed = mixed ^ (mixed >> 16)
	return absi(mixed)
