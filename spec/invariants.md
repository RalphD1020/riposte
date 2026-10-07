# Invariants

> Source: architectural constraints

Normative contracts for the Riposte project. RFC 2119: MUST / MUST NOT / SHOULD / SHOULD NOT / MAY.

Conflict rule: **spec > code > docs**. Code that violates this file is defective unless this file has been explicitly superseded.

---

## Monorepo (MONO)

### MONO-001

Sibling packages. `@riposte/web` (`apps/web`) and `@riposte/game` (`game`) MUST be siblings under the root monorepo. Next.js MUST NOT own the Godot runtime. Godot MUST NOT be initialized under `apps/web`.

Next MAY **serve** the exported Web artifact staged at `apps/web/public/game/`, which is gitignored build output produced by `pnpm game:stage:web` from the canonical `dist/game/web/`. Serving bytes is not owning a runtime: Godot sources (`.gd`, `.tscn`, `.tres`, `project.godot`) MUST continue to live only under `game/`, and no Next source may import, build, or configure the engine.

### MONO-002

No-op ban. A package MUST NOT add a script that only echoes success to satisfy Turbo.

### MONO-003

Command-name abstraction. Root `dev` / `build` / `lint` / `typecheck` / `test` MUST invoke Turbo. Implementation technology MUST belong to each package.

---

## Documentation (DOC)

### DOC-001

Authority: spec > code > docs

Code that violates spec is defective. Docs that contradict code are stale.

---

## Web (WEB)

### WEB-001

Godot renderer. Riposte's canonical Godot renderer MUST be Compatibility.

Rationale: the browser is a first-class deployment target and Godot 4 Web exports use WebGL 2 through Compatibility. Forward+ and Mobile MUST NOT be used.

### WEB-002

Gameplay runtime language. Production Godot gameplay/runtime code MUST use typed GDScript.

C# MUST NOT enter the production game runtime without an architecture decision. Godot 4 C# cannot export to Web.

### WEB-003

Web threading. Riposte uses Godot's single-threaded Web export (Compatibility / WebGL 2.0). The committed Web preset MUST enable both `vram_texture_compression/for_desktop` and `vram_texture_compression/for_mobile`.

### WEB-004

Export hosting. `dist/game/web/` is the canonical Godot Web export and the itch.io upload; itch.io MUST NOT receive the Next.js app. The same artifact MAY be **copied** (never moved or symlinked) into `apps/web/public/game/` by `pnpm game:stage:web`, which MUST fail closed when the export is absent or missing any of `index.html`, `index.js`, `index.wasm`, `index.pck`.

`/game/:path*` MUST receive a path-scoped Content-Security-Policy granting `script-src 'wasm-unsafe-eval'` and `worker-src 'self' blob:`; those capabilities MUST NOT be added to the site-wide policy. `'unsafe-eval'` MUST NOT appear in either. The export MUST stay single-threaded (`variant/thread_support=false`), so COOP/COEP MUST NOT be required. `/game/index.html` MUST be served `no-cache`.

### WEB-005

Play admission. Every Play CTA MUST navigate to `/play`; only `resolvePlaySurface` decides the destination, and it MUST prefer, in order: the export staged on this origin (`/game/index.html`), `NEXT_PUBLIC_PLAY_URL` (the itch page), `NEXT_PUBLIC_LOCAL_PLAY_URL` (default `http://127.0.0.1:8060/`), then the `/play` explanation.

Admission MUST NOT depend on the visitor's hostname. Server builds MAY rewrite `/play` to the staged shell, but only when the artifact is present; static exports perform the same hop in `PlayGateway`. Components MUST NOT branch on hosts or on itch, and itch MUST be presented as a secondary destination rather than the primary Play target.

### WEB-006

Purpose-named destinations. Community (shown as Discord) and support (shown as Patreon) are configured by `NEXT_PUBLIC_COMMUNITY_URL` / `NEXT_PUBLIC_SUPPORT_URL` on the web and `CommunityLinks.COMMUNITY` / `SUPPORT` in the game. An unconfigured destination MUST render an announced "Coming soon" stub. URLs MUST NOT be invented or hardcoded elsewhere. Environment destinations MUST be validated: public URLs https only; local play may also use loopback http or a same-origin path; anything else is unconfigured.

---

## Simulation (SIM)

### SIM-001

Authoritative duel. Only `DuelSimulation.step(state, command_0, command_1)` advances authoritative state: exactly one `PlayerCommand` per fighter per 60 Hz tick (`SimulationTimebase`). The simulation MUST NOT read render delta, wall-clock time, input devices, Godot physics, scene nodes, or which source sent a command. `src/domain` and `content/rules` MUST NOT depend on application or presentation (SIM-PURITY lint). Same **build**, same `DuelRules`, same seed, same commands MUST reproduce the same duel, bit for bit, including the state hash. The guarantee is deliberately scoped to one build rather than to "every platform": every arithmetic operation in `src/domain` goes through `SimMath`, but the double-precision result of a transcendental function is the engine's and the C library's, and promising cross-platform identity would be promising something no gate can check. What is checked is replay verification against the recorded commands (SIM-002), which is the strongest claim the gates can actually hold. Modes are configuration (rules + controllers), never separate simulations.

### SIM-002

Determinism proof. `StateHasher` MUST hash every authoritative field from exact IEEE-754 bits in a fixed order (SHA-256); presentation values MUST NOT enter the hash. `ReplayRecord` stores rules id + version, seed, and every tick's commands. `ReplayVerifier` re-simulates and MUST reject a rules mismatch, invalid rules, or a final-hash mismatch. Changing any rules value MUST bump `DuelRules.version`.

### SIM-MATH-001

Deterministic math. Simulation code MUST use `SimMath` (only + − × ÷ sqrt, each a separate operation) instead of engine trig / pow / lerp helpers (platform libm, FMA contraction), and scalar float fields instead of float32 engine vectors (`Vector2`, `Vector3`, …).

