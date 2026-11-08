# The character asset library

> See also: [character-layering.md](./character-layering.md) (how layers map and cover), [docs/concepts/character-modeling.md](../concepts/character-modeling.md) (the foundation), [spec/invariants.md](../../spec/invariants.md#character-library-001) (CHARACTER-LIBRARY-001)

Riposte's character creator is asset-driven, non-destructive and data-driven. The default foundation is the canonical anatomy; a character is assembled on a resolved variant of it; every approved reusable piece is published once, as an immutable version, to one library under `art-src/blender/library/`. A creator's menus are generated from the library's shared categories and each asset's compatibility, never from per-character lists.

## The four parts

| Part | What it is | Changes how |
| --- | --- | --- |
| Default foundation | canonical anatomy, body and head generator, skeleton contract, landmarks, the bare model (`male_base.foundation.*`) | only by a new, separately reviewed revision: new files, a new library version |
| Character assembly | a resolved body variant plus identity, hair, facial hair, skin and attire (the character manifest, `appearance.resolve`) | per character; never writes the foundation |
| Asset library | approved, versioned, reusable assets with provenance and compatibility (`character_modeling.asset_library`) | promotion of a new version only |
| Creator UI (later) | menus from `asset_library.menu`: every category, the compatible current versions | never hardcoded per character |

Wolf is the first character assembled from the foundation at the 1.0 reference (1.80 m, 80 kg), not its source. His approved features become library assets another character may select without inheriting the rest of his identity.

## Three approval scopes

Not every improvement is a foundation revision. What a change touches decides what is versioned:

| Change | Versioned as | Example |
| --- | --- | --- |
| Canonical anatomy: the base body and head, a study that reshapes the reference body, the landmark contract, the skeleton contract | a foundation revision: a new foundation document (and base if it changes), a new `male_base_foundation` version | the chest candidate (`chest_fit` reshapes the 1.80 m reference's chest) |
| How the derived height and build variants are generated, leaving the reference identical | a new `male_base_variants` version (`riposte.foundation_variants`), with the lock of the variants it regenerates | the face response (`face_response`: the reference face stays byte-identical) |
| A character's identity: face refinement, eyes and brows of its own, facial hair, hair, palette, skin, attire | a new version of that character's asset only | Wolf's `face_refine`, his hairstyles |

A Wolf asset never requires a foundation or variants version. `foundation.VARIANT_KEYS` are the switches variant generation may set; the foundation document keeps them off as its canonical default (`foundation.problems` refuses one turned on there); `foundation.apply(..., variants)` sets them from the current approved variants version, which the builder reads from the library (a review copy through `RIPOSTE_VARIANTS_REVIEW`). A variant switch must leave the reference resolution identical, proven by its tests and its lock.

## Building a character

1. Resolve the approved foundation at the character's body inputs (`variation.resolve`, `foundation.apply`). Nothing is written to the foundation.
2. Take the resolved bare body and head.
3. Apply the face: the foundation's default face, or a refinement over it (`face_refine`), fitted to the resolved head.
4. Apply facial hair and the outfit's hairstyle through the appearance plan; later the approved skin and attire.
5. Run Gate A (Blender geometry and art), then Gate B / C (facial animation, skeleton and deformation) where they apply.
6. Promote each approved reusable feature to the library as a new version; record its category, origin, compatibility, coverage and approval.

The assembled character is never saved as a new base. A later character starts again from the foundation.

## Categories and origins

One schema (`asset_library.CATEGORIES`), the same for every character:

| Category | Subtypes |
| --- | --- |
| `foundation` | body, head, skeleton, landmarks, regions |
| `face` | face, eyes, brows, nose, expressions |
| `hair` | hairstyle |
| `facial_hair` | beard, moustache, sideburns, stubble |
| `skin` | tone, material |
| `attire` | top, trousers, armour, footwear, belt, accessory |
| `rigging` | fit_profile, weights, corrective |

A `riposte.garment` definition's `type` maps onto it (`hair` → hair, `facial_hair` → facial_hair, `garment` → attire). Every origin (the `default_foundation` and each character) carries every category directory with its `category.json`, empty or not, so tools can build the same menus for every character.

Category and origin are independent: the category says what an asset is; the origin says who first produced it. Origin is provenance, never ownership: Wolf originates the Ranger hairstyle, the library owns its approved versions, another character references a version, and fitting it to that character produces that character's own derived output; the library version is never changed by a use, and the referencing character takes nothing else of Wolf's. Every asset carries a stable UUID (from its id) for catalogs, which, as in Blender's asset catalogs, are independent of where files live.

## Compatibility states

Reuse is not universal compatibility. For one body configuration (its height, frame and muscularity, `asset_library.configuration_key`) an asset version is:

| State | Meaning | Offered by the creator |
| --- | --- | --- |
| `validated` | built on that configuration and visually approved there (a recorded validation: version, configuration, foundation, evidence, date) | yes |
| `compatible_by_contract` | its foundation supports the configuration (inside the foundation's envelope) and its fitting contract maps onto it, not yet visually approved there | yes, marked as such |
| `unsupported` | another foundation, or outside the envelope | never |

Validations are recorded per version (`validations.json` beside the versions, append-only); a new version earns its own. `asset_library.menu(foundation, body=..., envelope=...)` gives each asset's state and leaves unsupported ones out.

## Layout

```text
art-src/blender/library/
  library.json                                   index: categories, origins, assets, versions, current
  <origin>/<category>/category.json              every origin, every category
  <origin>/<category>/<asset id>/v<NNN>/
    asset.json                                   riposte.library_asset (read-only)
    <payload files>                              read-only byte copies
```

`asset.json` holds the stable id, `version`, `category`, `subtype`, `origin`, `status`, `approval` (date, by, evidence), `compatibility` (foundations, foundation fingerprint, skeleton, required regions), `dependencies` (asset id and version), `coverage`, `files` (payload sha256 and where they came from, repository-relative), `protected` (sources kept in place, by sha256), `sources` (builder versions), `tags`, `notes`.

**A hairstyle version pins its geometry.** A hair definition's geometry is a design variant of its builder (`wolf_hair.py`'s variant tables), named by `design.variant` (`garments.hair_variant`); the builder's own default never decides what a version builds. Definitions approved before the field (`wolf_hair_ranger` / `wolf_hair_training` v001) rebuild the variant they were approved with (`garments.HAIR_V001_VARIANTS`: Ranger D, Training E), and those variants are frozen: a refinement is a new variant and a new version. A review manifest names candidate definitions through its `garment_library`.

## Lifecycle and immutability

| State | Where it lives | Overwrites an approved asset? |
| --- | --- | --- |
| candidate | an iteration folder | never |
| reviewed | an iteration folder | never |
| approved | the library, a new version | never: promotion refuses an existing version |
| superseded | the library, kept (rollback, existing consumers) | never |
| rejected | the iteration's evidence | never |

- **Promotion is explicit:** `python -m character_modeling.asset_library promote <spec.json>`, from a spec naming the approval; never automatic because a build or a test passed. It refuses a non-approved asset, an unknown category or subtype, missing evidence, an unknown dependency, a protected source that no longer matches, an id already owned by another origin or category, and an existing version directory.
- **Protected in place:** large approved sources that stay where they are (the foundation's blend, record, lock and regions) are listed with their sha256; `verify` fails if one changes (for an approved or a superseded version: a rollback needs its sources), and the builders refuse to write them (`asset_library.refuse_overwrite` in `male_base_v2.py --foundation` and `fitting_regions.py --foundation`; a candidate lock is written beside its build, never in place). A foundation revision is a new document and a new library version.
- **One path, however it is named:** every check compares `asset_library.canonical` paths: repository-relative or absolute, `..` and symbolic links resolved, case-normalized where the file system ignores case; a path resolving outside the permitted roots (the repository) is refused for payloads, protected sources and writes.
- **Verification:** `python -m character_modeling.asset_library verify` (and the test suite) re-hashes every version's files and every protected source, and flags a missing category, an edited copy or an unlisted file.
- **Improving an approved asset** is a new candidate, its approvals, and a new version; the previous one stays.

## What is committed

| Committed | Evidence only (`.reports`, local work) |
| --- | --- |
| the library (index, categories, versions), the schemas and resolver, the builders, definitions, tests | candidate meshes and renders, review copies, promotion specs and their iteration's payload drafts, logs |
| the foundation's approved sources (protected) | experimental builds |

A binary is committed when it is an intentional approved deliverable, with its source, version and evidence traceable.

## The acceptance test

Build Wolf, then a second character, from the same foundation, and prove neither changes the foundation or inherits the other's identity (`test_foundation.Independence`, `test_asset_library.Shipped`): the foundation document is unchanged after resolving variants and layering Wolf; the reference variant keeps the approved face; a second character on the default face selects Wolf's library hairstyle and its plan contains only that, with no beard, skin or palette of Wolf's.

## In the library now (2026-11-06)

The builders read the current `male_base_foundation` version's document (`asset_library.current_foundation_document`); a superseded version's sources stay protected in place for rollback.

| Asset | Origin / category | Version | Approved |
| --- | --- | --- | --- |
| `male_base_foundation` | default_foundation / foundation (body) | v002 (v001 superseded) | v001 2026-11-02, the default bodies; v002 2026-11-06, the three-physique head and the eye's fixed white (`male_base.foundation.v002.json`); each validated on the 15 sweep configurations |
| `male_base_variants` | default_foundation / foundation (variant_generation) | v001 | 2026-11-02, face response off; validated on the sweep |
| `default_face` | default_foundation / face | v002 (v001 superseded) | v001 2026-11-01, the default eyes and brows; v002 2026-11-06, the same with the fixed white; each validated on the sweep |
| `wolf_face` | wolf / face | v001 | 2026-11-06, Wolf's `face_refine` (heavier outer lid, deeper brows) and his iris and hair colours; validated at the reference |
| `wolf_hair_ranger` | wolf / hair | v001 | 2026-10-31, Ranger D; compatible by contract on the foundation (fit checked on five builds, not yet visually approved there) |
| `wolf_hair_training` | wolf / hair | v001 | 2026-10-31, Training E; compatible by contract on the foundation |
| `wolf_skin` | wolf / skin (tone) | v001 | 2026-11-02, skin_02; validated at the reference |

Wolf is clean-shaven (his manifest names no facial hair; the layer is proven by a test fixture). His face is `wolf_face` v001, his manifest carrying the same `face_refine`; the chest smoothing is a foundation-revision candidate; the face response is a variants candidate, blocked by the iris gate at the 1.60 m lean.
