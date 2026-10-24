"""The presentation layout both Blender and CrowdStage read.

Numbers live in game/content/presentation/arena_section.json. This module
checks them. It does not write combat rules. A disc radius here that
disagrees with DuelRules.platform_radius is a recorded expectation; the
match still uses the rules.

See also: docs/concepts/presentation.md
"""

import json
import math
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PATH = os.path.join(ROOT, "game", "content", "presentation", "arena_section.json")

## Crown top of masonry.voussoirs: spring + arch radius + voussoir thickness.
CROWN_TOLERANCE = 1.0e-3
## How far a pier's outer edge must stay inside the bay wedge.
SEAM = 1.0e-3


def load():
    with open(PATH, encoding="utf-8") as handle:
        data = json.load(handle)
    problems = validate(data)
    if problems:
        raise SystemExit("arena section layout: " + "; ".join(problems))
    return data


def validate(data):
    problems = []
    if not isinstance(data, dict):
        return ["layout is not an object"]

    def num(bag, key):
        if key not in bag:
            problems.append("missing %s" % key)
            return None
        value = bag[key]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            problems.append("%s is not a number" % key)
            return None
        return float(value)

    disc = num(data, "expected_disc_radius")
    num(data, "angular_zero")
    foot = num(data, "foot_offset")
    bays = data.get("bay_count")
    sections = data.get("section_count")
    if not isinstance(bays, int) or isinstance(bays, bool) or bays < 3:
        problems.append("bay_count must be an integer >= 3")
        bays = 0
    if not isinstance(sections, int) or isinstance(sections, bool) or sections < 1:
        problems.append("section_count must be an integer >= 1")
    if foot is not None and not math.isfinite(foot):
        problems.append("foot_offset is not finite")
    floor = data.get("floor")
    if data.get("kind") == "pit":
        return _pit(data, problems, num, floor)
    water = num(data, "water_height")
    inner = data.get("inner_arcade")
    outer = data.get("outer_arcade")
    moat = data.get("moat")
    tiers = data.get("tiers")
    if not isinstance(floor, dict) or not isinstance(inner, dict) or not isinstance(outer, dict) or not isinstance(moat, dict):
        problems.append("floor, arcades, and moat are required")
        return problems
    if not isinstance(tiers, list) or len(tiers) < 4:
        problems.append("the colonnade keeps its four treads")
        tiers = []

    soffit = num(floor, "soffit")
    paving = num(floor, "paving_top")
    curb_h = num(floor, "curb_height")
    curb_inner = num(floor, "curb_inner_radius")
    curb_mid = num(floor, "curb_mid_radius")
    length = num(floor, "brick_length")
    width = num(floor, "brick_width")
    thick = num(floor, "brick_thickness")
    joint = num(floor, "joint")
    stagger = num(floor, "stagger")
    if floor.get("course_axis") != "east_west":
        problems.append("fighting floor courses run east-west")
    if None not in (length, width, stagger) and abs(stagger - length * 0.5) > CROWN_TOLERANCE:
        problems.append("brick stagger is half the brick length")
    if None not in (length, width) and not (length > width > 0.0):
        problems.append("bricks are longer east-west than across the row")
    if joint is not None and width is not None and not (0.0 < joint < width * 0.25):
        problems.append("brick joints stay a joint, not a trench")
    if thick is not None and not (thick > 0.0):
        problems.append("brick thickness")
    if None not in (soffit, paving) and not (soffit < paving):
        problems.append("the floor soffit is below the paving")
    if curb_h is not None and abs(curb_h) > CROWN_TOLERANCE:
        problems.append("no floor edge rises above the fighting surface")
    if None not in (curb_inner, curb_mid, disc):
        if not (curb_inner < curb_mid < disc):
            problems.append("the curb is a ring inside the combat radius")

    def arcade(name, bag, soffit_key):
        inner_r = num(bag, "inner_radius")
        outer_r = num(bag, "outer_radius")
        opening = num(bag, "opening")
        pier = num(bag, "pier_width")
        spring = num(bag, "spring")
        arch = num(bag, "arch_radius")
        voussoir = num(bag, "voussoir_thickness")
        count = bag.get("voussoir_count")
        crown_soffit = num(bag, soffit_key) if soffit_key != "floor" else soffit
        if not isinstance(count, int) or isinstance(count, bool) or count < 3:
            problems.append("%s voussoir_count" % name)
        if None not in (inner_r, outer_r) and not (inner_r > 0.0 and outer_r > inner_r):
            problems.append("%s radii" % name)
        if opening is not None and not (opening > 0.0):
            problems.append("%s opening" % name)
        if pier is not None and not (pier > 0.0):
            problems.append("%s pier" % name)
        if None not in (opening, arch) and abs(opening - 2.0 * arch) > CROWN_TOLERANCE:
            problems.append("%s opening is the arch diameter" % name)
        if None not in (spring, arch, voussoir, crown_soffit):
            crown = spring + arch + voussoir
            if abs(crown - crown_soffit) > CROWN_TOLERANCE:
                problems.append("%s crown meets its soffit" % name)
        if None not in (water, spring) and not (water < spring - 0.2):
            problems.append("%s water sits below the spring" % name)
        if bays and None not in (inner_r, opening, pier):
            limit = inner_r * math.sin(math.pi / bays)
            if opening * 0.5 + pier >= limit - SEAM:
                problems.append("%s piers cross the next bay" % name)
        return inner_r, outer_r

    inner_r, inner_outer = arcade("inner arcade", inner, "floor")
    if "pier_depth" in inner:
        problems.append("inner arcade depth is the radius span")
    outer_r, outer_outer = arcade("outer arcade", outer, "soffit")
    pier_depth = num(outer, "pier_depth")
    outer_soffit = num(outer, "soffit")
    if None not in (pier_depth,) and not (pier_depth > 0.0):
        problems.append("outer pier depth")
    if None not in (inner_outer, disc) and abs(inner_outer - disc) > CROWN_TOLERANCE:
        problems.append("the inner arcade meets the combat radius")
    moat_inner = num(moat, "inner_radius")
    moat_outer = num(moat, "outer_radius")
    if None not in (moat_inner, moat_outer, inner_outer, outer_r):
        if not (moat_outer > moat_inner):
            problems.append("the moat has width")
        if abs(moat_inner - inner_outer) > CROWN_TOLERANCE or abs(moat_outer - outer_r) > CROWN_TOLERANCE:
            problems.append("the moat is the open gap between the arcades")
    previous = None
    for index, tier in enumerate(tiers):
        if not isinstance(tier, dict):
            problems.append("tier %d" % index)
            continue
        tier_inner = num(tier, "inner_radius")
        tier_outer = num(tier, "outer_radius")
        height = num(tier, "tread_height")
        seat = num(tier, "seat_radius")
        seats = tier.get("seat_count")
        if None not in (tier_inner, tier_outer) and not (tier_outer > tier_inner > 0.0):
            problems.append("tier %d moves outward" % index)
        if None not in (seat, tier_inner, tier_outer) and not (tier_inner < seat < tier_outer):
            problems.append("tier %d seat sits on its tread" % index)
        if not isinstance(seats, int) or isinstance(seats, bool) or seats < 1:
            problems.append("tier %d seat_count" % index)
        elif bays and seats % bays != 0:
            problems.append("tier %d seats divide into the bays" % index)
        if previous is not None and None not in (tier_inner, height, previous[0], previous[1]):
            if tier_inner < previous[0] - CROWN_TOLERANCE:
                problems.append("tier %d overlaps the tread below" % index)
            if abs(tier_inner - previous[0]) > 0.02:
                problems.append("tier %d leaves a gap in the steps" % index)
            if height <= previous[1]:
                problems.append("tier %d does not rise" % index)
        previous = (tier_outer, height)
        if index == 0 and None not in (tier_inner, outer_r, height, outer_soffit, pier_depth, tier_outer):
            if abs(tier_inner - outer_r) > CROWN_TOLERANCE:
                problems.append("the first tread starts at the outer arcade")
            if height <= outer_soffit:
                problems.append("the first tread is above its soffit")
            fourth = tiers[3].get("outer_radius") if len(tiers) > 3 and isinstance(tiers[3], dict) else None
            if isinstance(fourth, (int, float)) and outer_r + pier_depth > float(fourth) + 0.02:
                problems.append("the bleachers do not cover the outer arch")
    if len(tiers) >= 4 and outer_outer is not None and isinstance(tiers[3], dict):
        fourth = tiers[3].get("outer_radius")
        if isinstance(fourth, (int, float)) and abs(float(fourth) - outer_outer) > CROWN_TOLERANCE:
            problems.append("the outer arcade ends at the fourth tread")
    gallery = data.get("gallery")
    if len(tiers) > 4:
        if not isinstance(gallery, dict):
            problems.append("tiers behind the colonnade need the gallery")
        else:
            g_inner = num(gallery, "inner_radius")
            g_outer = num(gallery, "outer_radius")
            g_soffit = num(gallery, "soffit")
            g_spring = num(gallery, "spring")
            g_arch = num(gallery, "arch_radius")
            g_voussoir = num(gallery, "voussoir_thickness")
            if None not in (g_inner, outer_outer) and abs(g_inner - outer_outer) > CROWN_TOLERANCE:
                problems.append("the gallery starts where the colonnade ends")
            last = tiers[-1].get("outer_radius") if isinstance(tiers[-1], dict) else None
            if isinstance(last, (int, float)) and g_outer is not None and abs(float(last) - g_outer) > CROWN_TOLERANCE:
                problems.append("the gallery ends at the top tread")
            if None not in (g_soffit, outer_soffit, g_spring, g_arch) and (
                abs(g_soffit - outer_soffit) > CROWN_TOLERANCE
                or abs(g_spring - num(outer, "spring")) > CROWN_TOLERANCE
                or abs(g_arch - num(outer, "arch_radius")) > CROWN_TOLERANCE
            ):
                problems.append("the gallery arcade matches the outer arcade height")
            if None not in (g_spring, g_arch, g_voussoir, g_soffit):
                crown = g_spring + g_arch + g_voussoir
                if abs(crown - g_soffit) > CROWN_TOLERANCE:
                    problems.append("gallery arcade crown meets its soffit")
            rise = tiers[4].get("inner_radius") if isinstance(tiers[4], dict) else None
            if isinstance(rise, (int, float)) and outer_outer is not None and abs(float(rise) - outer_outer) > CROWN_TOLERANCE:
                problems.append("the rising treads start behind the colonnade")
    return problems


