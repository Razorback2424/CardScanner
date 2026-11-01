#!/usr/bin/env python3
"""Deterministic offline census of the five retained game catalogs.

Reads repository files only; never fetches providers, allocates identities, signs,
promotes, or edits catalog data. Source hashes identify the exact audited bytes.
Intentional scope gaps are reported, not failed. Only malformed structural data
returns a nonzero exit status. This is not an optical/physical completeness test.
"""
import argparse
import base64
import collections
import csv
import hashlib
import json
from pathlib import Path
import re
import sys
import uuid


class CatalogIntegrityError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise CatalogIntegrityError(message)


def counts(values):
    return dict(sorted(collections.Counter(values).items()))


def unique(rows, key, scope):
    result = {}
    for row in rows:
        identity = key(row)
        require(identity not in result, f'{scope}: duplicate identity {identity}')
        result[identity] = row
    return result


def uid(value):
    return str(uuid.UUID(value))


def footer_key(footer):
    return ':'.join(footer[key] for key in ['language', 'printedSetMarker', 'collectorNumber', 'denominator'])


def decode_json(data, scope):
    # Reject duplicate JSON object keys instead of silently keeping the last.
    def decode_pairs(pairs):
        return {key: pair[1] for key, pair in unique(pairs, lambda pair: pair[0], scope).items()}
    return json.loads(data, object_pairs_hook=decode_pairs)


class Audit:
    def __init__(self, repo):
        self.repo = Path(repo).resolve()
        self.sources = {}
        self.discrepancies = []

    def text(self, path):
        target = (self.repo / path).resolve()
        require(target.is_relative_to(self.repo), f'Resource escapes repository: {path}')
        data = target.read_bytes()
        relative = target.relative_to(self.repo).as_posix()
        self.sources[relative] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        return data.decode('utf-8')

    def json(self, path):
        return decode_json(self.text(path), str(path))

    def gap(self, game, code, identity, scope, detail, disposition='review_required'):
        self.discrepancies.append(dict(game=game, code=code, identity=str(identity),
            scope=scope, disposition=disposition, detail=detail))


def validate_pokemon_slots(entry, rows):
    expected = entry['set']['catalogID']
    require(entry['providerID'] == expected['providerID'], 'Pokemon manifest provider/set identity mismatch')
    unique(rows, lambda row: (row['providerID'], (row.get('masterSetVariant') or {}).get('id')),
        f"Pokemon physical slots in {entry['resource']}")
    for row in rows:
        require(row['game'] == 'pokemon' and row['setID'] == expected,
            f"Pokemon slot belongs to another set: {row['providerID']}")
    return {'rows': len(rows), 'standardSlots': sum(not row.get('isExpandedMasterSetVariant', False) for row in rows)}


