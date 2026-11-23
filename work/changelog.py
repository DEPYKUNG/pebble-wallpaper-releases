"""Select the installed app's latest three release notes without network access."""
from datetime import date
import re


def recent_releases(entries, version, build, *, local_test=False):
    if not isinstance(entries, list):
        raise ValueError('changelog.json must contain a list of releases')
    seen = set()
    normalized = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError('Each changelog entry must be an object')
        number = entry.get('build')
        if type(number) is not int or number < 1 or number in seen:
            raise ValueError('Changelog builds must be positive, unique integers')
        seen.add(number)
        release = entry.get('version')
        if not isinstance(release, str) or not re.fullmatch(r'\d+(?:\.\d+){1,2}', release):
            raise ValueError('Invalid changelog version')
        try:
            date.fromisoformat(entry.get('date', ''))
        except (ValueError, TypeError) as error:
            raise ValueError('Invalid changelog date') from error
        summary = entry.get('summary')
        if not isinstance(summary, str) or not summary.strip() or len(summary) > 500:
            raise ValueError('Changelog summaries must contain 1-500 characters')
        normalized.append(dict(version=release, build=number, date=entry['date'], summary=summary.strip()))
    number = int(build)
    if not local_test and not any(e['build'] == number and e['version'] == version for e in normalized):
        raise ValueError(f'Add a changelog.json entry for {version} (Build {build}) before building')
    return sorted((e for e in normalized if e['build'] <= number), key=lambda e: e['build'], reverse=True)[:3]
