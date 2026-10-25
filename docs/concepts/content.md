# Content

> See also: [spec/invariants.md](../../spec/invariants.md) — CONTENT-001, CONTENT-002, COMBATANT-GENERIC-001, LOADOUT-001, PHYS-005, PHYS-006, SIM-001
> See also: [docs/concepts/combat.md](./combat.md), [docs/concepts/simulation.md](./simulation.md)
> See also: [examples/catalog-authoring.md](../../examples/catalog-authoring.md) — a worked scaled fighter and weapon
> Source: `game/src/domain/rules/`, authored values in `game/content/rules/`

Fighters, weapons, their handling, and arenas are **data**. A greatsword is another `WeaponDefinition`, not new combat code; a heavier duelist is another `FighterDefinition`, not a special case in the solver; the heavier duelist holding the greatsword is a `WeaponHandlingProfile` for that pair. The simulation never sees any of them by name — only the `CombatantPhysicsSpec` each slot resolves to.

## Three kinds of value

Almost every content bug is a confusion between these, so they are worth naming separately.

| Kind         | What it is                                  | Where it lives                                             | Rule                                 |
| ------------ | ------------------------------------------- | ---------------------------------------------------------- | ------------------------------------ |
| **Authored** | A measured or designed fact about an object | `FighterDefinition`, `WeaponDefinition` fields             | Immutable after creation; validated  |
| **Derived**  | A consequence of authored facts             | Definition methods (`move_accel()`, `moment_of_inertia()`) | Computed, never stored as authorable |
| **Runtime**  | What is happening to one body right now     | `FighterState`, `WeaponState`                              | Mutable, hashed, reset per round     |

**An authored definition is not mutable match state.** A definition never holds a position, a velocity, a charge, or a health value, and nothing writes to one after it is built. Conversely, runtime state never holds a mass or a length — it asks the definition.

Derived values are functions, not fields. `move_accel()` is `locomotion_force / mass`; `moment_of_inertia()` is `k · m · L²`. Caching either one is permitted only where recomputation is measurably wasteful, and a cache is never authorable — otherwise someone eventually tunes the cache and the physics quietly stops agreeing with the mass.

## Catalogs are pure functions

Definitions come from pure, id-keyed catalog functions — `FighterCatalog.of(id)`, `WeaponCatalog.of(id)` and `HandlingCatalog.of(fighter, weapon)` — and `LoadoutCatalog.compile(fighter_id, weapon_id)` assembles the three into one `CombatantPhysicsSpec`. They are **not** Godot `Resource`s: the domain must stay free of engine types (SIM-001), and a `Resource` is an editable, shareable, mutable object — exactly the thing a definition must not be.

Each call returns a fresh object, so tuning one match can never reach into another. An id nobody ships yields nothing rather than a plausible substitute, and `DuelRules.is_valid()` then refuses the match — a typo cannot silently become a different duel.

A rule set _selects_ its two combatants by id (`StandardDuelRules.with_combatants`) and tunes the arena around them; it does not author them. Each slot is compiled on its own. That is what makes "same rules, different duelist" a one-line change in `standard_duel_rules.gd` instead of a fork of it.

## Character, weapon, handling (LOADOUT-001)

`game/content/characters/wolf.character.json` (`riposte.character_art` v2) is the only author of Wolf's display name, `body_scale`, palette, block geometry, and face clearance ([character-art.md](./character-art.md)). `body` on that file is presentation. `CharacterCatalog` does not read it. `CharacterCatalog` reads that identity and `spec_at` compiles a `CombatantPhysicsSpec`. Scale 1.0 returns the shipped `FighterCatalog.duelist()`. Any other scale uses `FighterCatalog.prototype_at` and the existing bastard sword at length 1.0. A scale whose grip cannot hold that sword returns null. The product match does not call the catalog. It still compiles through `LoadoutCatalog` and `FighterCatalog.duelist()`. A body scale other than 1.0 is not a shipped look; the hands-on-grip proof is the 1.0 rig (`PRES-RIG`), and a scaled visual accept is future tool work. The intro card, the victory card, and the announcer's spoken name are presentation cues on those kits. A match does not copy them from the JSON. The sword model is the code in `WeaponKinematics` and `SwordContactGeometry`; there is no model registry. Weapon scale is not a field.

Three independently authored pieces meet only in `LoadoutCatalog`:

- the **character** (`FighterDefinition`) — body and actuators; it knows no weapon;
- the **weapon** (`WeaponDefinition`) — the object; it knows no wielder;
- the **handling** (`WeaponHandlingProfile`) — how this body carries this weapon: the hilt track `C(θ)` and its carriage.

A pair with no authored handling yields null and the match fails closed; it never borrows another pair's track or falls back to the reference duelist. `CombatantPhysicsSpec.problem()` validates the whole loadout (each part, the pairing ids, the hilt at the grip, nothing of the held sword inside the torso), and `fingerprint()` hashes every resolved value so a replay header can pin it. Content is authored as GDScript catalogs today; editor `Resource` authoring would compile through the same seam into the same immutable spec, never be read by the simulation directly.

## A shipped entry states its facts; a prototype is a size

A shipped fighter states its physical facts — height, mass, push and hurt geometry, hands, the lying body — and three actuator scales relative to the reference duelist (`strength_scale`, `traction_scale`, `turn_support_scale`, Wolf 1.0 each), which `FighterCatalog.resolve_actuators` turns into newtons and newton-metres. Strength is never inferred from size, and the simulation never reads a scale.

