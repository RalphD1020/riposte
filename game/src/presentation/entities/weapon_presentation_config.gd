class_name WeaponPresentationConfig
extends RefCounted
## WEAPON-PATH-004: everything a body declares about how its weapon is drawn,
## in one value built once when the body binds — the weapon's path data, the
## carriage radius, the body's Long Guard key, its projection, its charged
## load, whether the long edge leads, and both hands' grip frames on the
## weapon's own stations. Immutable by construction: every `with_*` returns a
## new value, and `WeaponPoseEvaluator` / `CombatPresentationField` derive their
## tables from it once. Presentation data only, outside every rules
## fingerprint.
##
## See also: /docs/concepts/presentation.md

var path: WeaponPathDefinition = WeaponPathDefinition.reference_sword()
## Pommel to carriage along the blade (m): the domain's `carriage_radius`.
var carriage_radius: float = PhysicalBaseline.CARRIAGE_REFERENCE_M
## The body's Long Guard key, moved from the path's (m, degrees).
var centre_raise_delta: float = 0.0
var centre_pitch_delta_degrees: float = 0.0
## The combat-aligned projection: level at `interaction_raise` in every phase.
var combat_aligned: bool = false
var interaction_raise: float = 0.0
## The charged-cut load: hands above the plane (m), blade pitch (degrees), and
## a declared high guard's roll at the right load (degrees). NAN is the path's.
var load_raise: float = NAN
var load_pitch_degrees: float = NAN
var load_roll_authored: bool = false
var load_roll_degrees: float = 0.0
## The long edge leads the motion: the strike region `edge_strike_from_carriage`
## beyond the carriage (the centre of percussion) orients the roll; the cutting
## edge's outward normal in the sword frame.
var edge_leads: bool = false
var edge_strike_from_carriage: float = 0.6765
var cutting_edge: Vector3 = SwordGripFrame.CROSSGUARD_AXIS
## Both hands' grips in the sword frame (index 0 the dominant / right hand,
## 1 the off / left hand). The weapon owns where each hand holds the handle
## (`grip_stations`, from its definition's grip radii); the body owns only how
## its hand bone sits there (`hand_offsets`, from its authored contact or the
## common grip); the Hand bone's transform on the sword is their product,
## `grip_frames[i] = T(grip_stations[i]) · hand_offsets[i]`
## (T_hand = T_sword · T_weapon_grip · T_rig_hand_offset). `grip_wrists` is the
## wrist the arm reaches in that grip's own space. Empty until a body binds
## hands to the weapon.
var grip_stations := PackedVector3Array()
var hand_offsets: Array[Transform3D] = []
var grip_frames: Array[Transform3D] = []
var grip_wrists := PackedVector3Array()


## The shared defaults: the reference sword's path, no body overrides, no hands.
static func shared() -> WeaponPresentationConfig:
	return WeaponPresentationConfig.new()


func copy() -> WeaponPresentationConfig:
	var out := WeaponPresentationConfig.new()
	out.path = path
	out.carriage_radius = carriage_radius
	out.centre_raise_delta = centre_raise_delta
	out.centre_pitch_delta_degrees = centre_pitch_delta_degrees
	out.combat_aligned = combat_aligned
	out.interaction_raise = interaction_raise
	out.load_raise = load_raise
	out.load_pitch_degrees = load_pitch_degrees
	out.load_roll_authored = load_roll_authored
	out.load_roll_degrees = load_roll_degrees
	out.edge_leads = edge_leads
	out.edge_strike_from_carriage = edge_strike_from_carriage
	out.cutting_edge = cutting_edge
	out.grip_stations = grip_stations.duplicate()
	out.hand_offsets = hand_offsets.duplicate()
	out.grip_frames = grip_frames.duplicate()
	out.grip_wrists = grip_wrists.duplicate()
	return out


func with_path(data: WeaponPathDefinition) -> WeaponPresentationConfig:
	var out := copy()
	out.path = data
	return out


