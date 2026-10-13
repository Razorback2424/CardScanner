import json, pathlib, csv, datetime, zipfile
ROOT=pathlib.Path('/mnt/data/lorcana_real_corpus')
S={
 'OFF_FIRST':('publisher','https://www.disneylorcana.com/en-US/product','Ravensburger First Chapter product: Hades and Mulan playable/oversized foil cards'),
 'OFF_QUEST':('publisher','https://www.disneylorcana.com/en-US/product/deep-trouble','Ravensburger Deep Trouble: 50 scenario cards, gold-backed deck, Ursula and battleground oversized cards'),
 'OFF_ELSA':('publisher','https://cards.disneylorcana.com/en-US/?cardId=207','Official Elsa Spirit of Winter Enchanted collector 207/204 EN 1'),
 'OFF_ENCHANT':('publisher','https://www.disneylorcana.com/en-US/news/enchanted-reveal','Ravensburger: Enchanted alternate artwork numbered beyond 204 with Inkwash foil'),
 'OFF_REPRINT':('publisher','https://www.disneylorcana.com/en-US/news/2025/08/2025-8-release-notes-fabled','Ravensburger: Stitch Rock Star first chapter vs Fabled reprint, gameplay identity preserved'),
 'OFF_Q1':('publisher','https://cards.disneylorcana.com/en-US/?cardId=943','Official Ursula Contract printed collector 30/31 EN Q1'),
 'OFF_VINE197':('publisher','https://cards.disneylorcana.com/en-US/?cardId=3168','Official The Vine Towering Stalk 197/207 EN 13'),
 'OFF_VINE207':('publisher','https://cards.disneylorcana.com/en-US/?cardId=3178','Official Vine Entrance 207/207 EN 13 (Location)'),
 'LORCAST_SPEC':('provider_documentation','https://lorcast.com/docs/api/cards','Provider IDs/collector strings/layout/unique=prints; not physical evidence'),
 'HADES':('community','https://lorcanaplayer.com/card/hades-king-of-olympus/','Hades 5/204 and playable/jumbo foils'),
 'HADES_JUMBO':('market','https://www.pricecharting.com/game/lorcana-first-chapter/hades-king-of-olympus-oversized-5','Separate jumbo market item with 5/204 number'),
 'MULAN':('community','https://mushureport.com/mulan-imperial-soldier-gift-set-clear-image/','Mulan 118/204 EN 1'),
 'ELSA':('market','https://inkdecks.com/cards/details-elsa-spirit-of-winter','Elsa TFC 42/204 normal and foil; 207/204 Enchanted'),
 'STITCH':('community','https://wiki.mushureport.com/wiki/Stitch_-_Rock_Star','Stitch footer history 1TFC EN 2/P1, 23/204 EN 1 and 3/204 EN 9'),
 'STITCH_FOILS':('market','https://inkdecks.com/cards/details-stitch-rock-star','Stitch standard and foil printing variants'),
 'MICKEY':('community','https://lorcanaplayer.com/card/mickey-mouse-brave-little-tailor-d23-expo/','D23 Mickey Brave Little Tailor promo and D23/1st stamps'),
 'MICKEY_PROMO':('community','https://lorcanaplayer.com/set/promo-set-1/','Original 2022 1TFC EN 1/P1 reversed footer order'),
 'D23_2022_FINISH':('community','https://lorcanaplayer.com/set/d23-expo/','2022 D23 Mickey nonfoil and other six Collector Set cards foil, all special stamps'),
 'D23_STITCH':('community','https://lorcanaplayer.com/card/stitch-rock-star-d23-expo/','2022 D23 Stitch 2/P1 Enchanted-like special stamped foil promo (not ordinary The First Chapter)'),
 'MOTUNUI':('community','https://wiki.mushureport.com/wiki/Into_the_Inklands_Card_List','Motunui 170/204 EN 3 Location'),
 'MOTUNUI_FINISH':('market','https://inkdecks.com/cards/details-motunui-island-paradise','Motunui 170/204 nonfoil and foil'),
 'PUPPIES':('community','https://wiki.mushureport.com/wiki/Dalmatian_Puppy_-_Tail_Wagger','Five alternate illustrations 4a–4e/204 EN 3'),
 'PUPPIES_FOIL':('market','https://inkdecks.com/cards/details-dalmatian-puppy-tail-wagger','Five lettered variants normal/foil'),
 'CINDERELLA':('community','https://wiki.mushureport.com/wiki/Cinderella_-_Stouthearted','Cinderella 177/204 EN2, 3/C1 EN2, 02/D23 EN2'),
 'CINDERELLA_C1':('community','https://lorcanaplayer.com/card/cinderella-stouthearted-challenge-promo-foil/','Same 3/C1 printed ID on foil and nonfoil, distinct prize distributions'),
 'CINDERELLA_STANDARD':('community','https://ready-set-draw.com/en/cards/cinderella-stouthearted','177/204 EN2 standard and foil finishes documented as collector printings'),
 'OFF_CINDERELLA_D23':('publisher','https://cards.disneylorcana.com/en-US/?cardId=1192','Official Cinderella D23 display shows 2/D23 EN2, while multiple third parties show 02/D23 EN2; raw physical footer requires confirmation'),
 'CINDERELLA_FR':('market','https://www.lorcards.fr/cards/ascension-des-floodborn-177-204-cendrillon-coeur-vaillant','French printing 177/204 FR 2'),
 'CINDERELLA_D23':('market','https://www.coleka.com/en/trading-cards/disney-lorcana-tcg/lorcana-promo-cards/cinderella-stouthearted_i1829509','D23 2024 printing 2/D23 EN2'),
 'Q1_STUDY':('community','https://lorcanaplayer.com/set/illumineers-quest-deep-trouble/','Q1 31 numbered cards and unnumbered oversized cards'),
 'QUEST_FRAMES':('community','https://wiki.mushureport.com/wiki/Illumineer%27s_Quest_-_Deep_Trouble','223/204 EN4 Yen Sid, 225/204 EN4 Mickey decorated Deep Trouble cards'),
 'QUEST_MMICKEY':('community','https://wiki.mushureport.com/wiki/Mickey_Mouse_-_Playful_Sorcerer','Mickey 187/204 EN4 and 225/204 EN4'),
 'QUEST_URSULA':('community','https://lorcanaplayer.com/card/ursula-ruler-of-lorcana-deep-trouble/','Ursula Ruler of Lorcana oversized lacks collector number'),
 'VINE_FINISH':('market','https://lorcanaplayer.com/card/the-vine-towering-stalk/','197/207 EN13 available normal and foil'),
 'FIRSTCHAPTER_FOIL':('publisher','https://disneyparksblog.com/products/getting-started-with-disney-lorcana-trading-card-game/','The First Chapter ordinary main-set cards each normal and foil'),
}
sources={k:{'category':v[0],'url':v[1],'supports':v[2]} for k,v in S.items()}
entries=[]
def add(k,name,collector,denom,language,marker,printing,finishes,source,tests,priority='core',layout='portrait',size='standard',status='candidate',item_kind='card',footer_override=None,more=None):
   if footer_override is None:
       footer_override=f'{collector}/{denom} · {language} · {marker}' if collector is not None else None
   spec={
     'case_id':k,
     'name':name,
     'published_footer':footer_override,
     'footer_parts':{'numerator':collector,'denominator_or_token':denom,'language':language,'printed_marker':marker},
     'physical_distinction_claim':printing,
     'layout_claim':layout,
     'size_claim':size,
     'item_kind_candidate':item_kind,
     'finish_candidates_not_authorized':finishes,
     'source_ids':source,
     'acceptance_tests':tests,
     'priority':priority,
     'review_status':'source_documented_physical_unreviewed' if status=='candidate' else status,
     'physical_uuid':None,
     'eligible_finish_ids':None,
     'provider_aliases':[],
     'reference_image_files':[],
     'actual_card_image_files':[],
     'measurement_mm':None,
     'review_signoff':None,
     'activation_permitted':False,
   }
   if more: spec.update(more)
   entries.append(spec)

