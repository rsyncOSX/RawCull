import unittest
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from CompareAFSharpness import evaluate


class PairAgreementTests(unittest.TestCase):
    @unittest.skipUnless(importlib.util.find_spec("cv2"), "OpenCV required for image integration")
    def test_exported_crop_workflow_prefers_sharp_edges(self):
        import cv2
        import numpy as np
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sharp = np.zeros((64, 64, 3), dtype=np.uint8)
            sharp[16:48, 16:48] = 255
            cv2.imwrite(str(root / "a.png"), sharp)
            cv2.imwrite(str(root / "b.png"), cv2.GaussianBlur(sharp, (0, 0), 3))
            (root / "manifest.json").write_text(json.dumps(dict(schema=1, complete=True, scenario="test", images=[
                dict(id="a", crop="a.png", rawcull=2), dict(id="b", crop="b.png", rawcull=1)])))
            (root / "pairs.csv").write_text("burst,a,b,label\nfirst,a,b,A\n")
            subprocess.run([sys.executable, str(Path(__file__).with_name("CompareAFSharpness.py")),
                            directory, "--pairs", str(root / "pairs.csv")], check=True, capture_output=True)
            result = json.loads((root / "agreement.json").read_text())
            for method in result["methods"].values():
                self.assertEqual(method["correct"], 1)
            page = (root / "review.html").read_text()
            self.assertNotIn("laplacian", page)
            self.assertNotIn("rawcull", page)

    def test_direction_ties_missing_and_exclusions(self):
        scores = {"one": dict(rawcull=2, laplacian=1, tenengrad=0),
                  "two": dict(rawcull=1, laplacian=2, tenengrad=0), "missing": {}}
        pairs = [dict(burst="burst1", a="one", b="two", label="A"),
                 dict(burst="burst2", a="two", b="missing", label="B"),
                 dict(burst="burst3", a="one", b="missing", label="uncertain")]
        result = evaluate(scores, pairs)
        self.assertEqual(result["judged"], 2)
        self.assertEqual(result["uncertain"], 1)
        self.assertEqual(result["methods"]["rawcull"], dict(correct=1, wrong=0, model_tie=0, unavailable=1))
        self.assertEqual(result["methods"]["laplacian"]["wrong"], 1)
        self.assertEqual(result["methods"]["tenengrad"]["model_tie"], 1)

    def test_reversed_duplicates_rejected(self):
        with self.assertRaises(ValueError):
            evaluate({"a": {}, "b": {}}, [dict(burst="x", a="a", b="b", label="A"),
                                           dict(burst="x", a="b", b="a", label="B")])

    def test_burst_membership_required(self):
        with self.assertRaises(ValueError):
            evaluate({"a": {}, "b": {}}, [dict(burst="", a="a", b="b", label="A")])


if __name__ == "__main__":
    unittest.main()
