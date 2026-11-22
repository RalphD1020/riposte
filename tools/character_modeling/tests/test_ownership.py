"""CHARACTER-OWNERSHIP-001 / CHARACTER-RELEASE-001: foundation, identity and skin each own their
fields; a foundation change reaches every character on it, an identity change every skin of that
character, a skin change that skin alone; published revisions are immutable and reproducible."""
import copy
import json
import unittest
from pathlib import Path

from character_modeling import asset_library, ownership, physique

BLENDER = Path(__file__).resolve().parents[3] / "art-src" / "blender"
WOLF = BLENDER / "characters" / "wolf" / "wolf.assembly.json"
APPROVAL = {"date": "2026-11-09", "by": "person", "evidence": "iteration evidence: fixture"}


def wolf():
    """Wolf's canonical manifest, his worn definitions and his snapshot."""
    return ownership.load(WOLF)


def snap_of(character, definitions, foundation):
    """A snapshot as `ownership.load` takes it (the character's shared skin swatches included)."""
    return ownership.snapshot(character, definitions, foundation, ownership.swatches_of(character))


def second(character, definitions, foundation, cid="character.fixture_b"):
    """Another character on Wolf's foundation: his manifest under another id, wearing only Ranger."""
    other = copy.deepcopy(character)
    other["id"] = cid
    other["outfits"] = {"ranger": copy.deepcopy(character["outfits"]["ranger"])}
    other["art"]["outfits"] = {"ranger": copy.deepcopy(character["art"]["outfits"]["ranger"])}
    return other, snap_of(other, definitions, foundation)


def family():
    """Wolf and a second character on the active foundation, and a third on another family."""
    character, definitions, snap = wolf()
    other, other_snap = second(character, definitions, snap["foundation"])
    unrelated = dict(snap["foundation"], id="character.female_base.foundation", sha256="f" * 16)
    third, third_snap = second(character, definitions, unrelated, "character.fixture_c")
    return {"character": character, "definitions": definitions,
            "snapshots": {snap["character"]: snap, other["id"]: other_snap, third["id"]: third_snap}}


def affected(report):
    return sorted("%s/%s" % (row["character"], row["skin"]) for row in report["affected"])


class Classification(unittest.TestCase):
    def test_every_field_has_one_owner(self):
        # ARRANGE / ACT / ASSERT: representative fields of each owner resolve to it.
        cases = {
            "foundation.definition": (ownership.FOUNDATION, ownership.REF),
            "skeleton.contract_sha256": (ownership.FOUNDATION, ownership.RIG),
            "foundation.body.muscularity": (ownership.IDENTITY, ownership.PHYSIQUE),
            "physique.mass_kg": (ownership.IDENTITY, ownership.PHYSIQUE),
            "foundation.face_refine.Brow": (ownership.IDENTITY, ownership.HEAD),
            "identity.head.archetype": (ownership.IDENTITY, ownership.HEAD),
            "identity.palette.hair": (ownership.IDENTITY, ownership.PIGMENT),
            "identity.palette.iris": (ownership.IDENTITY, ownership.PIGMENT),
            "art.style.geometry": (ownership.IDENTITY, ownership.DIRECTION),
            "outfits.ranger.palette.leather": (ownership.SKIN, "ranger"),
            "art.outfits.training.hair": (ownership.SKIN, "training"),
            "weapons": (ownership.EQUIPMENT, None),
            "budget.max_triangles": (ownership.DERIVED, None),
        }
        for path, owner in cases.items():
            self.assertEqual(ownership.classify(path), owner, path)

    def test_an_undeclared_field_has_no_owner(self):
        # PERTURB: a field outside the contract, a part its block does not declare, a skin
        # field without its outfit. ASSERT: classification refuses rather than guesses.
        for path in ("eye_override", "identity.skull", "foundation.topology", "outfits"):
            with self.assertRaises(ValueError, msg=path):
                ownership.classify(path)


