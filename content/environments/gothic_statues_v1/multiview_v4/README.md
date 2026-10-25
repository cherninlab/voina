# Selected statue multi-view investigation

The user selected E01 (crawling reach), E06 (seated turn) and E04 (fallen reaching). Their exact supplied PNGs are preserved as `E*/approved.png`; sources and hashes are recorded in [sources.json](sources.json).

Four camera-reference edits per statue were requested from native ImageGen, preserving pose and requesting clean alpha. Each sibling JSON records the exact prompt, references, camera convention and inspection. E04 back was blocked at output moderation and was not retried. Eleven candidate images were returned.

## Consistency review: failed

These are **rejected reconstruction inputs**, not verified turntables. Several side views remain near the same flank instead of opposing sides, and knees/elbows/head/drapery shift between views. Hidden surfaces in back views were imagined, not measured. Alpha fringes/halos and tight margins remain. No meshes were generated from these sets. The approved source poses remain unchanged.

See [review.json](review.json) and per-view receipts under E01/, E04/ and E06/. Do not feed the candidate pack into a multi-view model as if it were one rigid object.

## Separate local workflow experiment

`/Users/theochernin/Projects/CherninLab3D/web_ui/` has an experimental four-view mode. It uses the published InstantMesh NeRF-large checkpoint with Apache-licensed encoder/transformer code and an independently implemented PyTorch shape query. NVIDIA renderer/UV modules are not imported. Exact source revisions, weight hash and provenance are in that project's `models/InstantMesh/provenance.json`.

A consistent analytic sphere was reconstructed through the real MPS backend and browser UI. Each view has its own editable mask; saved jobs retain all four images, hashes and camera assumptions. New GLBs include vertex normals. This proves a working multi-view input path, **not improved statue quality**. The current single-image workflow remains available.

The full CL3D multi-view checkpoint was not installed: its published license has territorial restrictions, and the user was asked about permission versus an alternative. No license grant is inferred from a public download.

## Checks

Latest Godot4.7.2 headless editor import and full smoke suite passed. See [checks.json](checks.json) (the full smoke log is retained locally as ignored `game-smoke.log`). This does not establish statue geometry quality.