### SIM-RNG-001

Randomness. Duel physics uses no randomness. Decision makers (the CPU) MUST draw from `SeededRng`, the only domain wrapper of `RandomNumberGenerator`, seeded from the match seed. Global `randf()` / `randomize()` MUST NOT appear anywhere under `game/src/`.

### MOVE-001

Duel-relative footwork. `PlayerCommand` movement is intent in **duel axes**: `+y` closes on the opponent, `−y` retreats, `±x` orbits right and left. The simulation rotates it into world space through `DuelGeometry.duel_basis`, which uses the opponent's actual **bearing**, never body facing. When separation is below epsilon the fighter's remembered `duel_forward` is used instead, so footwork stays continuous at zero distance; that stored axis MUST be a unit vector in authoritative state (hashed, reset per round, invariant-checked). Every controller — human, CPU, replay, network — MUST emit the same duel-relative language; `PlayerCommand` gains no fields. Improved facing recovery while retreating MUST come from orbit geometry alone; no movement state may modify `turn_speed_max`. No tick may end with body centers interpenetrated, and `buffer_ticks` MUST NOT exceed `WeaponDefinition.BUFFER_TICKS_LIMIT`.

### MOVE-002

Burst footwork. A double tap in one duel direction launches a short burst of footwork, and it MUST be derived from the command stream alone — `PlayerCommand` gains no fields, so human, CPU, replay, and server re-simulation reach the identical burst and no client can claim a gesture. `DirectionalTapRecognizer` reads cardinal sectors with hysteresis (`burst_enter_deflection` to enter, `burst_neutral_deflection` to leave); only rising edges out of neutral count, so held input and key repeat MUST NOT register, and a deflection held past `tap_window_ticks` MUST cancel the pending tap. `MovementGestureState` lives in authoritative `FighterState` — hashed, reset per round and on death, invariant-checked. The heading is frozen in world space at activation and MUST NOT bend mid-burst; mode, kind, and remaining ticks MUST agree, and the heading MUST be a unit vector while bursting. A burst is bounded acceleration toward a bounded peak speed with normal body and arena collision; it MUST NOT phase, teleport, grant invulnerability, or restore facing. Commitment scales burst acceleration exactly as it scales ordinary footwork (PHYS-003), so a dash is never an escape from a swing already paid for. Spam control MUST stay physical — a required return to neutral plus burst duration — with no stamina and no cooldown.

### CMD-001

Command contract. `PlayerCommand` is the only input between a controller and the simulation (human, CPU, replay, future network). Movement is quantized to integer milli-units. Attack fields are edges within the tick window: pressed, released, canceled. Commands are untrusted; the simulation consumes `sanitized()` values. A cancel drops a charge without attacking (focus loss, touch cancel, pause).

### HITSTOP-001

Hitstop is wall-clock only. `FixedTickDriver.hold(seconds)` pauses tick consumption while impact feedback plays and MUST NOT change any tick-indexed result; headless runs and replays ignore it. A frame runs at most `MAX_CATCH_UP_TICKS`. Resuming from pause or a backgrounded tab MUST drop the backlog (`clear_backlog()`), never fast-forward.

---

## Combat (COMBAT)

### COMBAT-001

One-button language. A tap (release before `tap_threshold_ticks`) is exactly 0% charge and a 90° cut **from wherever the blade actually is** — never a move to the opposite canonical guard. Holding past the threshold winds the blade physically away from the swing; release launches from the actual retracted angle with arc `min_arc + earned wind-back`. The sword persists where it stops. Commitment `K ∈ [0, 1]` reduces control authority; recovery follows from what actually happened (whiff, hit, deflection, bind).

### COMBAT-004

Charge is earned displacement, never elapsed time. Charge MUST equal the outward travel a hold actually generated, measured past `max(guard_angle, |hold_start_angle|)` and expressed as a fraction of `windback_span()`. Therefore: restoring an under-prepared blade to the canonical guard earns nothing; a blade a collision flung outward earns nothing for being there; a blade that cannot travel (at the guard limit, or pinned in a bind) earns nothing however long it is held; and no single tick may credit more wind-back than the motor could have produced. `WeaponDefinition` MUST NOT expose a charge duration.

### COMBAT-005

Committed side and readiness. The blade's side is remembered state (`stable_side ∈ {+1, -1}`), updated only once `|angle| > side_deadzone`, so numerical noise near 0° cannot flip the next swing's direction; `swing_direction = -stable_side`. Readiness is the continuous `clamp(|angle| / guard_angle, 0, 1)`, captured once at release as `launch_readiness` and never recomputed in flight. Readiness gates achievable angular velocity only; it MUST NOT be a damage multiplier. ±`guard_angle` are reference guards, not mandatory resting positions, and angles MUST NOT be snapped toward them. `GuardRegion` is diagnostic classification for HUD, telemetry, and debug only: `src/domain/combat` and `src/domain/match` MUST NOT branch on it (lint-enforced). Physics drives classification, never the reverse.

### COMBAT-006

Totality and fail-closed. `StateInvariants.check(state, rules)` MUST run at the end of every authoritative tick. Problems originating outside the simulation (input, focus loss, impossible commands) MUST recover in-band — `ATTACK_CANCELED`, a clamp, or an idempotent ignore. A non-finite or structurally impossible _authoritative_ state MUST emit `SIMULATION_FAULT` and end the match as `REASON_NO_CONTEST` without repairing the evidence. `DuelSimulation.TICK_ORDER_VERSION` pins the canonical tick order documented in `docs/concepts/simulation.md` and MUST be bumped deliberately when that order changes.

---

## Combat physics (PHYS)

> These four laws exist to stop plausible-sounding but false shortcuts: that moving forward is a damage buff, that standing still is maximum force, that body mass is automatically strike mass, or that a vulnerable target makes a sword heavier.