def pokemon(audit):
    root = Path('TradingCardScanner/PokemonChecklistSnapshot')
    manifest = audit.json(root / 'manifest.json')
    entries = manifest['entries']
    unique(entries, lambda entry: json.dumps(entry['set']['catalogID'], sort_keys=True), 'Pokemon checklist sets')
    provider_ids, card_ids, variants, per_set, all_normal = set(), set(), [], [], []
    for entry in entries:
        rows = audit.json(root / entry['resource'])
        measured = validate_pokemon_slots(entry, rows)
        provider_ids.add(entry['providerID'])
        card_ids.update(row['providerID'] for row in rows)
        variants.extend((row.get('masterSetVariant') or {}).get('id', '(unspecified)') for row in rows)
        per_set.append(dict(providerID=entry['providerID'], printRun=entry['set']['catalogID'].get('pokemonPrintRun'),
            rows=measured['rows'], standardSlots=measured['standardSlots'], declaredCardCount=entry['set']['cardCount']))
        if rows and all((row.get('masterSetVariant') or {}).get('id') == 'normal' for row in rows):
            all_normal.append(dict(providerID=entry['providerID'], rows=len(rows)))
            audit.gap('pokemon', 'rawChecklistUsesOnlyNormalFinish', entry['providerID'], 'raw snapshot',
                f"{len(rows)} rows. Review physical finish evidence and read-time corrections before treating this as complete finish coverage.",
                'source_risk_cohort')
        if entry.get('expandedSlotCount') != measured['rows']:
            audit.gap('pokemon', 'declaredSlotCountDifference', entry['resource'], entry['providerID'],
                f"Manifest expandedSlotCount={entry.get('expandedSlotCount')}; retained rows={measured['rows']}.")
        if entry['set']['cardCount'] != measured['standardSlots']:
            audit.gap('pokemon', 'displayCountDiffersFromStandardSlots', entry['resource'], entry['providerID'],
                f"Display cardCount={entry['set']['cardCount']}; standard slots={measured['standardSlots']}; counts have different semantics.",
                'informational')
    # The bundled registry is assembled in Swift, not stored as a JSON release.
    # Inventory literal declarations only; this does not execute or validate Swift.
    definitions = audit.text('TradingCardScanner/Services/SetCodeMap.swift')
    registry = audit.text('TradingCardScanner/Services/PokemonCatalogRegistry.swift')
    declared = re.findall(r'\.init\(printed(?:Code|Prefix):\s*"([^"]+)",\s*tcgdexSetID:\s*"([^"]+)"', definitions)
    require(declared, 'No Pokemon literal seed definitions found; extraction needs review')
    literals = re.findall(r'providerSetID:\s*"([^"]+)"', registry)
    descriptor_ids = {provider for _, provider in declared} | set(literals)
    require(len({provider for _, provider in declared}) == len(declared), 'Duplicate Pokemon literal provider definition')
    publisher = audit.json('publisher/catalog-input.json')['sets']
    publisher_ids = set(unique(publisher, lambda row: row['providerSetID'], 'Pokemon publisher input'))
    for provider in sorted(descriptor_ids - provider_ids):
        audit.gap('pokemon', 'seedDescriptorWithoutOfflineChecklist', provider, 'bundled seed',
            'Static seed descriptor has no retained checklist payload; live resolution may still be available.')
    for provider in sorted(provider_ids - descriptor_ids):
        audit.gap('pokemon', 'checklistOutsideModernSeedDescriptors', provider, 'bundled checklist',
            'Not in the modern printed-code/promo/energy/membership seed; historical recognition may apply.', 'informational')
    for provider in sorted(descriptor_ids ^ publisher_ids):
        audit.gap('pokemon', 'seedPublisherDescriptorDifference', provider, 'publisher input',
            'Only in static bundled declarations.' if provider in descriptor_ids else 'Only in publisher input.')
    return dict(snapshotGeneratedAt=manifest['generatedAt'], checklistEntries=len(entries),
        distinctProviderSets=len(provider_ids), physicalSlotRows=len(variants), uniqueProviderCardIDs=len(card_ids),
        slotCountsByVariant=counts(variants), sets=per_set,
        staticSeedDescriptorCount=len(descriptor_ids), staticSeedDescriptorIDs=sorted(descriptor_ids),
        publisherInputDescriptors=len(publisher), seedDescriptorsAbsentOffline=sorted(descriptor_ids - provider_ids),
        rawNormalOnlyEntries=all_normal, rawNormalOnlyRows=sum(entry['rows'] for entry in all_normal),
        boundary='Static seed declarations and offline checklist slots are different inventories; historical/live routes are not executed.')


def validate_magic_treatments(row):
    # Match MagicTreatmentCatalog's whitespace/case handling. Unknown nonempty
    # IDs are retained for forward compatibility, not rejected as missing data.
    ids = [value.strip().lower() for value in row['treatments'] if value.strip()]
    require(ids and len(ids) == len(set(ids)), f"Invalid Magic treatment list: {row['id']}")
    qualifier_keys = []
    for key, value in row.get('qualifiers', {}).items():
        normalized = key.strip().lower()
        require(normalized and value.strip() and normalized in ids,
            f"Dangling Magic treatment qualifier: {row['id']}")
        require(normalized not in qualifier_keys, f"Duplicate Magic treatment qualifier: {row['id']}")
        qualifier_keys.append(normalized)
    return ids


