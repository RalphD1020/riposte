"""Stone roles. Hex values match `RiposteTheme` constants.

`stone_floor` is `WORLD_FLOOR` (#8a7f6c), the fighting surface only. The bowl
does not use it. Blender stores the same sRGB hex as linear base color, the
way `build_arena.py` does.
"""

ROLES = {
    "stone_pillar": "afa28a",
    "stone_edge": "918675",
    "stone_stand": "49463f",
    "stone_floor": "8a7f6c",
    "stone_terracotta": "805044",
    "stone_cliff": "34312d",
    "gold_trim": "8a6a3a",
    "basin_water": "1a3a40",
    "basin_glint": "c4a050",
}


def srgb(hex_code):
    def channel(value):
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    color = int(hex_code, 16)
    return tuple(channel(((color >> shift) & 0xFF) / 255.0) for shift in (16, 8, 0))
