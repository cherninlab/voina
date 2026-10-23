"""Inspect native PNGs and write Godot presets/metadata. Never edits bitmap pixels."""
from pathlib import Path
import hashlib
import json
import math
import re
from PIL import Image, ImageChops, ImageFilter, ImageStat

ROOT = Path(__file__).resolve().parents[1]
CONFIG = {
    "red_lime_plaster": (2.5, 0.45, "Matte iron-oxide red lime plaster, shallow fissures and small spalls"),
    "rubble_masonry": (2.5, 0.75, "Dark exposed structural rubble and recessed mortar"),
    "pale_limestone": (1.0, 0.35, "Pale limestone arch stones and exposed mineral substrate"),
    "broken_stone_floor": (3.0, 0.60, "Worn irregular floor slabs, grit-filled joints"),
    "aged_oak": (2.5, 0.45, "Dark hand-hewn structural timber; grain follows texture V"),
    "oxidized_iron": (0.5, 0.40, "Forged torch hardware with sparse rust and worn metal"),
}
MAPS = ("albedo", "height", "normal_gl", "roughness", "ao")


def inspect(path):
    with Image.open(path) as source:
        source.load()
        rgb = source.convert("RGB")
        stats = ImageStat.Stat(rgb)
        width, height = rgb.size
        # Edge jump is diagnostic, not a certificate of seamless tiling.
        horizontal = ImageChops.difference(rgb.crop((0, 0, 1, height)), rgb.crop((width - 1, 0, width, height)))
        vertical = ImageChops.difference(rgb.crop((0, 0, width, 1)), rgb.crop((0, height - 1, width, height)))
        red, green, blue = rgb.split()
        color_difference = max(ImageChops.difference(red, green).getextrema()[1], ImageChops.difference(green, blue).getextrema()[1])
        return {
            "path": path.relative_to(ROOT).as_posix(),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "bytes": path.stat().st_size,
            "size": list(rgb.size),
            "source_mode": source.mode,
            "channel_means": [round(value, 2) for value in stats.mean],
            "channel_extrema": stats.extrema,
            "max_rgb_channel_difference": color_difference,
            "opposite_edge_mean_difference_255": {
                "u": round(sum(ImageStat.Stat(horizontal).mean) / 3, 2),
                "v": round(sum(ImageStat.Stat(vertical).mean) / 3, 2),
            },
        }


def material(family, normal_scale):
    maps = list(MAPS) + (["metallic"] if family == "oxidized_iron" else [])
    lines = [f'[gd_resource type="StandardMaterial3D" load_steps={len(maps) + 1} format=3]', ""]
    for slot, name in enumerate(maps, 1):
        lines.append(f'[ext_resource type="Texture2D" path="res://content/environments/red_nave_v1/{family}/{name}.png" id="{slot}"]')
    slots = {name: slot for slot, name in enumerate(maps, 1)}
    lines += ["", "[resource]", f'resource_name = "Red Nave / {family.replace("_", " ")}"',
              'albedo_texture = ExtResource("1")', "roughness = 1.0",
              f'roughness_texture = ExtResource("{slots["roughness"]}")', "roughness_texture_channel = 0",
              "normal_enabled = true", f"normal_scale = {normal_scale}",
              f'normal_texture = ExtResource("{slots["normal_gl"]}")',
              "ao_enabled = true", "ao_light_affect = 0.0", f'ao_texture = ExtResource("{slots["ao"]}")',
              "ao_texture_channel = 0", "heightmap_enabled = false", "heightmap_scale = 1.0",
              f'heightmap_texture = ExtResource("{slots["height"]}")']
    if "metallic" in slots:
        lines += ["metallic = 1.0", f'metallic_texture = ExtResource("{slots["metallic"]}")', "metallic_texture_channel = 0"]
    return "\n".join(lines) + "\n"