def compare_magic_audit(runtime, snapshot, retained, audit):
    # Different generations can be legitimate; drift is a review item rather
    # than a structural failure or permission to regenerate either artifact.
    for runtime_key, source_value in [
        ('sourceContentSHA256', snapshot['source']['contentSHA256']),
        ('sourceBulkDataID', snapshot['source']['bulkDataID']),
        ('sourceBulkDataType', snapshot['source']['bulkDataType']),
        ('sourceAuditSchemaVersion', snapshot['schemaVersion']),
        ('sourceAuditRulesVersion', snapshot['rulesVersion']),
    ]:
        if runtime[runtime_key] != source_value:
            audit.gap('magic', 'runtimeAuditSourceDifference', runtime_key, 'treatment enrichment provenance',
                f"Runtime={runtime[runtime_key]}; retained audit={source_value}.")
    if len(retained) != snapshot['auditedCardCount']:
        audit.gap('magic', 'declaredAuditTotalDifference', 'manifest', 'test-only treatment snapshot',
            f"Manifest auditedCardCount={snapshot['auditedCardCount']}; retained rows={len(retained)}.")
    for row in runtime['entries']:
        identity = uid(row['id'])
        if identity not in retained:
            audit.gap('magic', 'runtimeTreatmentOutsideRetainedAudit', identity, 'runtime treatment catalog',
                'Runtime exact-printing enrichment is not present in the retained test-only treatment snapshot.')
        elif any(row[key].strip().lower() != retained[identity][key].strip().lower()
                 for key in ['setCode', 'collectorNumber']):
            audit.gap('magic', 'runtimeTreatmentIdentityDiffersFromAudit', identity, 'runtime treatment catalog',
                f"Runtime={row['setCode']}:{row['collectorNumber']}; retained audit="
                f"{retained[identity]['setCode']}:{retained[identity]['collectorNumber']}.")


def magic(audit):
    seed = audit.json('TradingCardScanner/MagicCatalogSeed/catalog.json')
    by_code = unique(seed['sets'], lambda row: row['code'].lower(), 'Magic production set descriptor')
    unique(seed['sets'], lambda row: uid(row['scryfallSetID']), 'Magic production set UUID')
    for row in seed['sets']:
        if row.get('parentSetCode'):
            require(row['parentSetCode'].lower() in by_code, f"Magic dangling parent: {row['code']}")
    compiled = audit.text('TradingCardScanner/Services/MagicSetSnapshot.swift')
    compiled_codes = set(re.findall(r'^\s*\("([A-Z0-9]+)",\s*(?:[0-9]+|nil)\)', compiled, re.MULTILINE))
    require(compiled_codes, 'No Magic compiled set definitions found; extraction needs review')
    seed_scan_codes = {row['code'].upper() for row in seed['sets'] if row['scanEnabled']}
    for code in sorted(seed_scan_codes ^ compiled_codes):
        audit.gap('magic', 'seedCompiledVocabularyDifference', code, 'cold-start vocabulary',
            'Only in production set seed; legacy-live mode initially uses the compiled snapshot, then refreshes from the provider.'
            if code in seed_scan_codes else 'Only in the compiled snapshot, absent from seed scan-enabled descriptors.')
    rollout = audit.text('Config/MagicCatalogProduction.xcconfig')
    mode = re.search(r'^MAGIC_CATALOG_ROLLOUT_MODE\s*=\s*(\S+)', rollout, re.MULTILINE)
    runtime = audit.json('TradingCardScanner/MagicTreatmentCatalog/manifest.json')
    vocabulary = set(audit.json('TradingCardScanner/MagicTreatmentCatalog/vocabulary.json'))
    mappings = unique(runtime['entries'], lambda row: uid(row['id']), 'Magic runtime treatment printing')
    treatment_ids = []
    for row in mappings.values():
        ids = validate_magic_treatments(row)
        treatment_ids.extend(ids)
        for value in set(ids) - vocabulary:
            audit.gap('magic', 'treatmentOutsideVocabulary', row['id'], row['setCode'], value,
                'informational')  # Unknown treatments are deliberately forward compatible.
    audit_root = Path('TradingCardScanner/MagicTreatmentSnapshot')
    snapshot = audit.json(audit_root / 'manifest.json')
    unique(snapshot['entries'], lambda row: row['code'], 'Magic test-only snapshot set')
    retained, english_paper, suffixes = 0, 0, collections.Counter()
    audit_rows = {}
    for entry in snapshot['entries']:
        if not entry.get('resource'):
            require(entry['auditedCardCount'] == 0, f"Magic missing nonempty audit resource: {entry['code']}")
            continue
        rows = audit.json(audit_root / entry['resource'])
        if len(rows) != entry['auditedCardCount']:
            audit.gap('magic', 'declaredAuditCountDifference', entry['code'], 'test-only treatment snapshot',
                f"Manifest auditedCardCount={entry['auditedCardCount']}; retained rows={len(rows)}.")
        for row in rows:
            identity = uid(row['id'])
            require(identity not in audit_rows, f'Magic test-only snapshot duplicate UUID: {identity}')
            require(row['setCode'] == entry['code'], f'Magic test-only snapshot set mismatch: {identity}')
            require(set(row.get('finishes', [])) <= {'nonfoil', 'foil', 'etched'}, f'Magic unsupported finish: {identity}')
            audit_rows[identity] = row
            english_paper += row.get('language') == 'en' and not row.get('digital', False)
            if row.get('collectorNumberSuffix'):
                suffixes[row['collectorNumberSuffix']] += 1
        retained += len(rows)
    compare_magic_audit(runtime, snapshot, audit_rows, audit)
    return dict(productionSetSeed=dict(generatedAt=seed['generatedAt'], revision=seed['revision'],
            descriptors=len(by_code), scanEnabledDescriptors=sum(row['scanEnabled'] for row in seed['sets']),
            browseEnabledDescriptors=sum(row['browseEnabled'] for row in seed['sets']),
            setTypeCounts=counts(row['setType'] for row in seed['sets'])),
        compiledColdStartVocabulary=dict(setCodes=len(compiled_codes),
            seedScanCodesAbsentCompiled=sorted(seed_scan_codes - compiled_codes),
            compiledCodesAbsentSeedScan=sorted(compiled_codes - seed_scan_codes)),
        configuredProductionRollout=mode.group(1) if mode else None,
        runtimeTreatmentCatalog=dict(generatedAt=runtime['generatedAt'], exactPrintingMappings=len(mappings),
            treatmentCounts=counts(treatment_ids)),
        testOnlyTreatmentAudit=dict(generatedAt=snapshot['generatedAt'], setEntries=len(snapshot['entries']),
            retainedAuditedRows=retained, declaredTotalSourceCards=snapshot['totalCardCount'],
            englishNonDigitalRetainedRows=english_paper, collectorSuffixCounts=dict(sorted(suffixes.items()))),
        boundary='Card-level Magic data remains live. The full treatment snapshot is test-only, includes excluded/non-English/digital records, and is not scanner coverage.')


