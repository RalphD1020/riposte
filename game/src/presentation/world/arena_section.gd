class_name ArenaSection
extends RefCounted

## Presentation layout for the floor, the two arcades, the moat, and the four
## treads. Combat still uses the rules' platform radius. This file does not
## write it. A disagreement is reported and ignored.
##
## See also: /docs/concepts/presentation.md
## Source: game/content/presentation/arena_section.json

const PATH := "res://content/presentation/arena_section.json"
const CROWN_TOLERANCE := 0.001

var expected_disc_radius: float = 0.0
var angular_zero: float = 0.0
var bay_count: int = 0
var section_count: int = 0
var foot_offset: float = 0.0
var water_height: float = 0.0
var floor_soffit: float = 0.0
var paving_top: float = 0.0
var curb_height: float = 0.0
var curb_inner_radius: float = 0.0
var curb_mid_radius: float = 0.0
var brick_length: float = 0.0
var brick_width: float = 0.0
var brick_stagger: float = 0.0
var brick_joint: float = 0.0
var course_axis: String = ""
var inner_radius: float = 0.0
var inner_outer_radius: float = 0.0
var inner_opening: float = 0.0
var inner_pier_width: float = 0.0
var inner_spring: float = 0.0
var inner_arch_radius: float = 0.0
var inner_voussoir: float = 0.0
var outer_inner_radius: float = 0.0
var outer_outer_radius: float = 0.0
var outer_opening: float = 0.0
var outer_pier_width: float = 0.0
var outer_pier_depth: float = 0.0
var outer_soffit: float = 0.0
var outer_spring: float = 0.0
var outer_arch_radius: float = 0.0
var outer_voussoir: float = 0.0
var moat_inner: float = 0.0
var moat_outer: float = 0.0
var tier_inner := PackedFloat32Array()
var tier_outer := PackedFloat32Array()
var tier_height := PackedFloat32Array()
var tier_seat_radius := PackedFloat32Array()
var tier_seat_count := PackedInt32Array()

var _parse_problems := PackedStringArray()


static func load_layout() -> ArenaSection:
	var section := ArenaSection.new()
	if not FileAccess.file_exists(PATH):
		section._parse_problems.append("missing layout")
		return section
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		section._parse_problems.append("layout is not an object")
		return section
	section._read(parsed as Dictionary)
	return section


## The match keeps the rules' radius even when the file records another.
func combat_disc(rules_radius: float) -> float:
	return rules_radius


func agrees(rules_radius: float) -> bool:
	return is_equal_approx(expected_disc_radius, rules_radius)


func tier_count() -> int:
	return tier_height.size()


