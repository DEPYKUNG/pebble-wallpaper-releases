"""Verify the whole automatic update path against a loopback appcast.

Builds two throwaway update-test bundles, signs the newer one into a feed served
from localhost, then launches the older one and waits for Sparkle to download,
install and relaunch it with no interface shown. The assertion is that the
installed bundle's CFBundleVersion changed on disk *and* that the wallpaper came
back up as a new process, which is the step the earlier install-on-quit harness
never reached. A silent install that replaces the bundle but fails to relaunch
would leave the user with no wallpaper until their next login.
"""

import argparse
from contextlib import closing
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import sys
from tempfile import mkdtemp
import threading
import time

# Sparkle stages downloads under the test bundle's cache, keyed by bundle id
# rather than by install path, so every run shares one directory. Leftovers from
# an earlier run can block a later install and make this gate flaky, which is
# worse than no gate: a release check that fails at random gets ignored.
TEST_CACHE = Path.home() / 'Library/Caches/app.painted-pebble.wallpaper.updatetest'

# Sparkle derives the public key from a 32-byte Curve25519 seed, and there is no
# stdlib way to do that, so borrow the system Swift toolchain for the keypair.
KEYGEN_SOURCE = '''import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
FileManager.default.createFile(atPath: CommandLine.arguments[1],
    contents: Data(key.rawRepresentation.base64EncodedString().utf8),
    attributes: [.posixPermissions: 0o600])
print(key.publicKey.rawRepresentation.base64EncodedString())
'''

work = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--version', default='1.6')
parser.add_argument('--installed-build', default='8')
parser.add_argument('--update-build', default='9')
parser.add_argument('--timeout', type=float, default=180,
                    help='seconds to wait for the silent install to land')
parser.add_argument('--keep', action='store_true',
                    help='leave the scratch directory and its log in place')
args = parser.parse_args()

if int(args.update_build) <= int(args.installed_build):
    parser.error('--update-build must be greater than --installed-build')


def run(*command, **kwargs):
    return subprocess.run([str(part) for part in command], check=True, **kwargs)


def free_port():
    with closing(socket.socket()) as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def installed_build(app):
    # Sparkle swaps the bundle in place, so a read can land mid-replacement.
    try:
        with (app / 'Contents/Info.plist').open('rb') as info:
            return plistlib.load(info)['CFBundleVersion']
    except (OSError, plistlib.InvalidFileException, KeyError):
        return None


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, format, *handler_args):
        pass


scratch = Path(mkdtemp(prefix='update-loopback-', dir=work))
installed = scratch / 'installed'
staged = scratch / 'next'
feed = scratch / 'feed'
key_file = scratch / 'signing-key'
log = scratch / 'install-test.log'
app = installed / 'Pebble Wallpaper.app'
port = free_port()
feed_url = f'http://127.0.0.1:{port}/appcast.xml'
binary = app / 'Contents/MacOS/Pebble'
server = None
replaced = False
passed = False

shutil.rmtree(TEST_CACHE, ignore_errors=True)
print(f'Scratch: {scratch}')
print('The two builds and the test run each paint a desktop-level window, so the '
      'wallpaper behind your windows will flicker for a few seconds.')

try:
    keygen = scratch / 'generate.swift'
    keygen.write_text(KEYGEN_SOURCE)
    public_key = subprocess.check_output(
        ['swift', str(keygen), str(key_file)], text=True, timeout=180).strip()

    build = ['--app-only', '--local-update-test', '--update-feed', feed_url,
             '--update-key', public_key, '--version', args.version]
    print(f'Building the installed build {args.installed_build}...')
    run(sys.executable, work / 'package.py', *build,
        '--build', args.installed_build, '--staging', installed)
    print(f'Building the update build {args.update_build}...')
    run(sys.executable, work / 'package.py', *build,
        '--build', args.update_build, '--staging', staged)

    print('Signing the update into a loopback appcast...')
    run(sys.executable, work / 'release_update.py',
        staged / 'Pebble Wallpaper.app', feed, '--test-key-file', key_file)

    server = ThreadingHTTPServer(
        ('127.0.0.1', port), functools.partial(QuietHandler, directory=str(feed)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f'Serving {feed.name}/ at {feed_url}')

    before = installed_build(app)
    if before != args.installed_build:
        raise SystemExit(f'Expected build {args.installed_build} on disk, found {before}')

    print('Launching the installed build with an automatic background check...')
    with log.open('wb') as stream:
        launched = subprocess.Popen([str(binary), '--check-for-updates'],
                                    stdout=stream, stderr=stream)

    # Sparkle relaunches the app itself, so the replaced bundle on disk is the
    # only reliable signal; the process we spawned is gone by then.
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        if installed_build(app) == args.update_build:
            replaced = True
            break
        time.sleep(1)
    if replaced:
        print(f'Build {args.update_build} is on disk; waiting for the relaunch...')
        # Sparkle terminates the running copy to replace it, so a surviving
        # wallpaper must be a different process than the one we started.
        while time.monotonic() < deadline:
            running = subprocess.run(['pgrep', '-f', str(binary)],
                                     capture_output=True, text=True).stdout.split()
            if {int(pid) for pid in running} - {launched.pid}:
                passed = True
                break
            time.sleep(1)
finally:
    # The relaunched app is not our child, so match on the scratch path instead.
    subprocess.run(['pkill', '-f', str(scratch)], check=False)
    if server:
        server.shutdown()
    transcript = log.read_text(errors='replace').strip() if log.exists() else ''
    if transcript:
        print('--- app log ---')
        print(transcript)
    shutil.rmtree(TEST_CACHE, ignore_errors=True)
    if passed and not args.keep:
        shutil.rmtree(scratch, ignore_errors=True)
    elif args.keep or not passed:
        print(f'Scratch kept at {scratch}')

if not replaced:
    raise SystemExit(f'The update did not install within {args.timeout:g}s: '
                     f'build on disk is still {installed_build(app)}')
if not passed:
    raise SystemExit(f'Build {args.update_build} was installed but the wallpaper '
                     'never relaunched, which would leave the desktop bare.')
print(f'Silent install and relaunch verified: '
      f'build {args.installed_build} -> {args.update_build}')