func with_carriage_radius(radius: float) -> WeaponPresentationConfig:
	var out := copy()
	out.carriage_radius = radius
	return out


func with_centre(raise_delta: float, pitch_delta_degrees: float) -> WeaponPresentationConfig:
	var out := copy()
	out.centre_raise_delta = raise_delta
	out.centre_pitch_delta_degrees = pitch_delta_degrees
	return out


func with_projection(aligned: bool, raise_above_plane: float) -> WeaponPresentationConfig:
	var out := copy()
	out.combat_aligned = aligned
	out.interaction_raise = raise_above_plane
	return out


func with_load(hands_above_plane: float, pitch_degrees: float, roll_authored: bool = false, roll_degrees: float = 0.0) -> WeaponPresentationConfig:
	var out := copy()
	out.load_raise = hands_above_plane
	out.load_pitch_degrees = pitch_degrees
	out.load_roll_authored = roll_authored
	out.load_roll_degrees = roll_degrees
	return out


func with_edge(leads: bool, strike_from_carriage: float, edge: Vector3 = SwordGripFrame.CROSSGUARD_AXIS) -> WeaponPresentationConfig:
	var out := copy()
	out.edge_leads = leads
	out.edge_strike_from_carriage = strike_from_carriage
	out.cutting_edge = edge
	return out


## Both hands' grips: `stations` the weapon's own grip stations on the handle
## (sword frame), `offsets` the body's hand-bone offsets there, `wrists` the
## wrist in each grip's own space. The frames are their product.
func with_grips(stations: PackedVector3Array, offsets: Array[Transform3D], wrists: PackedVector3Array) -> WeaponPresentationConfig:
	var out := copy()
	out.grip_stations = stations.duplicate()
	out.hand_offsets = offsets.duplicate()
	out.grip_wrists = wrists.duplicate()
	out.grip_frames = []
	for index in mini(stations.size(), offsets.size()):
		out.grip_frames.append(Transform3D(Basis.IDENTITY, stations[index]) * offsets[index])
	return out


## The weapon's own grip stations (dominant first), on the blade axis at its
## definition's grip radii: the only grip geometry a body may hold.
static func weapon_grip_stations(weapon: WeaponDefinition) -> PackedVector3Array:
	var radii := WeaponStationTopology.grip_radii(weapon)
	return PackedVector3Array([Vector3(0.0, 0.0, radii[0]), Vector3(0.0, 0.0, radii[1])])


## A body's declared lift (`SwordRig3D` exports) on top of this value.
func with_rig_lift(rig: SwordRig3D) -> WeaponPresentationConfig:
	return with_centre(rig.centre_raise_delta, rig.centre_pitch_delta_deg) \
		.with_projection(rig.combat_aligned_projection, rig.interaction_raise) \
		.with_load(rig.load_raise, rig.load_pitch_deg, rig.load_roll_authored, rig.load_roll_deg) \
		.with_edge(rig.edge_leads_motion, rig.edge_strike_from_carriage, SwordGripFrame.edge_normal(rig.cutting_edge))


func has_grips() -> bool:
	return grip_frames.size() == 2


## What is wrong with this value, empty when it is usable.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if path == null:
		out.append("no weapon path")
	else:
		out.append_array(path.problems())
	if carriage_radius <= 0.0:
		out.append("carriage radius %.4f must be positive" % carriage_radius)
	if not grip_frames.is_empty() and (grip_frames.size() != 2 or grip_stations.size() != 2 or hand_offsets.size() != 2 or grip_wrists.size() != 2):
		out.append("grips need two stations, offsets, frames and wrists (%d / %d / %d / %d)" % [grip_stations.size(), hand_offsets.size(), grip_frames.size(), grip_wrists.size()])
	if combat_aligned and edge_leads:
		out.append("a level, roll-0 projection cannot also have the edge lead")
	return out
