"""Reuse the nave pack inspector; write bridge presets and metadata, never bitmap pixels."""
from pathlib import Path
import importlib.util
import hashlib
import json
import sys

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
prior = ROOT.parent / "red_nave_v1/review/prepare_pack.py"
spec = importlib.util.spec_from_file_location("nave_pack", prior)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
helper.ROOT = ROOT
CONFIG = {"bridge_oak": (0.4, 0.35, 0.9, 0.0), "mineral_plaster": (2.5, 0.32, 0.35, 0.08),
          "damp_masonry": (2.5, 0.60, 0.8, 0.16)}
BASE = "res://content/environments/bridge_well_v1/"


def wet_material(family, strength, wetness, algae):
    normal_name = "normal_dx.png" if family == "mineral_plaster" else "normal_gl.png"
    files = ["wet_surface.gdshader", family + "/albedo.png", family + "/" + normal_name, family + "/roughness.png",
             family + "/ao.png", "masks/wet_patches.png", "masks/algae_coverage.png", family + "/height.png"]
    lines = ['[gd_resource type="ShaderMaterial" load_steps=9 format=3]', ""]
    for index, path in enumerate(files, 1):
        kind = "Shader" if index == 1 else "Texture2D"
        lines.append(f'[ext_resource type="{kind}" path="{BASE + path}" id="{index}"]')
    lines += ["", "[resource]", f'resource_name = "Bridge Well / wet {family}"', 'shader = ExtResource("1")']
    for index, name in enumerate(("albedo_map", "normal_map", "roughness_map", "ao_map", "wet_map", "algae_map", "height_map"), 2):
        lines.append(f'shader_parameter/{name} = ExtResource("{index}")')
    lines += [f"shader_parameter/normal_strength = {strength}", f"shader_parameter/wetness = {wetness}", f"shader_parameter/algae_amount = {algae}"]
    return "\n".join(lines) + "\n"


def main():
    maps, families = [], []
    for family, (meters, strength, wetness, algae) in CONFIG.items():
        entries = {name: helper.inspect(ROOT / family / ("normal_dx.png" if name == "normal_gl" and family == "mineral_plaster" else name + ".png")) for name in helper.MAPS}
        assert len({tuple(v["size"]) for v in entries.values()}) == 1, family + ": dimensions differ"
        assert entries["normal_gl"]["channel_means"][2] > 170
        maps.extend(entries.values())
        preset = helper.material(family, strength).replace("red_nave_v1", "bridge_well_v1")
        if family == "mineral_plaster":
            preset = preset.replace("normal_gl.png", "normal_dx.png")
        (ROOT / family / "material.tres").write_text(preset)
        (ROOT / family / "wet_material.tres").write_text(wet_material(family, strength, wetness, algae))
        families.append({"id": family, "starting_tile_width_m": meters, "normal_scale": strength, "maps": entries,
                         "normal_diagnostic": helper.normal_diagnostic(family, ROOT / entries["normal_gl"]["path"]),
                         "import_flip_y": family == "mineral_plaster"})
    water_normal = "ripple_normal_dx" if (ROOT / "water/ripple_normal_dx.png").exists() else "ripple_normal_gl"
    for path in ("water/ripple_height.png", "water/" + water_normal + ".png", "water/foam_mask.png", "masks/wet_patches.png", "masks/algae_coverage.png"):
        maps.append(helper.inspect(ROOT / path))
    assert len(maps) == 20
    for entry in maps:
        path = ROOT / entry["path"]
        helper.configure_import(path)
        if path.stem in ("ripple_normal_gl", "ripple_normal_dx", "normal_dx") and Path(str(path) + ".import").exists():
            recipe = Path(str(path) + ".import")
            text = recipe.read_text().replace("compress/normal_map=2", "compress/normal_map=1")
            if path.stem.endswith("_dx"):
                text = text.replace("process/normal_map_invert_y=false", "process/normal_map_invert_y=true")
            recipe.write_text(text)
    water = ['[gd_resource type="ShaderMaterial" load_steps=5 format=3]', "",
             f'[ext_resource type="Shader" path="{BASE}water.gdshader" id="1"]']
    for index, name in enumerate((water_normal, "ripple_height", "foam_mask"), 2):
        water.append(f'[ext_resource type="Texture2D" path="{BASE}water/{name}.png" id="{index}"]')
    water += ["", "[resource]", 'resource_name = "Bridge Well / deep green water"', 'shader = ExtResource("1")',
              'shader_parameter/ripple_normal = ExtResource("2")', 'shader_parameter/ripple_height = ExtResource("3")',
              'shader_parameter/foam_map = ExtResource("4")']
    (ROOT / "water/material.tres").write_text("\n".join(water) + "\n")
    manifest = {"task": "T-149", "native_map_count": len(maps), "families": families, "maps": maps,
                "reuse": ["res://content/environments/red_nave_v1/oxidized_iron/material.tres", "res://content/environments/red_nave_v1/pale_limestone/material.tres"],
                "source_sha256": hashlib.sha256((ROOT / "review/selected_bridge.png").read_bytes()).hexdigest(),
                "normal_convention": "OpenGL X+ Y+ Z+ in engine; sources named _dx use import green inversion (plaster and water).", "scalar_convention": "Linear red channel; white high/rough/open/coverage respectively",
                "scan_fragments": json.loads((ROOT / "review/scan_fragments.json").read_text()),
                "limits": ["Generated scalar maps are approximations; fine detail is not an exact derivative.",
                           "Wet shader defaults to finite-difference normal from scalar height; native normal is an optional alternate.",
                           "Wet shader clamps dry roughness to0.68..0.95 before controlled damp blending.",
                           "Height maps do not supply structural geometry or collision.", "Water uses depth color, specular and animated normal/height; no SSR/refraction."]}
    (ROOT / "pack.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("BRIDGE_PACK_OK: 20 native maps, three dry and three wet materials, water material, two scan fragments")


if __name__ == "__main__":
    main()
