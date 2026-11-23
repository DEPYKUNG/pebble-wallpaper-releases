import argparse
from base64 import b64decode
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
from unittest.mock import patch
from urllib.parse import urlsplit

import dmgbuild
from PIL import Image

from installer_art import build_icon, make_background
from changelog import recent_releases
from renderer_build import build_renderer, RendererBuildError


def run(*command, timeout=90):
    subprocess.run(command, check=True, timeout=timeout)


work = Path(__file__).resolve().parent
release_config = work / 'update-release.json'
release_defaults = json.loads(release_config.read_text()) if release_config.exists() else {}
parser = argparse.ArgumentParser()
parser.add_argument('--update-feed', default=release_defaults.get('feed'))
parser.add_argument('--update-key', default=release_defaults.get('public_key'))
parser.add_argument('--version', default=release_defaults.get('version', '1.5'))
parser.add_argument('--build', default=release_defaults.get('build', '6'))
parser.add_argument('--staging', type=Path, default=work.parent / 'build')
parser.add_argument('--installer-output', type=Path)
parser.add_argument('--app-only', action='store_true')
parser.add_argument('--local-update-test', action='store_true')
parser.add_argument('--test-identifier', default='app.painted-pebble.wallpaper.updatetest')
args = parser.parse_args()

if bool(args.update_feed) != bool(args.update_key):
    parser.error('--update-feed and --update-key must be specified together')
if args.update_feed:
    feed = urlsplit(args.update_feed)
    valid_https = feed.scheme == 'https' and feed.hostname and not feed.username
    valid_loopback = (args.local_update_test and feed.scheme == 'http'
                      and feed.hostname in {'localhost', '127.0.0.1'})
    if not (valid_https or valid_loopback):
        parser.error('The update feed must use HTTPS, except for a loopback test')
    if not re.fullmatch(r'[A-Za-z0-9+/]{43}=', args.update_key) or len(b64decode(args.update_key)) != 32:
        parser.error('--update-key must be a base64-encoded Sparkle public key')
if not re.fullmatch(r'\d+(?:\.\d+){1,2}', args.version) or not re.fullmatch(r'[1-9]\d*', args.build):
    parser.error('Use a dotted release version and a positive integer build number')
if args.local_update_test and not (args.app_only and args.update_feed):
    parser.error('--local-update-test requires --app-only and an update feed')

if args.local_update_test and not re.fullmatch(r'app\.painted-pebble\.[a-z0-9.]+\.updatetest', args.test_identifier):
    parser.error('Invalid isolated test bundle identifier')

output = work.parent / 'outputs'
output.mkdir(exist_ok=True)
staging = args.staging.resolve()
staging.mkdir(parents=True, exist_ok=True)
app = staging / 'Pebble Wallpaper.app'
contents = app / 'Contents'
resources = contents / 'Resources'
resources.mkdir(parents=True, exist_ok=True)
try:
    notes = recent_releases(json.loads((work / 'changelog.json').read_text()), args.version, args.build,
                            local_test=args.local_update_test)
except ValueError as error:
    parser.error(str(error))
(resources / 'changelog.json').write_text(json.dumps(notes, ensure_ascii=False, indent=2) + '\n')
# Solid native wallpapers used for the system menu bar tint.
for preset, rgb in {'nord0': (46, 52, 64), 'nord3': (76, 86, 106)}.items():
    Image.new('RGB', (64, 64), rgb).save(resources / f'desktop-base-{preset}.png')
shutil.copytree(work / 'kubai-settings', resources / 'kubai-settings', dirs_exist_ok=True)
binary = contents / 'MacOS' / 'Pebble'
binary.parent.mkdir(exist_ok=True)
generated = staging / 'generated'
generated.mkdir(exist_ok=True)

icon = build_icon(work / 'app-icon.png', resources, staging)
shutil.copyfile(work / 'refresh-label.png', resources / 'refresh-label.png')
try:
    build_renderer(work, generated, resources)
except RendererBuildError as error:
    parser.error(str(error))

