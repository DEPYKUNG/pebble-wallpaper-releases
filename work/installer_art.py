from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFilter


def build_icon(source, resources, scratch):
    iconset = scratch / 'Pebble.iconset'
    iconset.mkdir(exist_ok=True)
    with Image.open(source) as original:
        assert original.mode == 'RGBA' and original.width == original.height
        for size in (16, 32, 128, 256, 512):
            for scale, suffix in ((1, ''), (2, '@2x')):
                pixels = size * scale
                image = original.resize((pixels, pixels), Image.Resampling.LANCZOS)
                image.save(iconset / f'icon_{size}x{size}{suffix}.png')
    icon = resources / 'Pebble.icns'
    subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(icon)], check=True)
    return icon


def render_stones(original, work, scratch):
    marker = 'Eg.createRoot(document.getElementById("root"))'
    assert original.count(marker) == 1
    helpers = original.split(marker)[0]
    (scratch / 'render-stones.js').write_text(helpers + '''
const atlas = new Image();
atlas.src = Xg;
await atlas.decode();
const canvas = document.createElement('canvas');
canvas.width = canvas.height = 512;
const renderer = Mg(canvas, atlas);
const palettes = qg(Hg());
const images = Array.from({length: 4}, (_, index) => {
    const pebble = Bg({family: "mixed", grain: .3, shading: .52, thickness: .48});
    pebble.colors = palettes[Cg(pebble.seed, palettes.length)];
    pebble.yaw = (1.25 + index * .17);
    renderer.draw(pebble);
    return canvas.toDataURL().split(',')[1];
});
renderer.dispose();
return images;
''')
    renderer = scratch / 'RenderStones'
    subprocess.run(['clang', '-fobjc-arc', '-fblocks', '-framework', 'AppKit',
                    '-framework', 'WebKit', str(work / 'render-stones.m'),
                    '-o', str(renderer)], check=True)
    subprocess.run([str(renderer), str(scratch)], check=True, timeout=30)


def make_background(scratch, stone_assets, width, height):
    scale = 2
    background = Image.new('RGBA', (width * scale, height * scale), '#f5f4ef')
    for index, (x, y, size, angle) in enumerate((
        (510, 106, 57, 16),
        (676, 104, 69, -10),
        (676, 355, 57, 16),
    )):
        with Image.open(stone_assets / f'stone-{index}.png') as original:
            bounds = original.getchannel('A').getbbox()
            if not bounds:
                raise ValueError(f'Decorative stone {index} did not render')
            stone = original.crop(bounds)
        stone.thumbnail((size * scale, size * scale), Image.Resampling.LANCZOS)
        stone = stone.rotate(angle, Image.Resampling.BICUBIC, expand=True)
        origin = (round(x * scale - stone.width / 2), round(y * scale - stone.height / 2))
        mask = Image.new('L', background.size)
        mask.paste(stone.getchannel('A').point(lambda value: round(value * .15)),
                   (origin[0], origin[1] + 4 * scale))
        shadow = Image.new('RGBA', background.size, '#524a42')
        shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(4 * scale)))
        background.alpha_composite(shadow)
        background.alpha_composite(stone, origin)

    draw = ImageDraw.Draw(background)
    for start, end in (((357, 223), (401, 223)), ((391, 213), (401, 223)), ((391, 233), (401, 223))):
        points = [tuple(value * scale for value in point) for point in (start, end)]
        draw.line(points, fill='#8a8279', width=5)
        for x, y in points:
            draw.ellipse((x-2, y-2, x+2, y+2), fill='#8a8279')

    high_resolution = scratch / 'background@2x.png'
    standard = scratch / 'background.png'
    background.save(high_resolution)
    background.resize((width, height), Image.Resampling.LANCZOS).save(standard)
    result = scratch / 'background.tiff'
    subprocess.run(['tiffutil', '-cathidpicheck', str(standard), str(high_resolution),
                    '-out', str(result)], check=True)
    return result
