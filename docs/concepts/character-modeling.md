# Character modeling

> See also: [character-art.md](./character-art.md) — the blockout that ships today, [docs/reference/assets.md](../reference/assets.md) — export and Godot import
> Source: `tools/character_modeling/`

Three contracts stay separate. The modeling pose is how a body is judged. The shape is the head, torso, limbs, hands, and feet, with no costume on them. The game rig is `WolfRig`: bone names, rest transforms, grips, and combat clips. A clearer modeling pose does not move those bones. A mesh made in the modeling pose is fitted to the rig later, as its own step, and checked against the grip and the clips.

The blockout in `wolf.character.json` still ships. This module does not export a GLB and does not skin a fighter. `build_wolf.py` remains the blockout builder until a gameplay capture accepts an authored body. A study surface is judged by its silhouette and by whether the chest, waist, pelvis, and limbs actually meet. Closing that study with a remesh does not make the remesh the art direction (ART-STYLE-001).

## Head measurements

The shipping head stays until a gameplay capture accepts a replacement. The study keeps variant A as that head, unchanged. B and C are disposable comparisons on the same heroic body. They do not write `wolf.character.json` or the rig.

The head is two surfaces. The cranium is the volume: temples, crown, occiput, and the fit on the neck. The face is a shallow shell on the front of that volume: two flat cheek planes and the center edge where they meet. Flattening the shell must not shrink the skull. Rear depth is its own control.

Record these from the mesh, in metres, Z up and −Y forward:

- Height, width, and depth, and depth divided by width. A thin side profile is a low depth-to-width number. The study range for a fuller skull is about 0.24–0.27 m of depth on the current cheek width. That range is a test, not a shipped measurement.
- Temple width and crown width. A crown much narrower than the cheeks, with no rear skull, reads as a cap.
- Occipital depth: how far the back of the skull sits behind the neck.
- Cheek-plane angle, plane-fit error on the flat region only, and how far the center edge sits forward. The edge stays. An almost-flat shell is a smaller angle, not a deleted edge.
- Left/right asymmetry, connected components, boundary edges, and non-manifold edges.

The body profile from the last pass is the control: underarm half-width rises from the waist into the chest, shoulder span stays, and the head bone stays at 1.505 with its tail at 1.80. A head variant does not reopen those. A render is not an acceptance.

## Pose

The modeling pose is `relaxed-a-pose`.

- Up is +Z. Forward is −Y. Left is +X. The mirror plane is YZ. The floor is z = 0. The same frame as the Blender study.
- Feet flat and parallel. Knees straight. Legs apart by the rig's hip width, so the inner leg can be seen.
- Torso upright. Head faces forward, with no tilt.
- Arms drop 35° from horizontal, in the coronal plane. Elbows are straight. Both sides match.
- No weapon and no clothing in the proportion views.

35° is the middle of the usual 30–45° drop from a T-pose. A T-pose stays available as a rigging reference. It is not the pose used to compare silhouettes. The production rest pose stays the combat stance the clips were authored on.

Segment lengths used to place the preview come from Wolf's stations. The preview does not write them back.

## Shape

A profile is JSON (`riposte.character_model`, version 1). Each slider has a minimum, a default, and a maximum. The stored value is the thing it means — a width in head-widths, a ratio, a multiplier — not a vertex and not a bone coordinate. The same profile resolves to the same numbers every time.

Widths are multiples of the accepted cheek width, 0.263 m (`radius` 0.1125 × 1.17, both sides). Head width 1 is that head. Depth of the accepted head stays put unless a slider that owns depth says otherwise. `head_width` does not change depth.

| Slider                                            | Group | First panel | Range                                     | Default |
| ------------------------------------------------- | ----- | ----------- | ----------------------------------------- | ------- |
| Shoulder breadth                                  | Torso | yes         | 1.80–3.20 head widths, deltoid to deltoid | 3.00    |
| Chest mass                                        | Torso | yes         | 1.50–2.10                                 | 1.52    |
| Chest depth                                       | Torso | yes         | 0.50–0.75 of the front width              | 0.75    |
| Waist taper                                       | Torso | yes         | 0.72–0.94 of chest width                  | 0.88    |
| Hip breadth                                       | Torso | yes         | 1.10–2.05                                 | 1.34    |
| Thigh mass                                        | Limbs | yes         | 0.40–0.86                                 | 0.78    |
| Head width                                        | Head  | yes         | 0.90–1.15 × accepted                      | 1       |
| Crown fullness                                    | Head  | yes         | 0.94–1.12 × accepted crown                | 1       |
| Neck, arm, forearm, calf, hand, boot, cheek blend | —     | no          | bounded in `parameters.py`                | —       |

