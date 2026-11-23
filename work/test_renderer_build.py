"""Compatibility boundary tests: deliberately broken inputs must fail closed."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from renderer_build import RendererBuildError, apply_patches, build_renderer, texture_table


class RendererBuildTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.work = self.root / 'work'
        self.work.mkdir()
        self.out = self.root / 'out'
        self.out.mkdir()
        source = Path(__file__).resolve().parent
        shutil.copytree(source / 'renderer', self.work / 'renderer')
        for name in ('original.js', 'original.html', 'pass-card.png', 'desktop-question.png'):
            shutil.copyfile(source / name, self.work / name)

    def build(self):
        build_renderer(self.work, self.out, self.out)

    def rejected_without_output(self, text):
        with self.assertRaisesRegex(RendererBuildError, text):
            self.build()
        self.assertEqual(list(self.out.iterdir()), [])

    def test_upstream_drift_rejected_for_both_files(self):
        for name in ('original.js', 'original.html'):
            with self.subTest(name=name):
                path = self.work / name
                original = path.read_bytes()
                path.write_bytes(original + b'\n')
                self.rejected_without_output(name + ' SHA256 mismatch')
                path.write_bytes(original)

    def test_missing_and_duplicate_anchors_identify_patch(self):
        patch = [{'name': 'pause-policy', 'before': 'anchor', 'after': 'new'}]
        for text, count in [('gone', 0), ('anchor anchor', 2)]:
            with self.subTest(count=count):
                with self.assertRaisesRegex(RendererBuildError, f"pause-policy.*found {count}"):
                    apply_patches(text, patch)

    def test_duplicate_names_rejected(self):
        patch = {'name': 'same', 'before': 'a', 'after': 'a'}
        with self.assertRaisesRegex(RendererBuildError, 'Duplicate'):
            apply_patches('a', [patch, patch])

    def test_partial_texture_parse_rejected(self):
        for table in ('one:"One",...other', 'one:"One",one:"Two"'):
            with self.assertRaisesRegex(RendererBuildError, 'incomplete'):
                texture_table('Sg={' + table + '},Mo=Object.keys(Sg)')

    def test_native_api_loss_rejected_before_output(self):
        path = self.work / 'renderer/patches.json'
        patches = json.loads(path.read_text())
        for patch in patches:
            if patch['name'] == 'native-api':
                patch['after'] = patch['after'].replace('window.pebbleExport=', 'window.lostExport=')
        path.write_text(json.dumps(patches))
        self.rejected_without_output('pebbleExport')

    def test_unsafe_bridge_and_bad_template_rejected(self):
        bridge = self.work / 'renderer/bridge.js'
        original = bridge.read_text()
        bridge.write_text(original + '\n// </script>')
        self.rejected_without_output('Bridge JS')
        bridge.write_text(original)
        body = self.work / 'renderer/body.html'
        body.write_text(body.read_text().replace('@@SCRIPT@@', ''))
        self.rejected_without_output('html-script')

    def test_deterministic_offline_bundle(self):
        self.build()
        first = {p.name: p.read_bytes() for p in self.out.iterdir()}
        self.build()
        self.assertEqual(first, {p.name: p.read_bytes() for p in self.out.iterdir()})
        self.assertEqual(set(first), {'wallpaper.html', 'PebbleTextures.h', 'PebbleColors.h'})
        html = first['wallpaper.html'].decode()
        self.assertIn('Content-Security-Policy', html)
        self.assertNotRegex(html, r'<script[^>]+src=')
        self.assertNotIn('@@SCRIPT@@', html)
        self.assertIn('window.pebbleStaticPaused', html)


if __name__ == '__main__':
    unittest.main()