add('LRC-001','Hades – King of Olympus','5','204','EN','1','The First Chapter standard artwork/standard card',['nonfoil','cold_foil'],['OFF_FIRST','HADES','FIRSTCHAPTER_FOIL'],['standard-vs-foil-finish','same-footer-vs-oversized','no-inferred-size'])
add('LRC-002','Hades – King of Olympus','5','204','EN','1','The First Chapter Gift Set oversized artwork matched to standard card',['cold_foil'],['OFF_FIRST','HADES','HADES_JUMBO'],['same-footer-vs-standard','requires-explicit-size'],size='oversized')
add('LRC-003','Mulan – Imperial Soldier','118','204','EN','1','The First Chapter standard-size physical card',['nonfoil','cold_foil'],['OFF_FIRST','MULAN','FIRSTCHAPTER_FOIL'],['standard-vs-oversized','same-artwork-size-boundary'])
add('LRC-004','Mulan – Imperial Soldier','118','204','EN','1','The First Chapter Gift Set jumbo',['cold_foil'],['OFF_FIRST','MULAN'],['same-footer-vs-standard','requires-explicit-size'],size='oversized')
add('LRC-005','Elsa – Spirit of Winter','42','204','EN','1','The First Chapter ordinary illustration',['nonfoil','cold_foil'],['ELSA','FIRSTCHAPTER_FOIL'],['separate-standard-art-from-enchanted'])
add('LRC-006','Elsa – Spirit of Winter','207','204','EN','1','The First Chapter Enchanted different illustration',['inkwash_foil'],['OFF_ELSA','OFF_ENCHANT','ELSA'],['premium-numerator','artwork-not-finish','no-nonfoil-inference'],priority='core_reference_high_value')
add('LRC-007','Stitch – Rock Star','23','204','EN','1','The First Chapter normal illustration',['nonfoil','cold_foil'],['OFF_REPRINT','STITCH','STITCH_FOILS'],['cross-set-reprint-distinct-physical-key','shared-gameplay-identity'])
add('LRC-008','Stitch – Rock Star','3','204','EN','9','Fabled reprint of The First Chapter artwork',['nonfoil','cold_foil'],['OFF_REPRINT','STITCH','STITCH_FOILS'],['cross-set-reprint-distinct-physical-key','shared-gameplay-identity'])
add('LRC-009','Stitch – Rock Star',None,None,'EN',None,'D23 2022 Collector Set promotional artwork with event/first marks',['holo_foil'],['STITCH','MICKEY_PROMO','D23_STITCH','D23_2022_FINISH'],['2022-reversed-footer','separate-stamped-printing','no-silent-parser-rewrite'],priority='edge_hold',status='held_unsupported_footer_layout',footer_override='1TFC · EN · 2/P1',more={'footer_parts':{'numerator':None,'denominator_or_token':None,'language':'EN','printed_marker':None},'special_footer_tokens':['1TFC','EN','2/P1']})
add('LRC-010','Mickey Mouse – Brave Little Tailor','115','204','EN','1','The First Chapter ordinary illustration',['nonfoil','cold_foil'],['MICKEY','MICKEY_PROMO','FIRSTCHAPTER_FOIL'],['standard-versus-d23-stamp'])
add('LRC-011','Mickey Mouse – Brave Little Tailor',None,None,'EN',None,'D23 2022 first-edition stamped promo',['nonfoil'],['MICKEY','MICKEY_PROMO','D23_2022_FINISH'],['stamped-separate-physical-print','2022-reversed-footer'],priority='edge_hold',status='held_unsupported_footer_layout',footer_override='1TFC · EN · 1/P1',more={'footer_parts':{'numerator':None,'denominator_or_token':None,'language':'EN','printed_marker':None},'special_footer_tokens':['1TFC','EN','1/P1']})
add('LRC-012','Motunui – Island Paradise','170','204','EN','3','Into the Inklands horizontal Location',['nonfoil','cold_foil'],['MOTUNUI','MOTUNUI_FINISH','LORCAST_SPEC'],['landscape-roi','nonportrait-choice'],layout='landscape')
for ch in 'abcde':
 add(f'LRC-013{ch}','Dalmatian Puppy – Tail Wagger',f'4{ch}','204','EN','3',f'Into the Inklands illustration {ch} (one of five distinct arts)',['nonfoil','cold_foil'],['PUPPIES','PUPPIES_FOIL'],['alphanumeric-numerator','five-distinct-artworks','shared-gameplay-identity'],priority='core' if ch in 'ab' else 'expanded')
