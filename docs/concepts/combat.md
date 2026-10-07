# Combat

> See also: [spec/invariants.md](../../spec/invariants.md) — COMBAT-001 – COMBAT-011, PHYS-001 – PHYS-007, SIDE-001, CONTENT-002
> See also: [docs/concepts/simulation.md](./simulation.md), [docs/concepts/controls.md](./controls.md), [docs/concepts/content.md](./content.md)
> Source: `game/src/domain/combat/`, tuning values in `game/content/rules/`

Two verbs (move, attack) and real steel. Every outcome comes from simulated bodies and blades; nothing is a canned animation. Numbers live in the rules content file; this doc names mechanisms, not values.

## Swing semantics: describing a swing without deciding it (COMBAT-009)

Everything above decides outcomes. `SwingSemantics` is the other direction: named readings over authoritative state, for the player watching a blade, the HUD, a training overlay, and the debug vectors. Nothing in the simulation reads one back, and no presentation code recomputes a combat formula — a value not on `PresentationSnapshot` or an event payload is done without rather than invented.

**Swing potential** is how dangerous this part of this swing is, in `[0, 1]`, before anything about the opponent. It is quadratic in the blade's actual tip speed, because cutting is an energy problem and severity goes as `v²`. Charge and arc are deliberately absent from the formula: a charged swing is dangerous because the motor drove the blade faster and further, and that speed is already in the tip speed. Counting it again would make the same physical blade speed mean two different things depending on how it was reached.

Because it reads the blade rather than the input, **the dangerous part of an arc emerges from the acceleration curve instead of being authored**, and lands at a slightly different point every swing. There is a living curve to learn, not "frame 14 is the crit frame". A blade that is not carrying a strike has no potential at all, however fast it happens to be travelling — a wind-back is a fast-moving sword that cannot cut anyone.

**Swing progress** is physical travel along the commanded arc, never elapsed ticks. A sword stopped dead by another sword has stopped progressing; an animation clock would keep counting and tell the player their swing was further along than their blade.

**Potential is not prediction.** Convergence only exists at contact, so nothing before contact may promise what a strike would do. An interface may show the attacker's own potential and let vulnerability read from the target's own physical state — a displaced weapon, a committed swing, a bad angle, carried momentum — which is why each fighter's snapshot carries their own exposure rather than a meter predicting someone else's hit.

**Grades** (`GRAZE`, `LIGHT`, `SOLID`, `HEAVY`, `SWEET`, `DEVASTATING`) name a resolved strike. They describe what the physics produced and never choose it, and there is no dice roll anywhere near them. `SWEET` is the one grade that is not a magnitude: it means convergence, which is exactly what `critical` already decides, so it has no second independent definition that could eventually disagree.

## Cardinal sides and one locked world (SIDE-001)

The arena has a permanently fixed orientation — **north is `+y`, south is `-y`** — and the simulation never rotates for anyone's benefit.

`DuelSide { LIGHT_SOUTH, DARK_NORTH }` is a first-class identity, not a consequence. It decides canonical spawn, initial facing, presentation identity, and the local camera orientation; nothing infers it from slot number, spawn position, colour, or camera yaw. Light spawns at `(0, -spawn_offset)` looking north and Dark at `(0, +spawn_offset)` looking south, each already looking at the other. Quick Play draws sides 50/50 from the match seed, so both cardinal spawns and both camera orientations get exercised by ordinary play instead of the Dark path rotting until someone turns on multiplayer.

The local camera yaw is the one quantity two people watching the same match may legitimately disagree about: the local player is always at the bottom of the screen, so a local Dark player's view is turned half a revolution. That is exactly why it lives in presentation and never in `StateHasher` or replay state — it is what will let two networked players see opposite perspectives of one authoritative world.

Footwork stays encoded through the duel basis rather than world directions, which is what makes _local right projects right on screen_ and _local forward projects up_ true for both sides once the rig has turned. Without it, one of the two ends would be playing mirrored controls.

Side is communicated by more than colour: the two home ends are different **shapes** as well as different tints, the spawn orientation says it, and the HUD plate names it in words. The arena's cues stay close to the floor tone deliberately — cardinality is orientation, not decoration, and the floor must never compete with blade readability.