The first panel is those eight. The others are already named and checked, and stay off the panel until a preset needs them. Limb length, grip position, and floor height are not sliders. A thicker forearm does not slide the grip. A larger boot does not drop the sole through the floor.

`status` is `study` or `pending`. A file cannot mark itself `accepted`. That word waits for a person.

Current profiles:

| File                                 | What it is                                                        |
| ------------------------------------ | ----------------------------------------------------------------- |
| `profiles/male_base.json`            | Male baseline at the defaults. Pending. The same body as A.       |
| `profiles/study_wow_heroic.json`     | A. The baseline, with the accepted head.                          |
| `profiles/study_compact_chibi.json`  | B. The baseline made stockier and rounder, head a little broader. |
| `profiles/study_compact_hybrid.json` | C. The midpoint of A and B. Accepted head.                        |

## Baseline

The defaults are a height-normalized reading of one front-view human male, scaled so the figure is 1.80 m tall. WolfRig joints stay where they are. The shoulder slider is the outer deltoid span. It is wider than the 0.53 m shoulder-joint span, because the joint sits inside the muscle.

The reading, and where it is soft:

| Reading                          | Value used              | How it was taken                                                                |
| -------------------------------- | ----------------------- | ------------------------------------------------------------------------------- |
| Deltoid to deltoid               | 3.00 head widths        | Last full span before the arms leave the torso                                  |
| Chest                            | 1.52                    | Central span at the armpit                                                      |
| Waist / chest                    | 0.88                    | Even taper. The measured pinch was 0.78 and read as a sunk waist                |
| Pelvis                           | 1.34                    | The bottom of that taper, 0.88 of the chest                                     |
| Thigh, knee, calf, ankle         | 0.78, 0.56, 0.66, 0.48  | Each leg's span, legs nearly vertical                                           |
| Upper arm, elbow, forearm, wrist | 0.66, 0.50, 0.50, 0.36  | Horizontal span times the sine of the arm angle, about 44° below horizontal     |
| Chest depth                      | 0.75 of the front width | The side uses the same fraction at every station, so it follows the front taper |
| Neck                             | 0.56                    | Design choice. Hair and the beard cover the neck in the source                  |
| Hand and foot                    | 1.08 and 0.50           | Design choice. The source hand is open, and the ground shadow covers the feet   |

The accepted head is 0.263 m wide. In the source, the head is about 0.22 m at the same 1.80 m height, so this fighter's head stays larger relative to the body than the reference head. Shoulder breadth follows the body height.

A is that baseline. B adds bulk: a wider chest and hip, a straighter waist, thicker limbs, and the slightly broader head that study already had. C is the average of those two bodies and keeps the accepted head. None of the three is accepted.

No female profile yet. When the male body is accepted, the female profile gets its own shoulder, chest, waist, hip, thigh, and head values. It is not a uniform scale of the male.

There is no single `bulk` control. A control that only grows every radius at once is rejected as an unknown slider.

## What a later tool calls

```text
load_profile(path) -> resolve(profile)
```

`resolve` returns the style widths, the optional head overrides, and the cheek width in metres. A Blender study, a creator panel, and an exporter are supposed to call that and then build. They do not each invent a shoulder width.

Procedural parameters are the first backend, for studies and for sliders that the builder already understands. Shape keys stay available later for a sculpted chest or jaw, on a mesh whose topology can hold them. Hair, armour, and a scarf are separate meshes with a part id, a role, and a clearance rule. They are not a radius painted on the body. None of that exporter exists in this module yet.

## What this module will not do

- It will not move `WolfRig` to the A-pose.
- It will not replace `build_wolf.py` or `character_art.py`.
- It will not export a GLB.
- It will not open a creator UI.
- It will not decide the male default. The sheets do that, in this pose, at the gameplay camera as well as the orthographic views.

`python -c "import character_modeling; character_modeling.self_check()"` from `tools/character_modeling` checks the profiles, the ranges, the mirror, the 35° arm, and the unchanged arm length. `pnpm lint` runs it.

## Two mesh products

The study mesh and the production mesh are different things with different jobs.

- The **study mesh** explores shape. It is the fused lofts, voxel remesh, smoothing, and subdivision. A clean, connected, symmetric A-pose study mesh is not evidence that the mesh is ready to deform. Voxel topology does not follow how a body bends.
- The **production mesh** deforms and exports. Its topology is chosen for the existing rig, it goes through the existing builder to a GLB, and it is verified in Godot. It reproduces the accepted study silhouette; it never silently reinterprets it.