class Contract(unittest.TestCase):
    def test_wolf_holds_the_contract(self):
        # ARRANGE: the canonical manifest and what it wears. ACT / ASSERT: no violations.
        character, definitions, _ = wolf()
        self.assertEqual(ownership.problems(character, definitions), [])

    def test_a_skin_cannot_override_the_identity_or_reach_past_its_fields(self):
        character, definitions, _ = wolf()
        cases = {
            "colours the identity material iris": lambda c: c["outfits"]["ranger"]["palette"].update(iris={"srgb": [1, 0, 0]}),
            "not one of the character's costume slots": lambda c: c["outfits"]["ranger"]["palette"].update(glow={"srgb": [1, 1, 1]}),
            "outfit ranger.skull is not a skin field": lambda c: c["outfits"]["ranger"].update(skull={"jaw": 2}),
            "identity.eye_override is not a field": lambda c: c["identity"].update(eye_override={}),
            "override is not a field any owner declares": lambda c: c.update(override={"identity.face": {}}),
            "candidate's staging key": lambda c: c.update(garment_library="garments"),
        }
        for expected, perturb in cases.items():
            changed = copy.deepcopy(character)
            perturb(changed)
            found = ownership.problems(changed, definitions)
            self.assertTrue(any(expected in p for p in found), (expected, found))

    def test_a_candidate_may_stage_its_own_garment_library(self):
        character, definitions, _ = wolf()
        staged = dict(copy.deepcopy(character), garment_library="garments")
        self.assertEqual(ownership.problems(staged, definitions, canonical=False), [])

    def test_worn_assets_keep_their_owners(self):
        character, definitions, _ = wolf()
        beard = {"id": "fixture_beard", "type": "facial_hair", "materials": ["hair"]}
        belt = dict(definitions["wolf_ranger_belt"], materials=["leather", "skin"])
        hair = dict(definitions["wolf_hair_training"], id="wolf_hair_extra")
        changed = copy.deepcopy(character)
        changed["outfits"]["ranger"]["garments"] += ["fixture_beard", "wolf_hair_extra"]
        changed["foundation"]["facial_hair"] = ["wolf_ranger_belt"]
        found = ownership.problems(changed, dict(definitions, fixture_beard=beard, wolf_ranger_belt=belt, wolf_hair_extra=hair))
        for expected in ("wears facial hair fixture_beard, which is identity", "wolf_ranger_belt in skin ranger colours ['skin']",
                         "wears two hairstyles", "foundation.facial_hair names wolf_ranger_belt, which is not facial hair"):
            self.assertTrue(any(expected in p for p in found), (expected, found))

    def test_hairstyles_take_the_identity_hair_pigment(self):
        # ARRANGE: Wolf's hairstyles name only the hair slot. ASSERT: allowed, and a skin may
        # not recolour it (hair pigment is identity).
        character, definitions, _ = wolf()
        self.assertEqual({tuple(definitions[g]["materials"]) for g in ("wolf_hair_ranger", "wolf_hair_training")}, {("hair",)})
        changed = copy.deepcopy(character)
        changed["outfits"]["training"]["palette"]["hair"] = {"srgb": [0.5, 0.2, 0.1]}
        self.assertTrue(any("colours the identity material hair" in p for p in ownership.problems(changed, definitions)))

    def test_the_v1_physique_block_follows_the_identity_body(self):
        character, definitions, _ = wolf()
        changed = copy.deepcopy(character)
        changed["foundation"]["body"]["muscularity"] = 1.2
        found = ownership.problems(changed, definitions)
        self.assertTrue(any("physique.mass_kg 80.0 is not the identity body's" in p for p in found), found)
        changed["physique"]["height_m"] = 1.9
        self.assertTrue(any("physique.height_m 1.9" in p for p in ownership.problems(changed, definitions)))

    def test_the_combat_physique_is_the_identity_body(self):
        # ASSERT: the committed physique file is resolved from Wolf's identity body, not the
        # shared foundation profile, and is current.
        character, _, _ = wolf()
        self.assertEqual(physique._body_of("wolf/wolf.assembly.json"), character["foundation"]["body"])
        self.assertEqual(physique.physique_drift(), [])