## The canonical physical baseline (CONTENT-002)

Everything below is in SI units, measured against one concrete fighter holding one concrete sword. `scale = 1.0` _is_ this pairing; there are no abstract units anywhere.

| Quantity              | Baseline | Scaling                           |
| --------------------- | -------- | --------------------------------- |
| Fighter height        | 1.75 m   | linear in fighter scale           |
| Fighter mass          | 80 kg    | authored; cubic only as a default |
| Fighter body radius   | 0.27 m   | linear in fighter scale           |
| Sword overall length  | 1.22 m   | linear in weapon scale            |
| Sword effective blade | 0.97 m   | linear in weapon scale            |
| Sword mass            | 1.60 kg  | authored; cubic only as a default |
| Canonical guard       | ±45°     | invariant                         |
| Guard limit           | ±135°    | invariant                         |
| Tap arc               | 90°      | invariant                         |

These are a _normalized combat baseline_, not a demographic claim. 1.75 m is close to the modern adult male mean, but 80 kg is deliberately under the ~90 kg population mean, which includes bodies nobody would cast as a duelist. The sword needs no such apology: 1.22 m at 1.60 kg is almost directly represented by surviving museum examples, which makes it the more trustworthy of the two anchors.

The single law that governs all of it:

> **Scale changes physical inputs; physical equations produce gameplay outputs.**

Size, mass, force, and torque feed inertia; inertia feeds acceleration and speed; those feed relative motion; relative motion feeds collision; collision feeds impulse, severity, and exposure; and only then is there a combat result. There is never a step that reads "bigger fighter → +20% damage".

### Fighter mass

Mass resists everything and causes nothing. It sets translational acceleration (`a = F/m`), displacement under impulse, collision response, body contribution to a strike, stability, and rotational inertia. It is **not** a damage multiplier: a heavy fighter does not hit harder with the same sword at the same speed — they are simply harder to move and slower to get going.

### Weapon mass and geometry

Both are authored facts, kept independent (PHYS-005). Geometry scales linearly; mass is measured, not generated, because a longer sword is usually also a thinner one and a cubic rule would quietly invent a crowbar. Cubic mass exists only as an explicit default generator for hypothetical same-density geometry.

### Moment of inertia (PHYS-006)

`I = k · m · L²` for the weapon, `I_body = k_b · m · r²` for the fighter. `k` is the authored mass-distribution coefficient — a uniform rod about its own end is `1/3`, a tip-heavy weapon more, a pommel-weighted one less. A hand check on the baseline sword gives `⅓ × 1.6 × 1.22² ≈ 0.794 kg·m²`; the shipped blade sits a little above that because its mass starts at the hilt rather than at the pivot.

This is the only definition of resistance to being turned. The motor divides torque by it, blade contact divides impulse by it, and nothing authors an angular acceleration beside it — the two would drift apart and the blade would stop obeying its own mass.

### Force and torque scaling

Strength is authored as **force and torque**, never acceleration. A fighter authors `locomotion_force`, `braking_force`, `burst_force`, and `turn_torque`; the accelerations are quotients. This is where "larger is stronger but slower" comes from for free: default mass goes as `s³` and force as `s²`, so `a = F/m` goes as `1/s`. No speed penalty is authored anywhere, and none may be.

`weapon_torque_scale` is how the same sword behaves differently in different hands — it scales the wielder's applied torque. It never alters the weapon's mass or inertia, which are properties of the object.

Calibration order matters, because it is the only order in which the numbers mean anything: dimensions, then locomotion force, then turn torque against body inertia, then sword torque, then structural coupling, and the damage curve **last**. A baseline that feels right is never achieved by picking a damage number first.

## Mechanisms → code

