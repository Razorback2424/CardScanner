"""Offline safety/structure checks of the RESEARCH corpus; never signs/activates catalog data."""
import json, pathlib, hashlib
ROOT=pathlib.Path(__file__).resolve().parent
j=lambda x: json.loads((ROOT/x).read_text(encoding='utf-8'))
corpus=j('lorcana_real_card_corpus.json')
scenarios=j('acceptance_scenarios.json')
packet=j('physical_review_evidence_template.json')
assert corpus['schema_id']=='lorcana-real-physical-reference-corpus/v1'
assert corpus['manifest_eligible'] is False and corpus['production_registration_eligible'] is False
entries=corpus['entries']; sources=corpus['sources']
assert len(entries)==29 and len(sources)>=30
keys=[e['case_id'] for e in entries]
assert len(keys)==len(set(keys))
assert all(s['url'].startswith('https://') and s['supports'] for s in sources.values())
assert all(e['source_ids'] and all(s in sources for s in e['source_ids']) for e in entries)
assert all(e['physical_uuid'] is None and e['eligible_finish_ids'] is None and not e['activation_permitted'] for e in entries)
assert all(e['review_signoff'] is None and not e['actual_card_image_files'] for e in entries)
assert all(e['review_status']=='source_documented_physical_unreviewed' or e['review_status'].startswith('held_') for e in entries)
for e in entries:
  p=e['footer_parts']
  assert set(p)=={'numerator','denominator_or_token','language','printed_marker'}
  assert len(set(e['acceptance_tests'])) == len(e['acceptance_tests'])
  assert e['priority'] in {'core','core_reference_high_value','core_hold','edge_hold','expanded'}
find={e['case_id']:e for e in entries}
assert find['LRC-001']['published_footer']==find['LRC-002']['published_footer']=='5/204 · EN · 1'
assert find['LRC-001']['size_claim']=='standard' and find['LRC-002']['size_claim']=='oversized'
assert find['LRC-003']['published_footer']==find['LRC-004']['published_footer']=='118/204 · EN · 1'
assert find['LRC-005']['footer_parts']['numerator']=='42' and find['LRC-006']['footer_parts']['numerator']=='207'
assert find['LRC-007']['footer_parts']['printed_marker']=='1' and find['LRC-008']['footer_parts']['printed_marker']=='9'
assert [find['LRC-013'+c]['footer_parts']['numerator'] for c in 'abcde']==[f'4{c}' for c in 'abcde']
assert find['LRC-012']['layout_claim']=='landscape' and find['LRC-025']['layout_claim']=='landscape'
assert find['LRC-018']['footer_parts']['denominator_or_token']=='31' and find['LRC-018']['footer_parts']['printed_marker']=='Q1'
assert find['LRC-024']['footer_parts']['denominator_or_token']=='207'
assert find['LRC-025']['published_footer']=='207/207 · EN · 13'
assert find['LRC-017']['footer_display_conflict']['official_digital_gallery'] != find['LRC-017']['footer_display_conflict']['third_party_collectors']
assert find['LRC-023']['published_footer'] is None
assert packet['packet_status']=='UNFILLED_TEMPLATE_NOT_EVIDENCE' and not packet['proposed_activation']['approved_for_isolated_local_review_seed']
assert len(packet['reviewers'])==2 and all(x['identity_decision']=='pending' for x in packet['reviewers'])
checks=scenarios['scenarios']; ids=[x['scenario_id'] for x in checks]
assert len(checks)>=23 and len(ids)==len(set(ids)) and scenarios['execution_status']=='NONE_EXECUTED'
assert all(x['case_ids'] and set(x['case_ids']).issubset(keys) and x['execution_status']=='specified_not_run' for x in checks)
for file in ['README.md','lorcana_real_card_corpus.json','acceptance_scenarios.json','physical_review_evidence_template.json']:
 assert (ROOT/file).is_file() and (ROOT/file).stat().st_size>1000
print(f"PASS research corpus structural checks: {len(entries)} source-documented candidates, {len(sources)} cited links, {len(checks)} specified scenarios, NO authorized UUID/finish/production release")
for file in ['lorcana_real_card_corpus.json','acceptance_scenarios.json','physical_review_evidence_template.json']:
 b=(ROOT/file).read_bytes();print(file,hashlib.sha256(b).hexdigest())