class Isolation(unittest.TestCase):
    def setUp(self):
        self.f = family()
        self.wolf_id = "character.wolf"

    def edited(self, perturb, definitions=None):
        """The family after `perturb(wolf manifest)` (and optionally other definitions)."""
        changed = copy.deepcopy(self.f["character"])
        perturb(changed)
        snaps = dict(self.f["snapshots"])
        snaps[self.wolf_id] = snap_of(changed, definitions or self.f["definitions"], snaps[self.wolf_id]["foundation"])
        return snaps

    def test_a_foundation_revision_reaches_every_character_on_it_and_no_other(self):
        before = self.f["snapshots"]
        after = {cid: dict(s, foundation=dict(s["foundation"], sha256="0" * 16))
                 if s["foundation"]["id"] == "character.male_base.foundation" else s for cid, s in before.items()}
        report = ownership.impact(before, after)
        self.assertEqual(affected(report), ["character.fixture_b/ranger", "character.wolf/bare",
                                            "character.wolf/ranger", "character.wolf/training"])
        self.assertEqual(report["unaffected"], ["character.fixture_c/ranger"])
        self.assertEqual(ownership.scope_of(report), ownership.FOUNDATION)
        self.assertTrue(all("topology" in row["validations"] for row in report["affected"]))

    def test_a_rig_change_requires_skeleton_and_animation_validation(self):
        before = self.f["snapshots"]
        after = dict(before)
        after[self.wolf_id] = dict(before[self.wolf_id], rig="1" * 64)
        rows = ownership.impact(before, after)["affected"]
        self.assertEqual({r["skin"] for r in rows}, {"bare", "ranger", "training"})
        self.assertTrue(all({"skeleton", "animation", "weapon_handling"} <= set(r["validations"]) for r in rows))

    def test_a_physique_edit_rebuilds_every_wolf_skin_and_asks_for_physics(self):
        before = self.f["snapshots"]
        after = self.edited(lambda c: (c["foundation"]["body"].update(muscularity=1.1), c["physique"].update(mass_kg=81.0)))
        report = ownership.impact(before, after)
        self.assertEqual(affected(report), ["character.wolf/bare", "character.wolf/ranger", "character.wolf/training"])
        self.assertEqual(report["unaffected"], ["character.fixture_b/ranger", "character.fixture_c/ranger"])
        self.assertTrue(all(r["causes"] == [ownership.PHYSIQUE] and "physics" in r["validations"] for r in report["affected"]))
        self.assertEqual(after[self.wolf_id]["skins"], before[self.wolf_id]["skins"])

    def test_a_pigment_edit_reaches_both_hairstyles_without_touching_their_geometry(self):
        before = self.f["snapshots"]
        after = self.edited(lambda c: c["identity"]["palette"]["hair"].update(srgb=[0.3, 0.12, 0.06]))
        report = ownership.impact(before, after)
        self.assertEqual(affected(report), ["character.wolf/bare", "character.wolf/ranger", "character.wolf/training"])
        for row in report["affected"]:
            self.assertEqual(row["causes"], [ownership.PIGMENT])
            self.assertNotIn("physics", row["validations"])
        self.assertEqual(after[self.wolf_id]["skins"], before[self.wolf_id]["skins"])
        self.assertEqual(ownership.scope_of(report), ownership.IDENTITY)

    def test_a_face_edit_is_identity_and_checks_hair_and_scarf_fit(self):
        before = self.f["snapshots"]
        after = self.edited(lambda c: c["foundation"]["face_refine"]["Brow"].update(width=0.38))
        rows = ownership.impact(before, after)["affected"]
        self.assertEqual({r["skin"] for r in rows}, {"bare", "ranger", "training"})
        self.assertTrue(all(r["causes"] == [ownership.HEAD] and {"hair_fit", "scarf_fit"} <= set(r["validations"]) for r in rows))

    def test_a_ranger_edit_touches_ranger_alone(self):
        before = self.f["snapshots"]
        definitions = copy.deepcopy(self.f["definitions"])
        definitions["wolf_ranger_belt"]["notes"] = "more detail on the buckle"
        after = self.edited(lambda c: None, definitions)
        report = ownership.impact(before, after)
        self.assertEqual(affected(report), ["character.wolf/ranger"])
        self.assertEqual(report["affected"][0]["causes"], [ownership.SKIN])
        self.assertIn("character.wolf/training", report["unaffected"])
        self.assertEqual(after[self.wolf_id]["identity"], before[self.wolf_id]["identity"])
        self.assertEqual(ownership.scope_of(report), ownership.SKIN)

    def test_a_skin_palette_edit_touches_that_skin_alone(self):
        before = self.f["snapshots"]
        after = self.edited(lambda c: c["outfits"]["training"]["palette"]["scarf"].update(roughness=0.8))
        self.assertEqual(affected(ownership.impact(before, after)), ["character.wolf/training"])

    def test_a_shared_definition_reaches_every_skin_that_wears_it(self):
        # ARRANGE: Training wears Ranger's belt too. PERTURB: the belt changes. ASSERT: both.
        character = copy.deepcopy(self.f["character"])
        character["outfits"]["training"]["garments"].append("wolf_ranger_belt")
        snap = snap_of(character, self.f["definitions"], self.f["snapshots"][self.wolf_id]["foundation"])
        definitions = copy.deepcopy(self.f["definitions"])
        definitions["wolf_ranger_belt"]["layer"] = definitions["wolf_ranger_belt"].get("layer", 1) + 1
        moved = snap_of(character, definitions, snap["foundation"])
        self.assertEqual(affected(ownership.impact({self.wolf_id: snap}, {self.wolf_id: moved})),
                         ["character.wolf/ranger", "character.wolf/training"])

    def test_an_unchanged_family_is_unaffected_and_membership_changes_are_reported(self):
        before = self.f["snapshots"]
        report = ownership.impact(before, before)
        self.assertEqual(report["affected"], [])
        self.assertIsNone(ownership.scope_of(report))
        fewer = {k: v for k, v in before.items() if k != "character.fixture_c"}
        report = ownership.impact(fewer, before)
        self.assertEqual(report["added"], ["character.fixture_c"])
        self.assertEqual(ownership.impact(before, fewer)["removed"], ["character.fixture_c"])