| Mechanism                                                           | Code                                                                                 |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Footwork in duel axes, stability                                    | `game/src/domain/combat/movement_system.gd`                                          |
| Facing and tracking (degrades with commitment)                      | `game/src/domain/combat/facing_system.gd`                                            |
| Arena boundary and mass-aware body separation (PHYS-005, ARENA-001) | `game/src/domain/combat/arena_constraints.gd`                                        |
| Input language, motor, phases, recovery (COMBAT-001)                | `game/src/domain/combat/weapon_system.gd`                                            |
| Commitment `K`                                                      | `game/src/domain/combat/commitment_model.gd`                                         |
| Swept collision (COMBAT-002) — blade, blade-body, body-body         | `game/src/domain/combat/collision_system.gd`, `fighter_pose.gd`, `contact_report.gd` |
| Blade impulse, deflection, bind, parry, body push (COMBAT-003)      | `game/src/domain/combat/contact_resolver.gd`                                         |
| Relational contact: `v_rel`, impulse, severity (PHYS-001)           | `game/src/domain/combat/impact_model.gd`, `impact_result.gd`                         |
| Structural coupling and effective mass (PHYS-002)                   | `game/src/domain/combat/structural_coupling.gd`                                      |
| Strike quality and damage curve (COMBAT-003)                        | `game/src/domain/combat/damage_model.gd`, `strike_result.gd`                         |
| Initiative / time-to-threat                                         | `game/src/domain/combat/initiative_model.gd`                                         |
| Shared geometry (distance, bearing, duel axes, closing speed)       | `game/src/domain/combat/duel_geometry.gd`                                            |
| Contact lifecycle and hysteresis (COMBAT-007)                       | `game/src/domain/state/contact_pair_state.gd`                                        |
| Chronological contact loop (COMBAT-007)                             | `game/src/domain/match/duel_simulation.gd`                                           |
| Per-tick totality check (COMBAT-006)                                | `game/src/domain/state/state_invariants.gd`                                          |
| Guard classification — diagnostic only (COMBAT-005)                 | `game/src/domain/state/guard_region.gd`                                              |
| Swing semantics — descriptions only (COMBAT-009)                    | `game/src/domain/combat/swing_semantics.gd`                                          |
| Body-contact classification (COMBAT-010)                            | `game/src/domain/combat/contact_resolver.gd`, `strike_result.gd`                     |
| Reading a swing from the primitives (COMBAT-009)                    | `game/src/presentation/entities/sword_trail_3d.gd`                                   |
| Impact feedback from physical channels (COMBAT-009)                 | `game/src/presentation/match/match_presenter.gd`                                     |
| Cardinal sides and spawns (SIDE-001)                                | `game/src/domain/state/duel_side.gd`, `game/src/domain/match/duel_setup.gd`          |
| Local perspective flip — presentation only (SIDE-001)               | `game/src/presentation/camera/duel_camera_rig.gd`                                    |
| Physical baseline and scaling laws (CONTENT-002, PHYS-005)          | `game/src/domain/rules/physical_baseline.gd`                                         |
| Authored build, derived accelerations (PHYS-005, PHYS-006)          | `game/src/domain/rules/fighter_definition.gd`, `weapon_definition.gd`                |

## Attack language (COMBAT-001)

- **Tap**: release before the threshold → exactly 0% charge, and a 90° cut **from wherever the blade actually is**. +45° commands −45°, but +20° commands −70° and +135° commands +45°. A tap is a rotation, never a move to the opposite guard.
- **Hold**: winds the blade physically away from the swing under bounded torque; **release** swings from the actual retracted angle with arc `min_arc + earned wind-back`.
- **Direction**: from the side the blade is _committed_ to (`stable_side`), not the live sign of the angle, so a blade hovering near centre cannot alternate on noise. The sword rests where it stopped, so the next cut starts there.
- **Phases** (`CombatPhase`): `NEUTRAL → CHARGING → LAUNCH → ACTIVE_EARLY/THREAT/LATE → OVERSWING → RECOVERY`, plus `BIND`, `STAGGER`, `DEAD`.
- **Cancel**: a canceled input drops a charge into a short recovery, never an attack.

## Charge is earned displacement (COMBAT-004)

Charge is not a timer. It is the outward travel a hold actually generated, measured past a baseline of `max(guard_angle, |hold_start_angle|)`:

```text
earned_windback = max(0, |angle| - max(guard_angle, |hold_start_angle|))
charge          = earned_windback / windback_span()
arc             = min_arc + earned_windback
```

