import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('prepare_desktop', ROOT / 'scripts/prepare_desktop.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class DesktopSetupTests(unittest.TestCase):
    def test_patch_requires_exact_anchor(self):
        with tempfile.TemporaryDirectory() as folder:
            file = Path(folder) / 'source.swift'
            file.write_text('one\none\n')
            with self.assertRaises(ValueError):
                module.replace_once(file, 'one', 'two')
            self.assertEqual(file.read_text(), 'one\none\n')
            file.write_text('one\n')
            module.replace_once(file, 'one', 'two')
            self.assertEqual(file.read_text(), 'two\n')