class Releases(unittest.TestCase):
    def setUp(self):
        self.character, self.definitions, self.snap = wolf()
        self.releases = ownership.new_releases(self.snap, APPROVAL)

    def snapshot(self, perturb, definitions=None):
        changed = copy.deepcopy(self.character)
        perturb(changed)
        return snap_of(changed, definitions or self.definitions, self.snap["foundation"])

    def test_wolf_reproduces_his_published_revisions(self):
        # ARRANGE: the committed release record. ACT: today's canonical sources. ASSERT: every
        # owner is clean, pinned to the active foundation, and v001 names all three skins.
        record = json.loads(ownership.releases_path(WOLF).read_text(encoding="utf-8"))
        self.assertEqual(ownership.release_problems(self.snap, record), [])
        self.assertEqual(record["identity"]["versions"]["v001"]["skins"], {"bare": "v001", "ranger": "v001", "training": "v001"})
        self.assertEqual(ownership.pin_problems(self.character, asset_library.current_foundation_document()), [])
        self.assertEqual(ownership.check_canonical(), [])

    def test_a_first_release_publishes_the_identity_with_every_skin(self):
        self.assertEqual(self.releases["identity"]["current"], "v001")
        self.assertEqual({n: e["current"] for n, e in self.releases["skins"].items()}, {"bare": "v001", "ranger": "v001", "training": "v001"})
        self.assertEqual(ownership.status(self.snap, self.releases)["identity"], ownership.CLEAN)

    def test_a_published_identity_is_an_art_reference_not_a_shipping_asset(self):
        # ASSERT: publish produces ART_REFERENCE with no runtime pointer; an art approval can
        # never be mistaken for a validated runtime release.
        self.assertEqual(self.releases["identity"]["versions"]["v001"]["stage"], ownership.ART_REFERENCE)
        self.assertIsNone(ownership.runtime_version(self.releases))
        record = json.loads(ownership.releases_path(WOLF).read_text(encoding="utf-8"))
        self.assertIsNone(ownership.runtime_version(record), "Wolf v001 ships nothing until F8/F9/F10")
        self.assertEqual(record["identity"]["versions"]["v001"]["stage"], ownership.ART_REFERENCE)

    def test_the_committed_record_carries_durable_appearance_evidence(self):
        # Guide 2B: the record must stand alone if .reports is cleaned -- its approval carries
        # the appearance fingerprint and foundation version, not only a pointer into .reports.
        record = json.loads(ownership.releases_path(WOLF).read_text(encoding="utf-8"))
        approval = record["identity"]["versions"]["v001"]["approval"]
        self.assertEqual(approval["appearance"]["resolved_fingerprint"], "d15ee9d20b07c97d")
        self.assertEqual(approval["appearance"]["foundation_version"], "v002")
        # The content-addressed eligibility (committed-source digests) is present too.
        self.assertIn("sha256", record["identity"]["versions"]["v001"]["foundation"])

    def test_runtime_promotion_is_gated_on_f8_f9_f10_evidence(self):
        # PERTURB: promote to runtime with missing / full evidence.
        with self.assertRaisesRegex(ValueError, "f9_regression, f10_godot evidence"):
            ownership.promote_runtime(self.releases, "v001", {"f8_topology": "report"})
        with self.assertRaisesRegex(ValueError, "identity v009 was never published"):
            ownership.promote_runtime(self.releases, "v009", {k: "r" for k in ownership.RUNTIME_EVIDENCE})
        promoted = ownership.promote_runtime(self.releases, "v001", {k: "report-%s" % k for k in ownership.RUNTIME_EVIDENCE})
        self.assertEqual(ownership.runtime_version(promoted), "v001")
        self.assertEqual(promoted["identity"]["versions"]["v001"]["stage"], ownership.RUNTIME)
        self.assertIsNone(ownership.runtime_version(self.releases), "the source record is untouched")

    def test_an_unreleased_character_reports_every_owner_unreleased(self):
        state = ownership.status(self.snap, {"identity": {"current": None, "versions": {}}, "skins": {}})
        self.assertEqual(state["identity"], ownership.UNRELEASED)
        self.assertEqual(set(state["skins"].values()), {ownership.UNRELEASED})

    def test_a_skin_revision_leaves_published_versions_and_other_skins_untouched(self):
        definitions = copy.deepcopy(self.definitions)
        definitions["wolf_ranger_belt"]["notes"] = "buckle detail"
        edited = self.snapshot(lambda c: None, definitions)
        self.assertEqual(ownership.status(edited, self.releases)["skins"]["ranger"], ownership.EDITED)
        published = ownership.publish(self.releases, edited, ownership.SKIN, APPROVAL, skin="ranger")
        self.assertEqual(published["skins"]["ranger"]["current"], "v002")
        self.assertEqual(published["skins"]["ranger"]["versions"]["v001"], self.releases["skins"]["ranger"]["versions"]["v001"])
        self.assertEqual(published["skins"]["training"], self.releases["skins"]["training"])
        self.assertEqual(published["identity"], self.releases["identity"])
        self.assertEqual(self.releases["skins"]["ranger"]["current"], "v001")
        self.assertEqual(ownership.release_problems(edited, published), [])

    def test_a_skin_revision_needs_a_change_an_approval_and_a_clean_identity(self):
        cases = [
            (self.snap, APPROVAL, "ranger", "unchanged since v001"),
            (self.snap, {"date": "2026-11-09"}, "ranger", "the approval names its by"),
            (self.snap, APPROVAL, "jester", "has no skin jester"),
            (self.snapshot(lambda c: c["identity"]["palette"]["iris"].update(srgb=[0.2, 0.4, 0.2])), APPROVAL, "ranger",
             r"publish the identity \(with every skin\) instead"),
        ]
        for snap, approval, skin, expected in cases:
            with self.assertRaisesRegex(ValueError, expected):
                ownership.publish(self.releases, snap, ownership.SKIN, approval, skin=skin)

    def test_an_identity_revision_is_one_release_with_every_skin(self):
        edited = self.snapshot(lambda c: (c["identity"]["palette"]["hair"].update(srgb=[0.3, 0.12, 0.06]),
                                          c["outfits"]["ranger"]["palette"]["scarf"].update(roughness=0.8)))
        state = ownership.status(edited, self.releases)
        self.assertEqual((state["identity"], state["edited_aspects"]), (ownership.EDITED, [ownership.PIGMENT]))
        with self.assertRaisesRegex(ValueError, r"validated on every skin; missing \['training'\]"):
            ownership.publish(self.releases, edited, ownership.IDENTITY, APPROVAL, validated=["bare", "ranger"])
        published = ownership.publish(self.releases, edited, ownership.IDENTITY, APPROVAL, validated=["bare", "ranger", "training"])
        self.assertEqual(published["identity"]["current"], "v002")
        self.assertEqual(published["identity"]["versions"]["v002"]["skins"], {"bare": "v001", "ranger": "v002", "training": "v001"})
        self.assertEqual(published["skins"]["ranger"]["versions"]["v002"]["identity"], "v002")
        self.assertEqual(published["identity"]["versions"]["v001"], self.releases["identity"]["versions"]["v001"])
        self.assertEqual(ownership.release_problems(edited, published), [])

    def test_an_unchanged_identity_is_not_republished(self):
        with self.assertRaisesRegex(ValueError, "identity is unchanged since v001"):
            ownership.publish(self.releases, self.snap, ownership.IDENTITY, APPROVAL, validated=["bare", "ranger", "training"])
        with self.assertRaisesRegex(ValueError, "a foundation is a library asset"):
            ownership.publish(self.releases, self.snap, ownership.FOUNDATION, APPROVAL)

    def test_a_foundation_migration_republishes_the_identity_on_the_new_foundation(self):
        migrated = dict(self.snap, foundation=dict(self.snap["foundation"], sha256="0" * 16))
        state = ownership.status(migrated, self.releases)
        self.assertEqual((state["identity"], state["foundation"]), (ownership.CLEAN, ownership.EDITED))
        self.assertTrue(any("publish the migration" in p for p in ownership.release_problems(migrated, self.releases)))
        published = ownership.publish(self.releases, migrated, ownership.IDENTITY, APPROVAL, validated=sorted(migrated["skins"]))
        self.assertEqual(published["identity"]["versions"]["v002"]["foundation"]["sha256"], "0" * 16)
        self.assertEqual(published["identity"]["versions"]["v002"]["skins"], {"bare": "v001", "ranger": "v001", "training": "v001"})
        self.assertEqual(ownership.release_problems(migrated, published), [])

    def test_canonical_edits_are_refused_until_published(self):
        edited = self.snapshot(lambda c: c["foundation"]["body"].update(height_m=1.85))
        found = ownership.release_problems(edited, self.releases)
        self.assertTrue(any("identity is edited (physique) since v001" in p for p in found), found)
        dropped = dict(self.snap, skins={k: v for k, v in self.snap["skins"].items() if k != "bare"})
        self.assertTrue(any("skin bare was published but the character no longer has it" in p
                            for p in ownership.release_problems(dropped, self.releases)))

    def test_a_record_naming_unpublished_versions_is_refused(self):
        broken = copy.deepcopy(self.releases)
        broken["identity"]["versions"]["v001"]["skins"]["ranger"] = "v009"
        broken["skins"]["training"]["versions"]["v001"]["identity"] = "v007"
        found = ownership.release_problems(self.snap, broken)
        self.assertTrue(any("names skin ranger v009" in p for p in found))
        self.assertTrue(any("names identity v007" in p for p in found))
        self.assertEqual(ownership.release_problems(self.snap, {"schema": "other"}),
                         ["character.wolf: not its riposte.character_releases"])