Four consequences follow without a single special case:

| Situation                                           | Earns   | Why                                                  |
| --------------------------------------------------- | ------- | ---------------------------------------------------- |
| Hold from +20° out to +45°                          | nothing | restoring an under-prepared blade is not preparation |
| A bind leaves the blade at +100°, press and release | nothing | the baseline is where the hold started               |
| Hold from +100° out to +135°                        | 35°     | only the travel the hold added                       |
| Hold at +135° forever                               | nothing | a blade with nowhere to go cannot charge             |

Readiness (`|angle| / guard_angle`, saturating at the canonical guard) is separate: it caps the angular velocity a swing can reach, is captured once at release as `launch_readiness`, and is never a damage multiplier. Inside ±`guard_angle` the blade is quick but under-loaded; outside it has full authority but a longer arc before it threatens. Neither is uniformly better, and nothing snaps an angle toward a canonical guard.

## Guard classification (COMBAT-005)

`GuardRegion` labels a blade `UNDER_PREPARED` / `BASELINE` / `OUTWARD` for the HUD, telemetry, and debug. It is a readout, not a rule: lint forbids `src/domain/combat` and `src/domain/match` from referencing it, because physics must branch on continuous angle, readiness, and earned wind-back. Physics drives classification, never the reverse.

## Relational physics (PHYS-001 – PHYS-004)

The central law: **the same sword swing produces different consequences because both fighters participate in the collision.** Movement changes collision physics; it never applies a damage modifier.

```text
BODY MOTION + BODY ROTATION + SWORD ROTATION
        ↓  v_blade = v_fighter + ω_body × r_pivot + ω_weapon × r_blade
BLADE-POINT VELOCITY
        ↓  minus target velocity, projected on the contact normal
RELATIVE CONTACT VELOCITY
        ↓  combined with effective mass = m_weapon + coupling × m_body
PHYSICAL IMPULSE  (J ~ m_eff · v_rel)   and   SEVERITY  (E ~ ½ m_eff · v_rel²)
        ↓  blade region, edge alignment
PHYSICAL SEVERITY
        ↓  target exposure, from pre-contact state only
DAMAGE / STAGGER / RECOVERY CONSEQUENCE
```

**Impulse and severity are different quantities.** Impulse drives displacement, blade deflection, stagger, and camera kick. Severity drives cutting, injury, and lethality. A heavy weapon shoves; a light fast weapon cuts. Letting one scalar do both is what makes weapons feel like stat blocks.

Because `J = m·v` and `E = ½m·v²`, the two disagree in a way that is worth stating: `J = 2E / v`. For the same cutting energy, the **slower** strike carries more momentum. So a moderate swing with the body behind it shoves a fighter out of position, and a vicious fast one opens them up without moving them much. Each consequence reads the quantity that actually causes it:

| Consequence             | Driven by                                                   |
| ----------------------- | ----------------------------------------------------------- |
| Body displacement       | `Δv = J / m_resisting` — no knockback constant, no exposure |
| Stagger                 | normalized impulse × exposure-as-susceptibility             |
| Attacker's swing arrest | normalized impulse (the momentum it gave away)              |
| Damage and lethality    | normalized severity × blade efficiency × edge × exposure    |
| Critical classification | physical severity plus blade region, alignment, exposure    |

Damage curves are **compressive** at the top. Severity is genuinely quadratic in closing speed, but injury is not: a cut that already opens a fighter up is not improved by more energy. Without that compression the quadratic would make heavy charges strictly dominant and spacing, timing, and punishment would stop paying.

**Effective mass is not body mass** (PHYS-002). A bounded `structural_coupling ∈ [0, 1]` decides how much body inertia is actually behind the blade, derived from plant quality, how coherently body motion supports the strike, body angular coherence, and acceleration debt. Commitment and coupling are different questions — "how hard is this to change?" versus "how well is the body supporting it?" — and a fully committed swing made mid-sidestep is extremely committed _and_ badly structured.

`StructuralCoupling.effective_mass(share, rules)` is the one place that formula is written, and it takes the coupling rather than the fighter: the caller that resolves a hit also _reports_ the coupling in the strike event, and deriving it twice is how the number shown and the number used come to disagree.

