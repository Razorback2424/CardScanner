#!/usr/bin/env python3
"""Research-only independent, fail-closed input review. No Swift simulation or signing."""
from __future__ import annotations
import hashlib, json
from pathlib import Path
from typing import Any

ROOT=Path(__file__).resolve().parent

def load(relative): return json.loads((ROOT/relative).read_text(encoding='utf-8'))

def sha(relative): return hashlib.sha256((ROOT/relative).read_bytes()).hexdigest()

def is_approved(packet:dict[str,Any])->tuple[bool,list[str]]:
    """Minimum evidence readiness precheck, NOT a certification of human signoffs or catalog correctness."""
    problems=[]
    p=packet
    a=p.get('physical_card_access') or {}
    if a.get('observed_mode') not in ('actual_card_in_hand','permissioned_collector_specimen'):
        problems.append('No valid first-hand/permissioned actual specimen provenance')
    for k in ('origin_or_custodian','observed_at_utc','retention_permission_reference'):
        if not a.get(k): problems.append('Missing provenance '+k)
    assets={x['kind']:x for x in p.get('assets',[]) if x.get('kind')}
    for typ in ('uncropped_front','uncropped_back','macro_literal_footer','artwork_or_stamp_macro','angled_light_finish'):
        x=assets.get(typ)
        if not x or not x.get('path') or not x.get('sha256'):
            problems.append('Missing retained physical evidence and SHA256: '+typ)
    obs=p.get('literal_physical_observations') or {}
    for k in ('footer_text_preserve_exact_glyphs_and_spacing','front_artwork_description','physical_width_mm',
              'physical_height_mm','dimension_method','physical_card_back_description',
              'finish_observed_under_light','finish_observation_is_confident'):
        if obs.get(k) in (None,'',False): problems.append('Missing real physical observation: '+k)
    review=p.get('review_scopes') or {}
    for k in ('physical_identity_confirmed','finish_authority_confirmed','literal_footer_mapping_confirmed',
              'footer_candidate_universe_complete_for_explicit_scope'):
        if review.get(k) is not True: problems.append('Unapproved evidence scope: '+k)
    if not review.get('scope_definition'):problems.append('No explicitly bounded full same-footer candidate universe')
    reviewers=p.get('reviewers') or []
    ids=[x.get('reviewer_id') for x in reviewers]
    if len(reviewers)!=2 or not all(ids) or len(set(ids))!=2:
        problems.append('Two distinct independent reviewers not identified')
    for i,r in enumerate(reviewers):
        if not all(r.get(k)=='approved' for k in ('identity_decision','finish_decision','universe_decision')):
            problems.append('Reviewer '+str(i+1)+' has not approved all required scopes')
        if not r.get('reviewed_hashes') or not r.get('signed_at_utc'):
            problems.append('Reviewer '+str(i+1)+' has no audited image hashes/time')
    act=p.get('proposed_activation') or {}
    for k in ('app_owned_permanent_physical_uuid','approved_eligible_finish_ids','footer_mapping_reference','protected_transition_reference'):
        if not act.get(k): problems.append('No authorized activation identity: '+k)
    if act.get('approved_for_isolated_local_review_seed') is not True:
        problems.append('Explicit local seed approval is false')
    if act.get('production_or_shared_sync_allowed') is not False:
        problems.append('Production/shared-sync must stay disabled')
    return not problems,problems