def one_piece_registry(registry):
    cards = unique(registry['canonicalCards'], lambda row: row['id'], 'One Piece canonical card')
    artworks = unique(registry['artworks'], lambda row: uid(row['id']), 'One Piece artwork')
    printings = unique(registry['printings'], lambda row: uid(row['id']), 'One Piece printing')
    products = unique(registry['products'], lambda row: row['id'], 'One Piece product')
    variants = set(unique(registry['variants'], lambda row: row['id'], 'One Piece variant'))
    families, market_keys, mapped_eligible = collections.defaultdict(list), set(), set()
    eligible = []
    for identity, row in printings.items():
        require(row['canonicalCardID'] in cards and uid(row['artworkID']) in artworks,
            f'One Piece dangling canonical/artwork reference: {identity}')
        require(not row.get('releaseID') or row['releaseID'] in products, f'One Piece dangling product: {identity}')
        require(row['language'] == cards[row['canonicalCardID']]['language'], f'One Piece language mismatch: {identity}')
        require(set(row['supportedVariantIDs']) <= variants, f'One Piece unknown finish: {identity}')
        if row['status'] != 'superseded':
            families[row['canonicalCardID']].append(row)
        if row['status'] == 'verified' and row['language'] == 'en':
            require(row['supportedVariantIDs'], f'One Piece verified printing without finish: {identity}')
            eligible.append(row)
        for mapping in row.get('marketMappings', []):
            require(uid(mapping['printingID']) == identity and mapping['variantID'] in row['supportedVariantIDs'],
                f'One Piece dangling market printing/finish: {identity}')
            if mapping['status'] == 'exact' and mapping['provider'] == 'tcgplayer':
                require({'normal': 'Normal', 'foil': 'Foil'}.get(mapping['variantID']) == mapping.get('providerVariantID'),
                    f'One Piece invalid exact market finish: {identity}')
                if row['status'] == 'verified':
                    market_key = (int(mapping['productID']), mapping['providerVariantID'])
                    require(market_key not in market_keys, f'One Piece duplicate exact market lane: {market_key}')
                    market_keys.add(market_key)
                    if row['language'] == 'en':
                        mapped_eligible.add(identity)
    for appearance in registry.get('appearances', []):
        require(uid(appearance['printingID']) in printings and appearance['productID'] in products,
            'One Piece dangling product appearance')
    english_families = [families[identity] for identity, card in cards.items() if card['language'] == 'en']
    return dict(canonicalCards=len(cards), printingRecords=len(printings), statuses=counts(row['status'] for row in printings.values()),
        verifiedEnglishPrintings=len(eligible), exactMarketMappings=len(market_keys),
        exactMarketProvider='tcgplayer', verifiedEnglishMappedPrintings=len(mapped_eligible),
        verifiedEnglishPrintingsWithoutExactMarketMapping=len(eligible) - len(mapped_eligible),
        canonicalCompleteFlags=sum(card.get('printingCoverageComplete', False) for card in cards.values()),
        automaticSingletonFamilies=sum(len(rows) == 1 and rows[0]['status'] == 'verified' for rows in english_families),
        printingChoiceFamilies=sum(len(rows) > 1 and any(row['status'] == 'verified' for row in rows) for rows in english_families),
        heldOnlyCanonicalCards=sum(not any(row['status'] == 'verified' for row in rows) for rows in english_families)), printings, families


