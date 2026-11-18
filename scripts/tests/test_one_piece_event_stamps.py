import copy
from io import BytesIO
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from PIL import Image
from reconcile_one_piece_event_stamps import build_event_stamps, page_text, rarities

EVENT = "https://en.onepiece-cardgame.com/events/2023/store_tournament_op02/"
LIST = "https://en.onepiece-cardgame.com/cardlist/?series=569102"
RENDER = "https://en.onepiece-cardgame.com/images/cardlist/card/OP02-003.png?261016"
SPEC = ["1 types in total", "Pre-Release Stamped cards are from PARAMOUNT WAR [OP-02] Common and Uncommon cards."]


def image(color):
    buffer = BytesIO()
    Image.new("RGB", (430, 600), color).save(buffer, "PNG")
    return buffer.getvalue()


def cardlist(rarity="C"):
    return f'''<select name="series"><option value="569102" selected>[OP-02]</option></select>
    <div class="countCol">1 result</div><dl class="modalCol" id="OP02-003">
    <div class="infoCol"><span>OP02-003</span> | <span>{rarity}</span> | <span>CHARACTER</span></div>
    <div class="cardName">Atmos</div><div class="getInfo"><h3>Card Set(s)</h3>OP-02</div></dl>'''.encode()


class Captures:
    def __init__(self, responses):
        self.responses = responses

    def capture(self, url, filename):
        raw = self.responses[url]
        import hashlib
        return {"sourceURL": url, "payloadSHA256": hashlib.sha256(raw).hexdigest(),
                "observedAt": "2026-11-18T00:00:00+00:00"}, raw


class Market:
    def __init__(self, products, lanes):
        root = "https://tcgcsv.com/tcgplayer/68/22934/"
        self.documents = {root + "products": {"results": products}, root + "prices": {"results": lanes}}
        self.manifest = {"captures": {root + "products": {"payloadSHA256": "a" * 64,
                                                          "observedAt": "2026-11-18T00:00:00+00:00"}}}

    def fetch_json(self, url):
        return self.documents[url]


def fixture():
    import hashlib
    official = image((200, 40, 40))
    digest = hashlib.sha256(official).hexdigest()
    release = {
        "registry": {
            "canonicalCards": [{"id": "one-piece:en:OP02-003", "printedNumber": "OP02-003", "language": "en", "name": "Atmos"}],
            "products": [{"id": "product:op02", "label": "Paramount War"}],
            "artworks": [{"id": "ART", "imageSHA256": digest, "observationIDs": ["base:render"]}],
            "appearances": [],
            "printings": [{"id": "BASE", "canonicalCardID": "one-piece:en:OP02-003", "artworkID": "ART",
                           "releaseID": "product:op02", "status": "verified", "supportedVariantIDs": ["normal"],
                           "review": {"evidence": [{"kind": "printedIdentity", "observationID": "base:list"}]}}]},
        "observations": [
            {"id": "base:list", "sourceURL": LIST, "alias": {"provider": "bandai", "sourceID": "OP02-003"},
             "productEvidence": ["product:op02"], "printedEvidence": {"number": "OP02-003", "sourceArtworkAlias": "OP02-003"}},
            {"id": "base:render", "sourceURL": RENDER, "alias": {"provider": "bandai", "sourceID": "OP02-003"},
             "imageSHA256": digest, "observedAt": "2026-11-12T00:00:00+00:00", "productEvidence": ["product:op02"],
             "printedEvidence": {"number": "OP02-003"}}],
    }
    rule = {"productID": "event:paramount-war-pre-release-cards", "label": "Paramount War Pre-Release Cards",
            "releaseDate": "2023-03-03", "marketplaceGroupID": 22934, "eventURL": EVENT, "specification": SPEC,
            "types": 1, "series": ["569102"], "prefixes": ["OP02"], "rarities": ["C", "UC"], "stamp": "Pre-Release stamp"}
    product = {"productId": 500, "name": "Atmos", "extendedData": [{"name": "Number", "value": "OP02-003"}]}
    captures = {
        "bandai": {LIST: cardlist()},
        "events": {EVENT: ("<ul><li>*" + "</li><li>*".join(SPEC) + "</li></ul>").encode()},
        "artwork": {RENDER: official, "https://product-images.tcgplayer.com/fit-in/600x600/500.jpg": official},
    }
    return release, {"events": [rule]}, captures, [product], [{"productId": 500, "subTypeName": "Normal"}]


def run(release, rules, captures, products, lanes):
    return build_event_stamps(release, rules, Captures(captures["bandai"]), Captures(captures["events"]),
                              Captures(captures["artwork"]), Market(products, lanes))


