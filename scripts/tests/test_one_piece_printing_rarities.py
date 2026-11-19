import sys
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
from build_one_piece_printing_rarities import build_rarities


class OnePiecePrintingRarityTests(unittest.TestCase):
    def test_exact_catalog_alias_can_distinguish_rarities_for_the_same_number(self):
        number = "OP05-119"
        standard = number
        special = f"{number}_p1"

        def row(artwork, rarity):
            return (f'<dl class="modalCol" id="{artwork}"><div class="infoCol">'
                    f'<span>{number}</span><span>{rarity}</span></div></dl>')

        observations, printings = [], []
        for series, artwork in [("569105", standard), ("569111", special)]:
            alias = {"provider": "bandai", "sourceID": f"product:{series}:{artwork}"}
            observations.append({
                "alias": alias, "kind": "catalog", "language": "en",
                "sourceURL": f"https://en.onepiece-cardgame.com/cardlist/?series={series}",
                "printedEvidence": {"number": number, "sourceArtworkAlias": artwork},
            })
            printings.append({"id": series, "language": "en", "canonicalCardID": number,
                              "sourceAliases": [alias]})
        printings.append({"id": "no-exact-alias", "language": "en", "canonicalCardID": number,
                          "sourceAliases": []})
        release = {"observations": observations, "registry": {
            "canonicalCards": [{"id": number, "printedNumber": number}], "printings": printings,
        }}
        with TemporaryDirectory() as tmp:
            base = Path(tmp) / "bandai-569105.html"
            reprint = Path(tmp) / "bandai-569111.html"
            base.write_text(row(standard, "SEC"))
            reprint.write_text(row(special, "SP CARD"))
            self.assertEqual(build_rarities(release, [base, reprint]), {"569105": "SEC", "569111": "SP CARD"})
            reprint.write_text(row(special, "SP CARD") + row(special, "SEC"))
            self.assertEqual(build_rarities(release, [base, reprint]), {"569105": "SEC"})
