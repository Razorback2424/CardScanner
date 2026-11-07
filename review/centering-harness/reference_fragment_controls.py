#!/usr/bin/env python3
"""Counterexamples for research-only reference/fragment corroboration."""
import copy
import json

from reference_fragment_corroboration import compare


def hypothesis(values, origins=None):
    origins = origins or ['observed_candidate']*61
    return dict(possibleTrackHopping=False, points=[dict(point=[float(i), float(value)], origin=origins[i])
                                                    for i, value in enumerate(values)])


def profile(indices):
    return dict(rows=[dict(point=[float(i), 100.0], stable=i in indices) for i in range(61)])


def run():
    straight = hypothesis([100]*61)
    wrong_rule = hypothesis([125]*61)
    ambiguous = dict(hypotheses=[straight, wrong_rule])
    full = compare(profile(set(range(61))), ambiguous, 'bottom')
    assert full['hypotheses'][0]['agreement'] == 61
    assert full['hypotheses'][1]['disagreement'] == 61
    assert full['selectedCandidate'] is None and full['reviewRequired']

    # Both sides agree in the middle; one diverges outside that evidence.
    # Good local agreement must not resolve or certify the full edge.
    drifting = hypothesis([100 if 15 <= i <= 44 else 110 for i in range(61)])
    middle = compare(profile(set(range(15, 45))), dict(hypotheses=[straight, drifting]), 'bottom')
    assert [item['agreement'] for item in middle['hypotheses']] == [30, 30]
    assert middle['stableReferenceRegions'] == [1, 2, 3]
    assert middle['selectedCandidate'] is None and middle['reviewRequired']

    origins = ['extrapolated' if i < 10 or i > 50 else
               'interpolated' if 25 <= i <= 33 else 'observed_candidate' for i in range(61)]
    partial = compare(profile(set(range(61))), dict(hypotheses=[hypothesis([100]*61, origins)]), 'bottom')
    row = partial['hypotheses'][0]
    assert row['agreement'] == 41 and row['unsupported'] == 20
    assert row['inferredBrackets'] == 9 and row['pointOrigins']['interpolated'] == 9

    # Even a single apparently perfect track is never treated as proof of
    # physical identity or as permission to report automatically.
    hidden_cut = compare(profile(set(range(61))), dict(hypotheses=[straight]), 'bottom')
    assert hidden_cut['hypotheses'][0]['agreement'] == 61
    assert hidden_cut['selectedCandidate'] is None and hidden_cut['reviewRequired']

    bad = copy.deepcopy(straight)
    bad['points'][5]['origin'] = 'imagined'
    try:
        compare(profile(set(range(61))), dict(hypotheses=[bad]), 'bottom')
    except ValueError:
        pass
    else:
        raise AssertionError('unknown point provenance was accepted')
    print(json.dumps(dict(controls=5, status='passed', selection='none'), indent=2), flush=True)


if __name__ == '__main__':
    run()
