import unittest
from changelog import recent_releases


def note(build, version=None):
    return dict(version=version or f'1.19.{build}', build=build, date='2026-11-23', summary=f'Change {build}')


class ChangelogTests(unittest.TestCase):
    def test_numeric_order_limit_and_current_release(self):
        entries = [note(29, '1.19.8'), note(32), note(30, '1.19.9'), note(28), note(31, '1.19.10')]
        result = recent_releases(entries, '1.19.10', '31')
        self.assertEqual([e['build'] for e in result], [31, 30, 29])
        self.assertEqual(result[0]['version'], '1.19.10')

    def test_requires_matching_version_and_build(self):
        for version, build in [('1.20', '1'), ('1.19.1', '2')]:
            with self.assertRaisesRegex(ValueError, 'Add a changelog'):
                recent_releases([note(1)], version, build)

    def test_bad_records_do_not_ship(self):
        for patch in [dict(build=True), dict(build=-1), dict(version='latest'), dict(date='bad'), dict(summary='')]:
            with self.subTest(patch=patch), self.assertRaises(ValueError):
                recent_releases([dict(note(1), **patch)], '1.19.1', '1')
        with self.assertRaises(ValueError):
            recent_releases([note(1), note(1)], '1.19.1', '1')

    def test_isolated_update_builds_may_have_no_production_notes(self):
        self.assertEqual(recent_releases([note(31)], '1.0', '1', local_test=True), [])


if __name__ == '__main__':
    unittest.main()
