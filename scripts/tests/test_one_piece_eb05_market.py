import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_one_piece_eb05_market import reviewed_title_matches


class ReviewedMarketTitleTests(unittest.TestCase):
    def test_alternate_art_uses_both_titles_and_printed_number(self):
        self.assertTrue(reviewed_title_matches('Baby 5 (Alternate Art)', 'Baby 5 (Alternate Art)',
                                               'Baby 5', 'EB05-004', 'Alternate artwork'))
        self.assertFalse(reviewed_title_matches('Baby 5', 'Baby 5 (Alternate Art)',
                                                'Baby 5', 'EB05-004', 'Alternate artwork'))
        self.assertFalse(reviewed_title_matches('Baby 5 (SP)', 'Baby 5 (Alternate Art)',
                                                'Baby 5', 'EB05-004', 'Alternate artwork'))
        self.assertFalse(reviewed_title_matches('Baby 5 (OP01-004) (Alternate Art)', 'Baby 5 (Alternate Art)',
                                                'Baby 5', 'EB05-004', 'Alternate artwork'))

    def test_unknown_and_conflicting_treatments_remain_held(self):
        for title in ('Baby 5 (Gold Stamped)', 'Baby 5 (Alternate Art) (Winner)'):
            self.assertFalse(reviewed_title_matches(title, title, 'Baby 5', 'EB05-004', 'Alternate artwork'))
        self.assertFalse(reviewed_title_matches('Baby 5 (Alternate Art)', 'Baby 5 (Alternate Art)',
                                                'Baby 5', 'EB05-004', 'Standard artwork'))


if __name__ == '__main__':
    unittest.main()
