# Browse reliability visual acceptance

Target screens: Pokémon first-card detail and One Piece sealed directory/product/detail.
Routes: `Browse`, `SealedAcceptance` with `ready`, `blocked`, or `offline`.
Expected devices: iOS 26.5 iPhone 17 Pro and iPad simulator.

- Pokémon opens its first card from a cold launch without an identity error.
- Recorded One Piece directory navigates to products and exact sealed detail.
- Permitted Add displays Undo; Undo returns owned quantity to its prior value.
- Blocked saving states its availability and disables Add.
- Connectivity failure offers Retry without an empty vendor section; Retry recovers.
- Error text and actions remain readable at accessibility Dynamic Type sizes.

Recorded-provider evidence does not establish live-provider, physical-device, or CloudKit readiness.
