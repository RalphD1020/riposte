# Example: authoring a new fighter, weapon and handling

> See also: [docs/concepts/content.md](../docs/concepts/content.md), [docs/concepts/combat.md](../docs/concepts/combat.md)
> See also: [spec/invariants.md](../spec/invariants.md) — CONTENT-001, CONTENT-002, COMBATANT-GENERIC-001, LOADOUT-001, PHYS-005, PHYS-006
> Source: `game/content/rules/fighter_catalog.gd`, `weapon_catalog.gd`, `handling_catalog.gd`, `loadout_catalog.gd`, `game/content/content_ids.gd`

Add a heavier duelist with a longer, heavier sword — without touching a single
gameplay number or a single line of physics. Physical inputs change; the
physical equations produce the gameplay outputs (CONTENT-002), and the engine
never learns the new fighter's name (COMBATANT-GENERIC-001).

## The rule you are following

There is exactly one forbidden move here, and it is the intuitive one:

```gdscript
# NEVER. This is a gameplay output being authored directly.
fighter.max_speed = 4.2 * 0.9
weapon.swing_speed_full = 18.0 * 0.85
damage *= 1.2  # "because they are big"
```

A heavier fighter is slower to turn because their moment of inertia fell out
of a larger mass and radius, not because somebody typed a smaller number. A
longer sword is harder to swing because `I = k·m·L²` grew. If you find
yourself scaling a torque _and_ the geometry that torque acts on, you have
counted the size twice.

## 1. The character: state the body, author the actuators

A shipped fighter states its physical facts and three actuator scales relative
to the reference duelist (1.0 each). Strength is never inferred from size:

```gdscript
static func heavy() -> FighterDefinition:
	var fighter := FighterDefinition.new()
	fighter.id = ContentIds.FIGHTER_HEAVY
	fighter.height = 1.90
	fighter.mass = 105.0                 # a measured fact, not a derivation
	fighter.push_radius = 0.31
	fighter.hurt_radius = 0.22           # measured from the model, at blade height
	fighter.hand_radius = 0.038
	fighter.grip_radius = 0.25
	fighter.hand_mass = fighter.mass * PhysicalBaseline.HAND_REFLECTED_MASS_SHARE
	fighter.body_inertia_coefficient = 0.5
	fighter.lying_half_length = 0.93
	fighter.lying_radius = 0.20
	## strength 1.20, traction 1.15, turn support 0.90 — resolved to N and N·m here.
	resolve_actuators(fighter, 1.20, 1.15, 0.90)
	_semantics(fighter)
	return fighter
```

Nothing in `_semantics` moves — reaction, timing windows, tracking gain and
the burst windows are decisions about how a fighter _fights_, and a bigger
fighter is not a dimmer one (PHYS-005). Do not adjust a force to compensate
for the mass: the forces are in newtons, so `a = F/m` has already made this
fighter accelerate less. For a quick prototype, `FighterCatalog.prototype_at(size)`
still derives a whole build from one size — never ship it.

## 2. The weapon: the object only

```gdscript
var longsword := WeaponCatalog.bastard_sword_at(1.12, 1.85, fighter.grip_radius)
```

Length and mass are both required. Longer blades are made thinner and better
distally tapered precisely so they stay wieldable, so deriving mass from length
would quietly invent a crowbar. A weapon that ships authors its own
`WeaponMassProfile`; the motor torques stay, and the larger `I` makes the
swing slower and more reluctant by itself.

## 3. The handling: this body with this weapon

The hilt track is neither the fighter's nor the weapon's — it is how these
arms carry this grip (LOADOUT-001). Author it for the pair:

```gdscript
static func of(fighter: FighterDefinition, weapon: WeaponDefinition) -> WeaponHandlingProfile:
	if fighter.id == ContentIds.FIGHTER_DUELIST and weapon.id == ContentIds.WEAPON_BASTARD_SWORD:
		return two_handed_track(fighter, weapon, ContentIds.HANDLING_DUELIST_BASTARD_SWORD)
	if fighter.id == ContentIds.FIGHTER_HEAVY and weapon.id == ContentIds.WEAPON_LONGSWORD:
		return two_handed_track(fighter, weapon, ContentIds.HANDLING_HEAVY_LONGSWORD)
	return null
```

A pair with no handling yields `null` and the match fails closed. It never
borrows another pair's track: the heavy fighter does not silently swing the
longsword on Wolf's arms. Calibrate the knots against the new rig and the
gameplay camera; `CombatantPhysicsSpec.problem()` refuses any track that puts
a hand or the sword inside the wielder's torso.

## 4. Wire the identities and the match

Every catalog is keyed by `ContentIds` and **fails closed** (CONTENT-001).
`LoadoutCatalog.compile` resolves a character with a weapon into one
`CombatantPhysicsSpec`, and the rule set selects one per slot:

```gdscript
var rules := StandardDuelRules.with_combatants(
	ContentIds.FIGHTER_DUELIST, ContentIds.WEAPON_BASTARD_SWORD,
	ContentIds.FIGHTER_HEAVY, ContentIds.WEAPON_LONGSWORD
)
```

## 5. Bump what changed

A new shipped loadout changes no existing rule, but any change to a shipped
value does, so `StandardDuelRules` has to say so (`rules.version`). Replays also
pin each slot's loadout ids and a fingerprint of its resolved content
(`ReplayRecord` format 2), so a recording made against different content under
the same ids is refused rather than reinterpreted.

## What you did not have to do

No damage number, no speed, no timing window, no reaction delay, no balance
pass on the opponent, and no change to any system in `game/src/domain/`. The
duel between Wolf and a heavy fighter with a longsword is decided by `a = F/m`,
`α = τ/I`, and the contact equations — which is why the matchup is
_interesting_ rather than authored.

The generic-combatant proofs in `game/tests/domain/test_generic.gd` exercise a
heterogeneous pair through the same path, so a system that quietly assumes the
reference fighter fails the gate rather than ships.