### PHYS-001

Relational contact. All contact severity MUST derive from contact-time _relative_ velocity along the contact normal. Blade-point velocity is `v_fighter + ω_body × r_pivot + ω_weapon × r_blade`; closing speed is that velocity minus the target's, projected on the normal. Target motion therefore participates in every collision: the same swing MUST produce a larger closing speed against an advancing target than a stationary one, and a smaller one against a retreating target. No movement state may carry a direct damage bonus or penalty.

### PHYS-002

Structural coupling. Fighter mass is not automatically strike mass. Effective mass MUST be the weapon's effective mass plus a bounded `structural_coupling ∈ [0, 1]` share of the body's contribution. Coupling is derived from plant quality, movement coherence with the strike, body angular coherence, and acceleration debt — not from forward speed alone, and not identical to commitment. A planted strike MUST have the highest average coupling; an abrupt mid-swing direction change MUST have the lowest. Coupling curves MUST stay forgiving enough that lateral and retreating swordplay remain viable.

### PHYS-003

Momentum integrity. Attack commitment reduces _control authority_, not existing momentum. Implementations MUST scale desired acceleration and corrective torque (`A_move`, `A_turn`), and MUST NOT scale `velocity` or `angular_velocity` directly. Facing correction MUST resolve as `α = τ/I` against existing angular velocity, so reversal costs time rather than snapping. No attack phase may instantaneously erase velocity except through a resolved force or constraint. Collision-induced velocity changes (from body-body contact, arena boundaries, or weapon-body pushback) persist as the initial condition for the next tick's motor step. The movement motor accelerates _toward_ player intent; it does not _set_ velocity. A body-collision push at tick T is still partially present at tick T+1 because the motor's per-tick acceleration budget cannot fully counteract it.

### PHYS-004

Exposure separation. Target exposure MUST be computed from target state immediately _before_ contact, never from post-impact state, so a hit cannot amplify itself. Exposure modifies combat consequence — damage, stagger susceptibility, recovery debt, defensive capability — and MUST NOT fabricate incoming kinetic energy, impulse, or relative momentum. Displacement, blade deflection, and camera impulse MUST be driven by impulse; injury and lethality by severity. A single scalar MUST NOT drive both.

### PHYS-005

Independent mass and geometry. Size and mass are separate authored facts. Implementations MUST NOT derive a fighter's mass from their height or a weapon's mass from its length at runtime; cubic scaling is available only as an explicit default _generator_ for hypothetical same-density geometry. Geometry MUST scale linearly. Strength MUST be authored as force and torque, never as acceleration: every linear acceleration MUST resolve as `a = F/m` and every angular acceleration as `α = τ/I`, so a heavier build pays for its own mass without any authored speed penalty. Fighter mass MUST NOT multiply strike damage, and a wielder MUST NOT alter a weapon's mass or inertia — a stronger arm scales applied torque only. Size and mass MUST NOT affect reaction delay, decision cadence, input timing windows, or buffer length. Body-body collision uses inverse-mass normal impulse (nearly inelastic) plus bounded Coulomb tangential friction: the tangential impulse MUST NOT exceed `body_friction × normal_impulse`, and MUST NOT reverse the direction of sliding.

### PHYS-006

Rotational inertia. A weapon's resistance to being turned MUST be `I = k · m · L²`, where `L` is its effective rotational length and `k` is an authored mass-distribution coefficient (a uniform rod about one end is `1/3`). A fighter's body MUST use `I_body = k_b · m · r²`. Angular acceleration MUST be derived through `α = τ / I`; implementations MUST NOT author an angular acceleration independently of the inertia it acts against, because the two would drift apart and the object would stop obeying its own mass.

### PHYS-007

Shared contact kinematics. All sword/sword, blade/body, and point/body interactions MUST derive contact-point velocity from the same translational and rotational kinematic model: `v_contact = v_fighter + ω_total × r_contact`, where `ω_total = ω_body + ω_weapon`. No attack classification may apply duplicate movement or momentum bonuses. A sword does not need angular velocity to have contact velocity — body translation alone moves the entire weapon. A stationary weapon struck by a body-translated weapon MUST receive impulse through ordinary relative contact velocity. Forward movement coherence (`v_fighter · â_sword`) participates through structural coupling, not as a separate multiplier on tip velocity, because the translational contribution is already present in `v_contact`. Double-counting forward speed — once in `v_tip` and again as a bonus — is explicitly prohibited.

### PHYS-008

Conditional weapon/body coupling. A weapon→body ENTER always computes the physical impact (ImpactResult). The resolved impact drives both target pushback and, conditionally, blade reaction.

**Non-stabbing contact** (transverse slash, hilt-region hit, oblique edge contact): the target receives impact-derived pushback AND the weapon receives an opposite reactive angular impulse computed from the physical impact, the contact lever arm (distance from fighter pivot to contact point), and the weapon's moment of inertia: `Δω = (r × J_reaction) / I_weapon`. This angular impulse is applied to `weapon.speed` (angular velocity), never directly to `weapon.angle`. The chronological solver then carries the corrected trajectory through the remainder of the tick. Hits near the tip produce larger angular reaction than near-hilt hits because the lever arm is longer.

**Stabbing-angle contact** (point-first entry with sufficient axial alignment and incidence): the target receives impact-derived pushback but the weapon receives **no** reactive body impulse — no angular velocity change, no arrest, no deflection, no phase transition. The blade penetrates cleanly. This asymmetry is an intentional game rule permitting clean point penetration, not a physics shortcut. It deliberately breaks local momentum conservation.

The stabbing-angle predicate uses the same thresholds as point-strike classification: `is_stabbing_angle = blade_fraction >= tip_region_start AND thrust_alignment >= point_strike_alignment AND incidence_quality >= point_strike_incidence`. There is intentionally one definition, not two: if the contact geometry qualifies as a point strike (POKE or THRUST), the blade penetrates without reaction. If it does not qualify, the blade reacts. Maintaining separate "weak stabbing" thresholds below the classification bar would allow contacts that suppress blade reaction without being classified as point strikes, which is incoherent.

