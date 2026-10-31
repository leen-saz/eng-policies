import pathlib
import subprocess
import sys
import unittest


class BuildTest(unittest.TestCase):
    def test_build_writes_index(self):
        root = pathlib.Path(__file__).resolve().parent.parent
        subprocess.run([sys.executable, "build.py"], cwd=root, check=True)
        self.assertTrue((root / "public" / "index.html").exists())


if __name__ == "__main__":
    unittest.main()
