"""Reproducible adapter: public Tiled map geometry -> CC0 Kenney atlas."""
import json
import copy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = json.loads((ROOT / 'maps/platform.original.json').read_text())
width, height = source['width'], source['height']
original = source['layers'][0]['data']
# The source uses gid 1 for background. Other tiles include terrain and props.
# This fixture deliberately treats every non-background occupied cell as solid.
occupied = [gid not in (0, 1) for gid in original]
data = []
for i, solid in enumerate(occupied):
    surface = i < width or not occupied[i - width]
    data.append((46 if surface else 126) if solid else 0)

result = {
    'type': 'map', 'version': '1.10', 'orientation': 'orthogonal',
    'renderorder': 'right-down', 'infinite': False,
    'width': width, 'height': height, 'tilewidth': 16, 'tileheight': 16,
    'tilesets': [{'firstgid': 1, 'name': 'Kenney',
                  'image': '../assets/kenney_tiles.png',
                  'imagewidth': 320, 'imageheight': 320,
                  'tilewidth': 16, 'tileheight': 16,
                  'columns': 20, 'tilecount': 400, 'spacing': 0, 'margin': 0}],
    'layers': [
        {'type': 'tilelayer', 'name': 'Terrain', 'width': width, 'height': height,
         'properties': [{'name': 'solid', 'type': 'bool', 'value': True}],
         'data': data},
        {'type': 'objectgroup', 'name': 'Markers',
         'objects': [{'name': 'spawn', 'point': True, 'x': 56, 'y': 390}]},
    ],
}
target = ROOT / 'maps/platform.kenney.json'
target.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(f'{target.name}: {width}x{height}, {sum(occupied)} solid cells')

# A separate, controlled fixture demonstrates changing heights, gaps and layers.
# It is authored here; it is NOT claimed to come from the public map or music.
demo = copy.deepcopy(result)
dw, dh = 100, 24
demo.update(width=dw, height=dh)
ground = [0] * (dw * dh)
profile = [19, 19, 18, 17, 17, 19, 18, 16, 17, 19]
gaps = {23, 24, 48, 49, 73, 74}
for x in range(dw):
    if x in gaps:
        continue
    top = profile[x // 10]
    for y in range(top, dh):
        ground[y * dw + x] = 46 if y == top else 126
demo['layers'][0].update(width=dw, height=dh, data=ground)
demo['layers'][1]['objects'][0].update(x=56, y=280)
floating = [0] * (dw * dh)
for start, y in [(14, 14), (35, 13), (56, 14), (81, 13)]:
    for x in range(start, start + 5):
        floating[y * dw + x] = 46
demo['layers'].insert(1, {
    'type': 'tilelayer', 'name': 'Floating platforms', 'width': dw, 'height': dh,
    'data': floating,
    'properties': [{'name': 'solid', 'type': 'bool', 'value': True}],
})
(ROOT / 'maps/demo.json').write_text(json.dumps(demo, indent=2) + '\n', encoding='utf-8')
print('demo.json: controlled steps, gaps and floating platforms')