def one_piece(audit):
    envelope = audit.json('TradingCardScanner/OnePieceOwnerCatalog/one-piece-owner-catalog.json')
    encoded = envelope['payload']
    installed = decode_json(base64.urlsafe_b64decode(encoded + '=' * (-len(encoded) % 4)), 'One Piece owner payload')
    active_summary, active, active_families = one_piece_registry(installed['registry'])
    reviewed = audit.json('OnePieceCatalogCore/ReviewCorpus/english-stress/registry.json')
    review_summary, review, _ = one_piece_registry(reviewed)
    active_summary.update(revision=installed['revision'], generatedAt=installed['generatedAt'])
    rollout = audit.text('Config/OnePieceCatalogProduction.xcconfig')
    mode = re.search(r'^ONE_PIECE_CATALOG_ROLLOUT_MODE\s*=\s*(\S+)', rollout, re.MULTILINE)
    for identity in sorted(set(review) - set(active)):
        row = review[identity]
        siblings = active_families.get(row['canonicalCardID'], [])
        automatic = len(siblings) == 1 and siblings[0]['status'] == 'verified'
        audit.gap('one-piece', 'reviewedPrintingAbsentFromOwnerSeed', identity, row['canonicalCardID'],
            f"{row.get('treatment') or row.get('distributionLabel') or row['status']}; active number-only singleton={automatic}.",
            'signed_adoption_pending')
    for canonical, rows in sorted(active_families.items()):
        if not any(row['status'] == 'verified' for row in rows):
            audit.gap('one-piece', 'noVerifiedPrinting', canonical, 'bundled owner catalog',
                'Retained states: ' + ', '.join(sorted({row['status'] for row in rows})), 'intentionally_held')
    return dict(bundledOwnerCatalog=active_summary, retainedReviewCorpus=review_summary,
        configuredProductionRollout=mode.group(1) if mode else None,
        reviewOnlyPrintingIDs=sorted(set(review) - set(active)), ownerOnlyPrintingIDs=sorted(set(active) - set(review)),
        boundary='The owner seed is signed/local-only. This census decodes but does not verify its signature or activate a release; production configuration remains a separate gate.')


