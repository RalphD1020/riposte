"""CHARACTER-LIBRARY-001: approved assets are published once per version, never overwritten;
every origin carries the same categories; the menus come from the shared schema; an approved
asset is reused by another character without its origin's identity."""
import json
import os
import shutil
import stat
import tempfile
import unittest
from pathlib import Path

from character_modeling import appearance, asset_library as lib, foundation

ROOT = Path(__file__).resolve().parents[3]
CHARACTERS = ROOT / "art-src" / "blender" / "characters"


def _writable(func, path, _info):
    os.chmod(path, stat.S_IWRITE)
    func(path)


class Scratch(unittest.TestCase):
    """A library in a temporary folder, with payload files of its own."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.root = self.dir / "library"
        self.payload = self.dir / "style.json"
        self.payload.write_text(json.dumps({"style": "a"}), encoding="utf-8")
        self.source = self.dir / "approved.blend"
        self.source.write_bytes(b"approved source")

    def tearDown(self):
        shutil.rmtree(self.dir, onerror=_writable)

    def spec(self, **overrides):
        spec = {"id": "fixture_style", "category": "hair", "subtype": "hairstyle", "origin": "fixture_hero",
                "status": "approved", "approval": {"date": "2026-11-02", "by": "the person", "evidence": "board"},
                "compatibility": {"foundations": ["character.male_base.foundation"]}, "payload": [str(self.payload)]}
        spec.update(overrides)
        return spec


class Promotion(Scratch):
    def test_promotion_publishes_immutable_versions_and_supersedes_the_previous(self):
        ## ACT: two approved versions of one asset.
        first = lib.promote(self.spec(), self.root, (self.dir,))
        self.payload.write_text(json.dumps({"style": "b"}), encoding="utf-8")
        second = lib.promote(self.spec(), self.root, (self.dir,))
        ## ASSERT: v001 and v002; v001 superseded, kept and unchanged; read-only copies.
        index = lib.index(self.root)
        self.assertEqual((first, second), ("v001", "v002"))
        self.assertEqual(index["assets"]["fixture_style"]["current"], "v002")
        self.assertEqual(index["assets"]["fixture_style"]["versions"]["v001"]["status"], "superseded")
        self.assertEqual(lib.payload("fixture_style", "style.json", "v001", self.root), {"style": "a"})
        self.assertEqual(lib.payload("fixture_style", "style.json", root=self.root), {"style": "b"})
        copy = self.root / "fixture_hero" / "hair" / "fixture_style" / "v001" / "style.json"
        self.assertFalse(os.access(copy, os.W_OK))
        self.assertEqual(lib.verify(self.root, check_protected=False, roots=(self.dir,)), [])

    def test_promotion_fails_closed(self):
        lib.promote(self.spec(), self.root, (self.dir,))
        ## PERTURB: not approved; an unknown category or subtype; no evidence; an unknown
        ## dependency; a protected source that no longer matches; a version that exists.
        cases = {
            "only an approved asset": self.spec(status="candidate"),
            "unknown category": self.spec(category="weapons"),
            "is not one of hair's": self.spec(subtype="beard"),
            "names its evidence": self.spec(approval={"date": "2026-11-02", "by": "the person"}),
            "unknown asset": self.spec(dependencies=[{"id": "nothing", "version": "v001"}]),
            "does not match its sha256": self.spec(protected={str(self.source): "0" * 64}),
            "already an asset of": self.spec(origin="other_hero"),
        }
        for reason, spec in cases.items():
            with self.assertRaisesRegex(ValueError, reason):
                lib.promote(spec, self.root, (self.dir,))
        (self.root / "fixture_hero" / "hair" / "fixture_style" / "v002").mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, "never overwritten"):
            lib.promote(self.spec(), self.root, (self.dir,))

    def test_verify_finds_a_changed_version_an_unlisted_file_and_a_source_changed_in_place(self):
        ## ARRANGE: an asset protecting a source in place.
        lib.promote(self.spec(protected={str(self.source): lib.sha256(self.source)}), self.root, (self.dir,))
        folder = self.root / "fixture_hero" / "hair" / "fixture_style" / "v001"
        ## PERTURB: the approved source overwritten, a copy edited, a stray file.
        os.chmod(self.source, stat.S_IWRITE)
        self.source.write_bytes(b"overwritten")
        os.chmod(folder / "style.json", stat.S_IWRITE)
        (folder / "style.json").write_text("{}", encoding="utf-8")
        (folder / "stray.txt").write_text("x", encoding="utf-8")
        ## ACT
        problems = " | ".join(lib.verify(self.root, roots=(self.dir,)))
        ## ASSERT
        self.assertIn("changed in place", problems)
        self.assertIn("style.json changed", problems)
        self.assertIn("stray.txt is not part of the version", problems)
        with self.assertRaises(SystemExit):
            lib.refuse_overwrite(self.source, self.root, (self.dir,))

    def test_every_origin_has_every_category_and_the_menu_lists_them_all(self):
        ## ACT: one asset promoted, one origin without assets.
        lib.promote(self.spec(), self.root, (self.dir,))
        lib.ensure_origin(self.root, "second_hero")
        menu = lib.menu("character.male_base.foundation", self.root)
        other = lib.menu("character.another_foundation", self.root)
        ## ASSERT: every origin carries every category; the menu has every category (empty
        ## included) and filters by foundation compatibility.
        for origin in ("fixture_hero", "second_hero"):
            for category in lib.CATEGORIES:
                self.assertTrue((self.root / origin / category / "category.json").exists(), (origin, category))
        self.assertEqual(set(menu), set(lib.CATEGORIES))
        self.assertEqual([a["id"] for a in menu["hair"]], ["fixture_style"])
        self.assertEqual(other["hair"], [])


class ProtectedPaths(Scratch):
    """One protected file, however it is named, is one file; nothing escapes the roots."""

    def setUp(self):
        super().setUp()
        self.roots = (self.dir,)
        (self.dir / "sub").mkdir()
        lib.promote(self.spec(protected={str(self.source): lib.sha256(self.source)}), self.root, self.roots)

    def refused(self, path):
        with self.assertRaises(SystemExit):
            lib.refuse_overwrite(path, self.root, self.roots)

    def test_every_spelling_of_the_protected_file_is_refused(self):
        ## ACT / ASSERT: absolute, through `..`, mixed separators and (where the file system
        ## ignores case) another case all name the protected source.
        self.refused(self.source)
        self.refused(str(self.source))
        self.refused(self.dir / "sub" / ".." / "approved.blend")
        self.refused(str(self.dir) + os.sep + "sub" + os.sep + os.pardir + os.sep + "approved.blend")
        if os.path.normcase("A") == os.path.normcase("a"):
            self.refused(str(self.source).upper())
        ## PERTURB: an unprotected neighbour is writable.
        lib.refuse_overwrite(self.dir / "other.blend", self.root, self.roots)

    def test_a_link_to_the_protected_file_is_refused(self):
        ## ARRANGE: a symbolic link to the protected source (skipped where links need rights).
        link = self.dir / "sub" / "link.blend"
        try:
            os.symlink(self.source, link)
        except (OSError, NotImplementedError):
            self.skipTest("symbolic links are not available here")
        ## ACT / ASSERT
        self.refused(link)

    def test_a_path_outside_the_permitted_roots_is_refused(self):
        ## PERTURB: a path that resolves outside the roots, directly or through `..`.
        outside = Path(tempfile.gettempdir()).resolve().parent / "outside.blend"
        self.refused(outside)
        self.refused(self.dir / ".." / ".." / "outside.blend")
        with self.assertRaisesRegex(ValueError, "outside the permitted roots"):
            lib.canonical(outside, self.roots)
        ## A promotion naming a payload outside the roots fails closed.
        with self.assertRaisesRegex(ValueError, "outside the permitted roots"):
            lib.promote(self.spec(id="fixture_two", payload=[str(outside)]), self.root, self.roots)

    def test_repository_relative_and_absolute_names_of_a_shipped_source_agree(self):
        ## ACT / ASSERT: the foundation document, relative, absolute and through `..`.
        rel = "art-src/blender/characters/male_base.foundation.json"
        for path in (rel, ROOT / rel, ROOT / "art-src" / "blender" / ".." / "blender" / "characters" / "male_base.foundation.json"):
            with self.assertRaises(SystemExit):
                lib.refuse_overwrite(path)
        self.assertEqual(lib.canonical(rel), lib.canonical(ROOT / rel))


class Compatibility(Scratch):
    def test_validated_by_contract_and_unsupported_are_distinct(self):
        ## ARRANGE: an asset for the foundation, validated on one configuration.
        lib.promote(self.spec(), self.root, (self.dir,))
        envelope = {"height_m": (1.6, 2.0), "frame_build": (0.85, 1.15), "muscularity": (0.8, 1.25)}
        reference = {"height_m": 1.8, "frame_build": 1.0, "muscularity": 1.0}
        tall = {"height_m": 2.0, "frame_build": 1.0, "muscularity": 1.0}
        giant = {"height_m": 2.4, "frame_build": 1.0, "muscularity": 1.0}
        lib.record_validation("fixture_style", "v001", reference, "character.male_base.foundation", "board", "2026-11-02", self.root)
        state = lambda body, f="character.male_base.foundation": lib.compatibility("fixture_style", f, body, envelope, root=self.root)
        ## ACT / ASSERT
        self.assertEqual(state(reference), lib.VALIDATED)
        self.assertEqual(state(tall), lib.BY_CONTRACT)
        self.assertEqual(state(giant), lib.UNSUPPORTED)
        self.assertEqual(state(reference, "character.other"), lib.UNSUPPORTED)
        ## The menu shows the state and never offers an unsupported asset.
        offered = lib.menu("character.male_base.foundation", self.root, reference, envelope)
        self.assertEqual(offered["hair"][0]["compatibility"], lib.VALIDATED)
        self.assertEqual(lib.menu("character.male_base.foundation", self.root, giant, envelope)["hair"], [])
        ## PERTURB: a new version is not validated by its predecessor's evidence.
        lib.promote(self.spec(), self.root, (self.dir,))
        self.assertEqual(state(reference), lib.BY_CONTRACT)
        ## A validation names its evidence, a known version and a supported foundation.
        with self.assertRaises(ValueError):
            lib.record_validation("fixture_style", "v009", reference, "character.male_base.foundation", "board", "2026-11-02", self.root)
        with self.assertRaises(ValueError):
            lib.record_validation("fixture_style", "v001", reference, "character.other", "board", "2026-11-02", self.root)
        with self.assertRaises(ValueError):
            lib.record_validation("fixture_style", "v001", reference, "character.male_base.foundation", "", "2026-11-02", self.root)

    def test_every_asset_has_its_stable_uuid(self):
        lib.promote(self.spec(), self.root, (self.dir,))
        self.assertEqual(lib.index(self.root)["assets"]["fixture_style"]["uuid"], lib.asset_uuid("fixture_style"))
        self.assertEqual(lib.asset_uuid("fixture_style"), lib.asset_uuid("fixture_style"))


class Shipped(unittest.TestCase):
    def test_the_committed_library_verifies(self):
        ## ACT / ASSERT: every approved version intact, every protected source unchanged.
        self.assertEqual(lib.verify(), [])

    def test_the_foundation_sources_are_protected_in_place(self):
        ## ASSERT: every foundation version's blend and documents (the current and the one it
        ## supersedes, kept for rollback) cannot be overwritten by the builders.
        protected = lib.protected_paths()
        for stem in ("male_base.foundation", "male_base.foundation.v002"):
            for suffix in (".json", ".blend", ".lock.json", ".regions.json", ".record.json"):
                self.assertIn(lib.canonical("art-src/blender/characters/" + stem + suffix), protected)
                with self.assertRaises(SystemExit):
                    lib.refuse_overwrite(CHARACTERS / (stem + suffix))

    def test_the_builders_read_the_current_foundation_version(self):
        ## ACT: the document the builders read.
        current = lib.current_foundation_document()
        ## ASSERT: the current version's document; the superseded one kept in place.
        entry = lib.index()["assets"][lib.FOUNDATION_ASSET]
        self.assertEqual(entry["current"], "v002")
        self.assertEqual(entry["versions"]["v001"]["status"], "superseded")
        self.assertEqual(current, lib.canonical(CHARACTERS / "male_base.foundation.v002.json"))
        self.assertEqual(foundation.load(current)["status"], "approved")
        self.assertEqual(foundation.problems(foundation.load(CHARACTERS / "male_base.foundation.json")), [])

    def test_a_second_character_reuses_wolfs_approved_hairstyle_without_his_identity(self):
        ## ARRANGE: a second character on the foundation choosing Wolf's Ranger hairstyle
        ## from the library (its approved version), nothing else of Wolf's.
        doc = foundation.load(lib.current_foundation_document())
        record = json.loads(Path(foundation.path_of(doc, "record", CHARACTERS.parent)).read_text(encoding="utf-8"))
        regions = json.loads(Path(foundation.path_of(doc, "regions", CHARACTERS.parent)).read_text(encoding="utf-8"))
        hair = lib.payload("wolf_hair_ranger", "wolf_hair_ranger.garment.json")
        second = json.loads((CHARACTERS / "wolf" / "wolf.assembly.json").read_text(encoding="utf-8"))
        second["id"] = "character.fixture_second"
        second["foundation"] = {"id": doc["id"], "body": {"height_m": 1.9, "frame_build": 1.1, "muscularity": 0.9}, "face": "default"}
        second["outfits"] = {"field": {"collections": [], "body_mask": None, "garments": [hair["id"]]}}
        second["art"]["outfits"] = {"field": dict(second["art"]["outfits"]["ranger"])}
        ## ACT
        plan = appearance.resolve(second, "field", {hair["id"]: hair}, regions, foundation.garment_target(doc, record, second))
        ## ASSERT: only the hairstyle; the default face; no beard, no Wolf skin or palette.
        self.assertEqual([c["id"] for c in plan["components"]], ["wolf_hair_ranger"])
        self.assertEqual(plan["face"], "default")
        self.assertEqual(lib.asset("wolf_hair_ranger")["origin"], "wolf")
        self.assertIn("wolf_skin", lib.index()["assets"])
        self.assertNotIn("wolf_skin", json.dumps(plan))
        ## The library owns the version: the second character's use leaves it unchanged.
        self.assertEqual(lib.verify(), [])

    def test_the_shipped_validations_are_what_was_approved(self):
        ## ASSERT: the default bodies and face validated on the sweep, each version on its own
        ## evidence; Wolf's skin and face at the reference; his hairstyles only compatible by
        ## contract on the foundation.
        envelope = {"height_m": (1.6, 2.0), "frame_build": (0.85, 1.15), "muscularity": (0.8, 1.25)}
        reference = {"height_m": 1.8, "frame_build": 1.0, "muscularity": 1.0}
        fid = "character.male_base.foundation"
        self.assertEqual(lib.compatibility("default_face", fid, reference, envelope), lib.VALIDATED)
        self.assertEqual(lib.compatibility("wolf_skin", fid, reference, envelope), lib.VALIDATED)
        self.assertEqual(lib.compatibility("wolf_face", fid, reference, envelope), lib.VALIDATED)
        self.assertEqual(lib.compatibility("wolf_hair_ranger", fid, reference, envelope), lib.BY_CONTRACT)
        for asset_id in ("default_face", "male_base_foundation"):
            for version in ("v001", "v002"):
                self.assertEqual(len([r for r in lib.validations(asset_id) if r["version"] == version]), 15, (asset_id, version))


if __name__ == "__main__":
    unittest.main()
