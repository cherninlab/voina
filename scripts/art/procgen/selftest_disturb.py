"""Calibrates disturb.py on a small deck: two beams, nailed boards, posts on
hinges, a pinned handrail. Intensity 0 must leave everything as built; more
intensity must loosen more.

blender --factory-startup -b --python-exit-code 1 --python scripts/art/procgen/selftest_disturb.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import bpy
from mathutils import Vector

from procgen import core, disturb, rigid, shapes

UP = Vector((0, 0, 1))


def piece(name, build, frame=None):
    builder = shapes.Builder(name)
    build(builder)
    obj = builder.to_object()
    if frame is None:
        disturb.centre(obj)
    else:
        disturb.orient(obj, *frame)
    return obj


def deck(seed: int, intensity: float, weak_share: float, ball: bool) -> dict:
    core.empty_scene()
    disturb.reset()
    rigid.world(frame_end=600, substeps=10, iterations=20)
    rng = core.rng(seed, 'deck', intensity)
    beams = [piece(f'Beam{k}', lambda b, y=y: shapes.timber(b, Vector((-0.2, y, -0.26)), Vector((6.2, y, -0.26)), 0.22, 0.4, UP, rng),
                   (Vector((-0.2, y, -0.26)), Vector((6.2, y, -0.26)), UP))
             for k, y in enumerate((-1.3, 1.3))]
    for beam in beams:
        rigid.body(beam, passive=True, shape='BOX')
    # Pieces knocked off fall onto a catch floor and count as fallen.
    catch = piece('Catch', lambda b: shapes.prism(b, Vector((3.0, -6.0, -4.0)), Vector((3.0, 6.0, -4.0)), 14.0, 0.2, UP, rng))
    rigid.body(catch, passive=True, shape='BOX')
    disturb.kinematic(beams)
    boards = []
    for k in range(20):
        x = 0.15 + k * 0.3
        board = piece(f'Board{k}', lambda b, x=x: shapes.plank(b, Vector((x, -1.45, -0.03)), Vector((x, 1.45, -0.03)), 0.28, 0.06, UP, rng),
                      (Vector((x, -1.45, -0.03)), Vector((x, 1.45, -0.03)), UP))
        rigid.body(board, mass=rigid.mass(board, 700.0), friction=0.9, shape='BOX')
        for y in (-1.3, 1.3):
            disturb.nail(board, beams[0 if y < 0 else 1], Vector((x, y, -0.06)), disturb.strength(rng, weak_share, board))
        boards.append(board)
    posts = []
    for k, x in enumerate((0.0, 2.0, 4.0, 6.0)):
        post = piece(f'Post{k}', lambda b, x=x: shapes.timber(b, Vector((x, 1.55, -0.5)), Vector((x, 1.55, 1.14)), 0.16, 0.16, Vector((0, 1, 0)), rng),
                     (Vector((x, 1.55, -0.5)), Vector((x, 1.55, 1.14)), Vector((0, 1, 0))))
        rigid.body(post, mass=rigid.mass(post, 700.0), shape='BOX')
        disturb.hinge(post, beams[1], Vector((x, 1.55, -0.46)), Vector((1, 0, 0)), (-0.05, 0.17))
        disturb.nail(post, beams[1], Vector((x, 1.55, -0.2)), disturb.strength(rng, weak_share, post))
        posts.append(post)
    rails = []
    for k in range(3):
        a, b = Vector((k * 2.0, 1.55, 1.06)), Vector((k * 2.0 + 2.0, 1.55, 1.06))
        rail = piece(f'Rail{k}', lambda bl, a=a, b=b: shapes.timber(bl, a, b, 0.13, 0.09, UP, rng), (a, b, UP))
        rigid.body(rail, mass=rigid.mass(rail, 700.0), shape='BOX')
        for end, post in ((a, posts[k]), (b, posts[k + 1])):
            disturb.pin(rail, post, end, disturb.strength(rng, weak_share * 0.5, rail, (6.0, 20.0)))
            disturb.nail(rail, post, end, disturb.strength(rng, weak_share, rail), collide=False)
        rails.append(rail)
    movers = boards + posts + rails
    rest = disturb.rest_pose(movers)
    shaken = disturb.shake(beams, rng, intensity) if intensity > 0 else None
    if ball:
        disturb.roll(Vector((-0.3, 0.6, 0.3)), Vector((3.5, 0, 0)))
    settled = rigid.settle(movers, min_frames=disturb.quiet_frame(), max_frames=600)
    moved = disturb.displacements(movers, rest)
    loose = [n for n, (d, a) in moved.items() if n.startswith('Board') and (d > 0.005 or a > 1.0)]
    fallen = [b.name for b in boards if b.matrix_world.translation.z < -1.0]
    if fallen:
        print('DISTURB_FALLEN', fallen, [tuple(round(c, 2) for c in bpy.data.objects[n].matrix_world.translation) for n in fallen], flush=True)
    leaning = [n for n, (d, a) in moved.items() if n.startswith('Post') and a > 2.0]
    broken = [n for n, (d, a) in moved.items() if n.startswith('Rail') and d > 0.05]
    return {'seed': seed, 'intensity': intensity, 'ball': ball, 'loose_boards': len(loose), 'fallen': len(fallen), 'leaning_posts': len(leaning),
            'broken_rails': len(broken), 'max_board_move_m': round(max(moved[b.name][0] for b in boards), 4),
            'max_post_lean_deg': round(max(moved[p.name][1] for p in posts), 2), 'settled': settled['settled'],
            'frames': settled['frame'], 'shake': shaken}


results = []
for seed in (1, 2):
    for intensity, ball in ((0.0, False), (0.5, False), (1.0, False), (1.0, True), (2.0, False)):
        result = deck(seed, intensity, 0.2, ball)
        results.append(result)
        print('DISTURB_TRY', json.dumps({k: v for k, v in result.items() if k != 'shake'}), flush=True)
calm = [r for r in results if r['intensity'] == 0 and not r['ball']]
assert all(r['loose_boards'] == 0 and r['leaning_posts'] == 0 and r['broken_rails'] == 0 for r in calm), calm
strong = [r for r in results if r['intensity'] >= 1.0]
assert sum(r['loose_boards'] for r in strong) > 0, 'strong tremors should loosen weak nails'
print('DISTURB_SELFTEST_OK', flush=True)
