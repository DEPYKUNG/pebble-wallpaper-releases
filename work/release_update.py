"""Prepare a signed full update from a built Pebble Wallpaper app."""

import argparse
from pathlib import Path
import plistlib
import re
import subprocess
from tempfile import TemporaryDirectory
from urllib.parse import urljoin, urlsplit


parser = argparse.ArgumentParser()
parser.add_argument('app', type=Path)
parser.add_argument('destination', type=Path)
parser.add_argument('--notes', type=Path)
parser.add_argument('--account', default='app.painted-pebble.wallpaper')
parser.add_argument('--test-key-file', type=Path)
args = parser.parse_args()

app = args.app.resolve()
destination = args.destination.resolve()
with (app / 'Contents/Info.plist').open('rb') as info:
    metadata = plistlib.load(info)
feed = metadata.get('SUFeedURL')
key = metadata.get('SUPublicEDKey')
if not feed or not key or not metadata.get('SURequireSignedFeed'):
    parser.error('Build the app with a signed Sparkle feed before releasing it')
parsed = urlsplit(feed)
is_test = (parsed.scheme == 'http' and parsed.hostname in {'localhost', '127.0.0.1'}
           and metadata['CFBundleIdentifier'].endswith('.updatetest'))
if args.test_key_file and not is_test:
    parser.error('--test-key-file is only for loopback integration tests')
if parsed.scheme != 'https' and not is_test:
    parser.error('The release feed must use HTTPS')
feed_name = Path(parsed.path).name
if not re.fullmatch(r'[\w-]+\.xml', feed_name):
    parser.error('The feed URL must end with a named XML file')

version = metadata['CFBundleShortVersionString']
build = metadata['CFBundleVersion']
if not re.fullmatch(r'\d+(?:\.\d+){1,2}', version) or not re.fullmatch(r'[1-9]\d*', build):
    parser.error('Invalid release version or build number')
download_prefix = urljoin(feed, './')
github_release_feed = re.fullmatch(r'(/[^/]+/[^/]+/releases)/latest/download/[^/]+', parsed.path)
if parsed.hostname == 'github.com' and github_release_feed:
    releases_path = github_release_feed.group(1)
    download_prefix = urljoin(feed, f'{releases_path}/download/v{version}-{build}/')

work = Path(__file__).resolve().parent
sparkle = work / 'vendor/Sparkle/bin'
account = ['--account', args.account]
if not args.test_key_file:
    actual_key = subprocess.check_output([str(sparkle / 'generate_keys'), *account, '-p'], text=True).strip()
    if actual_key != key:
        parser.error('The signing key does not match the public key embedded in the app')

subprocess.run(['codesign', '--verify', '--strict', '--deep', str(app)], check=True)
destination.mkdir(parents=True, exist_ok=True)
archive = destination / f'Pebble-Wallpaper-{version}-{build}.zip'
if archive.exists():
    parser.error(f'{archive.name} exists. Use a new destination or increment the build number.')
with TemporaryDirectory(prefix='.sparkle-', dir=destination) as scratch, \
     TemporaryDirectory(prefix='signing-', dir=work) as private_directory:
    staging = Path(scratch)
    if args.test_key_file:
        private_key = args.test_key_file.resolve()
    else:
        # Export with the same Keychain tool that owns the entry. Other Sparkle
        # executables can sign through stdin without requesting their own access.
        private_key = Path(private_directory) / 'ed25519'
        subprocess.run([str(sparkle / 'generate_keys'), *account, '-x', str(private_key)], check=True)
        private_key.chmod(0o600)
    signing = ['--ed-key-file', '-']
    private_seed = private_key.read_bytes()
    staged_archive = staging / archive.name
    staged_feed = staging / feed_name
    subprocess.run(['ditto', '-c', '-k', '--keepParent', str(app), str(staged_archive)], check=True)
    if args.notes:
        staged_archive.with_suffix('.md').write_text(args.notes.read_text())
    subprocess.run([
        str(sparkle / 'generate_appcast'), *signing, '--download-url-prefix', download_prefix,
        '--maximum-deltas', '0', '--maximum-versions', '1', '--embed-release-notes',
        '-o', str(staged_feed), str(staging),
    ], input=private_seed, check=True)
    subprocess.run([str(sparkle / 'sign_update'), *signing, '--verify', str(staged_feed)],
                   input=private_seed, check=True)
    staged_archive.rename(archive)
    staged_feed.replace(destination / feed_name)
print(f'Release archive: {archive}')
print(f'Signed feed: {destination / feed_name}')
