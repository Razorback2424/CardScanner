#!/usr/bin/env python3
"""Unit tests of the evidence guard only; these are not scanner/runtime acceptance tests."""
import copy, unittest
from gate_audit import checks, is_approved,load

class IndependentEvidenceGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p=load('evidence_packets/MIN-10.json')
    def test_every_research_preflight_invariant(self):
        result,_=checks()
        self.assertTrue(all(x['passed'] for x in result),[x for x in result if not x['passed']])
    def test_no_public_image_promotes_a_physical_card(self):
        ok,reasons=is_approved(self.p)
        self.assertFalse(ok)
        self.assertTrue(any('actual specimen' in x for x in reasons))
    def test_published_footer_cannot_stand_in_for_actual_footer(self):
        p=copy.deepcopy(self.p)
        p['literal_physical_observations']['footer_text_preserve_exact_glyphs_and_spacing']=p['published_research_not_physical_observation']['published_footer']
        ok,_=is_approved(p)
        self.assertFalse(ok)
    def test_fake_uuid_alone_never_authorizes(self):
        p=copy.deepcopy(self.p)
        p['proposed_activation']['app_owned_permanent_physical_uuid']='not-a-real-uuid'
        p['proposed_activation']['approved_eligible_finish_ids']=['foil']
        ok,_=is_approved(p)
        self.assertFalse(ok)
    def test_one_reviewer_cannot_promote(self):
        p=copy.deepcopy(self.p)
        p['reviewers'][0].update(reviewer_id='reviewer-1', identity_decision='approved',finish_decision='approved',universe_decision='approved',reviewed_hashes=['abc'],signed_at_utc='2026-10-12T00:00:00Z')
        ok,reasons=is_approved(p)
        self.assertFalse(ok)
        self.assertTrue(any('Two distinct independent' in x for x in reasons))
    def test_two_identical_reviewers_are_not_independent(self):
        p=copy.deepcopy(self.p)
        for r in p['reviewers']:
            r.update(reviewer_id='same-person', identity_decision='approved',finish_decision='approved',universe_decision='approved',reviewed_hashes=['abc'],signed_at_utc='2026-10-12T00:00:00Z')
        ok,reasons=is_approved(p)
        self.assertFalse(ok)
        self.assertTrue(any('Two distinct independent' in x for x in reasons))
    def test_quarantine_without_full_candidate_universe(self):
        p=copy.deepcopy(self.p)
        p['review_scopes']['physical_identity_confirmed']=True
        p['review_scopes']['finish_authority_confirmed']=True
        ok,reasons=is_approved(p)
        self.assertFalse(ok)
        self.assertTrue(any('universe' in x.lower() for x in reasons))
    def test_production_shared_sync_flag_must_remain_false(self):
        p=copy.deepcopy(self.p)
        p['proposed_activation']['production_or_shared_sync_allowed']=True
        ok,reasons=is_approved(p)
        self.assertFalse(ok)
        self.assertTrue(any('Production/shared-sync' in x for x in reasons))
    def test_actual_photos_and_dimensions_required(self):
        p=copy.deepcopy(self.p)
        ok,reasons=is_approved(p)
        self.assertFalse(ok)
        self.assertTrue(any('uncropped_front' in x for x in reasons))
        self.assertTrue(any('physical_width_mm' in x for x in reasons))
    def test_held_promo_footer_does_not_become_ordinary(self):
        c=load('source_snapshot/lorcana_real_card_corpus.json')
        row=next(x for x in c['entries'] if x['case_id']=='LRC-011')
        self.assertEqual(row['footer_parts']['numerator'],None)
        self.assertEqual(row['published_footer'],'1TFC · EN · 1/P1')
    def test_same_footer_size_is_not_finish_only(self):
        c=load('source_snapshot/lorcana_real_card_corpus.json')
        d={x['case_id']:x for x in c['entries']}
        self.assertEqual(d['LRC-001']['published_footer'],d['LRC-002']['published_footer'])
        self.assertNotEqual(d['LRC-001']['size_claim'],d['LRC-002']['size_claim'])
    def test_quest_raw_kind_distinguished(self):
        c=load('source_snapshot/lorcana_real_card_corpus.json')
        row=next(x for x in c['entries'] if x['case_id']=='LRC-018')
        self.assertEqual(row['item_kind_candidate'],'scenario_card')
        self.assertFalse(row['activation_permitted'])
    def test_lettered_numbers_remain_literal(self):
        c=load('source_snapshot/lorcana_real_card_corpus.json')
        nums={x['case_id']:x['footer_parts']['numerator'] for x in c['entries'] if x['case_id'] in ('LRC-013a','LRC-013c')}
        self.assertEqual(set(nums.values()),{'4a','4c'})
    def test_retailer_finish_claim_not_authority(self):
        p=load('evidence_packets/MIN-08.json')
        self.assertIsNone(p['literal_physical_observations']['finish_observed_under_light'])
        self.assertIsNone(p['proposed_activation']['approved_eligible_finish_ids'])
    def test_d23_cinderella_conflict_not_normalized(self):
        c=load('source_snapshot/lorcana_real_card_corpus.json')
        row=next(x for x in c['entries'] if x['case_id']=='LRC-017')
        self.assertNotEqual(row['footer_display_conflict']['official_digital_gallery'],row['footer_display_conflict']['third_party_collectors'])
    def test_all_original_runtime_scenarios_remain_unexecuted(self):
        x=load('scenario_execution_matrix.json')
        self.assertEqual(x['actual_runtime_passes'],0)
        self.assertEqual(len(x['scenarios']),25)
        self.assertTrue(all(y['iOS_runtime_execution_status']=='NOT_RUN_BLOCKED' for y in x['scenarios']))

if __name__=='__main__': unittest.main(verbosity=2)