Game-feel pushback may scale the target impulse (`body_push_feel_scale`) for readability, but that extra amplification MUST NOT be reflected back into the blade reaction. A charged attack pushes harder than a walk-into-point because it carries greater resolved impact, not because the pushback system reads the word `CHARGED`. Charge influences push only through `charge → weapon velocity → relative contact velocity → impact impulse → pushback`.

Body↔body collision MUST NOT directly modify weapon angular state on either fighter.

**Blade reaction model distinction.** Target pushback uses the full system `ImpactResult` (attacker effective mass × closing speed), capturing how hard the whole body-weapon system hit. Blade angular reaction uses a separate reduced-mass collision between the weapon's effective mass at the contact point (`I_weapon / r²`) and the target's effective mass. These models are deliberately distinct: target push answers "how hard was the target hit?"; blade reaction answers "how much did the contact point's collision deflect the weapon?". A well-braced fighter with high structural coupling pushes harder (more effective mass behind the strike) but deflects less (the body absorbs more of the reaction through the grip). Do not "unify" these into one impulse model — they measure different physical quantities and the asymmetry is load-bearing.

### COMBAT-002

Swept collision. Blade and body contact MUST be detected across the whole tick motion in substeps sized so no blade point travels more than `substep_travel`; the earliest contact wins. Blade contact MUST outrank body contact when both fall in the same substep. An exact TOI tie between a defensive blade contact and a weapon→body contact MUST be resolved as defense-wins: the blade interception invalidates the body strike. Godot physics MUST NOT decide a hit.

### COMBAT-007

Contact chronology and lifecycle. All contact types — blade↔blade, blade→body, tip→body, and body↔body — MUST share one unified chronological TOI loop. The tick MUST be resolved in the order its contacts actually happened: find the earliest contact among all interaction types in what remains of the tick, advance to that time of impact, resolve it according to its interaction type (bilateral blade physics, one-way weapon→body consequence per PHYS-008, or bilateral body mass impulse), then carry the remainder forward from the **post-resolution** state and search again. Body separation MUST NOT be applied as a pre-contact pass before sword contacts are evaluated, because a body-separation correction can move a fighter away from a sword tip and erase a stab that chronologically preceded the body overlap. Implementations MUST NOT enumerate candidates from the original start and end poses and sort them, because an early blade contact changes whether a later body contact exists at all. The loop MUST be bounded by `max_contacts_per_tick`; exhausting it MUST hold the pair in contact and report a diagnostic rather than permit tunnelling.

Whether a touch is a _new_ blade contact MUST be decided by a `ContactPairState` lifecycle (`SEPARATED → CONTACTING → BOUND → SEPARATING`) with `separation_epsilon` hysteresis, not by a cooldown counter: touching parts MUST genuinely separate before they can strike again, and a bound pair MUST register no further impulses. A bind MUST always remain escapable — separation, authored duration, and a hard `bind_escape_ticks` bound are independent exits, and equal pressure MUST produce no winner.

Weapon→body contact MUST use a per-attacker entry-contact lifecycle (`OUTSIDE → ENTERED → INSIDE → EXITED → OUTSIDE`) with separation hysteresis. Damage is applied only on the `OUTSIDE → ENTERED` transition. While the weapon remains inside the body volume (`INSIDE`), no further damage is dealt. The lifecycle rearms only after a genuine geometric exit (`EXITED → OUTSIDE`). This prevents a penetrating sword from dealing repeated damage across successive ticks while overlapping. Arbitrary invulnerability timers MUST NOT be used; geometry decides when the weapon has genuinely left the body.

### COMBAT-003

Physical, relational consequences. Blade contact resolves as a 2D rigid impulse (relative contact-point velocity, effective mass, effective inertia, contact radii, normal); low-energy contact binds. Parry and riposte are classified outcomes (the defender ends up threatening first), never inputs. A body strike resolves in two stages that MUST stay separate: a _physical interaction_ producing impulse and severity from blade-point velocity, target velocity, effective mass, and contact geometry; then a _combat consequence_ mapping severity, blade efficiency, and edge alignment through exposure to damage, stagger, and recovery disruption. Criticals come from convergence, never chance. Simultaneous body hits are evaluated against pre-hit state, so double hits stay symmetric. See PHYS-001 – PHYS-004.

### COMBAT-008

