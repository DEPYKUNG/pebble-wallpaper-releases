"""Export the quote column of a Feishu view into a local build resource."""
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
for name in ('base', 'table', 'view', 'field'):
    parser.add_argument('--' + name, required=True)
args = parser.parse_args()
quotes = {}
offset = 0
revision = None
while True:
    response = json.loads(subprocess.check_output([
        'lark-cli', 'base', '+record-list', '--as', 'user', '--format', 'json',
        '--base-token', args.base, '--table-id', args.table, '--view-id', args.view,
        '--field-id', args.field, '--limit', '200', '--offset', str(offset),
    ]))
    if not response.get('ok'):
        raise SystemExit('Feishu record query failed')
    page = response['data']
    if page['field_id_list'] != [args.field]:
        raise SystemExit('Unexpected quote column')
    if revision is not None and revision != page.get('rev'):
        raise SystemExit('The view changed during export. Run the import again.')
    revision = page.get('rev')
    rows = page['data']
    for (value,) in rows:
        if isinstance(value, str) and value.strip():
            quotes.setdefault(value.strip(), None)
    if not page['has_more']:
        break
    if not rows:
        raise SystemExit('Unexpected empty page')
    offset += len(rows)

if not quotes:
    raise SystemExit('No quotes found')
target = Path(__file__).with_name('pet-quotes.local.json')
temporary = target.with_suffix('.tmp')
temporary.write_text(json.dumps(list(quotes), ensure_ascii=False, indent=2) + '\n')
temporary.replace(target)
print(f'Imported {len(quotes)} unique quotes')