def _pit(data, problems, num, floor):
    """A sand pit: wall at the combat radius, seats on top of that wall, two gates."""
    disc = num(data, "expected_disc_radius")
    if not isinstance(floor, dict):
        problems.append("floor is required")
        return problems
    wall = data.get("wall")
    gates = data.get("gates")
    tiers = data.get("tiers")
    if not isinstance(wall, dict) or not isinstance(gates, dict):
        problems.append("the pit needs a wall and gates")
        return problems
    if not isinstance(tiers, list) or len(tiers) < 2:
        problems.append("the seats start above the wall")
        tiers = []
    soffit = num(floor, "soffit")
    paving = num(floor, "paving_top")
    curb_h = num(floor, "curb_height")
    if floor.get("course_axis") != "east_west":
        problems.append("fighting floor courses run east-west")
    if None not in (soffit, paving) and not (soffit < paving):
        problems.append("the floor soffit is below the paving")
    if curb_h is not None and abs(curb_h) > CROWN_TOLERANCE:
        problems.append("no floor edge rises above the fighting surface")
    inner = num(wall, "inner_radius")
    outer = num(wall, "outer_radius")
    height = num(wall, "height")
    if None not in (inner, disc) and abs(inner - disc) > CROWN_TOLERANCE:
        problems.append("the wall starts at the combat radius")
    if None not in (inner, outer, height) and not (outer > inner and height > 0.5):
        problems.append("the wall has thickness and height")
    width = num(gates, "width")
    gate_h = num(gates, "height")
    depth = num(gates, "depth")
    radius = num(gates, "radius")
    if None not in (width, gate_h, height, depth) and not (width > 0.5 and gate_h > height and depth > 0.0):
        problems.append("the gates are doors in the wall")
    if None not in (radius, disc, outer) and not (disc < radius < outer):
        problems.append("the gates sit in the wall")
    previous = outer
    previous_height = height
    bays = data.get("bay_count")
    for index, tier in enumerate(tiers):
        if not isinstance(tier, dict):
            problems.append("tier %d" % index)
            continue
        tier_inner = num(tier, "inner_radius")
        tier_outer = num(tier, "outer_radius")
        tread = num(tier, "tread_height")
        seats = tier.get("seat_count")
        if None not in (tier_inner, previous) and abs(tier_inner - previous) > 0.02:
            problems.append("tier %d leaves a gap in the steps" % index)
        if None not in (tread, previous_height) and tread <= previous_height:
            problems.append("tier %d does not rise" % index)
        if isinstance(bays, int) and bays and isinstance(seats, int) and seats % bays != 0:
            problems.append("tier %d seats divide into the bays" % index)
        previous = tier_outer
        previous_height = tread
    return problems