class OnePieceEventStampTests(unittest.TestCase):
    def test_page_text_and_rarity_parsing(self):
        self.assertEqual(page_text(b"<li>*75 types\n in&nbsp;total</li>").strip(), "*75 types in total")
        self.assertEqual(rarities(cardlist("UC")), {"OP02-003": "UC"})

    def test_complete_event_adds_a_stamped_printing_in_its_own_product(self):
        result, stats, report = run(*fixture())
        self.assertEqual(stats["verified-new"], 1)
        printing = result["printings"][0]
        self.assertEqual((printing["releaseID"], printing["stamp"], printing["supportedVariantIDs"]),
                         ("event:paramount-war-pre-release-cards", "Pre-Release stamp", ["normal"]))
        self.assertEqual({e["kind"] for e in printing["review"]["evidence"]},
                         {"printedIdentity", "language", "artwork", "release", "stamp", "finish"})
        self.assertIn({"provider": "tcgplayer", "sourceID": "500"}, printing["sourceAliases"])
        listing = next(o for o in result["observations"] if o["id"].endswith(":marketplace"))
        self.assertEqual(listing["printedEvidence"]["retailerReferenceProductID"], "500")
        self.assertEqual(result["products"], [{"id": "event:paramount-war-pre-release-cards",
                                               "label": "Paramount War Pre-Release Cards", "releaseDate": "2023-03-03"}])
        self.assertEqual(report[0]["accepted"], ["OP02-003"])

    def test_event_is_held_whole_when_any_gate_fails(self):
        cases = {
            "official-specification-changed": lambda r, rules, c, p, l: c["events"].update({EVENT: b"75 types"}),
            "marketplace-group-has-2": lambda r, rules, c, p, l: p.append(
                {"productId": 501, "name": "Blenheim", "extendedData": [{"name": "Number", "value": "OP02-012"}]}),
            "no-card-passed": lambda r, rules, c, p, l: c["bandai"].update({LIST: cardlist("R")}),
        }
        for expected, mutate in cases.items():
            args = fixture()
            mutate(*args)
            result, stats, report = run(*args)
            self.assertEqual(result["printings"], [], expected)
            self.assertTrue(report[0]["eventHeld"].startswith(expected), report[0]["eventHeld"])

    def test_never_priced_card_becomes_a_known_unpriced_printing(self):
        release, rules, captures, products, _ = fixture()
        result, stats, report = run(release, rules, captures, products, [])
        printing = result["printings"][0]
        self.assertEqual((printing["status"], printing["supportedVariantIDs"]), ("provisional", []))
        self.assertNotIn("finish", {e["kind"] for e in printing["review"]["evidence"]})
        listing = next(o for o in result["observations"] if o["id"].endswith(":marketplace"))
        self.assertEqual(listing["printedEvidence"]["marketplaceFinishLanes"], "none")
        self.assertNotIn("finishVariantID", listing["printedEvidence"])
        self.assertEqual(stats["known-unpriced-new"], 1)

    def test_card_level_holds_name_their_reason(self):
        for reason, mutate in {
            "marketplace-finish-lane-not-normal-only": lambda r, rules, c, p, l: l.append({"productId": 500, "subTypeName": "Foil"}),
            "marketplace-title-not-plain": lambda r, rules, c, p, l: p[0].update(name="Atmos (Parallel)"),
            "marketplace-photo-does-not-match-base-artwork": lambda r, rules, c, p, l: c["artwork"].update(
                {"https://product-images.tcgplayer.com/fit-in/600x600/500.jpg": image((10, 200, 10))}),
            "base-printing-not-uniquely-verified": lambda r, rules, c, p, l: r["registry"]["printings"][0].update(status="provisional"),
        }.items():
            args = copy.deepcopy(fixture())
            mutate(*args)
            _, _, report = run(*args)
            self.assertEqual(report[0]["held"], {"OP02-003": reason})


    def test_reviewed_photo_pair_accepts_only_its_pinned_images(self):
        import hashlib
        release, rules, captures, products, lanes = fixture()
        stamped = image((200, 40, 120))
        captures["artwork"]["https://product-images.tcgplayer.com/fit-in/600x600/500.jpg"] = stamped
        official = captures["artwork"][RENDER]
        pair = {"number": "OP02-003", "productID": "event:paramount-war-pre-release-cards",
                "retailerImageSHA256": hashlib.sha256(stamped).hexdigest(),
                "bandaiImageSHA256": hashlib.sha256(official).hexdigest()}
        args = (release, rules, Captures(captures["bandai"]), Captures(captures["events"]),
                Captures(captures["artwork"]), Market(products, lanes))
        result, _, _ = build_event_stamps(*args, {"500": pair})
        listing = next(o for o in result["observations"] if o["id"].endswith(":marketplace"))
        self.assertEqual(listing["printedEvidence"]["artworkReview"], "reviewed-photo-pair")
        for key in pair:
            changed = dict(pair, **{key: "x"})
            _, _, report = build_event_stamps(*args, {"500": changed})
            self.assertEqual(report[0]["held"], {"OP02-003": "marketplace-photo-does-not-match-base-artwork"})


if __name__ == "__main__":
    unittest.main()
