# Maia model

Run `Scripts/download-maia-model.sh` from the repository root before building.
The ignored, caller-provisioned model is copied into the app bundle; no model is
downloaded during play. No MaiaEmbedded sibling checkout is required.

The supported Maia-3 79M FP32 export is 316,034,244 bytes, SHA-256
`3454b03ae78baa64a87b345fdb1a457265d912caec531039b074f07eda0d8010`.
It comes from Mobile Maia revision `5f6743eed5491d2e8413fe0dfd1f8ef612d0aa84`
and retains AGPL-3.0-only terms. See `THIRD_PARTY.md` and MaiaEmbedded's public
provenance for the checkpoint, conversion source and retained notices.
