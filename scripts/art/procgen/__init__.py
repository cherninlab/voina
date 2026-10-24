"""Shared Blender toolkit for SECHA's procedural asset generators.

Run generators headless and reproducibly:

    blender --factory-startup -b --python-exit-code 1 --python scripts/art/<generator>.py -- <args>

Each generator starts with:

    import sys; from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from procgen import core, shapes, curves, bake, export

Modules:
    core    arguments, Blender version pin, empty scene, seeded RNG, Godot<->Blender axes, reports
    shapes  hewn timber and planks with metre UVs and per-piece colour attributes
    curves  catenary sag, chain links and rope tubes between two attachment points
    bake    ambient occlusion into a vertex colour channel (Godot Mobile has no SSAO), LODs
    export  GLB export with Godot collision suffixes and vertex colours

Conventions:
    Units are metres. Positions passed between Godot and Blender go through
    core.to_blender / core.to_godot. Colour attribute "Color": R = baked AO,
    G = per-piece variation, B = edge wear, A = 1. Owned by board task T-159:
    add new modules freely; change existing ones only after a note on T-159.
"""
