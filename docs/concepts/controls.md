# Controls

> See also: [spec/invariants.md](../../spec/invariants.md) — CMD-001, MOVE-001, MOVE-002, SIDE-001, COMBAT-001
> See also: [docs/concepts/ux.md](./ux.md), [docs/concepts/combat.md](./combat.md)
> Source: `game/project.godot` `[input]`, `game/src/application/input/human_input_state.gd`, `game/src/application/app/screens/match_screen.gd`, `game/src/presentation/input/touch_controls.gd`

Two verbs on every device. All sources merge into one `HumanInputState`, consumed once per tick into a `PlayerCommand`. Action names come only from `InputActions` (`game/src/application/input/input_actions.gd`); APP-SHELL proves each one exists in the InputMap.

| Verb          | Desktop                        | Touch                                              |
| ------------- | ------------------------------ | -------------------------------------------------- |
| Move          | WASD or arrows (physical keys) | Floating joystick: anywhere in the lower-left zone |
| Burst         | Double-tap a move direction    | Double-deflect the joystick in one direction       |
| Attack        | Left mouse or Space            | Lower-right zone; hold to charge                   |
| Pause         | Esc or the HUD pause button    | HUD pause button                                   |
| Debug overlay | F3 (debug builds only)         | —                                                  |

## Semantics

- One logical attack button: held while any source holds it; press/release edges accumulate until the next tick, so a sub-frame tap still counts.
- Touch moves override keys while a thumb is down. Fingers are tracked by index; two thumbs never steal from each other.
- Cancel without attacking: OS-canceled touches, pause, focus loss, and the rotate prompt call `cancel_all()` → `attack_cancel` edge (CMD-001).
- The HUD pause button is never keyboard-focusable, so Space always attacks. GUI focus is released when a duel starts and on resume.
- Touches over GUI exclusions (the pause button) belong to the GUI; `emulate_mouse_from_touch=false`, and Godot 4.7 `BaseButton` handles `ScreenTouch` natively.
- Whichever end of the arena you are given, you are always at the bottom of your own screen (SIDE-001). The world does not turn; only your camera does, so W is always up the screen and D is always right — for both sides.
- You always face your opponent (tracking), and footwork is relative to them, not to the arena (MOVE-001). W closes the measure, S retreats, A and D orbit. A duel is fought along the line between two people, so that is the axis the controls mean; world-axis movement would make the same key advance, retreat, or sidestep depending on where the pair had drifted.
- The axis is the opponent's **bearing**, not your body facing — a torso turning through recovery must not drag your footwork with it. At zero separation the last meaningful bearing is reused, so movement stays continuous instead of snapping.
- Every controller speaks this same language. The CPU reasons geometrically and then expresses its step in the axis it _believes_ the opponent lies on, so stale perception shows up as a slightly misaimed step rather than privileged information.
- The attack buffer is three ticks (50 ms). Deliberately short: a longer one fires an attack you have already mentally abandoned.
- A double tap in one duel direction buys a burst: a lunge forward, a leap back, or a hard slide-step sideways (MOVE-002). The two dashes along the line between you are stronger than the lateral step, because the whole body drives them. There is no stamina bar and no cooldown — the limits are physical. The intent has to come genuinely to **rest** between the two taps, so holding a direction and then tapping it never dashes, and a thumb steering continuously around the stick never earns one it did not ask for.
- A burst commits to the heading it launched in and will not bend, so a lunge cannot chase an opponent who circles away. It _adds_ to your footwork rather than replacing it, so you keep your feet and can lean out of a dash while it carries you — reacting faster must never cost you anything. Bursting during a committed swing is exactly as sluggish as any other repositioning (PHYS-003): a dash is never an escape from a swing you already paid for.