def normal_diagnostic(family, normal_path=None):
    """Sample slope sign/correspondence. A positive score is not proof of exact registration."""
    with Image.open(ROOT / family / "height.png") as image:
        height = image.convert("L").filter(ImageFilter.GaussianBlur(2))
    with Image.open(normal_path or ROOT / family / "normal_gl.png") as image:
        normal = image.convert("RGB")
    hp, np = height.load(), normal.load()
    xs, ys, lengths = [], [], []
    for y in range(3, height.height - 3, 4):
        for x in range(3, height.width - 3, 4):
            r, g, b = np[x, y]
            nx, ny, nz = r / 127.5 - 1, g / 127.5 - 1, b / 127.5 - 1
            xs.append((hp[x - 1, y] - hp[x + 1, y], nx))
            ys.append((hp[x, y + 1] - hp[x, y - 1], ny))
            lengths.append(math.sqrt(nx * nx + ny * ny + nz * nz))

    def correlation(pairs):
        count = len(pairs)
        sx, sy = sum(x for x, y in pairs), sum(y for x, y in pairs)
        denominator = (count * sum(x * x for x, y in pairs) - sx * sx) * (count * sum(y * y for x, y in pairs) - sy * sy)
        return round((count * sum(x * y for x, y in pairs) - sx * sy) / math.sqrt(denominator), 3) if denominator > 0 else None

    mean = sum(lengths) / len(lengths)
    return {"height_slope_correlation_x_y": [correlation(xs), correlation(ys)],
            "normal_vector_length_mean": round(mean, 3),
            "normal_vector_length_std": round(math.sqrt(sum((v - mean) ** 2 for v in lengths) / len(lengths)), 3),
            "method": "Stride4 sample; height Gaussian radius2; X=-dH/dU, Y=+dH/d(image V). Diagnostic only."}


def configure_import(path):
    """Keep native PNGs intact; configure Godot's generated import recipe when present."""
    recipe = Path(str(path) + ".import")
    if not recipe.exists():
        return
    original = recipe.read_text()
    source = original
    settings = {"compress/mode": "0", "compress/normal_map": "1" if path.stem == "normal_gl" else "2",
                "mipmaps/generate": "true", "process/normal_map_invert_y": "false", "detect_3d/compress_to": "0"}
    for key, value in settings.items():
        source = re.sub(r"^" + re.escape(key) + r"=.*$", key + "=" + value, source, flags=re.MULTILINE)
    if source != original:
        recipe.write_text(source)


def main():
    families = []
    all_maps = []
    for family, (meters, strength, description) in CONFIG.items():
        entries = {}
        for name in MAPS + (("metallic",) if family == "oxidized_iron" else ()):
            entry = inspect(ROOT / family / (name + ".png"))
            entries[name] = entry
            all_maps.append(entry)
        assert len({tuple(entry["size"]) for entry in entries.values()}) == 1, family + ": map dimension mismatch"
        assert all(entry["size"][0] == entry["size"][1] for entry in entries.values()), family + ": non-square texture"
        assert entries["normal_gl"]["channel_means"][2] > 170, family + ": invalid normal-map blue channel"
        for name in ("height", "roughness", "ao", "metallic"):
            if name in entries:
                means = entries[name]["channel_means"]
                assert max(means) - min(means) < 2 and entries[name]["max_rgb_channel_difference"] < 24, family + ": color cast in scalar map " + name
        (ROOT / family / "material.tres").write_text(material(family, strength))
        families.append({"id": family, "description": description, "starting_tile_width_m": meters,
                         "normal_scale": strength, "maps": entries, "normal_diagnostic": normal_diagnostic(family)})
    masks = [inspect(ROOT / "masks" / (name + ".png")) for name in ("plaster_peel", "damp_grime")]
    assert all(max(entry["channel_means"]) - min(entry["channel_means"]) < 2 and entry["max_rgb_channel_difference"] < 24 for entry in masks), "color cast in mask"
    all_maps += masks
    assert len(all_maps) == 33
    for entry in all_maps:
        configure_import(ROOT / entry["path"])
    manifest = {"version": 1, "task": "T-148", "generation": "Built-in ImageGen; exact prompts and ordered inputs in review/*_generation.json",
                "source": "review/selected_nave.png", "source_sha256": hashlib.sha256((ROOT / "review/selected_nave.png").read_bytes()).hexdigest(),
                "source_provenance": "Pixel-identical to the built-in generated quality_studies_v2/03-red-plaster-nave.png selected by the user.",
                "map_count": len(all_maps), "families": families, "masks": masks,
                "conventions": {"normal": "OpenGL tangent-space X+ Y+ Z+", "height": "white high; black recessed; 8-bit native source",
                                "roughness": "white rough; black smooth", "ao": "white open; black occluded",
                                "metallic": "white exposed metal; black rust/oxide", "masks": "white coverage; black no coverage"},
                "limitations": ["Native generated map correspondences are inspected, not a mathematically derived scan.",
                                "Tile borders are not certified seamless; use repeat preview and hide remaining seams with material blending.",
                                "Height/parallax does not fix geometry or collision. Presets leave parallax disabled."]}
    (ROOT / "pack.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"NAVE_PACK_OK: {len(all_maps)} PNG maps; six Godot materials; sizes {sorted({tuple(entry['size']) for entry in all_maps})}")


if __name__ == "__main__":
    main()
