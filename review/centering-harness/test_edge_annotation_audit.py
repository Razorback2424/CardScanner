"""Known-pixel checks for the review-only annotation fitter."""
import unittest

import numpy as np
from scipy.ndimage import gaussian_filter

from edge_annotation_audit import audit_edge


class ObservedEdgeAuditTests(unittest.TestCase):
    def setUp(self):
        self.seed = [(80, 60), (420, 60), (420, 540), (80, 540)]

    def image(self, occluded=False):
        y, x = np.mgrid[:600, :500]
        # The left edge slopes by 24 native pixels; the annotation seed is
        # vertical. A translated seed cannot satisfy both endpoint checks.
        cut = 80 + .05 * (y - 60)
        gray = np.where(x < cut, 230., 35.)
        gray = gaussian_filter(gray, .8)
        if occluded:
            gray[250:290] = 230
        return np.repeat(gray[:, :, None], 3, axis=2).astype(np.float32)

    def test_observed_angle_is_independent_of_seed_angle(self):
        result = audit_edge(self.image(), self.seed, "left")
        self.assertAlmostEqual(result["endpoints"][0][0], 80, delta=1)
        self.assertAlmostEqual(result["endpoints"][1][0], 104, delta=1)
        self.assertGreater(result["retainedCount"], 50)
        self.assertLess(result["fitRMSNativePixels"], 1)

    def test_interrupted_edge_keeps_supported_line_and_rejections(self):
        result = audit_edge(self.image(occluded=True), self.seed, "left")
        self.assertAlmostEqual(result["endpoints"][1][0], 104, delta=1)
        self.assertTrue(any(not p["retained"] for p in result["observations"]))

    def test_wrong_polarity_and_flat_pixels_cannot_create_evidence(self):
        with self.assertRaisesRegex(ValueError, "insufficient"):
            audit_edge(self.image(), self.seed, "left", polarity="rising")
        with self.assertRaisesRegex(ValueError, "insufficient"):
            audit_edge(np.full((600, 500, 3), 125, dtype=np.float32), self.seed, "left")

    def test_inverse_transition_has_same_geometry_when_polarity_changes(self):
        result = audit_edge(255 - self.image(), self.seed, "left", polarity="rising")
        self.assertAlmostEqual(result["endpoints"][0][0], 80, delta=1)
        self.assertAlmostEqual(result["endpoints"][1][0], 104, delta=1)


if __name__ == "__main__":
    unittest.main()