For scaling proofs and quick prototypes, `FighterCatalog.prototype_at(1.5)` still produces a whole build from a size: geometry grows linearly, mass cubically, force quadratically, torque cubically; the accelerations follow from `a = F/m` and `α = τ/I`. Nobody hand-writes "and this one accelerates a bit less", and no authored speed penalty exists anywhere.

Only the physical frame scales. Health, speeds, commitment, stability, and the burst input windows are decisions about how a fighter _fights_ and stay fixed: scale changes physical inputs, and the physical equations produce the gameplay outputs.

**Mass is a default, not a law.** Volumetric mass assumes uniform density, which is a reasonable starting guess for a body and a poor final answer for any particular one, so a lean build simply assigns `mass` after the frame is laid down.

Weapons get no such default, and the signature of `WeaponCatalog.bastard_sword_at(length_scale, mass)` says so: longer blades are made thinner and better distally tapered precisely so they stay wieldable, so generating mass from length would quietly invent a crowbar. Reach is still expensive, because length enters inertia squared — but for the honest reason.

Motor torques do not scale with the geometry either. They are authored against the baseline's inertia, and scaling them as well as the `I` they already act on would count the size twice.

## FighterDefinition

Authored in three groups, deliberately kept apart:

- **Body physics** — `height`, `mass`, `push_radius`, `hurt_radius`, hands, `body_inertia_coefficient`, `lying_half_length` / `lying_radius`. Size and mass are independent (PHYS-005): a lean duelist and a heavy one of the same height are both legitimate, and neither value is ever derived from the other at runtime.
- **Actuators** — `locomotion_force`, `braking_force`, `burst_force`, `turn_torque`, `weapon_torque_scale`, and the speed caps. Forces and torques, never accelerations; resolved from authored scales. This is the separation that makes mass cost something.
- **Semantics** — speeds, commitment penalties, stability, stagger, and the burst input windows. These are the fighter's _behaviour_ and are not physical magnitudes.

Timing is deliberately absent from the physical groups. Size and mass must not reach the input or decision layers: a big fighter is not a laggy one, and a small fighter does not get a wider tap window.

## WeaponDefinition

- **Geometry** — `blade_base_radius`, `tip_radius`, `blade_radius`. Every radius is measured from the blade's origin, the pommel, so `tip_radius` is both the overall length and the effective rotational length. (An origin offset is the natural future extension; at MVP it is zero.)
- **Reach is the wielder's grip plus the blade.** `blade_base_radius` is the holder's `FighterDefinition.grip_radius` (the baseline duelist's 0.25 m, `PhysicalBaseline.GRIP_RADIUS_M`), and `tip_radius` adds the weapon's blade. A rule set mounts its weapon at its fighter's grip (`WeaponCatalog.of(id, fighter.grip_radius)`) and `DuelRules.is_valid()` refuses one mounted for a different grip. A longer-armed fighter reaches further with the same sword; no mesh measurement ever decides it. For the baseline the numbers are bit-identical to before (rules version 20, golden replay hashes unchanged).
- **Mass distribution** — `mass`, `inertia_coefficient`. Mass is measured; the coefficient is where balance lives.
- **Motor** — torques, not accelerations. Speeds stay authored because they are the arm's limit, not the blade's.
- **Contact and consequence** — restitution, bind, efficiency curve, impulse thresholds.

What is deliberately **not** on a weapon: `damage`, `attack_speed`, `knockback`. Those are outcomes of a collision, not identity. A weapon that authored its own damage would stop being a physical object and become a stat block, and every relational law in [combat.md](./combat.md) would have nothing to act on.

## Diagnostics

Definitions expose normalized ratios against the baseline (`mass_ratio()`, `length_ratio()`, `inertia_ratio()`) so a designer can see at a glance that a fighter is "1.1× tall and 1.3× heavy", and so the debug overlay can show derived inertia beside the mass and torque it came from. The simulation must not read them: the absolute quantities already carry every effect of scale, and reading a ratio _and_ the quantity it came from would count scale twice.

## Validation

Every definition validates before a match can start: positive physical magnitudes, a blade no longer than the weapon, a guard limit wider than the canonical guard, and a positive moment of inertia. Invalid content fails closed rather than producing a duel with a weightless sword.

| Concept                     | Code                                                                            |
| --------------------------- | ------------------------------------------------------------------------------- |
| Physical baseline           | `game/src/domain/rules/physical_baseline.gd`                                    |
| Fighter definition          | `game/src/domain/rules/fighter_definition.gd`                                   |
| Weapon definition           | `game/src/domain/rules/weapon_definition.gd`                                    |
| Combat tuning               | `game/src/domain/rules/combat_tuning.gd`                                        |
| Fighter catalog             | `game/content/rules/fighter_catalog.gd`                                         |
| Weapon catalog              | `game/content/rules/weapon_catalog.gd`                                          |
| Handling catalog            | `game/content/rules/handling_catalog.gd`                                        |
| Loadout compile             | `game/content/rules/loadout_catalog.gd`                                         |
| Combatant spec, handling    | `game/src/domain/rules/combatant_physics_spec.gd`, `weapon_handling_profile.gd` |
| Arena, rounds, combat       | `game/content/rules/standard_duel_rules.gd`                                     |
| Baseline and scaling proofs | `game/tests/domain/test_scaling.gd`                                             |
| Content validity proofs     | `game/tests/domain/test_rules.gd`                                               |
