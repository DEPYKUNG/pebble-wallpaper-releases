
window.pebbleConfig = window.pebbleConfig || {};

function pebblePitch(pitch) {
    const degrees = window.pebbleConfig.tiltDegrees ?? 0;
    return pitch + degrees * Math.PI / 180;
}

window.pebbleFamilies = pebbleFamilies;

// Ported from the renderer's own colour helpers, so a pinned family yields
// stones built exactly the way the random ones are rather than look-alikes.
function pebbleRandom(seed) {
    return () => {
        let state = seed += 1831565813;
        state = Math.imul(state ^ state >>> 15, state | 1);
        state ^= state + Math.imul(state ^ state >>> 7, state | 61);
        return ((state ^ state >>> 14) >>> 0) / 4294967296;
    };
}

function hslHex(hue, saturation, light) {
    const chroma = (1 - Math.abs(2 * light - 1)) * saturation;
    const channel = offset => {
        const position = ((hue / 30 + offset) % 12 + 12) % 12;
        const value = light - chroma * .5 * Math.max(-1, Math.min(position - 3, 9 - position, 1));
        return Math.round(255 * value).toString(16).padStart(2, '0');
    };
    return '#' + channel(0) + channel(8) + channel(4);
}

function towards(value, amount) {
    return amount >= 0 ? value + (1 - value) * amount : value * (1 + amount);
}

// Every stone is a base colour plus a lighter and a darker facet, using the same
// contrast and hue shift the renderer applies to its own random palettes.
function familyPalette(family, seed) {
    const spec = pebbleFamilies[family];
    const next = pebbleRandom(seed + 90001);
    const chromatic = Boolean(spec.hue);
    const hue = chromatic ? (spec.hue[0] + (spec.hue[1] - spec.hue[0]) * next()) % 360 : 0;
    // Black, white and grey have to sit at zero saturation: the renderer's own
    // 12% floor would tint them and the hue shift would colour their facets.
    const saturation = chromatic ? .12 + .34 * next() : 0;
    const light = chromatic ? .45 + .28 * next()
        : spec.light[0] + (spec.light[1] - spec.light[0]) * next();
    const shift = chromatic ? 18 : 0;
    const contrast = .48;
    return [
        hslHex(hue, saturation, light),
        hslHex(hue + shift, saturation * (1 - .35 * contrast), towards(light, contrast)),
        hslHex(hue - shift, saturation * (1 - .18 * contrast), towards(light, -contrast * .9)),
    ];
}

// Falls back inline rather than calling the bundle's own helper, so this does
// not depend on a minified name surviving an upstream rebuild.
function pebblePaletteSeed() {
    const pinned = (window.pebbleConfig || {}).paletteSeed;
    return Number.isInteger(pinned) ? pinned : Math.floor(Math.random() * 2147483647);
}

function pebbleSeed() {
    const pinned = window.pebbleRestoring?.seed ?? window.pebbleConfig.seed;
    return Number.isInteger(pinned) ? pinned : Math.floor(Math.random() * 1e6);
}

// Called for the pebble raised on load and for every later one. An unrecognized
// name would quietly render as an untextured or randomly coloured stone, so
// only honour keys that are actually in the tables.
function applyPebbleConfig(pebble) {
    if (pebbleTextures.includes(window.pebbleConfig.texture)) {
        pebble.texture = window.pebbleConfig.texture;
    }
    const family = window.pebbleConfig.palette;
    if (pebbleFamilies[family]) pebble.colors = familyPalette(family, pebble.seed);
    if (window.pebbleRestoring) {
        pebble.texture = window.pebbleRestoring.texture;
        pebble.colors = window.pebbleRestoring.colors;
    }
    pebble.yaw = window.pebbleRestoring?.yaw ?? 0;
    pebble.pitch = window.pebbleRestoring?.pitch ?? pebble.pitch;
    // Exposed so the build self-check can prove the choices are honoured.
    window.pebbleTexture = pebble.texture;
    window.pebblePalette = pebbleFamilies[family] ? family : null;
    window.pebbleColors = pebble.colors;
    // The renderer gates its face on the fourth draw of this same PRNG, so
    // recovering it lets the build self-check tell which stones carry one.
    const roll = pebbleRandom(pebble.seed);
    roll(); roll(); roll();
    window.pebbleFaceRoll = roll();
}