class Lifecycle(unittest.TestCase):
    """The end-to-end candidate -> scoped impact -> publish flow, proving the committed active
    release references are never touched by a candidate build or a disposable publish, and a
    failed publish leaves the active pointer unchanged (guide step 4)."""

    def test_ranger_candidate_impacts_ranger_alone_and_publishes_without_touching_the_committed_record(self):
        import tempfile
        character, definitions, snap = wolf()
        committed_before = WOLF.read_text(encoding="utf-8")
        releases_before = ownership.releases_path(WOLF).read_text(encoding="utf-8")
        # ARRANGE: a Ranger-only candidate (a belt-detail change) staged beside the canonical.
        candidate = copy.deepcopy(character)
        candidate_defs = copy.deepcopy(definitions)
        candidate_defs["wolf_ranger_belt"]["notes"] = "candidate: more buckle detail"
        staged = snap_of(candidate, candidate_defs, snap["foundation"])
        # ACT 1: scoped impact is Ranger alone, and the candidate still holds the ownership contract.
        report = ownership.impact({"character.wolf": snap}, {"character.wolf": staged})
        self.assertEqual([("%s/%s" % (r["character"], r["skin"]), r["causes"]) for r in report["affected"]],
                         [("character.wolf/ranger", [ownership.SKIN])])
        self.assertIn("character.wolf/training", report["unaffected"])
        self.assertEqual(ownership.problems(candidate, candidate_defs), [])
        # ACT 2: publish the Ranger revision against a DISPOSABLE copy of the real record.
        releases = json.loads(releases_before)
        published = ownership.publish(releases, staged, ownership.SKIN, APPROVAL, skin="ranger")
        with tempfile.TemporaryDirectory() as folder:
            disposable = Path(folder) / "wolf.releases.json"
            disposable.write_text(json.dumps(published, indent=1, sort_keys=True), encoding="utf-8")
            self.assertEqual(json.loads(disposable.read_text(encoding="utf-8"))["skins"]["ranger"]["current"], "v002")
        # ASSERT: the committed manifest and release record are byte-for-byte unchanged, and the
        # active (runtime) pointer is still null -- a candidate advanced nothing shipping.
        self.assertEqual(WOLF.read_text(encoding="utf-8"), committed_before)
        self.assertEqual(ownership.releases_path(WOLF).read_text(encoding="utf-8"), releases_before)
        self.assertEqual(json.loads(releases_before)["skins"]["ranger"]["current"], "v001")
        self.assertIsNone(ownership.runtime_version(json.loads(releases_before)))

    def test_an_incomplete_identity_release_leaves_the_active_references_unchanged(self):
        character, definitions, snap = wolf()
        releases = json.loads(ownership.releases_path(WOLF).read_text(encoding="utf-8"))
        edited = snap_of(dict_merge(character, lambda c: c["identity"]["palette"]["hair"].update(srgb=[0.3, 0.1, 0.06])),
                         definitions, snap["foundation"])
        # PERTURB: an identity revision missing a skin's validation must raise and return nothing.
        with self.assertRaisesRegex(ValueError, "validated on every skin"):
            ownership.publish(releases, edited, ownership.IDENTITY, APPROVAL, validated=["bare", "ranger"])
        self.assertEqual(releases["identity"]["current"], "v001", "the active identity pointer is unchanged")


