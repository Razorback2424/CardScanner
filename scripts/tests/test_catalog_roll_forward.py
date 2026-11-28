"""Offline regression tests for signed content roll-forward and recovery rehearsals."""
from __future__ import annotations

import base64
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import catalog_roll_forward as rf  # noqa: E402


class RollForwardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.site = self.root / "site"
        self.site.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def _write_tree(self, mapping: dict[str, bytes]):
        for rel, raw in mapping.items():
            path = self.site / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)

    def _seed_all_games(self):
        self._write_tree(rf._drill_pokemon_files(2, set_display_name="Good Set", generated_at="2026-11-26T00:00:00Z"))
        self._write_tree(rf._drill_pokemon_files(3, set_display_name="Bad Set", generated_at="2026-11-27T00:00:00Z"))
        self._write_tree(rf._drill_one_piece_files(2, card_name="Luffy Good", generated_at="2026-11-26T00:00:00Z"))
        self._write_tree(rf._drill_one_piece_files(3, card_name="Luffy Bad", generated_at="2026-11-27T00:00:00Z"))
        self._write_tree(rf._drill_magic_files(2, set_display_name="Dominaria Good", generated_at="2026-11-26T00:00:00Z"))
        self._write_tree(rf._drill_magic_files(3, set_display_name="Dominaria Bad", generated_at="2026-11-27T00:00:00Z"))
        self._write_tree(
            rf._drill_yugioh_files(2, generation="ygo-gen-2", card_name="Blue-Eyes Good", generated_at="2026-11-26T00:00:00Z")
        )
        self._write_tree(
            rf._drill_yugioh_files(3, generation="ygo-gen-3", card_name="Blue-Eyes Bad", generated_at="2026-11-27T00:00:00Z")
        )

    def test_prepares_monotonic_roll_forward_candidates_for_all_four_games(self):
        self._seed_all_games()
        for game in rf.GAMES:
            with self.subTest(game=game):
                out = self.root / "out" / game
                manifest = rf.prepare_roll_forward(
                    game=game,
                    target_revision=2,
                    output_dir=out,
                    reason=f"Recover {game} from defective rev 3",
                    local_site=self.site,
                    generated_at="2026-11-27T18:00:00Z",
                    verify_signatures=False,
                )
                self.assertEqual(manifest["activeRevision"], 3)
                self.assertEqual(manifest["targetRevision"], 2)
                self.assertEqual(manifest["nextRevision"], 4)
                self.assertTrue(manifest["parityVerified"])
                self.assertTrue((out / "roll-forward-manifest.json").is_file())
                for rel, expected_sha in manifest["artifacts"].items():
                    self.assertEqual(rf.sha256_bytes((out / rel).read_bytes()), expected_sha)

        # Verify Pokémon candidate matches active rev 3 -> rev 4 diff classification.
        poke_report = json.loads((self.root / "out/pokemon/candidate/review-report.json").read_text())
        self.assertEqual(poke_report["revision"], 4)
        self.assertEqual(poke_report["changeClass"], "contentOnly")
        self.assertEqual(poke_report["contentChangedProviderSetIDs"], ["sv99"])

        # Verify Magic candidate matches active rev 3 -> rev 4 diff classification.
        mtg_report = json.loads((self.root / "out/magic/candidate/review-report.json").read_text())
        self.assertEqual(mtg_report["revision"], 4)
        self.assertEqual(mtg_report["changeClass"], "contentOnly")
        self.assertEqual(mtg_report["contentChangedCodes"], ["DMU"])

        # Verify One Piece candidate bumped revision and preserved rev 2 content.
        op_cand = json.loads((self.root / "out/one-piece/candidate-rev-4.json").read_text())
        self.assertEqual(op_cand["revision"], 4)
        self.assertEqual(op_cand["registry"]["canonicalCards"][0]["name"], "Luffy Good")

        # Verify Yu-Gi-Oh! candidate reused rev 2 catalog bytes verbatim and staged rev 3 parent.
        self.assertEqual(
            (self.root / "out/yugioh/catalog.json").read_bytes(),
            (self.site / "yugioh/v1/releases/2/catalog.json").read_bytes(),
        )
        self.assertEqual(
            (self.root / "out/yugioh/parent-release.json").read_bytes(),
            (self.site / "yugioh/v1/current.json").read_bytes(),
        )

    def test_rejects_non_monotonic_target_revision_and_empty_reason(self):
        self._seed_all_games()
        with self.assertRaisesRegex(rf.RollForwardError, "strictly less than active revision"):
            rf.prepare_roll_forward(
                game="pokemon",
                target_revision=3,
                output_dir=self.root / "bad-eq",
                reason="Invalid equal revision",
                local_site=self.site,
                verify_signatures=False,
            )
        with self.assertRaisesRegex(rf.RollForwardError, "strictly less than active revision"):
            rf.prepare_roll_forward(
                game="pokemon",
                target_revision=4,
                output_dir=self.root / "bad-future",
                reason="Invalid future revision",
                local_site=self.site,
                verify_signatures=False,
            )
        with self.assertRaisesRegex(rf.RollForwardError, "non-empty --reason"):
            rf.prepare_roll_forward(
                game="pokemon",
                target_revision=2,
                output_dir=self.root / "bad-reason",
                reason="   ",
                local_site=self.site,
                verify_signatures=False,
            )

    def test_invokes_signature_verifier_when_enabled_and_fails_closed(self):
        self._seed_all_games()
        verified: list[tuple[str, int]] = []

        def ok_verifier(game: str, path: Path, expected_revision: int, root: Path):
            verified.append((game, expected_revision))

        manifest = rf.prepare_roll_forward(
            game="pokemon",
            target_revision=2,
            output_dir=self.root / "sig-ok",
            reason="Verify signature hook",
            local_site=self.site,
            verify_signatures=True,
            signature_verifier=ok_verifier,
        )
        self.assertEqual(manifest["signatureVerification"], "verified")
        self.assertEqual(verified, [("pokemon", 3), ("pokemon", 2)])

        def bad_verifier(game: str, path: Path, expected_revision: int, root: Path):
            raise rf.RollForwardError("Invalid Ed25519 signature")

        with self.assertRaisesRegex(rf.RollForwardError, "Invalid Ed25519 signature"):
            rf.prepare_roll_forward(
                game="pokemon",
                target_revision=2,
                output_dir=self.root / "sig-fail",
                reason="Must fail closed",
                local_site=self.site,
                verify_signatures=True,
                signature_verifier=bad_verifier,
            )

    def test_one_piece_fails_closed_if_active_revision_added_permanent_printing_uuid(self):
        self._seed_all_games()
        # Mutate rev 3 to introduce an extra permanent printing UUID not in rev 2.
        _, rev3_payload = rf.decode_envelope((self.site / "one-piece/v1/current.json").read_bytes(), "rev3")
        extra_printing = copy.deepcopy(rev3_payload["registry"]["printings"][0])
        extra_printing["id"] = "33333333-3333-4333-8333-333333333333"
        rev3_payload["registry"]["printings"].append(extra_printing)
        env3 = rf._fake_signed_envelope(rev3_payload)
        (self.site / "one-piece/v1/current.json").write_bytes(env3)
        (self.site / "one-piece/v1/releases/3/catalog-release.json").write_bytes(env3)

        with self.assertRaisesRegex(rf.RollForwardError, "permanent printing UUID"):
            rf.prepare_roll_forward(
                game="one-piece",
                target_revision=2,
                output_dir=self.root / "op-blocked",
                reason="Should fail closed",
                local_site=self.site,
                verify_signatures=False,
            )

    def test_pokemon_authority_change_classification_and_magic_none_rejection(self):
        self._seed_all_games()
        # If bad rev 3 changed printedCode (an authority field), rolling forward to rev 2 is an authority change.
        _, rev3 = rf.decode_envelope((self.site / "v1/current.json").read_bytes(), "rev3")
        rev3["sets"][0]["printedCode"] = "SV99BAD"
        env3 = rf._fake_signed_envelope(rev3)
        (self.site / "v1/current.json").write_bytes(env3)
        manifest = rf.prepare_roll_forward(
            game="pokemon",
            target_revision=2,
            output_dir=self.root / "poke-auth",
            reason="Revert authority field change",
            local_site=self.site,
            verify_signatures=False,
        )
        self.assertEqual(manifest["details"]["changeClass"], "authority")

        # Magic rejects rolling forward when target rev 2 is semantically identical to rev 3.
        self._write_tree(rf._drill_magic_files(3, set_display_name="Dominaria Good", generated_at="2026-11-27T00:00:00Z"))
        with self.assertRaisesRegex(rf.RollForwardError, "changeClass=none"):
            rf.prepare_roll_forward(
                game="magic",
                target_revision=2,
                output_dir=self.root / "magic-noop",
                reason="No semantic diff",
                local_site=self.site,
                verify_signatures=False,
            )

    def test_yugioh_rejects_tampered_catalog_hash_and_same_generation_collision(self):
        self._seed_all_games()
        (self.site / "yugioh/v1/releases/2/catalog.json").write_bytes(b'{"tampered":true}\n')
        with self.assertRaisesRegex(rf.RollForwardError, "hash does not match signed manifest"):
            rf.prepare_roll_forward(
                game="yugioh",
                target_revision=2,
                output_dir=self.root / "ygo-tampered",
                reason="Tamper check",
                local_site=self.site,
                verify_signatures=False,
            )

        # Re-seed with colliding generation on rev 3 vs rev 2 but different card content.
        self._seed_all_games()
        self._write_tree(
            rf._drill_yugioh_files(3, generation="ygo-gen-2", card_name="Blue-Eyes Bad", generated_at="2026-11-27T00:00:00Z")
        )
        with self.assertRaisesRegex(rf.RollForwardError, "shares generation"):
            rf.prepare_roll_forward(
                game="yugioh",
                target_revision=2,
                output_dir=self.root / "ygo-gen",
                reason="Generation check",
                local_site=self.site,
                verify_signatures=False,
            )

    def test_end_to_end_offline_infrastructure_failure_and_recovery_rehearsal(self):
        import ast

        source = (Path(__file__).resolve().parents[1] / "catalog_roll_forward.py").read_text(encoding="utf-8")
        tree = ast.parse(source)
        asserts = [node.lineno for node in ast.walk(tree) if isinstance(node, ast.Assert)]
        self.assertEqual(asserts, [], f"catalog_roll_forward.py must not rely on assert (stripped under -O): {asserts}")

        receipt = rf.rehearse_recovery()
        self.assertTrue(receipt["allPassed"])
        self.assertEqual(receipt["rehearsalMode"], "offline-fixture")
        for phase_name, phase in receipt["phases"].items():
            with self.subTest(phase=phase_name):
                self.assertTrue(phase["passed"])
        self.assertEqual(
            set(receipt["phases"]["contentRollForwardAllGames"]["games"].keys()),
            set(rf.GAMES),
        )


if __name__ == "__main__":
    unittest.main()
