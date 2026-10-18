# MPEG datamosh

T-059 adds an MPEG-style compression post effect, ported from VANSCANS (`js/vfx/mpeg/`). The 3D frame really goes through an encoder and decoder on the GPU every frame: YCbCr 4:2:0, 8×8 DCT with the JPEG quantization tables, motion-compensated P-frames on 16×16 macroblocks and a GOP with I-frames. The blocking, ringing and smearing come from that maths, not from a filter imitating it.

Datamosh is what the codec does when I-frames are skipped and the residual (the decoder's correction) is starved: the old picture keeps being moved by the new motion vectors and is never fully repaired.

It is local presentation only. Nothing is networked, and each machine's settings are its own.

## Controls

| Key | Action |
| --- | --- |
| F8 | Effect on/off (on by default; the choice persists) |
| F7 | Cycle debug views: Y, Cb/Cr, motion vectors, residual, I/P |
| F6 | Manual mosh burst |

Esc → the pause screen shows **MPEG tweaks** (top right), beside the sword tweaks. Every value below is live and persists in `user://mpeg_tweaks.cfg`. **Defaults** restores the shipped values; **Print values** logs `MPEG_TWEAKS name=value …` for updating them.

`--datamosh` on the command line forces the effect on; `--datamosh-view=N` starts in a debug view.

## Triggers

- **Cutting a raider in half** moshes: both halves fly apart dragging the old picture with them. `HostileMob.bisected` runs on every peer and spawns two `RaiderHalf` nodes into the scene; `ui/datamosh.gd` watches `SceneTree.node_added` for them, so the mob code is untouched. Only bisects within **Bisect range** of the camera count.
- **Dash** smears briefly.
- **Respawn** (the local player moving more than 3 m in one frame) is the classic transition mosh: the cut's I-frame is skipped, so the old view is dragged around by the new one's motion.
- Regular hits do not mosh. An earlier version also dropped the codec resolution on hits; changing resolution reallocates the codec buffers and forces I-frames, which wiped the mosh, so it was removed.

After a burst the residual gain eases back over **Release** (slowly at first) with I-frames still off, so the smear is painted over rather than cut. The GOP count restarts afterwards so no I-frame pops the moment the release ends.

## Settings

| Setting | Default | Meaning |
| --- | --- | --- |
| Effect on | on | The whole effect. Off costs nothing. |
| Datamosh always | off | Never send scheduled I-frames. With a low residual gain the picture smears permanently. |
| Mosh through camera cuts | off | Camera switches and teleports skip their clean I-frame. |
| Gameplay triggers | on | Bisect, dash and respawn bursts. F6 works either way. |
| Resolution | 0.5 | Codec size as a share of the 3D frame, padded to whole macroblocks. Lower is chunkier and cheaper. |
| Quality | 92 | libjpeg-style 1 (mush) … 100 (quantizer off). |
| GOP length | 100 | An I-frame every N frames; 1 = intra only (no smear ever). |
| Residual gain | 0.69 | P-frame correction: 1 = correct picture, towards 0 the old picture smears behind motion. |
| Motion error | 0 | Share of macroblocks with a neighbour's or jittered vector: tearing blocks. |
| Release (ms) | 350 | Ease-back after any burst. |
| Manual burst (ms) / gain | 500 / 0.1 | F6. |
| Bisect burst (ms) / gain | 210 / 0.08 | Gain is the residual during the burst: lower is harder. |
| Bisect range (m) | 17 | Bisects further from the camera are ignored. |
| Dash burst (ms) / gain | 450 / 0.15 | |
| Respawn burst (ms) / gain | 700 / 0.04 | |

The defaults are Mike's playtest tuning (2026-10-18).

## How it works

`ui/datamosh_effect.gd` is a `CompositorEffect` attached to whichever `Camera3D` is current, at `EFFECT_CALLBACK_TYPE_POST_TRANSPARENT`: after the scene, before tonemapping, glow, the fisheye and the HUD, so the HUD stays sharp. `ui/datamosh.gd` owns the policy (when to mosh); the effect owns the GPU work and the I/P decision for the frame actually being rendered. Four compute passes, all in `ui/datamosh/`:

1. `ycbcr.glsl`: the linear HDR scene colour is squashed by an invertible curve, `(c / (1 + c))^(1/2.2)`, so the quantizer works on a perceptual signal like gamma-coded video, then converted to BT.601 YCbCr in 8-bit units with 4:2:0 chroma at the internal resolution.
2. `motion.glsl`: one vector per 16×16 macroblock. The search is seeded with the camera motion (the block centre's depth reprojected through last frame's view-projection), then a block-matching search (luma SAD against last frame's source, coarse ±8 then fine ±2 pixels) finds what moved on its own: players, raiders, swords.
3. `block.glsl`: one workgroup per 8×8 block does prediction, residual × gain, forward DCT, quantization, inverse DCT and reconstruction in shared memory, in one dispatch. The output is the next frame's reference.
4. `display.glsl`: nearest upscale (blocks stay hard), undoes the curve and writes the frame.

The Mobile renderer stores scene colour as RGB10A2 at half scale (luminance multiplier 2) and the texture has no storage usage, so the display pass writes an intermediate texture of the same format and `texture_copy` puts it over the colour. Both RGB10A2 and RGBA16F colour buffers are supported through shader versions.

Differences from VANSCANS: one compute dispatch per stage instead of fragment passes (the whole 2D DCT is one pass); motion comes from depth reprojection plus a real block search instead of a separate velocity render of moving objects; integer-pixel vectors; the HDR curve above instead of compressing the tone-mapped picture.

## Checks

```sh
"$GODOT" --headless --editor --path . --quit
"$GODOT" --path . --resolution 1152x720 --script scripts/capture_datamosh.gd -- --host --pve --port=7795 --capture-dir=/absolute/output
```

The capture needs a real window (compute does not run headless). It checks that the codec runs on the GPU, that quality 100 at full resolution reproduces the plain frame (mean absolute difference 0.0037 per channel measured on an Apple Silicon Mac), that a real raider bisect starts a mosh, and saves the default look, quality 4, each debug view while turning, a manual burst, the bisect mosh and a respawn mosh. Headless test runs skip the effect entirely.

Not measured: GPU cost per frame on the two target Macs, and how the effect feels over a full match. Frame-time measurement remains a human check.