| Style                   | Gains                                                                            | Costs                                                                   |
| ----------------------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Planted                 | highest coupling, control, rotational authority, deflection resistance, recovery | no closing contribution; target can retreat out of measure              |
| Advancing               | translational blade velocity, closing speed, often good coupling                 | forward momentum, weak braking and lateral correction, large whiff wake |
| Retreating              | measure, lower incoming closing speed, counter timing                            | less own contribution, weaker coupling while actively backpedalling     |
| Abrupt mid-swing change | positional escape                                                                | lowest coupling                                                         |

Retreating therefore carries **no blanket damage penalty**: a retreating fighter whose opponent charges into the blade can land the hardest strike in the duel, because the closing velocity is relational. The same symmetry makes charging recklessly into a developed swing dangerous rather than automatically jamming it — jamming works only on _early_ entry, inside the useful radius before dangerous blade velocity develops.

**Commitment spends the ability to change the future, not the present** (PHYS-003). Rising commitment reduces desired acceleration and corrective turn torque; it never scales existing velocity or angular velocity. Facing resolves as `α = τ/I` against current angular momentum, so a body already rotating into its swing must first arrest that rotation — reversal costs time, and overshoot is emergent rather than scripted.

**Exposure answers one question**: how incapable is the target of responding structurally or defensively to this strike? It is read from pre-contact state (PHYS-004) so a hit cannot amplify itself, and it modifies consequence only — never the impulse that displaces a body.

## Contact (COMBAT-002, COMBAT-003, COMBAT-007)

Three intentionally different coupling models govern all contacts:

| Interaction   | A affects B | B affects A     | Meaning                                                                    |
| ------------- | ----------- | --------------- | -------------------------------------------------------------------------- |
| Sword ↔ Sword | Yes         | Yes             | True bilateral weapon collision                                            |
| Body ↔ Body   | Yes         | Yes             | Mass-aware physical collision                                              |
| Sword → Body  | Yes         | **Conditional** | Non-stabbing: blade reacts (PHYS-008). Stabbing-angle: one-way penetration |

