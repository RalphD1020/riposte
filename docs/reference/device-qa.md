# Device QA

> See also: [docs/concepts/ux.md](../concepts/ux.md), [docs/concepts/controls.md](../concepts/controls.md)
> See also: [docs/reference/testing.md](./testing.md)
> See also: [spec/invariants.md](../../spec/invariants.md) — UX-001, MOVE-002
> Source: `game/tests/application/test_app_e2e.gd`

The one pass the automated gates cannot do. Everything here is either a
physical property of a hand on glass or a judgement about legibility at arm's
length, which is exactly why it is a written procedure rather than a memory:
a checklist that lives in someone's head gets shorter every release.

## What is already proven, and therefore not on this list

Do not re-test these by hand. APP-E2E drives real `InputEventScreenTouch` and
`InputEventScreenDrag` through the shipped `main.tscn`, and PRES-HUD drives
`TouchControls` directly:

| Claim                                                      | Proof                                                                   |
| ---------------------------------------------------------- | ----------------------------------------------------------------------- |
| The stick is duel-relative, not a compass                  | `test_touch_moves_and_attacks_through_the_same_input_path`              |
| Hold charges, release swings exactly once                  | same                                                                    |
| An OS-canceled touch drops the attack and never swings     | same                                                                    |
| Both thumbs act in the same frames, on independent indices | `test_both_thumbs_work_at_the_same_time`                                |
| All four directional double-tap bursts, one per gesture    | `test_a_thumb_double_tap_bursts_in_the_duel_direction`                  |
| Two thumbs never steal each other's control                | `test_two_thumbs_never_steal_from_each_other`                           |
| The pause button is touch-sized and never takes focus      | `test_pause_button_is_touch_sized_named_and_never_takes_keyboard_focus` |
| Combat stays legible with every motion cue off             | `test_combat_stays_legible_with_every_motion_cue_switched_off`          |

A simulated touch event is a real touch event as far as the game is
concerned. What it is not is a real _hand_: it cannot tell you that the stick
sits under a palm, that a thumb occludes the health bar, or that the blade is
invisible at 5 inches in daylight.

## Support floor (MVP-0)

"Works on mobile" has to name something, or a failure has no verdict. These
are the targets MVP-0 claims; anything outside them may work and is not a
release blocker.

| Surface         | Floor                                                  |
| --------------- | ------------------------------------------------------ |
| Desktop         | Current Chrome, Edge, and Firefox                      |
| iOS / iPadOS    | Current Safari (the only real engine on the platform)  |
| Android         | Current Chrome                                         |
| Reference phone | A mid-range Android handset no newer than ~3 years     |
| Orientation     | Landscape. Portrait shows the rotate prompt and pauses |
| Screen          | ≥ 360 CSS px on the short edge                         |

The export is single-threaded Compatibility (WebGL2), so there is no
`SharedArrayBuffer` and no COOP/COEP requirement — which is what makes this
list short rather than a matrix of header support.

Record the actual device and browser with every pass. A floor nobody measured
against is a guess.

## Sustained performance

Measured on the **lowest** device in the floor above, in a browser, not in the
editor. Web exports render through WebGL/Compatibility, so desktop editor and
headless numbers say nothing about this.

| What                           | Target                                                |
| ------------------------------ | ----------------------------------------------------- |
| Simulation rate                | 60 Hz, unconditionally                                |
| Tick backlog                   | Never sustained at `MAX_CATCH_UP_TICKS`               |
| Render rate, combat            | ≥ 30 fps sustained through a full round               |
| Render rate, reference desktop | 60 fps sustained                                      |
| Worst frame during contact     | No visible stall at an impact, with hitstop accounted |
| Across a full match            | No downward drift between round 1 and the final round |

The split matters: frame rate and tick rate are different promises. The
simulation is fixed-step and authoritative, so a phone that renders at 34 fps
is still playing the same duel as a desktop at 60 — but a phone that cannot
_keep up_ with 60 Hz of simulation starts consuming catch-up ticks, and that
is a correctness problem wearing a performance costume. Watch the backlog, not
just the frame counter.

A full match, not a benchmark scene: thermal throttling and a growing event
log only show up over time, which is the entire reason this is a sustained
test rather than a spot reading.

## Setup

Serve the staged build over the network, not over a cable, so the measured
load is the one players get:

```bash
pnpm game:export:web && pnpm game:stage:web
pnpm dev:web     # then open http://<your-lan-ip>:3000/play on the phone
```

Test in landscape. Portrait is expected to show the rotate prompt and pause
the clock; confirm that once and move on.

## Two-thumb parity

1. Left thumb on the stick, right thumb in the attack zone, **both down**.
   Walk a full circle while holding a charge. The charge must not drop and the
   walk must not stall.
2. Release the attack while still walking. One swing, in the direction the
   blade was already travelling.
3. Press attack with the left thumb and steer with the right. Nothing in the
   layout may be handed; the zones are regions, not buttons for a specific hand.
4. Hold the attack and lift the stick thumb entirely. The charge survives.
5. Three fingers down at once — an accidental palm. No swing, no dash.

## Directional deflection bursts

For each of forward, back, left, and right: push, rest, push again. Each must
dash once, in the direction you pushed **relative to the opponent**, not up the
screen.

Then prove the negatives, which is where a gesture recognizer actually fails:

- Push and hold the same direction for two seconds. A walk, never a dash.
- Push, rest, then push a _different_ direction. No dash.
- Push, wait past the window, push again. No dash.
- Drag the thumb from forward around to back without resting. No dash.

## Touch cancellation

- Swipe up to the notification shade mid-charge. The charge drops; no swing.
- Take a call, or lock and unlock the screen, mid-charge. Same.
- Drag a finger off the bottom edge of the screen while charging. Same.
- Background the browser tab and return. Paused, no swing, and the clock has
  not fast-forwarded.

## Readability at arm's length

Judged on the phone, in daylight if possible, with the default settings:

1. Both blades are findable at a glance, at every blade angle, including when
   the two overlap.
2. The thicker part of a ribbon reads as the dangerous part without being
   explained.
3. The sweet-region rib is distinguishable from the ribbon it sits on.
4. A wind-back reads as a wind-back — the blade visibly travelling backwards —
   and not as a recovery.
5. Health, round, and clock are readable without looking away from the blades.
6. No thumb occludes anything in the priority order above decorative effects.
7. Repeat 1–4 with **Blade trail: Off** and **Sweet spot emphasis: Off**. The
   fight must still be winnable; that is what makes those settings supported
   rather than a handicap.
8. Repeat with **Screen shake: Off** and **Reduced motion: On**.

## Recording a pass

Note the device, OS, browser, and build, and which numbered items failed. An
unqualified "mobile works" is not a result — the items are numbered so a
failure can be named.