add('LRC-014','Cinderella – Stouthearted','177','204','EN','2','Rise of the Floodborn ordinary English printing',['nonfoil','cold_foil'],['CINDERELLA','CINDERELLA_STANDARD'],['standard-versus-promos','language-boundary'])
add('LRC-015','Cendrillon – Cœur vaillant','177','204','FR','2','Rise of the Floodborn ordinary French printing, same gameplay identity',['nonfoil','cold_foil'],['CINDERELLA_FR'],['language-part-of-identity','no-English-default'],priority='expanded')
add('LRC-016','Cinderella – Stouthearted','3','C1','EN','2','Challenge Set 1 promo artwork; nonfoil and foil distributed by different event channels',['nonfoil','foil'],['CINDERELLA','CINDERELLA_C1'],['literal-token-C1','same-footer-finish-ambiguity','distribution-versus-finish-policy'],priority='edge_hold',status='held_requires_distribution_identity_policy',more={'finish_distribution_review':'Nonfoil ticket-prize / foil high-placement prize; decide physical UUID treatment from reviewed contract before activation.'})
add('LRC-017','Cinderella – Stouthearted','02','D23','EN','2','D23 Expo 2024 promo with special event edition/mark',['special_finish_requires_capture'],['CINDERELLA','CINDERELLA_D23','OFF_CINDERELLA_D23'],['literal-promo-denominator-D23','promo-versus-base-artwork','retain-two-conflicting-lexical-claims'],priority='edge_hold',status='held_printed_footer_lexeme_conflict',more={'footer_display_conflict':{'official_digital_gallery':'2/D23 · EN · 2','third_party_collectors':'02/D23 · EN · 2','resolution_needed':'Inspect literal printed numeral including any leading zero before mapping; do not normalize away mismatch or accept a uniqueness conclusion.'}})
add('LRC-018',"Ursula's Contract",'30','31','EN','Q1','Deep Trouble gold-backed scenario card',['finish_unknown'],['OFF_QUEST','OFF_Q1','Q1_STUDY'],['denominator-31','nonnumeric-set-marker-Q1','gold-back','scenario-item-kind'],priority='core_hold',status='held_scenario_itemkind_authority',item_kind='scenario_card')
add('LRC-019','Mickey Mouse – Playful Sorcerer','187','204','EN','4',"Ursula's Return ordinary printing",['nonfoil','cold_foil'],['QUEST_MMICKEY','QUEST_FRAMES'],['high-number-reprint-counterpart'])
add('LRC-020','Mickey Mouse – Playful Sorcerer','225','204','EN','4','Deep Trouble deck exclusive inky frame; not Enchanted',['cold_foil'],['OFF_QUEST','QUEST_FRAMES','QUEST_MMICKEY'],['premium-numerator-not-necessarily-enchanted','distribution-and-frame-distinction'])
add('LRC-021','Yen Sid – Powerful Sorcerer','59','204','EN','4',"Ursula's Return ordinary printing",['nonfoil','cold_foil'],['QUEST_FRAMES'],['paired-with-decorated-223'],priority='expanded')
add('LRC-022','Yen Sid – Powerful Sorcerer','223','204','EN','4','Deep Trouble decorated inky border foil',['cold_foil'],['QUEST_FRAMES'],['premium-not-enchanted','printed-same-card-gameplay'],priority='expanded')
add('LRC-023','Ursula – Ruler of Lorcana',None,None,None,None,'Unnumbered oversized boss/representational card from Deep Trouble',['speckled_foil_reported'],['OFF_QUEST','QUEST_URSULA','Q1_STUDY'],['no-collector-footer','no-fabricated-identity'],priority='edge_hold',status='held_unnumbered_no_footer',size='oversized',item_kind='oversized_scenario',footer_override=None)
add('LRC-024','The Vine – Towering Stalk','197','207','EN','13','Attack of the Vine! normal character',['nonfoil','cold_foil'],['OFF_VINE197','VINE_FINISH'],['real-non204-denominator','finish-pair'],priority='expanded')
add('LRC-025','Vine Entrance – Ominous Passageway','207','207','EN','13','Attack of the Vine! landscape Location',['nonfoil','cold_foil'],['OFF_VINE207'],['real-non204-denominator','207-equals-denominator','landscape-roi'],layout='landscape')

