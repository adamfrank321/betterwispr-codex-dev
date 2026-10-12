import importlib.util
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('check_source', ROOT / 'scripts/check_source.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class SourceValidatorTests(unittest.TestCase):
    def test_real_tree(self):
        self.assertEqual(module.validate(), [])

    def test_detects_drift_and_missing_target(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'repo'
            shutil.copytree(ROOT, target, ignore=shutil.ignore_patterns('.git', '.build'))
            (target / 'Shared/Sources/BetterWisprShared/Domain/Transcript.swift').write_text('modified')
            (target / 'iOS/Keyboard/KeyboardViewController.swift').unlink()
            errors = module.validate(target)
            self.assertTrue(any('source drift' in item for item in errors))
            self.assertTrue(any('Missing required input' in item for item in errors))
