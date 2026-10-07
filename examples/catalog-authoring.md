# Example: authoring a scaled fighter and weapon

> See also: [docs/concepts/content.md](../docs/concepts/content.md), [docs/concepts/combat.md](../docs/concepts/combat.md)
> See also: [spec/invariants.md](../spec/invariants.md) — CONTENT-001, CONTENT-002, PHYS-005, PHYS-006
> Source: `game/content/rules/fighter_catalog.gd`, `game/content/rules/weapon_catalog.gd`, `game/content/content_ids.gd`

Add a smaller, lighter duelist with a longer, heavier sword — without touching
a single gameplay number. Scale changes **physical inputs**; the physical
equations produce the gameplay outputs (CONTENT-002).

## The rule you are following

There is exactly one forbidden move here, and it is the intuitive one:

```gdscript
# NEVER. This is a gameplay output being authored directly.
fighter.max_speed = 4.2 * 0.9
weapon.swing_speed_full = 20.0 * 0.85
damage *= 1.2  # "because they are big"
```

A smaller fighter is slower to turn because their moment of inertia fell out
of a smaller mass and radius, not because somebody typed a smaller number. A
longer sword is harder to swing because `I = k·m·L²` grew. If you find
yourself scaling a torque _and_ the geometry that torque acts on, you have
counted the size twice.

## 1. A smaller fighter

`duelist_at` already takes the only input it needs:

```gdscript
var small := FighterCatalog.duelist_at(0.9)
```

That one argument moves: height and body radius linearly, mass by the cube
(`volumetric_mass`), locomotion / braking / burst **force** by the square
(`structural_scale`), and turn torque and `weapon_torque_scale` by the cube
(`torque_scale`). Nothing in `_semantics` moves at all — reaction, timing
windows, tracking gain, and the burst windows are decisions about how this
fighter _fights_, and a smaller fighter is not a dimmer one (PHYS-005).

Mass is the one derived default content is expected to override, because
uniform density is a fair starting guess for a body and a poor final answer
for any particular one:

```gdscript
var lean := FighterCatalog.duelist_at(0.9)
lean.mass = 58.0            # a measured fact, not a derivation
```

Assign it and stop. Do not also adjust a force to compensate: the forces are
in newtons, so `a = F/m` has already made this fighter accelerate less. That
is the whole point — a heavier build pays for its own mass instead of being
handed the same acceleration for free.

## 2. A longer, heavier sword

The weapon signature is deliberately **not** the fighter's:

```gdscript
var longsword := WeaponCatalog.bastard_sword_at(1.12, 1.85)
```

Length and mass are both required. A body may plausibly be assumed uniform
density; a sword may not. Longer blades are made thinner and better distally
tapered precisely so they stay wieldable, so deriving mass from length would
quietly invent a crowbar.

`inertia_coefficient` stays at `0.415636`. A distribution coefficient is a
_shape_ fact — where the mass sits along the blade — so it does not scale with
length. `moment_of_inertia()` grows anyway, through `m` and `L²`, and the
unchanged motor torques then produce a slower, more reluctant swing.

## 3. Wire the identity

Both catalogs are keyed by `ContentIds` (`game/content/content_ids.gd`) and **fail closed** (CONTENT-001):

```gdscript
static func of(id: StringName) -> WeaponDefinition:
	if id == ContentIds.WEAPON_BASTARD_SWORD:
		return bastard_sword()
	if id == ContentIds.WEAPON_LONGSWORD:
		return bastard_sword_at(1.12, 1.85)
	return null
```

An unknown id yields `null` rather than a plausible substitute, and
`DuelRules.is_valid()` then refuses the match. A silent fallback would mean
shipping a duel fought with a weapon nobody authored.

## 4. Bump the version

Any change to a shipped value changes the rules, so `StandardDuelRules` has to say so:

```gdscript
rules.version = 7   # was 6
```

`ReplayVerifier` rejects a recording made under different rules, so skipping
this turns every existing replay into a hash mismatch with no explanation
(SIM-002).

## What you did not have to do

No damage number, no speed, no timing window, no reaction delay, and no
balance pass on the opponent. The duel between a small fast duelist and a tall
one with a heavy longsword is decided by `a = F/m`, `α = τ/I`, and the contact
equations — which is why the matchup is _interesting_ rather than authored.

The scaling proofs in `game/tests/domain/test_scaling.gd` exercise exactly
these two entry points, so a future catalog that reaches past them and writes
a gameplay output directly will fail the gate rather than ship.
