import collections
import json
import math
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
manifest = json.loads((root / 'manifest.json').read_text())
reports = []
metrics = []
for test in manifest:
    for attachment in test['attachments']:
        name = attachment['suggestedHumanReadableName']
        path = root / attachment['exportedFileName']
        if 'development-metrics' in name:
            metrics = json.loads(path.read_text())
        elif '-native-research-' in name:
            value = json.loads(path.read_text())
            value['fixture'] = name.split('-native-research-')[0]
            reports.append(value)

def distribution(values):
    values = sorted(v for v in values if v is not None)
    return {'count': len(values), 'upperMedian': values[len(values) // 2] if values else None,
            'p95': values[max(0, math.ceil(len(values) * .95) - 1)] if values else None,
            'worst': values[-1] if values else None}

def summarize(rows):
    sides = [s for row in rows for s in row['sides'] if s['frame'] == 'inner']
    return {
        'images': len(rows), 'innerSides': len(sides),
        'coarseRecallAt2px': sum(s['coarseCandidateRecallAtTwoNativePixels'] for s in sides),
        'refinedRecallAt2px': sum(s['refinedCandidateRecallAtTwoNativePixels'] for s in sides),
        'selected': sum(s.get('selectedMaximumLineError') is not None for s in sides),
        'selectedWrongAt2px': sum(s.get('selectedMaximumLineError', 0) > 2 for s in sides),
        'abstentions': dict(collections.Counter(s['disposition'] for s in sides)),
        'baselineLR': distribution(r.get('baselineLRAbsoluteErrorPP') for r in rows),
        'baselineTB': distribution(r.get('baselineTBAbsoluteErrorPP') for r in rows),
        'localFitLR': distribution(r.get('localFitLRAbsoluteErrorPP') for r in rows),
        'localFitTB': distribution(r.get('localFitTBAbsoluteErrorPP') for r in rows),
        'localFitLineError': distribution(s.get('selectedMaximumLineError') for s in sides),
        'missingRatios': sum(r.get('localFitLRAbsoluteErrorPP') is None for r in rows)
    }

groups = collections.defaultdict(list)
for row in metrics:
    config = row['configuration']
    key = (config['signal'], config['sigma'], config.get('threshold'))
    groups[key].append(row)
summary = []
for key, rows in groups.items():
    entry = {'configuration': key, **summarize(rows)}
    entry['byFace'] = {face: summarize([r for r in rows if r['face'] == face]) for face in sorted(set(r['face'] for r in rows))}
    entry['byEncasement'] = {state: summarize([r for r in rows if r['encasement'] == state]) for state in sorted(set(r['encasement'] for r in rows))}
    summary.append(entry)
result = {'configurations': summary, 'images': [{k: r.get(k) for k in ['fixture', 'inputSHA256', 'seconds', 'decodeSeconds', 'firstCropSeconds', 'memoryBeforeDecode', 'memoryAfterDecode', 'memoryAfterFirstCrop', 'memoryAtEnd']} for r in reports]}
(root.parent / (root.name + '-summary.json')).write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'metrics': len(metrics), 'images': len(reports), 'configurations': len(summary), 'timing': distribution(r['seconds'] for r in reports), 'baseline': {k: summary[0][k] for k in ['images','innerSides','coarseRecallAt2px','baselineLR','baselineTB']} if summary else None}, indent=2))
for row in summary:
    print(json.dumps({k: row[k] for k in ['configuration','refinedRecallAt2px','selected','selectedWrongAt2px','localFitLR','localFitTB']}, separators=(',', ':')))