# Conservative source claims are not a materialized real-card manifest.
corpus={
 'schema_id':'lorcana-real-physical-reference-corpus/v1',
 'as_of':'2026-10-12',
 'source_basis':'public publisher and third-party website research retrieved Oct 12 2026; separate from provider capture receipts and reviewed card-in-hand evidence',
 'manifest_eligible':False,
 'production_registration_eligible':False,
 'default_physical_evidence_status':'NO PHYSICAL PHOTOS OR MEASUREMENTS RETAINED',
 'identifiers_policy':'No app-owned physical UUIDs allocated; case IDs are temporary research labels, not collection or catalog keys.',
 'finish_policy':'finish_candidates_not_authorized is documentation inventory only; never copy it into reviewed eligible finishes without physical validation',
 'sources':sources,
 'entries':entries,
 'review_required_per_entry':[
   'Full-resolution front image with card/ruler showing physical scale',
   'Full-resolution back image (especially Q1 scenario gold back)',
   'Uncropped screenshot of actual scanner ROI observation',
   'Macro bottom footer showing all literal printed separators and tokens',
   'Angled-light front photographs for each asserted finish, with comparison when ambiguity exists',
   'Macro distinguishing artwork, stamp, frame, size, distribution',
   'Legal/permission and evidence provenance; SHA-256 per retained file',
   'Two-person signoff on exact physical identity, complete candidate universe and eligible finishes',
   'Permanent app-owned physical UUID allocated only by reviewed signed transition process',
 ],
 'known_limitations':['One Piece repository branch not available through connected GitHub installation in this session; use as standalone research input, not codebase edit.',
   'No direct Lorcast live API JSON downloaded or verified for these entries; provider aliases not populated.',
   'No real card-in-hand evidence collected; site catalog scans and vendor listings are not physical corpus acceptance.',
   'No rights or publication consent to redistribute images established.',
   'Real camera geometry, orientation, size, finish classification and timing are not measured.' ],
}
assert len(set(e['case_id'] for e in entries))==len(entries)
assert all(not e['activation_permitted'] and e['physical_uuid'] is None and e['eligible_finish_ids'] is None for e in entries)
assert all(all(x in sources for x in e['source_ids']) for e in entries)
(ROOT/'lorcana_real_card_corpus.json').write_text(json.dumps(corpus,ensure_ascii=False,indent=2)+'\n')
print('entries',len(entries),'sources',len(sources))