def dict_merge(character, perturb):
    changed = copy.deepcopy(character)
    perturb(changed)
    return changed


class FoundationPin(unittest.TestCase):
    """A historical pin is not an invalid pin (guide 2C): a character pinned to a known but
    superseded foundation is awaiting migration, not misconfigured; only an unknown pin fails."""

    def setUp(self):
        self.character, _, _ = wolf()
        self.active = asset_library.current_foundation_document()
        self.known = ownership.known_foundation_documents()

    def test_the_library_knows_every_foundation_version(self):
        # ASSERT: both the current (v002) and the superseded (v001) documents are known.
        names = sorted(Path(p).name for p in self.known)
        self.assertEqual(names, ["male_base.foundation.json", "male_base.foundation.v002.json"])

    def test_the_active_pin_is_clean(self):
        self.assertEqual(ownership.pin_problems(self.character, self.active, self.known), [])
        self.assertFalse(ownership.migration_pending(self.character, self.active))

    def test_a_superseded_but_known_pin_is_migration_pending_not_a_problem(self):
        pinned = copy.deepcopy(self.character)
        pinned["foundation"]["definition"] = "characters/male_base.foundation.json"  # v001, superseded
        self.assertEqual(ownership.pin_problems(pinned, self.active, self.known), [])
        self.assertTrue(ownership.migration_pending(pinned, self.active))

    def test_an_unknown_pin_is_a_hard_problem(self):
        pinned = copy.deepcopy(self.character)
        pinned["foundation"]["definition"] = "characters/male_base.foundation.v099.json"
        found = ownership.pin_problems(pinned, self.active, self.known)
        self.assertTrue(any("not a known foundation version" in p for p in found), found)

    def test_check_canonical_does_not_fail_on_the_active_character(self):
        self.assertEqual(ownership.check_canonical(), [])
        self.assertEqual(ownership.pending_migrations(), {})