with (contents / 'Info.plist').open('wb') as info:
    plistlib.dump({
        'CFBundleDisplayName': 'Pebble Wallpaper',
        'CFBundleName': 'Pebble Wallpaper',
        'CFBundleIconFile': icon.name,
        'CFBundleIdentifier': args.test_identifier if args.local_update_test else 'app.painted-pebble.wallpaper',
        'CFBundleExecutable': 'Pebble',
        'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': args.version,
        'CFBundleVersion': args.build,
        'LSMinimumSystemVersion': '13.0',
        'LSUIElement': True,
        'NSHighResolutionCapable': True,
        **({
            'SUFeedURL': args.update_feed,
            'SUPublicEDKey': args.update_key,
            'SURequireSignedFeed': True,
            'SUVerifyUpdateBeforeExtraction': True,
            'SUEnableAutomaticChecks': True,
            # Sparkle polls the appcast; there is no push. SUAutomaticallyUpdate is
            # the key that makes it download in the background and stage the install,
            # which Sparkle then applies the next time the app quits.
            'SUAutomaticallyUpdate': True,
            'SUScheduledCheckInterval': 86400,
        } if args.update_feed else {}),
    }, info)

sparkle_flags = []
if args.update_feed:
    vendor = work / 'vendor/Sparkle'
    frameworks = contents / 'Frameworks'
    frameworks.mkdir(exist_ok=True)
    framework = frameworks / 'Sparkle.framework'
    if framework.exists():
        shutil.rmtree(framework)
    run('ditto', str(vendor / framework.name), str(framework))
    shutil.copyfile(vendor / 'LICENSE', resources / 'Sparkle-LICENSE.txt')
    sparkle_flags = ['-F', str(frameworks), '-framework', 'Sparkle',
                     '-Wl,-rpath,@executable_path/../Frameworks']
    if args.local_update_test:
        sparkle_flags.append('-DPEBBLE_UPDATE_TEST=1')
elif (contents / 'Frameworks/Sparkle.framework').exists():
    shutil.rmtree(contents / 'Frameworks/Sparkle.framework')
    (resources / 'Sparkle-LICENSE.txt').unlink(missing_ok=True)

run('clang', '-arch', 'arm64', '-arch', 'x86_64', '-mmacosx-version-min=13.0',
    '-fobjc-arc', '-fblocks', '-O2', '-framework', 'AppKit', '-framework', 'WebKit',
    '-framework', 'CoreGraphics', '-framework', 'UniformTypeIdentifiers', '-I', str(generated),
    *sparkle_flags, str(work / 'Pebble.m'),
    *(str(path) for path in sorted(work.glob('PebbleApp*.m'))),
    str(work / 'PebbleMenuIcon.m'), str(work / 'PebbleState.m'), str(work / 'PebbleWallpaperPolicy.m'), str(work / 'PebbleSettingsSurface.m'), str(work / 'PebbleChangelogView.m'), '-o', str(binary))
run('codesign', '--force', '--sign', '-', str(app))
run('codesign', '--verify', '--strict', '--deep', str(app))
run('lipo', str(binary), '-verify_arch', 'arm64', 'x86_64')

preview = staging / 'wallpaper-verification.png'
run(str(binary), '--verify', str(preview), timeout=60)
if args.app_only:
    raise SystemExit(0)
window_width, window_height = 780, 462
background = make_background(staging, work / 'front-stone-candidates', window_width, window_height)
title = 'Pebble Wallpaper Installer'
# Carries the build, not just the version: bug-fix releases keep the version and
# would otherwise overwrite the previous installer.
disk = (args.installer_output.resolve() if args.installer_output
        else output / f'Pebble-Wallpaper-Installer-{args.version}-{args.build}.dmg')
disk.parent.mkdir(parents=True, exist_ok=True)
settings = {
    'format': 'UDZO',
    'filesystem': 'APFS',
    'files': [str(app)],
    'symlinks': {'Applications': '/Applications'},
    'icon': str(icon),
    'background': str(background),
    'window_rect': ((180, 140), (window_width, window_height)),
    'default_view': 'icon-view',
    'show_toolbar': False,
    'show_status_bar': False,
    'show_sidebar': False,
    'show_pathbar': False,
    'show_tab_view': False,
    'icon_size': 152,
    'text_size': 15,
    'icon_locations': {app.name: (204, 222), 'Applications': (560, 222)},
}
# Use the Finder alias as the sole background reference.
with patch.object(dmgbuild.core.Bookmark, 'for_file', return_value=None):
    dmgbuild.build_dmg(str(disk), title, settings=settings)
run('hdiutil', 'verify', str(disk))