func issues() -> PackedStringArray:
	var found := PackedStringArray()
	found.append_array(_parse_problems)
	if bay_count < 3:
		found.append("bay_count must be an integer >= 3")
	if section_count < 1:
		found.append("section_count must be an integer >= 1")
	if not is_finite(foot_offset):
		found.append("foot_offset is not finite")
	if course_axis != "east_west":
		found.append("fighting floor courses run east-west")
	if brick_length <= brick_width or brick_width <= 0.0:
		found.append("bricks are longer east-west than across the row")
	if absf(brick_stagger - brick_length * 0.5) > CROWN_TOLERANCE:
		found.append("brick stagger is half the brick length")
	if brick_joint <= 0.0 or brick_joint >= brick_width * 0.25:
		found.append("brick joints stay a joint, not a trench")
	if floor_soffit >= paving_top:
		found.append("the floor soffit is below the paving")
	if absf(curb_height) > CROWN_TOLERANCE:
		found.append("no floor edge rises above the fighting surface")
	if curb_inner_radius >= curb_mid_radius or curb_mid_radius >= expected_disc_radius:
		found.append("the curb is a ring inside the combat radius")
	_crown(inner_spring, inner_arch_radius, inner_voussoir, floor_soffit, "inner arcade", found)
	_crown(outer_spring, outer_arch_radius, outer_voussoir, outer_soffit, "outer arcade", found)
	_opening(inner_opening, inner_arch_radius, "inner arcade", found)
	_opening(outer_opening, outer_arch_radius, "outer arcade", found)
	if inner_outer_radius <= inner_radius or outer_outer_radius <= outer_inner_radius:
		found.append("arcade radii")
	if absf(inner_outer_radius - expected_disc_radius) > CROWN_TOLERANCE:
		found.append("the inner arcade meets the combat radius")
	if water_height >= inner_spring - 0.2 or water_height >= outer_spring - 0.2:
		found.append("water sits below the spring")
	_seam(inner_radius, inner_opening, inner_pier_width, "inner arcade", found)
	_seam(outer_inner_radius, outer_opening, outer_pier_width, "outer arcade", found)
	if moat_outer <= moat_inner:
		found.append("the moat has width")
	if absf(moat_inner - inner_outer_radius) > CROWN_TOLERANCE or absf(moat_outer - outer_inner_radius) > CROWN_TOLERANCE:
		found.append("the moat is the open gap between the arcades")
	if tier_count() != 4:
		found.append("exactly four treads")
	var previous_outer := -1.0
	var previous_height := -INF
	for index: int in tier_count():
		if tier_outer[index] <= tier_inner[index]:
			found.append("tier %d moves outward" % index)
		if tier_seat_radius[index] <= tier_inner[index] or tier_seat_radius[index] >= tier_outer[index]:
			found.append("tier %d seat sits on its tread" % index)
		if bay_count > 0 and tier_seat_count[index] % bay_count != 0:
			found.append("tier %d seats divide into the bays" % index)
		if previous_outer >= 0.0:
			if tier_inner[index] < previous_outer - CROWN_TOLERANCE:
				found.append("tier %d overlaps the tread below" % index)
			if absf(tier_inner[index] - previous_outer) > 0.02:
				found.append("tier %d leaves a gap in the steps" % index)
			if tier_height[index] <= previous_height:
				found.append("tier %d does not rise" % index)
		previous_outer = tier_outer[index]
		previous_height = tier_height[index]
	if tier_count() > 0:
		if absf(tier_inner[0] - outer_inner_radius) > CROWN_TOLERANCE:
			found.append("the first tread starts at the outer arcade")
		if tier_height[0] <= outer_soffit:
			found.append("the first tread is above its soffit")
		if outer_inner_radius + outer_pier_depth > tier_outer[tier_count() - 1] + 0.02:
			found.append("the bleachers do not cover the outer arch")
		if absf(tier_outer[tier_count() - 1] - outer_outer_radius) > CROWN_TOLERANCE:
			found.append("the outer arcade ends at the top tread")
	return found


func slots_in_bay(tier: int) -> int:
	if bay_count <= 0:
		return 0
	return int(float(tier_seat_count[tier]) / float(bay_count))


func seats_clear_piers() -> bool:
	var jamb := outer_opening * 0.5
	for tier: int in tier_count():
		for slot: int in slots_in_bay(tier):
			if absf(_local_y(tier, slot)) > jamb - 0.2:
				return false
	return true


func pose_for(tier: int, bay: int, slot: int) -> Transform3D:
	var local_y := _local_y(tier, slot)
	var radius := tier_seat_radius[tier]
	var turned := angular_zero + TAU * float(bay) / float(bay_count)
	var rot := -turned
	var bx := radius * cos(rot) - local_y * sin(rot)
	var by := radius * sin(rot) + local_y * cos(rot)
	var height := tier_height[tier] - foot_offset
	var at := Vector3(bx, height, -by)
	return Transform3D(Basis.IDENTITY, at).looking_at(Vector3(0.0, height, 0.0), Vector3.UP)


func box_pose() -> Transform3D:
	var last := tier_count() - 1
	var bay := bay_near(PI * 0.5)
	var radius := tier_seat_radius[last]
	var turned := angular_zero + TAU * float(bay) / float(bay_count)
	var rot := -turned
	var bx := radius * cos(rot)
	var by := radius * sin(rot)
	var height := tier_height[last] - foot_offset
	var at := Vector3(bx, height, -by)
	return Transform3D(Basis.IDENTITY, at).looking_at(Vector3(0.0, height, 0.0), Vector3.UP)


func bay_near(angle: float) -> int:
	var step := TAU / float(bay_count)
	return posmod(int(round((angle - angular_zero) / step)), bay_count)


func section_for(angle: float) -> int:
	var relative := wrapf(angle - angular_zero, 0.0, TAU)
	if relative >= TAU - 0.000001:
		relative = 0.0
	var bucket := int(floor(relative / TAU * float(section_count)))
	return clampi(bucket, 0, section_count - 1)


