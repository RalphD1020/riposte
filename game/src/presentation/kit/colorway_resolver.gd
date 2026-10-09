class_name ColorwayResolver
extends RefCounted

## Decides each combatant's colorway variant (DEFAULT or ALTERNATE). Pure.
##
## Rule (mirror-match discriminator, not team identity):
## - a true visual mirror is both slots holding the same fighter identity AND
##   the same selected skin;
## - in a mirror the Light/South copy stays DEFAULT and the Dark/North copy
##   uses ALTERNATE, so the two are visually distinct;
## - in every other matchup every character wears its own DEFAULT, regardless
##   of which cardinal side it spawned on.
##
## See also: /docs/concepts/presentation.md

static func is_mirror(fighter_ids: Array, skin_ids: Array) -> bool:
	return fighter_ids.size() == 2 and fighter_ids[0] == fighter_ids[1] and skin_ids[0] == skin_ids[1]


static func variant_for(side: DuelSide.Id, mirror: bool) -> SkinColorwayProfile.Variant:
	if mirror and side == DuelSide.Id.DARK_NORTH:
		return SkinColorwayProfile.Variant.ALTERNATE
	return SkinColorwayProfile.Variant.DEFAULT