class OwnershipBoundaryBehavior(unittest.TestCase):
    """Guide 2C made executable: classify, impact and the physique resolver agree on the
    effect of each kind of edit, so the `foundation.body` naming can wait."""

    def setUp(self):
        self.f = family()
        self.snaps = self.f["snapshots"]

    def edited(self, perturb):
        changed = copy.deepcopy(self.f["character"])
        perturb(changed)
        snaps = dict(self.snaps)
        snaps["character.wolf"] = snap_of(changed, self.f["definitions"], self.snaps["character.wolf"]["foundation"])
        return changed, ownership.impact(self.snaps, snaps)

    def test_wolf_height_change_is_an_identity_revision_rebuilding_both_skins_only(self):
        self.assertEqual(ownership.classify("foundation.body.height_m"), (ownership.IDENTITY, ownership.PHYSIQUE))
        _c, report = self.edited(lambda c: (c["foundation"]["body"].update(height_m=1.85), c["physique"].update(height_m=1.85, mass_kg=86.9)))
        self.assertEqual(sorted(r["skin"] for r in report["affected"]), ["bare", "ranger", "training"])
        self.assertTrue(all(r["character"] == "character.wolf" and r["causes"] == [ownership.PHYSIQUE] for r in report["affected"]))
        self.assertTrue(all("physics" in r["validations"] for r in report["affected"]))
        self.assertIn("character.fixture_b/ranger", report["unaffected"])

    def test_another_character_on_the_shared_foundation_keeps_its_own_physique(self):
        # The second character's physique is unchanged by a Wolf physique edit (own identity).
        _c, report = self.edited(lambda c: c["foundation"]["body"].update(muscularity=1.2))
        self.assertNotIn("character.fixture_b/ranger", [("%s/%s" % (r["character"], r["skin"])) for r in report["affected"]])

    def test_a_skin_color_change_touches_materials_not_geometry(self):
        self.assertEqual(ownership.classify("identity.palette.skin"), (ownership.IDENTITY, ownership.PIGMENT))
        _c, report = self.edited(lambda c: c["identity"]["palette"]["skin"].update(swatch="skin_03"))
        for r in report["affected"]:
            self.assertEqual(r["causes"], [ownership.PIGMENT])
            self.assertNotIn("physics", r["validations"])

    def test_the_resolver_reads_the_identity_body(self):
        # The combat physique resolves from foundation.body (identity-owned) and is current.
        self.assertEqual(physique._body_of("wolf/wolf.assembly.json"), self.f["character"]["foundation"]["body"])
        self.assertEqual(physique.physique_drift(), [])


