# Ashen village presentation

Original SECHA procedural storm-sky shader, lantern/window geometry and material adjustments authored for this project. Reference: user-selected generated dark village target (exec-460bd294-6151-4821-a87c-07a2b74db253.png), plus user-supplied Diablo/Path of Exile and dark-fantasy lighting screenshots. Screenshots are inspiration only and are not shipped.

No new external texture assets: structural timber now uses the existing Valhalla WoodPlanksFlat basecolor, matching tangent normal and roughness maps. Ground keeps existing generated soil/mineral albedos and Valhalla stone/grass PBR maps; their provenance remains in the original asset directories. No normal maps are inferred from baked colour or light. Imported prop maps are retained with roughness floors and restrained material tint. The procedural storm sky replaces the daylight panorama at runtime, without altering its source asset. Cosmetic lamps/windows and distant red sheet lightning have no collision, damage or networking state.

## Storm panorama

`storm_sky.png` is an original AI-generated LDR appearance panorama made with the built-in ImageGen tool for this project on 2026-10-19. It is not a calibrated HDR lighting capture. No source screenshot pixels or game assets were copied. The runtime shader softens the wrap/pole transition and adds slow drift plus localized red cloud illumination.

Generation prompt: Generate a texture asset: seamless 2:1 equirectangular 360 degree panorama of a dark overcast northern storm sky for a realistic grim medieval action game. ONLY CLOUDS AND SKY, no land, no mountains, no trees, no sun disk, no buildings or text. Heavy layered charcoal blue-grey rainclouds overhead, subtle silver grey diffuse light through thinner patches, low horizon fades into desaturated grey teal haze. Natural photographic cloud structures, dramatic but subdued, full colour depth, no painting brushwork. Zenith at top, horizon at middle, below horizon continues grey haze. Matching left/right seam. Sky should be visibly darker than daytime overcast, reference Diablo dark fantasy atmosphere. No lightning baked into texture.
