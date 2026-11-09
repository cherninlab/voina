# Current cave and root-tunnel review

[Open the actual-game gallery](review.html). There are 18 normal-lighting frames and 18 matching inspection frames. Inspection adds a neutral camera lamp; it is not the normal game lighting. [Inspection overview 1](inspection-sheet-1.jpg) · [overview 2](inspection-sheet-2.jpg).

## Changed

The complete excavated cavity now supplies the rock surface. The older independent thin rock shell omitted some corner webs, while a separately tessellated backing could cross through it after relief. Those exposed backing fragments and their shadows caused the ugly overlays and large dark patches. Backing now derives from the final rock topology and sits 5.5 cm inside the solid. Run and bay share one ownership boundary, with a short relief fade at the join, rather than overlapping independently displaced faces.

Excavation is actual mesh displacement with <=.55 m sampling and <=.33 m maximum displacement; the floor edge stays fixed. Shared join collars remain constrained. The root exit's turning chamber and full-depth bridge-facing masonry arch are retained. The separate nave support now has actual underside wedge stones: [landing evidence](../landing-intrados/README.md).

## Evidence and limits

The rejected thin-shell attempt, its unshaded hole control, an intermediate seam/sliver attempt and the earlier exposed-backing view are retained in `iterations/`. They were not shipped as final repairs. Reusing one inspection light across camera teleports also produced a dark face absent in a fresh single-view capture. The helper now recreates that diagnostic lamp per view; both results are retained. This changes the review helper only. We have not established a general engine root cause for its lighting state.

Verified before shipment: editor import; core smoke/local ENet; 1,234 m native capsule traversal; construction audit (23 bearings, 184 members, four cloth pins); all 22 unchanged crawler detector controls; generator colour, cavity, backing and join-collar regressions; all 25 mesh exports finite/no validation repair; native root void/door/floor queries; five nearby render wall/roof rays plus one end-arch control. The four T-196 roof rays and E0330 control all hit geometry again. Raw `.txt` logs and `roof/probe.json` are alongside this report. This reruns the crawler controls, not its full spatial survey.

Thirty-one protected room/stair/wall/vascular GLBs remain byte-identical (`protected-assets.json`). Nine dependent passage growth outputs were regenerated. Their current audit reports zero vertices inside the walking corridor, two deeper than 1 cm into stone, and a maximum sampled attachment gap of .0536 m (`growth-qa.json`). Those two penetrations remain a small attachment cleanup item.

Fine seams, abrupt material/threshold changes, wet highlights and weak lighting/dressing still need visual review. The broad H-023 bridge and H-026 shaft redesigns are not accepted by this repair. Shutdown ObjectDB/Texture RID warnings remain. No manual input, two-Mac or performance acceptance is claimed. H-024 remains under review; this is a verified repair increment, not whole-builder acceptance.
