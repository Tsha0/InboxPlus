import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


root = Path(__file__).resolve().parents[2]
specification = importlib.util.spec_from_file_location("sbom", root / "Scripts/generate-sbom.py")
sbom = importlib.util.module_from_spec(specification)
specification.loader.exec_module(sbom)


class CombinedInventoryTests(unittest.TestCase):
    def setUp(self):
        self.reviews = json.loads((root / "docs/dependency-licenses.json").read_text())

    def test_go_replacement_records_executed_source_and_checksum_semantics(self):
        components = sbom.go_components(self.reviews)
        self.assertFalse(any(value["name"] == "github.com/imroc/req/v3" for value in components))
        replacement = next(value for value in components if value["name"] == "github.com/beeper/req/v3")
        self.assertIn({"name": "inboxplus:go:replaces", "value": "github.com/imroc/req/v3"}, replacement["properties"])
        self.assertTrue(replacement["properties"][0]["value"].startswith("h1:"))
        self.assertNotIn("hashes", replacement)

    def test_pub_inventory_keeps_different_locked_versions_without_duplicates(self):
        def record(name, version):
            return ('  ' + name + ':\n'
                    '    dependency: transitive\n'
                    '    description:\n'
                    '      name: ' + name + '\n'
                    '      sha256: "' + '0' * 64 + '"\n'
                    '      url: "https://pub.dev"\n'
                    '    source: hosted\n'
                    '    version: "' + version + '"\n')

        with tempfile.TemporaryDirectory() as directory:
            fixture_root = Path(directory)
            for location, version in (("apps/inboxplus_flutter", "1.0.0"), ("packages/inboxplus_storage", "2.0.0")):
                path = fixture_root / location / "pubspec.lock"
                path.parent.mkdir(parents=True)
                path.write_text('packages:\n' + record("shared", version) + record("same", "1.0.0"))
            reviews = {"pub:" + value: {"license": "MIT"} for value in ("shared@1.0.0", "shared@2.0.0", "same@1.0.0")}
            with patch.object(sbom, "ROOT", fixture_root):
                components = sbom.pub_components(reviews)
        references = [value["purl"] for value in components]
        self.assertEqual(len(references), len(set(references)))
        versions = {value["version"] for value in components if value["name"] == "shared"}
        self.assertEqual(versions, {"1.0.0", "2.0.0"})
        self.assertEqual(len(components), 3)
        for component in components:
            self.assertRegex(component["hashes"][0]["content"], r"^[a-f0-9]{64}$")

    def test_unreviewed_dependency_fails_closed(self):
        with self.assertRaises(KeyError):
            sbom.pub_components({})

    def test_generation_is_deterministic_and_keeps_meta_copyleft_license(self):
        legacy = json.dumps({"components": [], "metadata": {"component": {}}, "serialNumber": "unused"})
        first = sbom.generate(legacy)
        self.assertEqual(first, sbom.generate(legacy))
        meta = next(value for value in json.loads(first)["components"] if value["name"] == "go.mau.fi/mautrix-meta")
        self.assertEqual(meta["licenses"], [{"license": {"id": "AGPL-3.0-or-later"}}])


if __name__ == "__main__":
    unittest.main()
