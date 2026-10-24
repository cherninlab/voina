shader_type spatial;
// Modules crossing a room outline: discards fragments outside the convex clip planes.
#define CLIP
#include "res://content/environments/procedural_flagstone_v1/flagstone.gdshaderinc"