class Migration(unittest.TestCase):
    def test_a_shared_revision_is_never_partially_published(self):
        f = family()
        before = f["snapshots"]
        after = {cid: dict(s, foundation=dict(s["foundation"], sha256="0" * 16)) for cid, s in before.items()}
        report = ownership.impact(before, after)
        passing = {"%s/%s" % (r["character"], r["skin"]): {"passed": True, "evidence": "board"} for r in report["affected"]}
        self.assertEqual(ownership.migration_problems(report, passing), [])
        failing = dict(passing)
        failing["character.wolf/training"] = {"passed": False, "evidence": "scarf clips the jaw"}
        failing["character.fixture_b/ranger"] = {"passed": True}
        del failing["character.wolf/bare"]
        found = ownership.migration_problems(report, failing)
        self.assertEqual(len(found), 3)
        self.assertTrue(any("character.wolf/training failed validation: scarf clips the jaw" in p for p in found))
        self.assertTrue(any("character.wolf/bare was not validated" in p for p in found))
        self.assertTrue(any("character.fixture_b/ranger passed without evidence" in p for p in found))


class Provenance(unittest.TestCase):
    def test_a_build_records_its_revisions_inputs_and_geometry(self):
        character, definitions, snap = wolf()
        releases = ownership.new_releases(snap, APPROVAL)
        meshes = {"wolf_ranger.Body": "a" * 64, "wolf_ranger.Head": "b" * 64}
        record = ownership.provenance(snap, releases, "ranger", "builder-1", meshes)
        self.assertEqual(record["inputs"]["identity"]["revision"], "v001")
        self.assertEqual(record["inputs"]["skin"], {"name": "ranger", "revision": "v001", "digest": snap["skins"]["ranger"]})
        self.assertEqual(record, ownership.provenance(snap, releases, "ranger", "builder-1", dict(meshes)))
        # PERTURB: a builder change with the same geometry, then moved geometry.
        tool = ownership.provenance(snap, releases, "ranger", "builder-2", meshes)
        self.assertNotEqual(tool["resolved_input_hash"], record["resolved_input_hash"])
        self.assertEqual(tool["geometry_hash"], record["geometry_hash"])
        moved = ownership.provenance(snap, releases, "ranger", "builder-2", dict(meshes, **{"wolf_ranger.Body": "c" * 64}))
        self.assertNotEqual(moved["geometry_hash"], tool["geometry_hash"])

    def test_a_candidate_records_no_revision_for_its_edited_owners(self):
        character, definitions, snap = wolf()
        releases = ownership.new_releases(snap, APPROVAL)
        changed = copy.deepcopy(character)
        changed["outfits"]["ranger"]["palette"]["scarf"]["roughness"] = 0.5
        staged = snap_of(changed, definitions, snap["foundation"])
        ranger = ownership.provenance(staged, releases, "ranger", "b", {})
        training = ownership.provenance(staged, releases, "training", "b", {})
        self.assertEqual((ranger["inputs"]["skin"]["revision"], training["inputs"]["skin"]["revision"]), (None, "v001"))
        self.assertIsNone(ownership.provenance(staged, None, "ranger", "b", {})["inputs"]["identity"]["revision"])

    def test_the_builder_digest_covers_the_builder_sources(self):
        self.assertEqual(ownership.builder_sha256(), ownership.builder_sha256())
        self.assertEqual(len(ownership.builder_sha256()), 16)


class Commands(unittest.TestCase):
    def test_status_and_classify_and_candidate_impact(self):
        import contextlib
        import io
        import tempfile
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(ownership.main(["classify", "identity.palette.hair"]), 0)
            self.assertEqual(ownership.main(["status"]), 0)
        self.assertIn('"scope": "identity"', out.getvalue())
        # ARRANGE: a staged candidate (a Training-only scarf change) beside the canonical one.
        candidate = json.loads(WOLF.read_text(encoding="utf-8"))
        candidate["outfits"]["training"]["palette"]["scarf"]["roughness"] = 0.8
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "wolf.assembly.json"
            path.write_text(json.dumps(candidate), encoding="utf-8")
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(ownership.main(["impact", "--manifest", str(path)]), 0)
        report = json.loads(out.getvalue())
        self.assertEqual((report["scope"], affected(report)), (ownership.SKIN, ["character.wolf/training"]))

    def test_staging_a_foundation_reports_the_family_impact(self):
        import contextlib
        import io
        superseded = BLENDER / "characters" / "male_base.foundation.json"
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(ownership.main(["status", "--foundation", str(superseded)]), 0)
        report = json.loads(out.getvalue())["impact"]
        self.assertEqual(report["scope"], ownership.FOUNDATION)
        self.assertEqual(affected(report), ["character.wolf/bare", "character.wolf/ranger", "character.wolf/training"])


if __name__ == "__main__":
    unittest.main()