func _local_y(tier: int, slot: int) -> float:
	var count := slots_in_bay(tier)
	if count <= 1:
		return 0.0
	var usable := outer_opening * 0.5 - 0.35
	var span := usable * 2.0
	return (float(slot) - float(count - 1) * 0.5) * (span / float(count - 1))


func _crown(spring: float, arch: float, thick: float, soffit: float, label: String, found: PackedStringArray) -> void:
	if absf(spring + arch + thick - soffit) > CROWN_TOLERANCE:
		found.append("%s crown meets its soffit" % label)


func _opening(opening: float, arch: float, label: String, found: PackedStringArray) -> void:
	if absf(opening - 2.0 * arch) > CROWN_TOLERANCE:
		found.append("%s opening is the arch diameter" % label)


func _seam(radius: float, opening: float, pier: float, label: String, found: PackedStringArray) -> void:
	if bay_count < 3:
		return
	var limit := radius * sin(PI / float(bay_count))
	if opening * 0.5 + pier >= limit - CROWN_TOLERANCE:
		found.append("%s piers cross the next bay" % label)


func _read(data: Dictionary) -> void:
	expected_disc_radius = _float(data, "expected_disc_radius")
	angular_zero = _float(data, "angular_zero")
	bay_count = _int(data, "bay_count")
	section_count = _int(data, "section_count")
	foot_offset = _float(data, "foot_offset")
	water_height = _float(data, "water_height")
	var floor_data := _dict(data, "floor")
	floor_soffit = _float(floor_data, "soffit")
	paving_top = _float(floor_data, "paving_top")
	curb_height = _float(floor_data, "curb_height")
	curb_inner_radius = _float(floor_data, "curb_inner_radius")
	curb_mid_radius = _float(floor_data, "curb_mid_radius")
	brick_length = _float(floor_data, "brick_length")
	brick_width = _float(floor_data, "brick_width")
	brick_stagger = _float(floor_data, "stagger")
	brick_joint = _float(floor_data, "joint")
	course_axis = str(floor_data.get("course_axis", ""))
	var inner := _dict(data, "inner_arcade")
	inner_radius = _float(inner, "inner_radius")
	inner_outer_radius = _float(inner, "outer_radius")
	inner_opening = _float(inner, "opening")
	inner_pier_width = _float(inner, "pier_width")
	inner_spring = _float(inner, "spring")
	inner_arch_radius = _float(inner, "arch_radius")
	inner_voussoir = _float(inner, "voussoir_thickness")
	var outer := _dict(data, "outer_arcade")
	outer_inner_radius = _float(outer, "inner_radius")
	outer_outer_radius = _float(outer, "outer_radius")
	outer_opening = _float(outer, "opening")
	outer_pier_width = _float(outer, "pier_width")
	outer_pier_depth = _float(outer, "pier_depth")
	outer_soffit = _float(outer, "soffit")
	outer_spring = _float(outer, "spring")
	outer_arch_radius = _float(outer, "arch_radius")
	outer_voussoir = _float(outer, "voussoir_thickness")
	var moat := _dict(data, "moat")
	moat_inner = _float(moat, "inner_radius")
	moat_outer = _float(moat, "outer_radius")
	var rows: Variant = data.get("tiers", [])
	if typeof(rows) != TYPE_ARRAY:
		_parse_problems.append("exactly four treads")
		return
	var list: Array = rows
	for row: Variant in list:
		if typeof(row) != TYPE_DICTIONARY:
			_parse_problems.append("tier")
			continue
		var tier: Dictionary = row
		tier_inner.append(_float(tier, "inner_radius"))
		tier_outer.append(_float(tier, "outer_radius"))
		tier_height.append(_float(tier, "tread_height"))
		tier_seat_radius.append(_float(tier, "seat_radius"))
		tier_seat_count.append(_int(tier, "seat_count"))


func _dict(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key, null)
	if typeof(value) != TYPE_DICTIONARY:
		_parse_problems.append("missing %s" % key)
		return {}
	return value


func _float(data: Dictionary, key: String) -> float:
	if not data.has(key):
		_parse_problems.append("missing %s" % key)
		return 0.0
	var value: Variant = data[key]
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		_parse_problems.append("%s is not a number" % key)
		return 0.0
	return float(value)


func _int(data: Dictionary, key: String) -> int:
	var value := _float(data, key)
	if not is_equal_approx(value, round(value)):
		_parse_problems.append("%s is not an integer" % key)
	return int(round(value))