def lorcana(audit):
    root = Path('TradingCardScanner/LorcanaCatalogSeed')
    discovery = audit.json(root / 'discovery.json')
    market = audit.json(root / 'market.json')
    require(market['discoverySHA256'] == audit.sources[(root / 'discovery.json').as_posix()]['sha256'],
        'Lorcana physical catalog is bound to different discovery bytes')
    sources = unique(discovery['cards'], lambda row: row['id'], 'Lorcana discovery card')
    unique(discovery['sealed'], lambda row: row['id'], 'Lorcana sealed product')
    cards = unique(market['canonicalCards'], lambda row: uid(row['id']), 'Lorcana canonical card')
    families = unique(market['printFamilies'], lambda row: footer_key(row['footer']), 'Lorcana footer family')
    printings = unique(market['physicalPrintings'], lambda row: uid(row['id']), 'Lorcana physical printing')
    universes = unique(market['universes'], lambda row: footer_key(row['footer']), 'Lorcana footer universe')
    active, physical_sources, market_keys = collections.defaultdict(set), set(), set()
    lanes = 0
    for identity, row in printings.items():
        footer = footer_key(row['identity']['footer'])
        require(footer in families and uid(row['identity']['canonicalCardID']) in cards,
            f'Lorcana dangling family/canonical reference: {identity}')
        finishes = {value['finish'] for value in row['finishes']}
        require(len(finishes) == len(row['finishes']) and finishes <= {'normal', 'foil'}, f'Lorcana invalid finish: {identity}')
        if row['status'] != 'superseded':
            active[footer].add(identity)
        if row['status'] == 'verified':
            physical_sources.update(alias['id'] for alias in row['sourceAliases'])
        for mapping in row.get('marketMappings') or []:
            require(mapping['finish'] in finishes, f'Lorcana dangling mapping finish: {identity}')
            allowed = ['Normal'] if mapping['finish'] == 'normal' else ['Cold Foil', 'Holofoil']
            require(mapping['providerVariantID'] in allowed, f'Lorcana wrong market lane: {identity}')
            if row['status'] != 'superseded':
                key = (mapping['productID'], mapping['providerVariantID'])
                require(key not in market_keys, f'Lorcana duplicate market lane: {key}')
                market_keys.add(key)
            lanes += 1
    for footer, universe in universes.items():
        require(footer in families and {uid(value) for value in universe['printingIDs']} == active[footer],
            f'Lorcana dangling/incomplete universe membership: {footer}')
    held = [row for identity, row in sources.items() if identity not in physical_sources]
    for row in held:
        audit.gap('lorcana', 'discoveryOnly', row['id'], row['setCode'],
            row['name'] + ' | ' + row['printedIdentifier'], 'intentionally_held')
    return dict(discoveryGeneratedOn=discovery['generatedOn'], physicalReviewedAtFoundationSeconds=market['reviewedAt'],
        discoveryRows=len(sources), sourceSetCounts=counts(row['setCode'] for row in sources.values()),
        sealedProducts=len(discovery['sealed']), reviewedPhysicalPrintings=len(printings), reviewedFooterFamilies=len(families),
        completeReviewedUniverses=sum(row['isComplete'] for row in universes.values()),
        physicalStatusCounts=counts(row['status'] for row in printings.values()),
        mappedPrintings=sum(bool(row.get('marketMappings')) for row in printings.values()), exactFinishMappings=lanes,
        discoveryOnlyRows=len(held), discoveryOnlyBySet=counts(row['setCode'] for row in held),
        boundary='Discovery is not physical acquisition authority. Unreviewed rows and incomplete universes remain held.')


YUGIOH_EDITIONS = {'yugioh1stEdition', 'yugiohUnlimited', 'yugiohLimited'}