// Render the existing pose at the output pixel density, then flatten the background.
function renderPebbleWallpaper(stone, atlas, width, height) {
    const output = document.createElement('canvas');
    output.width = width;
    output.height = height;
    const layer = document.createElement('canvas');
    layer.width = layer.height = Math.min(width, height);
    const renderer = Mg(layer, atlas);
    try {
        renderer.draw(stone);
        const context = output.getContext('2d');
        context.fillStyle = getComputedStyle(document.body).backgroundColor;
        context.fillRect(0, 0, output.width, output.height);
        const backdrop = window.pebbleBackdrop;
        if (backdrop?.complete && backdrop.naturalWidth) {
            const pattern = context.createPattern(backdrop, 'repeat');
            const scale = Math.min(width, height) / 1080;
            pattern.setTransform(new DOMMatrix().scale(scale));
            context.fillStyle = pattern;
            context.fillRect(0, 0, output.width, output.height);
        }
        const centerY = height * (height > width ? 0.56 : 0.5);
        context.drawImage(layer, (width - layer.width) / 2, Math.round(centerY - layer.height / 2));
        return output.toDataURL('image/png').split(',')[1];
    } finally {
        renderer.dispose();
        layer.width = layer.height = 1;
    }
}

function validPebble(stone) {
    return stone && (stone.schemaVersion === undefined || stone.schemaVersion === 1)
        && (stone.yaw === undefined || Number.isFinite(stone.yaw) && Math.abs(stone.yaw) <= 2*Math.PI)
        && (stone.pitch === undefined || Number.isFinite(stone.pitch) && Math.abs(stone.pitch) <= Math.PI/2)
        && Number.isInteger(stone.seed) && stone.seed >= 0 && stone.seed < 1e6
        && pebbleTextures.includes(stone.texture) && Array.isArray(stone.colors)
        && stone.colors.length === 3 && stone.colors.every(color => /^#[0-9a-f]{6}$/i.test(color))
        && ['', 'on', 'off'].includes(stone.faces);
}

function pebbleFaces() {
    return window.pebblePetFaces ?? window.pebbleHistory?.current?.faces ?? window.pebbleConfig.faces;
}

function snapshotPebble(pebble, faces = pebbleFaces() ?? '') {
    return {schemaVersion: 1, seed: pebble.seed, texture: pebble.texture,
        colors: [...pebble.colors], faces, yaw: pebble.yaw, pitch: pebble.pitch};
}

function rememberPebble(pebble, saved) {
    const restored = window.pebbleRestoring;
    window.pebbleRestoring = null;
    const history = window.pebbleHistory;
    if (!history) return;
    const current = snapshotPebble(pebble, restored?.faces ?? window.pebbleConfig.faces ?? '');
    if (saved !== history.current) history.previous = history.current || null;
    history.current = current;
    window.webkit.messageHandlers.pebbleHistory.postMessage(history);
}

// The desktop question is painted in the stone's own colour on the #eeeee7
// wallpaper. A white or pale stone would leave it invisible, so darken the
// text until it clears the WCAG 3:1 ratio for large graphics.

function relativeLuminance(rgb) {
    const [red, green, blue] = rgb.map(channel => {
        const ratio = channel / 255;
        return ratio <= .03928 ? ratio / 12.92 : Math.pow((ratio + .055) / 1.055, 2.4);
    });
    return .2126 * red + .7152 * green + .0722 * blue;
}

function contrastRatio(first, second) {
    const [brighter, darker] = [relativeLuminance(first), relativeLuminance(second)]
        .sort((a, b) => b - a);
    return (brighter + .05) / (darker + .05);
}

function readableTone(rgb) {
    const backdrop = getComputedStyle(document.body).backgroundColor.match(/[0-9]+/g).slice(0, 3).map(Number);
    const black = [0, 0, 0], white = [255, 255, 255];
    const endpoint = contrastRatio(white, backdrop) > contrastRatio(black, backdrop) ? 255 : 0;
    let tone = rgb;
    for (let step = 0; step < 32 && contrastRatio(tone, backdrop) < 4.5; step++) {
        tone = tone.map(channel => Math.round(channel + (endpoint - channel) * .2));
    }
    return tone;
}

function dominantPebbleColor(canvas) {
    const sample = document.createElement('canvas');
    sample.width = sample.height = 96;
    const context = sample.getContext('2d', {willReadFrequently: true});
    context.drawImage(canvas, 0, 0, sample.width, sample.height);
    const pixels = context.getImageData(0, 0, sample.width, sample.height).data;
    const bins = new Map();
    let dominant;
    for (let offset = 0; offset < pixels.length; offset += 4) {
        if (pixels[offset + 3] < 235) continue;
        const [red, green, blue] = pixels.subarray(offset, offset + 3);
        // Group neighboring shades so lighting variations do not split the main color.
        const key = ((red >> 5) << 6) | ((green >> 5) << 3) | (blue >> 5);
        const bin = bins.get(key) ?? {count: 0, red: 0, green: 0, blue: 0};
        bins.set(key, bin);
        bin.count++;
        bin.red += red;
        bin.green += green;
        bin.blue += blue;
        if (!dominant || bin.count > dominant.count) dominant = bin;
    }
    return dominant && [dominant.red, dominant.green, dominant.blue]
        .map(total => Math.round(total / dominant.count));
}

function updatePassTone(canvas) {
    const rgb = dominantPebbleColor(canvas);
    if (!rgb) return;
    document.documentElement.style.setProperty('--pass-tone', rgb.join(', '));
    document.getElementById('pass-stone').src = canvas.toDataURL();
}

function updateDesktopTone(canvas) {
    if (!document.documentElement.classList.contains('pebble-desktop')) return;
    const rgb = dominantPebbleColor(canvas);
    if (!rgb) return;
    const tone = readableTone(rgb);
    window.pebbleTone = (tone[0] << 16) | (tone[1] << 8) | tone[2];
    document.documentElement.style.setProperty('--pebble-tone', `rgb(${tone.join(', ')})`);
    window.webkit.messageHandlers.pebbleTone.postMessage(window.pebbleTone);
}

// One task may request several sprites before WebKit processes context-loss events.
// Reuse two scratch surfaces within that task, then release them at its boundary.
let petScratch = null;
function releasePebblePet() {
    if (!petScratch) return;
    const scratch = petScratch;
    petScratch = null;
    clearTimeout(scratch.releaseTimer);
    for (const canvas of [scratch.probe, scratch.layer]) {
        canvas.getContext('webgl')?.getExtension('WEBGL_lose_context')?.loseContext();
        canvas.width = canvas.height = 1;
    }
    scratch.readback.width = scratch.readback.height = 1;
}
window.pebbleReleasePet = releasePebblePet;

// Find a broad view rather than assuming yaw=0 faces the camera. This preserves
// the original shape, including stones that are naturally long and narrow.
function renderFavoritePet(stone, atlas) {
    const previous = window.pebbleRestoring;
    window.pebbleRestoring = stone;
    window.pebblePetFaces = stone.faces;
    try {
        const shape = Bg({family:"mixed", grain:.3, shading:.52, thickness:.48});
        return renderPebblePet({...shape, ...stone}, atlas);
    } finally {
        window.pebbleRestoring = previous;
        delete window.pebblePetFaces;
    }
}

function renderPebblePet(stone, atlas) {
    if (!petScratch) {
        const probe = document.createElement('canvas');
        probe.width = probe.height = 96;
        const readback = document.createElement('canvas');
        readback.width = readback.height = 96;
        const layer = document.createElement('canvas');
        layer.width = layer.height = 640;
        petScratch = {probe, readback, layer, releaseTimer: null};
    }
    const scratch = petScratch;
    clearTimeout(scratch.releaseTimer);
    const {probe, readback, layer} = scratch;
    const context = readback.getContext('2d', {willReadFrequently: true});
    let probeRenderer = null, renderer = null;
    let best = {yaw: 0, pitch: -.12}, score = -1;
    try {
        probeRenderer = Mg(probe, atlas);
        // Stay near the front: the painted eyes live on the front hemisphere.
        for (const yaw of [0, -.3, .3]) {
            for (const pitch of [-.12, 0, .2]) {
                probeRenderer.draw({...stone, yaw, pitch});
                context.clearRect(0, 0, 96, 96);
                context.drawImage(probe, 0, 0);
                const pixels = context.getImageData(0, 0, 96, 96).data;
                let coverage = 0;
                for (let i = 3; i < pixels.length; i += 4) coverage += pixels[i] / 255;
                const candidate = coverage * (1 - Math.abs(yaw) * .008);
                if (candidate > score) {score = candidate; best = {yaw, pitch};}
            }
        }
        probeRenderer.dispose(); probeRenderer = null;
        renderer = Mg(layer, atlas);
        renderer.draw({...stone, ...best});
        return layer.toDataURL('image/png').split(',')[1];
    } finally {
        probeRenderer?.dispose();
        renderer?.dispose();
        scratch.releaseTimer = setTimeout(() => {
            if (petScratch === scratch) releasePebblePet();
        }, 0);
    }
}
