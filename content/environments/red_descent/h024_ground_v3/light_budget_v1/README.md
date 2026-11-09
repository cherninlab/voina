# Floor lighting boundary repair

The conspicuous straight light cut through the nave floor follows separate mesh light lists when too many practical omnis overlap. Removing baked colour, shadows, normal detail and specular did not remove it. Limiting the practical light set did. See controls-light-budget/ and the other retained controls.

The dungeon now selects at most six nearby torch lights, leaving allowance for fill and a player/review lamp. Energy fades to zero at the seventh-light distance, so exchanging ranks does not pop a whole floor patch. Distant flame meshes remain visible while their light pools are culled. These distant light pools are intentionally weaker/darker in the current views.

Matched actual-game views: before-inspection/ and after-inspection/; normal game lighting: after-game/. Both inspection sets use the neutral review lamp. Import, core smoke/local ENet and an 81-position native camera-motion regression pass. Largest energy change per5cm step: .3834. No geometry or collision assets changed in this increment. Shutdown leak warnings remain.

The attempted geometry-preserving local regrouping was insufficient and was not shipped as runtime behavior. Its source/test are retained in ../rejected-batching/. Natural wall/floor shapes and earth/mud/puddles are a separate work-in-progress increment.

Reproduce the light control via ../floor_controls.gd with --view=nave_5-forward --floor-modes=unbounded,baseline, always through scripts/godot_bg.sh.
