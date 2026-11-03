from pathlib import Path
import csv, re, json
import pandas as pd

root = Path(__file__).resolve().parent
data = root / 'nfl-big-data-bowl-2027' / 'nfl-big-data-bowl-2027'
description = Path(r'C:\Users\asche\.codex\attachments\6b6ed342-8f3f-4b2c-aa71-70be14243233\Pasted text.txt').read_text(encoding='utf-8-sig')
expected = {}
current = None
for line in description.splitlines():
    match = re.match(r'File \d+: (\w+\.csv)', line)
    if match:
        current = match.group(1)
        expected[current] = []
    elif line.startswith('Files 7, 8, 9:'):
        current = 'game_tracking_2023.csv'
        expected[current] = []
    elif current and re.match(r'^[a-z][a-z0-9_]*\t', line):
        expected[current].append(line.split('\t')[0])
for year in (2024, 2025):
    expected[f'game_tracking_{year}.csv'] = expected['game_tracking_2023.csv'][:]

players = pd.read_csv(data / 'players.csv', dtype=str, keep_default_na=False)
games = pd.read_csv(data / 'games.csv', dtype=str, keep_default_na=False)
player_ids = set(players.nfl_id) - {''}
game_ids = set(games.game_id) - {''}
play_keys = set()
report = {'files': {}, 'reference_keys': {
    'players_rows': len(players), 'unique_player_ids': len(player_ids),
    'duplicate_player_ids': int(players.nfl_id.duplicated().sum()),
    'games_rows': len(games), 'unique_game_ids': len(game_ids),
    'duplicate_game_ids': int(games.game_id.duplicated().sum())}}
order = ['players.csv', 'games.csv', 'combine_results.csv', 'player_career_successes.csv', 'player_play.csv', 'combine_tracking.csv'] + [f'game_tracking_{y}.csv' for y in (2023,2024,2025)]
for name in order:
    path = data / name
    with path.open(encoding='utf-8-sig', newline='') as f:
        header = next(csv.reader(f))
    result = {'path': str(path), 'column_count': len(header), 'expected_column_count': len(expected[name]),
        'missing_columns': sorted(set(expected[name])-set(header)),
        'extra_columns': sorted(set(header)-set(expected[name])),
        'duplicate_headers': sorted({c for c in header if header.count(c)>1}),
        'rows': 0, 'ids': {}}
    cols = [c for c in ('nfl_id','game_id','play_id') if c in header]
    seen = {c:set() for c in cols if c != 'play_id'}
    for c in seen:
        result['ids'][c] = {'blank_rows':0,'unmatched_rows':0,'unmatched_ids':[]}
    unmatched = {c:set() for c in seen}
    missing_play_keys = set()
    missing_play_rows = 0
    for chunk in pd.read_csv(path, usecols=cols, dtype=str, keep_default_na=False, chunksize=250000):
        result['rows'] += len(chunk)
        for c in seen:
            values = chunk[c]
            known = player_ids if c == 'nfl_id' else game_ids
            blank = values.eq('')
            bad = ~blank & ~values.isin(known)
            result['ids'][c]['blank_rows'] += int(blank.sum())
            result['ids'][c]['unmatched_rows'] += int(bad.sum())
            unmatched[c].update(values[bad])
            seen[c].update(values[~blank])
        if name == 'player_play.csv':
            play_keys.update(chunk[['game_id','play_id','nfl_id']].itertuples(index=False,name=None))
        elif name.startswith('game_tracking_'):
            keys = list(chunk[['game_id','play_id','nfl_id']].itertuples(index=False,name=None))
            bad_keys = [k for k in keys if k not in play_keys]
            missing_play_rows += len(bad_keys)
            missing_play_keys.update(bad_keys)
    for c in seen:
        result['ids'][c]['unique_nonblank_ids'] = len(seen[c])
        result['ids'][c]['unmatched_ids'] = sorted(unmatched[c])
        known = player_ids if c == 'nfl_id' else game_ids
        result['ids'][c]['reference_ids_not_in_file'] = sorted(known-seen[c])
    if name.startswith('game_tracking_'):
        result['player_play_join'] = {'unmatched_tracking_rows':missing_play_rows, 'unmatched_unique_keys':len(missing_play_keys), 'examples':sorted(missing_play_keys)[:20]}
    report['files'][name] = result
    print(json.dumps({'file':name, **{k:v for k,v in result.items() if k not in ('path','ids')}, 'ids':{k:{a:b for a,b in v.items() if a!='reference_ids_not_in_file'} for k,v in result['ids'].items()}}), flush=True)
out = root / 'validation_report.json'
out.write_text(json.dumps(report,indent=2),encoding='utf-8')
print('Report saved: '+str(out),flush=True)