def yugioh_summary(seed, audit=None):
    sets = unique(seed['sets'], lambda row: row['g'], 'Yu-Gi-Oh set group')
    cards = seed['cards']
    unique(cards, lambda row: uid(row['id']), 'Yu-Gi-Oh canonical card')
    printings = unique(seed['printings'], lambda row: uid(row['id']), 'Yu-Gi-Oh printing')
    unique(seed['printings'], lambda row: row['p'], 'Yu-Gi-Oh product')
    by_code, eligible, eligible_ids = collections.defaultdict(list), [], set()
    for identity, row in printings.items():
        require(isinstance(row['k'], int) and 0 <= row['k'] < len(cards) and row['g'] in sets,
            f'Yu-Gi-Oh dangling card/set reference: {identity}')
        require(set(row['e']) <= YUGIOH_EDITIONS and set(row['pe']) <= YUGIOH_EDITIONS,
            f'Yu-Gi-Oh unsupported edition: {identity}')
        require(len(row['e']) == len(set(row['e'])), f'Yu-Gi-Oh duplicate edition: {identity}')
        memberships = row.get('m') or []
        unique(memberships, lambda value: value['e'], f'Yu-Gi-Oh membership in {identity}')
        require({value['e'] for value in memberships} <= set(row['e']), f'Yu-Gi-Oh dangling edition membership: {identity}')
        supported = row.get('ir') is None and row['e'] and (row['ec'] or memberships)
        if supported:
            eligible.append(row)
            eligible_ids.add(identity)
        elif audit:
            audit.gap('yugioh', 'discoveryOnlyPrinting', identity, row['c'],
                row['pn'] + ' | ' + (row.get('ir') or 'no supported edition membership'), 'intentionally_held')
        by_code[row['c']].append(row)
    auto, incomplete = set(seed['autoEligibleCodes']), set(seed['incompleteCodes'])
    require(auto.isdisjoint(incomplete), 'Yu-Gi-Oh automatic and incomplete codes overlap')
    require(auto <= set(by_code), 'Yu-Gi-Oh automatic code has no printing')
    for code in auto:
        rows = by_code[code]
        require(len(rows) == 1 and uid(rows[0]['id']) in eligible_ids and (rows[0]['ec'] or rows[0].get('pf')),
            f'Yu-Gi-Oh automatic code lacks its unique reviewed family: {code}')
    conflicts = {code: rows for code, rows in by_code.items() if len({row['k'] for row in rows}) > 1}
    supported_conflicts = {code: rows for code, rows in conflicts.items() if any(uid(row['id']) in eligible_ids for row in rows)}
    if audit:
        for code, rows in sorted(conflicts.items()):
            names = sorted({cards[row['k']]['n'] for row in rows})
            audit.gap('yugioh', 'codeMultipleCanonicalCards', code, 'printing family', ' | '.join(names),
                'review_required' if code in supported_conflicts else 'unsupported_placeholder')
    return dict(generatedAt=seed['capturedAt'], generation=seed['generation'], setGroups=len(sets),
        canonicalCards=len(cards), printingRecords=len(printings), distinctPrintedCodes=len(by_code),
        explicitSelectionSupportedPrintings=len(eligible), automaticFamilyCodes=len(auto),
        automaticFamilyPrintings=sum(row['c'] in auto for row in eligible),
        explicitChoiceOnlyPrintings=sum(row['c'] not in auto for row in eligible),
        discoveryOnlyPrintings=len(printings) - len(eligible), incompleteCodes=len(incomplete),
        identityReasonCounts=counts(row.get('ir') or '(none)' for row in printings.values()),
        canonicalLinkCounts=counts(row.get('canonicalLink') or '(unspecified)' for row in printings.values()),
        codeCanonicalConflicts=sorted(conflicts), supportedCodeCanonicalConflicts=sorted(supported_conflicts),
        boundary='Supported/choice counts mirror seed edition eligibility; native picker distinction checks are not executed. Automatic-family eligibility does not establish optical success or complete edition coverage. Pricing memberships are retained provider evidence.')


def run(repo):
    audit = Audit(repo)
    if (audit.repo / 'scripts/audit_catalog_coverage.py').is_file():
        audit.text('scripts/audit_catalog_coverage.py')
    results, errors = {}, []
    functions = [('pokemon', pokemon), ('magic', magic), ('one-piece', one_piece), ('lorcana', lorcana),
                 ('yugioh', lambda state: yugioh_summary(state.json('TradingCardScanner/YuGiOhCatalogSeed/catalog.json'), state))]
    for game, operation in functions:
        try:
            results[game] = operation(audit)
        except (CatalogIntegrityError, KeyError, ValueError, TypeError, OSError) as error:
            errors.append(dict(game=game, error=str(error)))
            audit.gap(game, 'structuralError', game, 'input validation', str(error), 'structural_error')
    discrepancies = sorted(audit.discrepancies, key=lambda row: tuple(row[key] for key in ['game', 'code', 'scope', 'identity', 'detail']))
    return dict(schemaVersion=1, boundary='Offline retained-data census. No network, signing, publication, catalog promotion, camera test, or claim of all-card completeness.',
        games=results, structuralErrors=errors, discrepancyCounts=counts(row['game'] for row in discrepancies),
        sources=dict(sorted(audit.sources.items()))), discrepancies


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path, required=True, help='Directory for summary.json and discrepancies.csv')
    args = parser.parse_args()
    summary, discrepancies = run(args.repo)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'summary.json').write_text(json.dumps(summary, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    with (args.output / 'discrepancies.csv').open('w', newline='', encoding='utf-8') as stream:
        writer = csv.DictWriter(stream, fieldnames=['game', 'code', 'identity', 'scope', 'disposition', 'detail'], lineterminator='\n')
        writer.writeheader()
        writer.writerows(discrepancies)
    print(json.dumps(dict(games=list(summary['games']), sourceFiles=len(summary['sources']),
        discrepancies=len(discrepancies), structuralErrors=summary['structuralErrors']), sort_keys=True))
    return 1 if summary['structuralErrors'] else 0


if __name__ == '__main__':
    sys.exit(main())
