# One Piece signed seed

No production seed is supplied yet. Synthetic test fixtures must not be bundled
as a production catalog or used to claim printing-universe completeness.

Once reviewed source data/rights and dedicated signing keys are approved, retain
the verified publication envelope here as `one-piece-catalog-release.json` and
add that file to the app's Copy Bundle Resources phase. Bootstrap looks for this
exact resource name at the bundle root and verifies it against the One Piece
public keys supplied by the build configuration.

The default rollout is disabled. Validation-only mode verifies remote releases
without enabling One Piece scan/Browse or collection writes. Remote authority
enables local scanning and Browse only after the signed seed and configuration
pass validation; collection writes and pricing retain their independent gates.
Failed configuration/seed validation preserves Pokémon/Magic availability.