- Substeps per tick are sized so no blade point travels farther than `substep_travel`; the earliest contact wins, so fast blades never tunnel. An exact TOI tie between a defensive blade contact and a weapon→body contact resolves as defense-wins.
- **A tick is resolved chronologically, not all at once.** All contact types — blade↔blade, blade→body, tip→body, and body↔body — share one unified TOI loop. The remainder of the tick is searched for its earliest contact among all types, both fighters are rewound to that instant, the contact is resolved according to its interaction type, and the rest of the tick is carried forward from the post-resolution state before searching again. Body separation is part of this chronology, not a pre-contact pass, because a body-separation correction can move a fighter away from a sword tip and erase a stab that chronologically preceded the body overlap. A parry at `t = 0.20` has to decide whether the cut at `t = 0.34` happens, and sorting candidates found from the original poses would award a hit the parry prevented. The loop is bounded by `max_contacts_per_tick`; saturation holds the pair in contact and emits `CONTACT_SATURATED`.
- **One clash is one contact.** `ContactPairState` carries the blade lifecycle (`SEPARATED → CONTACTING → BOUND → SEPARATING`) with `separation_epsilon` hysteresis, so blades leaning on each other do not re-strike every tick and a bound pair generates no new impulses. Separation is physical; the cooldown counter this replaced was not. Parts that genuinely come apart may clash again immediately — even inside the same tick.
- **Weapon→body uses an entry-contact lifecycle.** `WeaponBodyContact` per attacker tracks `OUTSIDE → ENTERED → INSIDE → EXITED → OUTSIDE` with separation hysteresis. Damage is applied only on entry (`OUTSIDE → ENTERED`). While the weapon remains inside the body volume, no further damage is dealt. The lifecycle rearms after a genuine geometric exit. This prevents a penetrating sword from dealing repeated damage, and does not use an invulnerability timer — geometry decides when the weapon has left the body.
- **Blade on blade**: 2D rigid impulse about each fighter's pivot from relative contact-point velocity, both effective inertias, contact radii, and the normal. Faster, heavier, better-coupled blades displace the other. A swing slowed below the deflect fraction is interrupted into recovery. Low closing speed binds; a bind resolves by planting and squareness, and always remains escapable — separation, the authored duration, and the `bind_escape_ticks` fail-safe are three independent exits, and equal pressure frees both rather than picking a slot.
- **Parry**: classified, not pressed: the defender ends up threatening first by the parry margin.
- **Body→body**: inverse-mass impulse with low restitution plus bounded Coulomb tangential friction. A heavier fighter absorbs less velocity. The tangential impulse is bounded by `body_friction × normal_impulse` (Coulomb's law), so a glancing shoulder bump sheds some lateral speed but cannot halt a side-step. Body collision MUST NOT directly modify weapon angular state on either fighter.
- **Sword→Body (PHYS-008)**: conditionally coupled. Target movement participates in relative contact kinematics (closing velocity, severity), and the body always receives damage, displacement (scaled by `body_push_feel_scale` for game-feel readability — the extra scale is never reflected back into blade physics), stagger, and stamina shock. Blade reaction depends on a single stabbing-angle predicate that uses the **same thresholds** as point-strike classification (tip region, `point_strike_alignment`, `point_strike_incidence`). There is one definition, not two — if the geometry qualifies as a point strike, the blade penetrates without reaction:
  - **Non-stabbing contact** (transverse slashes, oblique impacts): the weapon receives an opposite reactive angular impulse from the collision, using the weapon's effective mass at the contact point (`I / r²`) and the target's effective mass to compute the reduced-mass collision impulse, then converting to Δω via lever arm and weapon inertia. A well-braced fighter keeps the blade driving through; a loose grip gets deflected more.
  - **Stabbing-angle contact** (point-first entry meeting all point-strike geometric thresholds): the weapon receives NO reactive body impulse. The blade penetrates cleanly. This deliberately breaks local momentum conservation for stabs.
- **Defense is chronological (COMBAT-013)**: determined entirely by the TOI contact loop, not by persisted flags. When a blade↔blade contact resolves before a weapon→body contact, the blade impulse changes the weapon trajectory and the body contact is re-evaluated from the post-deflection state. If the thrust classification no longer qualifies, the defense succeeded through physics. If the thrust still qualifies after the deflection, the point drove through and the thrust lands. There is no `attack_episode_id` or `intercepted_episode_id` in authoritative state.

## Debug

F3 (debug builds) shows distance, closing speed, orbit, each fighter's phase/charge/commitment/stability/time-to-threat, and the last contact (`game/src/presentation/hud/debug_overlay.gd`). Because every consequence decomposes into named physical quantities, the overlay can explain any hit: body speed and acceleration, blade-point speed, target speed, closing speed, structural coupling, effective mass, impulse, severity, edge alignment, exposure, and final quality. A debug vector mode draws fighter velocity, blade contact velocity, target velocity, and relative contact velocity as distinguishable arrows (never colour alone).

## Contact classification (COMBAT-010, COMBAT-011)

Every body contact is classified exactly once: `SLASH`, `POKE`, `THRUST`, or `GRAZE`. Classification happens **after** the contact is geometrically resolved — there is no stab button, no thrust animation, no `STAB_ATTACK` phase, and no separate stab damage multiplier. A point strike exists only when the physical state produces one.

**POINT_STRIKE** is the parent classification for point-first contacts. Two sub-kinds describe how the contact arose:

- **POKE**: point-first body contact during normal movement (walking/standing). The fighter's forward velocity is at or below normal speed. Common, and usually survivable — but a POKE MAY kill if physical severity reaches the lethal threshold (e.g. opponent dashing onto the point).
- **THRUST**: point-first body contact with forward burst and sword-to-motion alignment. Rare. A THRUST is an **instant kill** regardless of HP or severity. This is an explicit game rule: the forward burst velocity and sword alignment are the criteria. Defense is handled by the chronological TOI solver — a blade contact that precedes the body contact physically redirects the weapon, and the thrust is re-evaluated from the post-deflection trajectory.

### Point threat and emergent point strikes

The sword tip is a physical point at `T = P + L × [cos φ, sin φ]`. Its velocity has three independent components:

```text
v_tip = v_fighter + ω_body × r_pivot + ω_weapon × r_tip
```

So a completely motionless sword relative to the fighter can still have substantial point velocity from a forward dash, and a stationary fighter creates tip velocity through weapon rotation alone. Both components may act simultaneously, and target motion participates through the relative quantity `v_rel = v_tip − v_target`.

This means point strikes emerge naturally from:

- walking or dashing forward with a point-forward sword;
- standing still while the opponent runs onto the point;
- both fighters closing simultaneously;
- a post-deflection sword angle that aligns the point forward;
- a combined rotational-translational entry at the end of a swing.

### Axial relative velocity and alignment

The sword's axial direction from hilt toward point is `â = (T − P) / |T − P|`. Axial closing velocity `v_axial = v_rel · â` measures how fast the point is approaching the target along the blade's own axis. **Thrust alignment** `A = max(0, v_axial) / (|v_rel| + ε)` is the fraction of total relative motion that is axial: `A ≈ 1` is a clean thrust, `A ≈ 0` is a crosswise slash. **Incidence quality** `G = max(0, −â · n̂)` measures whether the point is entering the body surface rather than grazing past it.

### Point-strike qualification

A body contact is classified as a point strike (POKE or THRUST) only when **all** of:

1. Point-region contact first (`blade_fraction ≥ tip_region_start`)
2. Positive axial relative closing velocity
3. Sufficient thrust alignment
4. Sufficient incidence quality

Classification is purely geometric — severity affects damage, not classification. A weak aligned tip contact is a weak POKE, not a GRAZE. GRAZE means tangential geometry (low contact quality), not low energy.

The THRUST sub-kind additionally requires the attacker to be in an active forward burst with burst direction aligned to the sword axis. Without the burst, the same geometry classifies as POKE.

The chronological TOI loop is critical: a parry at `t = 0.17` changes the trajectory, so a point-strike candidate at `t = 0.28` must disappear or recompute.

### One physical severity curve, divergent lethality

All point strikes — POKE and THRUST — share **one physical severity model** for the base evaluation. Severity is computed from axial relative velocity, effective mass, incidence quality, and structural coupling through the existing `ImpactModel`. There is no `STAB_MULTIPLIER`. Lethality diverges:

- **POKE**: severity below the lethal threshold produces ordinary point damage from the compressive damage curve. Severity at or above the lethal threshold produces an instant kill. A poke at walking speeds is usually survivable; an opponent dashing onto the point can be lethal.
- **THRUST**: instant kill — no damage roll, no HP check, no severity threshold. The forward burst velocity and sword alignment are the criteria. The chronological TOI solver handles defense: if a blade contact at `t = 0.17` redirected the weapon, a re-evaluated thrust at `t = 0.23` may no longer qualify as a thrust at all. If it still qualifies, the physics says the point drove through. An exact TOI tie between blade defense and body contact resolves as defense-wins.

**Countering a thrust is physical.** If an opponent leaves their point forward and closes, the player swings, the blade reaches the opponent's blade, the impulse resolves, the stabbing sword gets knocked off line, and the point/body candidate disappears. There is no parry button — the counter is physical.

TOI attribution is unchanged: a lethal point strike at `t = 0.32` loses to any lethal contact at `t = 0.27`, and an exact tie is a draw.

### Shared contact kinematics (PHYS-007)

All contact types — blade/blade, blade/body slash, tip/body poke, tip/body thrust — derive contact-point velocity from the same kinematic model. There is no separate stab velocity formula. Forward movement coherence (`v_fighter · â_sword`) participates through structural coupling, not as a separate multiplier, because the translational contribution is already present in `v_tip`. Double-counting is the central danger: forward speed must appear exactly once, in the tip velocity computation, never again as a damage bonus.

### Point legibility

There is no "STAB READY" indicator. Players learn to see sword orientation, point direction, body movement, and open lines. The blade is the interface. Presentation derives trail shape from kinematics: high thrust alignment naturally produces a narrow directional streak rather than a broad curved ribbon, with no combat state change. A qualifying point-strike contact produces distinct concentrated feedback — short strong hitstop, directional impact cue, minimal knockback — because impulse and lethality are different quantities.

### CPU and point strikes

CPU does not receive a `stab()` action. It uses the same movement and attack primitives a human does. Hard CPU may observe that its point is aligned and the opponent's line is open, and select forward movement that the physics then converts into a point strike. Easy CPU misses these opportunities. This is emergent tactical depth, not an authored technique.

## Stamina and capability (STAMINA-001, STAMINA-002)

Stamina is the second axis of degradation alongside injury. Exertion drains stamina; rest recovers it; damage shocks it instantly. As stamina falls the capability scalar degrades, which reduces every motor's force/torque output. A critically fatigued fighter still controls their body (capability floor ≈ 40%) but can no longer sustain the acceleration that makes swordfighting work.

### Motor-based exertion

Stamina drain derives from **actual motor commands**, not from phase labels or inferred velocity changes. Each motor system — movement, facing, weapon — knows the force or torque it requested, what it applied, and the velocity during application. It writes physical work and utilization into a per-fighter `FighterTickScratch` that the simulation owns and resets each tick:

- **Weapon motor:** Dynamic work `P = τ_applied × ω_mid`, split into positive (driving) and braking. Utilization is the fraction of the motor's maximum angular acceleration that was demanded.
- **Movement motor:** Linear work `P = F_applied · v_mid`. Dash costs emerge naturally because burst force × burst velocity is high — no separate stamina channel for dashes.
- **Facing motor:** Torque work `P = τ_body × ω_body_mid`, same structure as the weapon motor.

Work quantities are normalized against the `PhysicalBaseline` (80 kg fighter, bastard sword) before combining, so the 1.6 kg sword's joules and the 80 kg body's joules contribute proportionally to fatigue.

Each channel's raw work is divided by a reference (max power × tick for the baseline), then weighted by work type: positive motor work (driving) costs the most stamina, braking costs less, and static force at near-zero velocity (isometric hold) costs the least. The three channels sum into one normalized effort signal that feeds drain and recovery.

### Contact shock

A body hit costs stamina instantly: `shock = damage × stamina_shock_rate`. Shock is accumulated in the scratch during the chronological contact loop and applied once during the stamina step at tick end, alongside motor drain and recovery. No 60 Hz stamina-changed events — shock rides on the `BODY_HIT` event payload.

### Stamina tick order

All stamina changes happen in one step at the end of the tick, after all motors have run and all contacts have resolved:

1. Compute total normalized effort from the scratch
2. Drain = effort × exertion_rate × dt
3. Recovery = recovery_rate × dt (only if total effort below the recovery ceiling)
4. Apply: `stamina = clamp(stamina − drain + recovery − shock, 0, stamina_max)`

Recovery requires the combined effort of all three motor channels to be below a threshold. Standing still with the sword at rest recovers; walking blocks it; fighting blocks it completely.

### Capability degradation

Capability `C = clamp(1 - P_injury - P_fatigue, floor, 1)` is **additive**, not multiplicative, so combined penalties cannot strand a fighter below the authored floor. Injury penalty uses a gentle nonlinear curve (`injury_load^1.25`); fatigue penalty uses a steepening quadratic (`fatigue_load²`). The capability scalar scales forces and torques — never speed caps — so a fatigued fighter accelerates slowly but hits no artificial speed wall (PHYS-003).

### Condition classification

Health is projected into four coarse bands (`HEALTHY`, `HURT`, `WOUNDED`, `CRITICAL`) for presentation and CPU. The simulation never reads condition; it is a downstream projection of continuous health. The HUD displays condition labels instead of exact HP.

### Presentation pipeline

`SnapshotProjector` copies stamina, stamina ceiling (derived from health), capability, and condition into `PresentationFighter` once per tick. Presentation reads these read-only facts for condition indicators, stamina bars, and capability feedback — it never writes them back. Point-strike contacts (`BODY_POKE`, `BODY_THRUST`) produce distinct audio cues alongside the `BODY_HIT` feedback so the player hears the contact kind; hitstop and camera impulse are already sized by the physics on the hit itself.
