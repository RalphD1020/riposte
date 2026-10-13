class_name HandlingCatalog
extends RefCounted

## Every fighter ↔ weapon pairing the game ships, keyed by the pair
## (LOADOUT-001). A handling is how one body carries one weapon — the hilt
## track `C(θ)` — so it belongs to neither alone: Wolf with a rapier, or a
## heavier body with the bastard sword, would each be a new entry here, never
## a tweak to the fighter or the weapon. An unauthored pair yields nothing and
## the match fails closed; no pair ever borrows another's track.
##
## See also: /docs/concepts/content.md, /docs/concepts/combat.md

## The two-handed hilt track of the reference duelist with the bastard sword
## (WEAPON-PATH-001): samples of one deformed rotational orbit at |weapon
## angle| 0 / 15 / 45 / 80 / 135° (Long Guard, the nose's shoulder, Ready,
## Gather, Load), the carriage's (grip centre's) distance forward of the body
## centre and toward the blade's side (m). Forward only falls and lateral only
## grows away from the centre, so the carriage never loops. A forward-biased,
## bilaterally mirrored teardrop whose centre is the longest posture on it
## (LONG-GUARD-GEOMETRY-001), one mirrored half (rules v40; calibrated against
## the right-lead Wolf rig):
## - 0°: Long Guard, the farthest-forward hilt — as far as both hands hold the
##   grip while the limiting (left, off-hand) arm keeps its extension reserve:
##   shoulder to hand 0.96 of the arm, elbow ~147°, never locked; the near right
##   arm falls where the grip puts it (~0.87); the shoulders do not move to
##   reach it. Authored from Wolf's own reach and clearance, never from where
##   an opponent's body would be: a centred point meets the opponent before the
##   bodies can, so the contact physics decides what yields.
## - 15°: a centimetre back and barely aside — the point corridor, so Long
##   Guard is a rounded top, not a point the hilt lunges through.
## - 45° / 80°: Ready and Gather, still strongly forward and drawn in toward
##   the centreline rather than out to the side.
## - 135°: the load, close to the body and narrow: the outside of the swing
##   compresses toward the fighter instead of spreading the hands sideways, so
##   the swept slash reads as a leaf in front of the fighter, not a propeller
##   round him. Forward depth is what keeps the crossguard and the near arm
##   off the chest here, so the load comes forward before it ever widens: the
##   0.32 m seed put the crossguard 4 mm into the torso; 0.33 m clears it.
const ATTACK_PATH_DEGREES: PackedFloat64Array = [0.0, 15.0, 45.0, 80.0, 135.0]
const ATTACK_PATH_CARRIAGE_FORWARD: PackedFloat64Array = [0.63, 0.62, 0.55, 0.43, 0.33]
const ATTACK_PATH_CARRIAGE_LATERAL: PackedFloat64Array = [0.0, 0.02, 0.08, 0.13, 0.16]


## The handling authored for `fighter` with `weapon`, or null when the pair has
## none (fail closed).
static func of(fighter: FighterDefinition, weapon: WeaponDefinition) -> WeaponHandlingProfile:
	if fighter == null or weapon == null:
		return null
	if fighter.id == ContentIds.FIGHTER_DUELIST and weapon.id == ContentIds.WEAPON_BASTARD_SWORD:
		return two_handed_track(fighter, weapon, ContentIds.HANDLING_DUELIST_BASTARD_SWORD)
	return null


## The reference two-handed track carried by `fighter`'s arms with `weapon`.
## It is the wielder's carriage of a two-handed grip, so it scales with the
## wielder (whose size the grip radius carries), not with blade length: at the
## reference grip the knots are exactly the authored ones. Game tuning judged
## against the rig and the gameplay camera, not historical measurements. The
## carriage — the point on the sword the track places — stays at the
## reference so θ, `C(θ)` and every authoritative sword point keep their
## meaning whatever grip the hands take on the handle.
static func two_handed_track(fighter: FighterDefinition, weapon: WeaponDefinition, handling_id: StringName) -> WeaponHandlingProfile:
	var handling := WeaponHandlingProfile.new()
	handling.id = handling_id
	handling.fighter_id = fighter.id
	handling.weapon_id = weapon.id
	handling.carriage_radius = PhysicalBaseline.CARRIAGE_REFERENCE_M
	var wielder := fighter.grip_radius / PhysicalBaseline.GRIP_RADIUS_M
	var knots := PackedFloat64Array()
	var forward := PackedFloat64Array()
	var lateral := PackedFloat64Array()
	for index in ATTACK_PATH_DEGREES.size():
		knots.append(deg_to_rad(ATTACK_PATH_DEGREES[index]))
		forward.append(ATTACK_PATH_CARRIAGE_FORWARD[index] * wielder)
		lateral.append(ATTACK_PATH_CARRIAGE_LATERAL[index] * wielder)
	handling.attack_path = WeaponAttackPath.from_carriage_knots(knots, forward, lateral)
	return handling