First-contact attribution. Every death MUST record the sub-tick instant the lethal blow arrived (`FighterState.lethal_fraction`, set only through `WeaponSystem.kill` from the contact's time of impact), and `StateInvariants` MUST reject a dead fighter without one, a living fighter with one, and a value outside `[0, 1]`. When both fighters are dead at round-end evaluation, the round MUST go to whoever fell later (`REASON_TRADE_FIRST_CONTACT`); only an exactly equal instant is a draw (`REASON_DOUBLE_KILL`). Attribution MUST NOT consult slot number, attacker or defender role, remaining health, iteration order, or randomness.

### COMBAT-009

Swing semantics are descriptions, never decisions. Named readings over authoritative state — swing potential, swing progress, contact quality, exposure as a fraction, and a strike grade — MUST be derived from the physics and MUST NOT participate in it. Nothing in the simulation may read one back, and no presentation code may recompute a combat formula: a value not carried on `PresentationSnapshot` or a `DuelEvent` payload MUST be done without rather than invented.

Swing potential MUST be a bounded reading of how dangerous the current part of the current swing is, taken from the blade's **actual** tip speed and quadratic in it (severity goes as `v²`), gated to zero whenever the blade is not carrying a strike. A quantity already carried by another MUST NOT be multiplied in again: charge and arc are expressed through the speed the motor achieved, so counting them a second time would make the same physical blade speed mean two different things. The dangerous part of an arc therefore emerges from the acceleration curve rather than being authored, and moves between swings.

Swing progress MUST be measured in physical travel along the commanded arc, never in elapsed ticks, so a blade stopped by another blade stops progressing.

Potential MUST NOT be prediction. Convergence exists only at contact, so no pre-contact surface may promise what a strike would do; before contact an interface may show the attacker's own potential and let vulnerability read from the target's own physical state. Grades MUST describe the resolved result and MUST NOT choose damage, and there MUST be no dice roll.

### COMBAT-010

Emergent point strike. A point strike is a **contact classification**, never an input, attack state, animation, or special move. There MUST NOT be a stab button, a `STAB_ATTACK` phase, or a thrust damage multiplier. A point strike exists only when the physical state produces one: the sword's point enters the opponent first, along a sufficiently axial trajectory, without the opponent's weapon intercepting it. Classification is purely geometric — it describes how the contact arose and MUST NOT be gated on severity. A weak aligned tip contact is a weak POKE, not a GRAZE. GRAZE means the contact geometry is glancing or tangential, not merely low-energy.

POINT_STRIKE is the parent classification. Two sub-kinds describe how the contact arose:

- **POKE**: point-first body contact. Classified when: tip-region contact (`blade_fraction >= tip_region_start`), sufficient thrust alignment, sufficient incidence quality, and the weapon supports thrusts. No severity threshold — a slow aligned tip contact is a weak POKE, not a GRAZE. A POKE MAY be lethal if physical severity reaches the lethal threshold (COMBAT-011).
- **THRUST**: point-first body contact with forward burst and sword-to-motion alignment. Classified when: all POKE criteria AND the attacker is in an active burst with burst direction aligned to the sword axis. A THRUST is an **instant kill** regardless of HP or severity. This is an explicit game rule, not a physics calculation. Defense is handled entirely by the chronological TOI solver: a blade contact that precedes the body contact changes the weapon trajectory, and the body contact is re-evaluated from the post-deflection state. If the thrust classification no longer qualifies, the defense succeeded. If it still qualifies, the physics says the point drove through despite the deflection.

A point-strike candidate MUST satisfy all of: (1) tip-region body contact (`blade_fraction >= tip_region_start`), (2) sufficient thrust alignment (`A = max(0, v_axial) / (|v_rel| + ε)`), (3) sufficient incidence quality (`G = max(0, -â · n̂)`), and (4) weapon supports thrust. Severity MUST NOT gate classification — it affects damage, not what kind of contact occurred. The chronological TOI contact loop (COMBAT-007) MUST evaluate point-strike candidates after blade contacts that precede them, because a parry at `t = 0.17` changes whether a thrust at `t = 0.28` exists at all. One body contact gets exactly one classification (`SLASH`, `POKE`, `THRUST`, or `GRAZE`); there MUST NOT be separate detectors that independently apply both slash damage and a thrust kill for the same contact.

**GRAZE** is a geometric classification: the contact quality (blade efficiency × edge alignment) is below the graze threshold, meaning the blade's edge did not lead the contact — it slid or scraped. A low-energy well-aligned cut is a weak SLASH, not a GRAZE. A low-energy well-aligned tip contact is a weak POKE, not a GRAZE. Classification separates geometry from severity.

Defense is determined entirely by the chronological TOI solver, not by persisted flags or episode tracking. If a blade↔blade contact at `t = 0.17` changes the weapon state and a recomputed thrust candidate at `t = 0.23` no longer qualifies, the defense succeeded — the physics redirected the weapon. If the thrust still qualifies after the deflection, the physics says the point drove through despite the interception attempt. An exact TOI tie between blade defense and body contact MUST resolve as defense-wins (COMBAT-002). There MUST NOT be a `target.is_unprotected` flag, an `attack_episode_id`, or any other persisted defense marker — the chronological loop itself decides.

Fighter translation, fighter rotation, weapon rotation, and target motion all contribute to tip velocity through shared contact-point kinematics (PHYS-007). A stationary sword on an advancing fighter, a motionless fighter whose opponent dashes onto the point, a post-deflection alignment, and a combined rotational-translational entry are all equally valid point-strike sources. A point strike MUST NOT require the fighter to be facing the opponent perfectly — it requires the sword point's trajectory to intersect the opponent. Facing affects structural coupling, control, and exposure; it MUST NOT veto a physically valid point contact. `WeaponDefinition.supports_thrust` controls whether a weapon can produce a lethal point strike; `tip_region_start` and `thrust_efficiency` are per-weapon content.

### COMBAT-011

Point-strike severity and lethality. POKE and THRUST share one physical severity model for the base evaluation. Severity is computed from axial relative velocity, effective mass, incidence quality, and structural coupling through the existing `ImpactModel`. Lethality diverges by classification:

- **POKE**: severity below the lethal threshold produces ordinary point damage from the compressive damage curve. Severity at or above the lethal threshold produces an instant kill. A POKE MAY be lethal if the physical severity is high enough (e.g. opponent dashes onto the point); a POKE at walking speeds is usually survivable.
- **THRUST**: an instant kill. No additional damage roll, no HP check, no severity threshold. The forward burst velocity and sword alignment are the criteria. The chronological TOI solver handles defense: a blade contact that precedes the body contact physically redirects the weapon, and the thrust is re-evaluated from the post-deflection trajectory. A thrust that still qualifies after a deflection is physically valid and lands.

There MUST NOT be a `STAB_MULTIPLIER` or a damage bypass that ignores physics for the base severity evaluation. The THRUST instant-kill rule is an explicit game-design decision layered on top of the physics, not a physics shortcut. Lethal-contact TOI ordering (COMBAT-008) remains the authoritative simultaneous-kill rule.

### COMBAT-012

Body-body impulse. Fighter-body contacts are reciprocal physical collisions. At contact TOI, the solver applies equal-and-opposite normal impulses derived from relative contact velocity, fighter masses, and authored restitution. Dash, walking, retreat, and counter-charge influence the result only through physical state; no movement mode receives an arbitrary body-collision multiplier. Collision-induced velocity persists into the remainder of the chronological simulation and MAY affect later weapon, body, or arena contacts. Input locomotion accelerates toward desired motion and MUST NOT erase the resulting impulse on the next tick. A stationary fighter MUST NOT be treated as infinite mass unless an explicit bracing mechanic is authored. Body-body collision does not directly reduce HP; the sword remains the lethal mechanism. Running-into-point parity: for equal masses and geometries, a fighter walking point-first at +4 m/s into a stationary target and a stationary sword with a target walking into the point at −4 m/s MUST produce approximately equal physical quality, damage, pushback, and lethality result — relative collision velocity is what matters, not which participant supplied the motion.

### COMBAT-013

Chronological defense resolution. Defense against a thrust is determined entirely by the chronological TOI contact loop (COMBAT-007), not by persisted state on the weapon. When a blade↔blade contact resolves before a weapon→body contact in the same tick, the blade impulse changes the weapon trajectory and the body contact is re-evaluated from the post-deflection state. If the thrust classification no longer qualifies, the defense succeeded through physics. If the thrust still qualifies after the deflection, the point drove through and the thrust lands. There MUST NOT be `attack_episode_id`, `intercepted_episode_id`, or any other per-episode defense tracking in authoritative combat state. The `DamageModel` MUST NOT accept a `defended` parameter — lethality is determined by classification alone.

---

## Stamina (STAMINA)

### STAMINA-001

Motor-based exertion. Stamina drain MUST derive from actual motor commands — force, torque, angular velocity — not from phase labels, inferred Δv, or arbitrary constants. Each motor system (movement, facing, weapon) reports its own physical work (positive dynamic work `P = F·v` or `P = τ·ω`) and utilization (fraction of motor capacity demanded) into a per-fighter `FighterTickScratch` that the simulation owns and resets each tick. Stamina is committed once at tick end, after all motors have run and contacts have resolved.

Normalization: each channel's raw work (joules/tick) is divided by its reference work — the max-power output per tick for the baseline fighter/weapon (`PhysicalBaseline`). The result is weighted by work type (`drive_weight > brake_weight > hold_weight`) and summed across channels into a single normalized effort signal. This effort feeds `StaminaModel.exertion()` for drain and `StaminaModel.recovery()` for the rest threshold. Contact shock (`damage × stamina_shock_rate`) accumulates in the scratch during the chronological contact loop and is applied in the same stamina step.

Dash costs emerge from the same `F·v` physics as walking — dash is high force at high velocity, not a separate stamina channel. No 60 Hz `STAMINA_CHANGED` events; shock rides on `BODY_HIT` payloads.

### STAMINA-002

Capability from stamina. Capability is a `[floor, 1]` scalar that scales motor forces and torques — never speed caps (PHYS-003). It degrades additively under injury and fatigue: `C = clamp(1 - P_injury - P_fatigue, floor, 1)`. Injury penalty is gentle nonlinear (`injury_load^1.25`); fatigue penalty is steepening quadratic (`fatigue_load²`). Combined floor prevents death spiral. Capability is frozen at tick start: within one tick, every system sees the same capability regardless of when it runs.

---

## CPU (CPU)

### CPU-001

Fair CPU. The CPU MUST emit the same `PlayerCommand` a human would and obey the same rules. It feels its own body now and perceives its opponent only through a reaction-delay memory extrapolated by its anticipation skill; it MUST NOT read hidden state or future commands. Difficulty is `CpuProfile` data (reaction, cadence, anticipation, discipline), never stat or rule changes. Variety comes from `SeededRng`, so CPU play is reproducible per seed.

### CPU-002

Physical parity. For identical `FighterDefinition` and `WeaponDefinition`, CPU difficulty MUST NOT modify any physical quantity: fighter mass, body inertia, movement force, braking force, turn torque, weapon mass, weapon inertia, weapon torque, charge rate, reach, damage, exposure, collision response, burst magnitude, movement cap, or stagger recovery. A harder opponent MUST be the same body and the same sword in better hands.

Difficulty MUST NOT reach `DuelRules`. `MatchConfig` MUST resolve identical rules content for every difficulty, so an identical command stream replayed under each difficulty produces an identical state hash. A difficulty that changed the physics could not satisfy that.

### CPU-003

CPU acceptance testing. Combat changes may require CPU profile retuning, but MUST NEVER weaken a tactical acceptance criterion merely to restore green tests. The acceptance-seed corpus is fixed and MUST NOT be inspected while tuning. If combat physics changes cause Hard to lose its decisive margin over Easy, the correct response is to fix the underlying physics or retune the profiles — not to lower the decisive threshold, shrink the seed corpus, or add variance tolerance. Acceptance tests that can be weakened into passing are not tests.

Information parity. CPU decisions about the opponent MUST read only delayed, perceived state. The CPU MUST NOT read a future or in-flight command, a private input edge before it manifests physically, hidden RNG state, or any authoritative value a watching human could not infer from the opponent's body. Prediction MUST extrapolate observation (`last seen position + last seen velocity × horizon`) and MUST NOT consult truth. Its own body it may feel immediately, which is proprioception rather than privilege.

A CPU MUST NOT receive a pre-contact strike quality (COMBAT-009): before contact nobody knows what a hit would do, so an expected outcome MUST be a coarse reading of perceived geometry rather than a call into the damage resolver.

### CPU-004

Difficulty is decision quality. The axes along which profiles MAY differ are perception delay, decision cadence, prediction horizon, tactical assessment weighting, planning depth, opponent-tendency memory, rhythm variation, and action-selection error rate. Every difficulty MUST share one tactical evaluator and one intent generator; there MUST NOT be a per-difficulty behaviour tree, and there MUST NOT be a scripted technique call (`perform_pull_counter()`) — tactics are plans over the same primitives a thumb drives.

Lower difficulties MUST express error by choosing a worse _plausible_ option, never by acting at random. A profile MUST NOT be made stronger by lowering reaction delay below a human-achievable latency; a strictly faster reader is not a better fencer.

### CPU-005

Behavioural support. A claimed tactical proficiency MUST declare a minimum count of eligible situations. Below it the verdict MUST be `INSUFFICIENT_SUPPORT`, which MUST NOT be reported as a pass — a 100% success rate over three opportunities is not evidence.

Where a test grades an emergent outcome rather than an authored value, calibration seeds and acceptance seeds MUST be disjoint, and the acceptance corpus MUST NOT be inspected while tuning. A claim whose effect size is too small for the affordable sample MUST be measured by a diagnostic tool rather than gated; raising the sample until a gate passes re-creates the overfitting the split prevents.

---

## Sides (SIDE)

### SIDE-001

Cardinal sides and one locked world. The arena has exactly one permanently fixed orientation — north is `+y`, south is `-y` — and the simulation MUST NOT rotate for anyone. `DuelSide { LIGHT_SOUTH, DARK_NORTH }` is a first-class identity that determines canonical spawn, initial facing, presentation identity, and local camera orientation; it MUST NOT be inferred from slot number, spawn position, colour, or camera yaw, all of which are consequences of it. Light spawns at `(0, -spawn_offset)` facing north and Dark at `(0, +spawn_offset)` facing south, each looking at the other. Exactly one fighter MUST hold each side, and side MUST survive a round reset. Side MUST be covered by `StateHasher`.

Quick Play MUST assign sides 50/50 from the match seed, so both cardinal spawns and both camera orientations are exercised by ordinary play.

Local camera yaw is **presentation only**: the local player is always at the bottom of the screen, so a local Dark player's view is turned half a revolution. It MUST NOT enter `StateHasher`, replay state, or any authoritative state — it is the one quantity two viewers of the same match may legitimately disagree about, which is what lets two networked players see opposite perspectives of one authoritative world. Footwork MUST stay encoded through the duel basis rather than world directions, and the presentation invariant _local right projects right on screen, local forward projects up_ MUST hold for both sides.

Side MUST be communicated by more than colour: colour plus edge pattern plus spawn orientation plus HUD label. Arena cardinality cues MUST NOT compete with blade readability.

---

## Content (CONTENT)

### CONTENT-001

Authored definitions are immutable data. Fighters, weapons, and arenas are plain id-keyed definitions produced by pure catalog functions, never mutable Godot `Resource`s inside the domain. A definition MUST NOT carry runtime state: an authored definition and a mutable match state are different things, and nothing may write to a definition after creation. Derived quantities (moment of inertia, available acceleration, collision geometry) MUST be computed from the definition rather than stored alongside it; caching is permitted only where recomputation is measurably wasteful, and the cache MUST NOT be authorable. Every definition MUST validate: positive physical magnitudes, `blade_length <= length`, `guard_limit > guard_angle`, `I > 0`.

### CONTENT-002

Physical baseline. The duel has exactly one normalized physical baseline, stated once in `PhysicalBaseline`: a 1.75 m, 80 kg fighter with a 0.27 m footprint, holding a 1.22 m bastard sword with a 0.97 m effective blade at 1.60 kg, with canonical guards at ±45°, a ±135° guard limit, and a 90° tap arc. `scale = 1.0` MUST mean exactly that fighter and that weapon, in SI units. Abstract units (`player_size = 100`) MUST NOT appear anywhere. Baseline magnitudes MUST NOT be duplicated as literals in content or code. Normalized ratios against the baseline MAY be exposed as diagnostics, but the simulation MUST NOT read them, because the absolute quantities already carry every effect of scale and reading both would count scale twice.

> Calibration order is normative, because it is the only order in which the numbers mean anything: freeze dimensions, then locomotion force, then turn torque against body inertia, then sword torque, then structural coupling, and only then collision severity and the damage curve. A baseline that feels right MUST NOT be achieved by picking a damage number first.

---

## Presentation (PRES)

### PRES-001

Presentation never authorizes outcomes. `SnapshotProjector` is the only place presentation reads `MatchState`, producing one immutable `PresentationSnapshot` per tick. `MatchPresenter`, proxies, directors, the HUD, and touch controls consume snapshots and events and emit intents or requests (hitstop, pause); they MUST NOT step, mutate, or read the simulation. `src/presentation` MUST NOT reference application classes (lint derives the ban from `class_name`s).

### PRES-002

Presentation architecture. The data flow is:

```text
Simulation → PresentationSnapshot + DuelEvents
→ CombatFeedbackDirector → FeedbackFrame (value-like requests)
→ CameraFeedback, FighterPresenter, WeaponPresenter, VfxPresenter,
  AudioPresenter, PresentationTimeController
```

`CombatFeedbackDirector` MUST be pure computation — no SceneTree dependency, no node manipulation. It outputs a `FeedbackFrame` of typed value-like requests (`CameraShakeRequest`, `HitstopRequest`, `AudioCueRequest`, `VfxRequest`, `FighterCueRequest`, `WeaponCueRequest`). Downstream presenters consume requests. Nothing below the director may modify authoritative state. Weapon visual transform is driven by authoritative weapon angle + fighter transform, not by animation clips. Character animation visually supports the authoritative sword position, never the reverse. Root motion, if used, MUST be warped to match the authoritative trajectory.

### PRES-KIT-001

One manifest per combatant identity. Each combatant is a `CombatantPresentationKit` composing a `FighterPresentationKit` (body scene, animation map, condition profile, audio) and a `WeaponPresentationKit` (blade scene, grip metadata, trail/spark/impact profiles, audio). This split exists because the same fighter MAY hold different weapons and different fighters MAY hold the same weapon; both MUST compose cleanly.

Changing an identity's art, animation, or sound MUST be a kit edit (an authored `.tres` at `RiposteKits.AUTHORED_KIT_PATHS`), never a presenter or gameplay change. Generic presentation code MUST NOT name content identities. Debug builds fail closed on a missing kit; release builds degrade to a placeholder.

Animation clips use semantic slots (`IDLE`, `MOVE_FORWARD`, `MOVE_BACKWARD`, `ORBIT_LEFT`, `ORBIT_RIGHT`, `DASH_FORWARD`, `DASH_BACK`, `DASH_LEFT`, `DASH_RIGHT`, `CHARGE`, `SWING`, `OVERSWING`, `RECOVERY`, `HURT`, `CRITICAL`, `DEATH`). `animation_clips` keys MUST be a subset of declared semantics; a kit mapping anything else has authored a clip the proxy will never ask for. Primitive presenters drive procedural transforms from these semantics; Blender presenters drive `AnimationTree`. An authored scene MUST NOT own the blade, a physics body, or a collision shape: the simulation decides position, facing, and contact, and the rig only shows them. Rig and animation contract: [docs/reference/godot.md](../docs/reference/godot.md).

Contact feedback uses shared semantic `ImpactPresentationProfile`s (clash, slash, poke, thrust, graze, kill) defining shake curve, hitstop band, baseline particle intensity, and audio category. `WeaponPresentationKit` MAY override cosmetic aspects (audio family, spark look, trail look) but MUST NOT redefine the semantic meaning of a contact class. Damage state belongs to fighter presentation (`FighterPresentationKit.condition_profile`), not weapon.

---

## UX (UX)

### UX-001

Accessible by construction. Every UI text/background pair MUST reach 4.5:1 and every essential non-text boundary 3:1 (WCAG 2.2), proven by tests over declared pairs (`RiposteTheme` pairs; `globals.css` tokens via `theme.test.ts`). Interactive targets are ≥ 48 UI units and one UI unit MUST be ≥ one CSS pixel (`UiScale`). State is never conveyed by color alone. Every shipped string MUST render in the shipped font. Every control has a visible label or an accessible name, and focus is always visible.

---

## Git (GIT)

### GIT-001

Agents MUST NOT create commits unless the user explicitly instructs it in the current request.

---

## Coverage (COVERAGE)

### COVERAGE-001

Every non-UX/UI production source file MUST achieve 100% line, function, and branch coverage individually. Web/TypeScript code MUST additionally achieve 100% statement coverage. Coverage is necessary but not sufficient: every behavioral invariant MUST also have an independent, non-vacuous behavioral test.

Coverage MUST be measured per file. Do not use project-average 100%. One file at 99.9% means the gate is RED. No `autoUpdate`. No coverage-ignore comments. No exclusions inside covered roots merely because something is difficult to test.

**Covered scope** includes: authoritative simulation/domain, deterministic math, combat, AI/targeting, economy, production, placement/build validation, game state machines, commands, config resolution, content validation, replay/hash/serialization, application orchestration, interaction/authorization logic, matchmaking, ELO calculation, nonvisual web application/domain logic, and executable presentation logic (directors, feedback mapping, settings scaling, snapshot projection, camera math, impact classification).

**Excluded from numeric 100%** (by architectural scope only): purely visual node hierarchy (scene tree wiring, mesh construction, material assignment), VFX/SFX asset playback, shaders, animation/art polish (what looks/sounds good), purely decorative camera feel (what feels right), third-party addons, generated code, test code itself.

If code affects authoritative state, permissions, simulation outcome, economy, progression, win/loss, deterministic hashes, matchmaking results, ELO ratings, or shipping product behavior, it MUST NOT reside in a coverage-excluded directory.

**Web/Vitest**: `coverage.include` MUST cover every in-scope web source file (`src/**/*.{ts,tsx}` minus tests, `*.d.ts`, and `src/test/`; routes and layouts included). Required: `thresholds: { 100: true, perFile: true }`. No v8/istanbul ignore comments in in-scope code. A mechanical manifest completeness check (`check-coverage-manifest.mjs`, run by `test:coverage`) MUST verify that the set of in-scope filesystem source files equals the set of files present in `coverage-final.json`. A new production file that no test imports MUST cause the manifest check to fail, not silently disappear from the coverage denominator.

**GDScript**: 100% measured line/function/branch coverage is required for in-scope non-UX/UI production scripts before Mechanical Freeze closes. Do not rewrite the existing deterministic harness merely for instrumentation. Mechanical Freeze stays OPEN until measurement exists.

**Content coverage**: catalog-driven content validators MUST cover 100% of canonical entries. A newly registered content item MUST automatically enter the test denominator.

---

## Testing (TEST)

### TEST-TRUTH-001

Every behavioral test MUST explicitly assert its fixture (ARRANGE), the perturbation (PERTURB), run production code (ACT), and verify the contract (ASSERT).

A test's function name and comments are not evidence. Preconditions MUST be asserted before the oracle is invoked.

**Anti-vacuity rules** (test lint MUST reject):

- `assert_true(true)` / equivalent tautologies
- disabled/skipped tests in covered suites
- zero-assertion test functions
- commented-out assertions
- warning-only correctness checks
- coverage-ignore directives
- ignored fallible fixture setup

**Expected results MUST be independent** of production logic under test.

Do NOT use `assert()` for required release behavior. Godot strips `assert()` in non-debug builds. Production handling MUST use explicit `if/else` branches that are testable and present in shipping builds.

### ZERO-TOLERANCE-001

Zero `@warning_ignore`; Godot default warnings are errors. The repository MUST contain zero `@warning_ignore`, `warning_ignore_start`, or `warning_ignore_restore` directives.
