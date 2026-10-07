# Combat Feel Gate

> See also: [docs/concepts/combat.md](../concepts/combat.md), [docs/concepts/presentation.md](../concepts/presentation.md), [docs/concepts/ux.md](../concepts/ux.md)
> See also: [docs/reference/testing.md](./testing.md), [docs/reference/device-qa.md](./device-qa.md)
> See also: [spec/invariants.md](../../spec/invariants.md) — COMBAT-009, PRES-001, UX-001

The last gate before mechanics are frozen. It asks one question the test suite structurally cannot: **can a person who has never seen the game read the fight?**

The suite proves that every cue is driven by the physical quantity that causes it, that no cue can exceed what the simulation applied, and that turning a cue off loses no information. None of that is the same as a human looking at the screen and knowing what just happened. A duel can be perfectly correct and still illegible, and no assertion will say so.

So this is a hand pass, and it is **the human's to run**. An agent may report that the mechanisms are wired and proven. An agent may not report that the game feels good.

## What the suite already proves, and therefore is not your job

Each row is the mechanism behind a gate item. If one of these fails, it is a bug and the suite will say so — you are not checking the wiring, you are checking the reading.

| Mechanism                                                     | Proof                                                             |
| ------------------------------------------------------------- | ----------------------------------------------------------------- |
| Ribbon thickness comes from simulated swing potential         | `test_the_ribbon_is_fed_the_simulated_swing_potential`            |
| A more dangerous part of a swing is drawn heavier             | `test_the_ribbon_is_thicker_where_the_swing_is_more_dangerous`    |
| A wind-back reads as no threat at all                         | `test_a_charging_blade_reads_as_no_threat`                        |
| The sweet region is its own shape, not just a tint            | `test_the_sweet_region_is_drawn_as_its_own_shape`                 |
| The region is a fraction of the blade, at any weapon length   | `test_the_sweet_region_is_a_fraction_of_the_blade`                |
| A heavy graze feels weaker than a perfect light hit           | `test_a_heavy_graze_feels_weaker_than_a_perfect_light_hit`        |
| Harder clashes punctuate harder, continuously                 | `test_a_harder_clash_punctuates_harder`                           |
| Impact leans the way the blow actually went                   | `test_impact_feedback_follows_the_carried_contact_direction`      |
| A bind sounds like itself and does not freeze                 | `test_a_bind_sounds_like_itself_and_does_not_freeze`              |
| Recoil never overstates the push the simulation applied       | `test_recoil_never_overstates_the_push_the_simulation_applied`    |
| A whiff is never punctuated like a hit                        | `test_a_whiff_is_never_punctuated_like_a_hit`                     |
| Burst dust writes on the floor, behind the fighter            | `test_a_burst_kicks_dust_along_the_floor_behind_the_fighter`      |
| Grade names agree with the damage they accompany              | `test_grades_agree_with_the_damage_they_accompany`                |
| Every motion cue off still leaves the hit marked, heard, felt | `test_combat_stays_legible_with_every_motion_cue_switched_off`    |
| Reduced motion removes camera impulses                        | `test_reduced_motion_disables_camera_impulses`                    |
| The sweet-spot cue scales the drawing, never the region       | `test_the_sweet_spot_cue_scales_the_drawing_not_the_region`       |
| Trail off draws nothing and loses no sample                   | `test_trail_strength_off_draws_nothing_and_loses_nothing`         |
| Diagnostics describe without changing anything                | `test_a_resolved_strike_describes_itself_without_changing_itself` |

## Setup

```bash
pnpm game:export:web
pnpm game:stage:web
pnpm dev:web
```

Open `http://localhost:3000`, click Play, and confirm `/play` loads the game on this origin rather than sending you to itch.io. Play through the product, not the editor: the gate is about the shipped build.

Recruit someone who has not played it. Do not explain the mechanics first — the whole point is what the screen teaches on its own. Watch them play a full match, then ask the questions below. Their answers are the gate; your knowledge of the code is not admissible.

## 1. The readability questions

A new player, after one match, should be able to answer all eight. Record the answers verbatim; a confident wrong answer is a worse failure than "I don't know", because it means the game taught something false.

1. Which way is the opponent's sword moving right now?
2. Are they winding up, or already swinging?
3. How heavily was that attack prepared?
4. At what moment did that swing look most dangerous?
5. Did the swords hit each other, or did a sword hit a body?
6. Who came out of that exchange in the worse position?
7. Why was that last hit unusually strong?
8. When is the opponent recovering — when can you hit them for free?

## 2. The feel checklist

All fourteen are required. Mark each pass or fail with a sentence, not a tick.

**Swing legibility**

1. A tap and a charged cut are visually distinguishable before they land.
2. The physical wind-back is visible — you can see the blade travel backwards.
3. An under-prepared strike visibly lands weaker than a prepared one.
4. The sweet region is identifiable on the blade without any meter or number on screen.
5. A great hit is visibly stronger than a bad hit **at the same nominal charge**. This is the one that catches a damage model that secretly reads the input instead of the blade.

**Contact legibility**

6. Collision direction is understandable — you can tell which way the blow went.
7. Blade-on-blade and blade-on-body are unmistakably different events.
8. A strong parry visibly creates positional advantage for the defender.
9. A whiff clearly communicates commitment and recovery: you can see it was a mistake and see the window it opened.

**State legibility**

10. Opponent vulnerability is legible from body and blade state alone, with no HUD.
11. Double-tap burst movement is readable as a deliberate dash, never confusable with a swing.

**Accessibility floor** — repeat a round with each of these and confirm nothing becomes unreadable:

12. Screen shake off, reduced motion on: no information is lost, only motion.
13. High-contrast weapons on, trail off, sweet-spot cue off: the blade and the sweet region are still readable. Off is a supported way to play, not a handicap.
14. Everything above holds on an actual phone. That pass is [device-qa.md](./device-qa.md); do not substitute a resized desktop window for it.

## 3. The browser pass

Through the real product, in a browser, on the staged build:

- The site loads, Play reaches `/play`, and Godot boots without a console error.
- Quick Play starts; Light and Dark spawn at opposite cardinal ends.
- The camera puts the human at the bottom of the screen, whichever side they drew.
- `W`/`S` move relative to the opponent, `A`/`D` orbit around them.
- All four directional double-taps burst in the duel direction, not a screen direction.
- A tap cuts; a hold winds the blade back and releases harder.
- Blades collide and the disturbed blade state persists after the clash.
- A parry leaves a riposte opportunity that is actually takeable.
- A mutual kill attributes to first contact rather than defaulting to a draw.
- A CPU match completes: round sequence, result screen, rematch, pause, settings, return to menu.

## 4. Recording a pass

Write the date, the build, the device, the player, their eight answers, and any failed checklist item with a sentence about what it looked like. A failure here is a presentation or tuning change, never a mechanics change — the mechanics are what this gate exists to freeze.

**Mechanics freeze only after this gate passes.** Freezing on a green test suite alone would freeze a game nobody has confirmed is readable, which is the one thing the suite was never able to tell us.