The study mesh is a design reference. The handoff to a deformable, imported, in-game fighter is a separate, mandatory gate (see [assets.md](../reference/assets.md)) and is proven with a small production-topology and deformation example before any wider rollout.

## Diagnostics are evidence, not a verdict

The scanner (`tools/character_modeling`, pure Python, no Blender) reads a captured study mesh and reports geometric evidence. It never changes geometry and never decides the art. Its layers stay separate on purpose: a mesh can have smooth normals and a polygonal outline, or intended facets and a clean outline.

- **Integrity** — holes, non-manifold edges, degenerate faces, components, winding.
- **Symmetry** — mirrored-vertex distance, authored-symmetric only.
- **Cross-sections** — width, depth, area, and centre at landmark stations, against each region's expected profile (never a blanket "monotonic everywhere" rule).
- **Outline corners** — on the silhouette projected from the mesh through fixed views; rendered masks are only a cross-check, because render antialiasing and shadows invent corners.
- **Crease clusters** — dihedral edges past a region threshold, grouped, with resolution persistence.
- **Offset probe** — EXPERIMENTAL dents against a smoothed copy; a ranking signal that needs corroboration, never a lone failure.

Regions (`anatomy.py`) are a confidence-weighted explanation, not ground truth. A remesh destroys loft identity, so a vertex's region is derived from landmarks; a boundary vertex reports both sides ("deltoid / upper arm") rather than false precision. Regions never generate geometry or override the loft and profile definitions.

## Regional controls, honestly

Controls (`anatomy.py` `CONTROLS`) are defined by the surface change each may make and the constraints it protects. 1.0 is the accepted default of whichever aesthetic is loaded, so every control at 1.0 reproduces the control exactly. Ranges near 0.9–1.1 are experimental until calibrated. Global `muscularity` exists but stays disabled until the default aesthetic is picked, so global scaling cannot hide which regional control produced a result.

A control is only a true control once it has a measurable, isolated effect on the actual profile. Until a phase gives it that effect, a control that merely scales a broad muscle overlay is marked `provisional`, and its value is read as a rough knob, not a contract. Do not keep adding environment switches as the permanent interface: switches isolate short-lived experiments, and once a shape is accepted its parameters are consolidated into a named, versioned profile.

## Protected measurements and the acceptance gate

A blanket sub-millimetre tolerance on a voxel-remeshed surface is precise in the report without being accurate about the mesh. Every protected measurement (`measurements.py`) declares a class, where it is measured, its tolerance, the reason, and a status:

- **Source invariant** — authored or rig value; exact, or a small source tolerance.
- **Geometry invariant** — integrity; pass or fail.
- **Shape invariant** — a measurement that defines the approved design; tolerance matches the measurement's resolution (a face landmark on the fine skull loft can hold a millimetre; a shoulder span on the 5.5 mm remesh cannot claim better than roughly one voxel).
- **Anatomy target** — a range plus visual review, not an exact value.
- **Heuristic** — a scanner signal; a review flag until calibrated.

Only the hard classes (source, geometry, shape) can fail a candidate. Each phase declares which hard invariant it is allowed to change; every other stays fixed.

Acceptance is a four-part gate, not a single score:

1. **Integrity** — the required mesh checks pass.
2. **Regression** — no unexplained new high-severity hard finding against the frozen control; protected measurements within their justified tolerances.
3. **Visual review** — the changed region reads right in the fixed views, the gameplay camera, and more than one lighting angle.
4. **Scope** — unchanged regions and the control reproduce as expected.

A phase meant to remove an existing defect must also improve that defect: the back phase cannot pass merely by adding no new findings; the back must acquire the intended relief and taper. A better score can still look worse — the scanner finds and verifies, the human accepts.

Thresholds (`regions.py`) are each labelled `calibrated` (checked against known-good and known-bad captures), `provisional` (a defensible starting value), or `advisory` (evidence only). The control is a regression baseline, not an oracle: its existing findings are not a to-do list, and thresholds are never tuned just to make it green.

## Three scan loops

- **Fast iteration** — generator measurements, selected views, cheap section and outline checks, offset probe skipped. Catches obvious regressions while tuning.
- **Phase gate** — full A/B/C builds, the complete scan, the control diff, and the fixed-view sheet. Decides whether a change is ready to accept.
- **Release gate** — full scan at final resolution, reproduction check, rig and animation checks, GLB import, and game tests. Proves the accepted result is safe to integrate.

A partial scan is never quietly treated as a full pass.