def checks():
    corpus=load('source_snapshot/lorcana_real_card_corpus.json')
    originals={x['case_id']:x for x in corpus['entries']}
    original_scenarios=load('source_snapshot/acceptance_scenarios.json')['scenarios']
    package=load('minimum_specimens.json'); selection=package['specimens']
    matrix=load('scenario_execution_matrix.json')
    packets=[load('evidence_packets/'+s['slot_id']+'.json') for s in selection]
    out=[]
    def check(name, condition):
        out.append({'check':name,'passed':bool(condition)})
    check('original corpus unchanged by selection (sha256)',sha('source_snapshot/lorcana_real_card_corpus.json')==package['basis_snapshot_sha256'])
    check('original supplied corpus still contains 29 records',len(corpus['entries'])==29)
    check('unique 12 specimen-instance slots',len(selection)==12 and len({s['slot_id'] for s in selection})==12)
    check('all target IDs exist in original',all(s['case_id'] in originals for s in selection))
    check('all source URLs use HTTPS and carry a concrete observation',all(all(c['url'].startswith('https://') and c['claim'] for c in s['research_claims']) for s in selection))
    check('all references treated as research not physical observation',all(s['physical_independent_review_decision']=='QUARANTINE_UNAPPROVED' and not s['physical_approval'] for s in selection))
    check('no physical UUIDs or reviewed finishes invented',all(originals[s['case_id']]['physical_uuid'] is None and originals[s['case_id']]['eligible_finish_ids'] is None for s in selection))
    check('exact Hades standard normal+foil and jumbo foil slot triad',
      [(s['target_physical_form'],s['target_finish_not_authorized']) for s in selection if s['case_id'] in ('LRC-001','LRC-002')]==[
        ('standard','nonfoil'),('standard','cold_foil'),('oversized','foil_unspecified')])
    check('Hades standard/oversized have same published footer but size collision',
      originals['LRC-001']['published_footer']==originals['LRC-002']['published_footer'] and originals['LRC-001']['size_claim']!=originals['LRC-002']['size_claim'])
    check('Stitch physical ownership differs by set with shared name',
      originals['LRC-007']['name']==originals['LRC-008']['name'] and originals['LRC-007']['footer_parts']['printed_marker']=='1' and originals['LRC-008']['footer_parts']['printed_marker']=='9')
    check('Elsa enchanted collector numerator exceeds ordinary denominator',
      int(originals['LRC-006']['footer_parts']['numerator'])>int(originals['LRC-006']['footer_parts']['denominator_or_token']))
    check('Dalmatian variants retain literal 4a and 4c identities',
      {'4a','4c'}=={originals[s['case_id']]['footer_parts']['numerator'] for s in selection if s['case_id'].startswith('LRC-013')})
    check('landscape Motunui and Vine retain standard physical size class',
      all(originals[k]['layout_claim']=='landscape' and originals[k]['size_claim']=='standard' for k in ('LRC-012','LRC-025')))
    check('Vine literal 207/207 and Q1 Ursula 30/31 kept verbatim',
      originals['LRC-025']['published_footer']=='207/207 · EN · 13' and originals['LRC-018']['published_footer']=='30/31 · EN · Q1')
    check('2022 D23 promo preserves historical footer and separate marks',
      originals['LRC-011']['published_footer']=='1TFC · EN · 1/P1' and originals['LRC-011']['review_status']=='held_unsupported_footer_layout')
    check('held special scenario raw kind not silently projected to ordinary card',
      originals['LRC-018']['item_kind_candidate']=='scenario_card' and originals['LRC-018']['review_status']=='held_scenario_itemkind_authority')
    check('Cinderella 2024 published printed-footer lexeme conflict retained',
      originals['LRC-017']['footer_display_conflict']['official_digital_gallery']!=originals['LRC-017']['footer_display_conflict']['third_party_collectors'] and any(c['case_id']=='LRC-017' for c in package['deferred_conflicts']))
    check('reference dimensions are explicitly NOT measurements',
      all(s['expected_acceptance_dimensions_mm_not_measured']['measured_specimen_width_mm'] is None and
          s['expected_acceptance_dimensions_mm_not_measured']['status']=='INDUSTRY_REFERENCE_NOT_AN_OBSERVED_CARD' for s in selection))
    check('secondary photos cannot substitute for specimen images or be redistributed',
      all(not p['physical_card_access']['retention_permission_reference'] and
          all(x['sha256'] is None and x['path'] is None for x in p['assets']) for p in packets))
    check('all 12 actual evidence packets fail real physical review gate',all(not is_approved(p)[0] for p in packets))
    check('all 12 physical reviewer sets remain unapproved',
      all(len(p['reviewers'])==2 and all(x['identity_decision']=='pending' for x in p['reviewers']) for p in packets))
    check('exact 25 original scenarios mapped without pretending execution',
      len(original_scenarios)==25 and len(matrix['scenarios'])==25 and
      {x['scenario_id'] for x in original_scenarios}=={x['scenario_id'] for x in matrix['scenarios']} and
      all(x['iOS_runtime_execution_status']=='NOT_RUN_BLOCKED' and x['pass_evidence'] is None for x in matrix['scenarios']))
    check('actual app passes remain zero; no activation or production',
      matrix['actual_runtime_passes']==0 and not package['seed_manifest_generated'] and not package['production_enabled'] and not package['runtime_scenarios_executed'])
    return out,packets


def main():
    out,packets=checks()
    result={
     'schema_id':'lorcana-offline-evidence-gate-audit/v1',
     'as_of':'2026-10-12',
     'context':'Python assertions against public-source research package; NOT iOS/Xcode/real-card tests',
     'assertions_passed':sum(x['passed'] for x in out),
     'assertions_total':len(out),
     'independent_reviewed_real_specimens':0,
     'local_review_seed_eligible':0,
     'actual_iOS_runtime_scenarios_passed':0,
     'actual_iOS_runtime_scenarios_run':0,
     'scenario_count_specified':25,
     'per_slot_gating':{p['target_slot_id']:{'eligible':is_approved(p)[0], 'blockers':is_approved(p)[1]} for p in packets},
     'checks':out,
    }
    (ROOT/'offline_gate_results.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
    print(f"Offline research/deny checks {result['assertions_passed']}/{result['assertions_total']} passed. Physical approvals 0/12. iOS acceptance execution 0/25. No seed.")
    if result['assertions_passed']!=result['assertions_total']:
        for x in out:
            if not x['passed']:print('FAIL',x['check'])
        raise SystemExit(1)

if __name__=='__main__': main()
