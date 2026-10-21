# Yu-Gi-Oh catalog build report

Policy: yugioh-provider-membership-v1-2026-10-21. Raw offline source replay; cross-snapshot audit projection is not an input.

Captured through 2026-10-21T02:26:40+00:00. All groups read successfully.

Positive exact-product observations support explicit edition choices; they do not establish physical coverage or current prices. No group unions authorize editions. Product-status precedence is contradiction, discovery without membership, automatic eligibility, then explicit choice. Unsupported grammar remains discovery-only. The separate exclusions ledger preserves every upstream omitted product and its reason.

```json
{
  "groups": 659,
  "products": 47910,
  "printings": 46542,
  "codes": 37869,
  "incompleteCodes": 11245,
  "automaticCodes": 0,
  "verifiedPhysicalProducts": 0,
  "unknownCoverageProducts": 46542,
  "manualEligibleProducts": 46303,
  "observedLanes": {
    "yugiohLimited": 2425,
    "yugioh1stEdition": 36539,
    "yugiohUnlimited": 21029
  },
  "productStatusPartition": {
    "automaticAcquisitionEligible": 0,
    "explicitChoiceOnlyEligible": 46303,
    "discoveryOnly": 239,
    "quarantined": 0
  },
  "legitimatelyExcluded": 932,
  "excludedPendingClassification": {
    "missingPrintedIdentity": 436
  },
  "supportedPairs": 59965,
  "quotePairs": 58264,
  "correspondenceRuleVersion": "yugioh-correspondence-v1-2026-10-21",
  "taxonomyScopeDriftGroups": [],
  "upstreamDisposition": {
    "legitimatelyExcluded": 932,
    "discoveryPendingIdentity": 436
  },
  "sourceProductStatusPartition": {
    "automaticAcquisitionEligible": 0,
    "explicitChoiceOnlyEligible": 46303,
    "discoveryOnly": 675,
    "quarantined": 0,
    "legitimatelyExcluded": 932
  }
}
```

## aliasMatch: 109

[58143, 33214, 33220, 39345, 183571, 483483, 26488, 29045, 23630, 23662, 23689, 23736, 23769, 23777, 24367, 33498, 33515, 23856, 23920, 23935, 23941, 25812, 25852, 25885, 80869, 32264, 21728, 22194, 21725, 56709, 21832, 22072, 22301, 22568, 22928, 21762, 57783, 22064, 22342, 23325, 26690, 23447, 58795, 22950, 23362, 23402, 23404, 58835, 33708, 33724]

## foreignLanguage: 51

[200191, 200195, 606744, 251882, 251883, 251884, 251885, 251886, 251887, 251888, 251889, 251890, 251891, 251892, 251893, 251894, 251896, 251897, 251898, 251899, 251900, 251901, 251902, 251903, 251904, 251905, 251906, 496776, 496778, 496780, 496781, 496782, 496783, 496786, 496789, 496795, 496799, 496806, 496809, 496810, 496812, 496815, 496819, 496824, 496826, 496828, 496830, 496832, 496836, 496837]

## noEditionLane: 212

[33075, 214603, 80868, 80869, 80870, 80871, 80873, 80874, 80877, 80878, 80881, 80895, 77404, 77619, 80347, 80474, 80487, 80510, 80526, 80531, 80556, 80558, 94929, 94949, 94968, 58655, 229394, 229395, 229407, 81888, 26691, 33482, 26169, 26579, 228257, 22708, 26596, 26598, 26599, 205181, 721768, 721769, 26600, 80626, 80632, 78131, 78166, 82261, 82263, 82265]

## noNumber: 1317

[206882, 206883, 206884, 206885, 206886, 206887, 206888, 206889, 206890, 206891, 206892, 206893, 206894, 206897, 206899, 206900, 206901, 206902, 206870, 206871, 206872, 206873, 206874, 206875, 206903, 206904, 206905, 206906, 206907, 206908, 206909, 206910, 206911, 206912, 206913, 206914, 206915, 206916, 206918, 206922, 206923, 206924, 206925, 206927, 206929, 206930, 206931, 206932, 206933, 206934]

## noRarity: 0

[]

## physicalCoverageUnknown: 46542

[22800, 22801, 22802, 22803, 22804, 22805, 23340, 23341, 23342, 23343, 23344, 23345, 24511, 24512, 24513, 24514, 24515, 24516, 26452, 26453, 26454, 80158, 90804, 90983, 26358, 26455, 26456, 26457, 26458, 26459, 33114, 33115, 33116, 33117, 79688, 79689, 81774, 33118, 33119, 33120, 33121, 79085, 79086, 79087, 79088, 38509, 38510, 38511, 38512, 38513]

## unparsedCode: 34

[108333, 108334, 108335, 178044, 178045, 194836, 194837, 194838, 196883, 196884, 721861, 721862, 217523, 217524, 217525, 217526, 217527, 217528, 217529, 217530, 217531, 217532, 246234, 246235, 246236, 246237, 246238, 246239, 246240, 617867, 617869, 616046, 616047, 616048]

## Incomplete reasons

{"nameMismatch": 821, "printingCorrespondenceGap": 9752, "printingShortfall": 239, "rarityShortfall": 1181, "unreviewedCorrespondence": 11120}

## Source provenance

Each input records URL, cache timestamp, provider timestamp when supplied, and SHA-256.

```json
[
  {
    "url": "https://tcgcsv.com/tcgplayer/categories",
    "sha256": "6613c903449d22d467880c49120f21c120dfc5d200260ff02d48ecdcdc670c48",
    "cachedAt": "2026-10-21T02:18:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/groups",
    "sha256": "58e899ec6252fdc28d411ba67b01d7415211b3eaf4a3f4820b39a0dfb806f8ed",
    "cachedAt": "2026-10-21T02:18:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24822/products",
    "sha256": "9778277c8eb42a22a06b1b778e9fbd06170fdaa4874c76f665eb0f91d2a19992",
    "cachedAt": "2026-10-21T02:18:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24822/prices",
    "sha256": "8d1ee40135d0dbd69a01fae93e4a83e9b26cec5aee0c2e34719b201e6d24eaca",
    "cachedAt": "2026-10-21T02:18:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24808/products",
    "sha256": "01819ad98af3a22d468ce9d58fdc0c010e4ab9fdcebca1adca658c34e5a52391",
    "cachedAt": "2026-10-21T02:18:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24808/prices",
    "sha256": "2ecede377fea7afb11cd20c87498fa7ddcf325162e4ec67a52a7e0f631041bc7",
    "cachedAt": "2026-10-21T02:18:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24806/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:18:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24806/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:18:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24815/products",
    "sha256": "4a76292004bc90ba977d32c1c711abc62b0e99f95fe552985faa2f63df31fb02",
    "cachedAt": "2026-10-21T02:18:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24815/prices",
    "sha256": "81fe3a4953c1db2cfa8fd7962483d8adb0f88cce25f81bbdb03e0ade2899b06e",
    "cachedAt": "2026-10-21T02:18:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24707/products",
    "sha256": "f16fce65f8d57191cfd0285636fc67dbd0384309ba2ce395305c8662451aebea",
    "cachedAt": "2026-10-21T02:18:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24707/prices",
    "sha256": "f01195d9372b2ef1883601f3f66c5a2eaa4b015418252487a82edd07317e728a",
    "cachedAt": "2026-10-21T02:18:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24703/products",
    "sha256": "8c15eb8bf4b3d0ba369a44d01c45fc94fb3ad41a00684147c31d31c4d0d8c41f",
    "cachedAt": "2026-10-21T02:18:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24703/prices",
    "sha256": "72dd3d8d4e1a1a86f710da716a7ff5d07dd687a987e68c9a4c2abdd4c2d51323",
    "cachedAt": "2026-10-21T02:18:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24679/products",
    "sha256": "7f757eaf301dd7690c514998f43d27c2acedd796ea12236566a589fa51fe7a5a",
    "cachedAt": "2026-10-21T02:18:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24679/prices",
    "sha256": "af4204903dddb095360e58c0ca0ef971dcdb94147e981b05093e7daa50735705",
    "cachedAt": "2026-10-21T02:18:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24918/products",
    "sha256": "41f3e9720aaf3429f5f3a521c4d9786ab9380be06e838c67232c46cbb53eb8f5",
    "cachedAt": "2026-10-21T02:18:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24918/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:18:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24789/products",
    "sha256": "2f878be967bcfdff0b378801585e0ef8b85537d485425aa07cc12ca2b362f4e3",
    "cachedAt": "2026-10-21T02:18:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24789/prices",
    "sha256": "1b1448089cf0d18dfc0022a6eb3db0fc073f06f044a97ddab995e4d3ed16a548",
    "cachedAt": "2026-10-21T02:18:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24704/products",
    "sha256": "93f985f64baceb326c8f93d911a63298c88c1f1998d1b508793b79e8da0a6722",
    "cachedAt": "2026-10-21T02:18:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24704/prices",
    "sha256": "c1112c3c61cb018073f2d1f3c2d1f3a9d6434c04cf56d69967e088b54ad0d26b",
    "cachedAt": "2026-10-21T02:18:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24675/products",
    "sha256": "502f708b29dc61d4bf77eb6191745babaddd8a52fc0610eafd36e91931af90e0",
    "cachedAt": "2026-10-21T02:18:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24675/prices",
    "sha256": "4e1402f1e75d3e101e2095b59317853dfc0d35834cfb2d36f623f806e82bc719",
    "cachedAt": "2026-10-21T02:18:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24621/products",
    "sha256": "4a0e4ee52d686f4372d2fb77514cc843a036efa85dce939b710922af9ecbe71c",
    "cachedAt": "2026-10-21T02:18:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24621/prices",
    "sha256": "7c837a64d1aac50e50cd5226d66ffab439326ac1b52145555216a5c3b283def9",
    "cachedAt": "2026-10-21T02:18:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24581/products",
    "sha256": "ed7b46d99b4b8b9a8718b4ccd1043b6c8e75e4e0c29dc7541c8120ea26a78b76",
    "cachedAt": "2026-10-21T02:18:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24581/prices",
    "sha256": "ca218590c61cbdd8ac5d81ddb8794cca076458ada7470c6448de5abec0e7623c",
    "cachedAt": "2026-10-21T02:18:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24555/products",
    "sha256": "f2c17c019a9f74c55ec9179a1bf5aca3f189c8b867214c89fff9e4c0826b3295",
    "cachedAt": "2026-10-21T02:18:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24555/prices",
    "sha256": "02b41a9719bdcb6e8fa7f8b7066ffa043a1c2ff63f90ccd4158c417d877720ed",
    "cachedAt": "2026-10-21T02:18:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24549/products",
    "sha256": "976f324d6c4c3554631f0702a9b320e8955b20361916e30c5b2bf79bef460c58",
    "cachedAt": "2026-10-21T02:18:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24549/prices",
    "sha256": "ba152188490ff30d55b5791e66a53c42fda5aee50ac13cd5c1c143c5ecfc30e2",
    "cachedAt": "2026-10-21T02:18:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24559/products",
    "sha256": "ab9f0d92217db04091dfe29a5b74c7344002b936a53486148709f1d236b8a251",
    "cachedAt": "2026-10-21T02:18:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24559/prices",
    "sha256": "e93d530539eb16fd155bc64a2fe6f9c1e4df7afe76f80577d23896e80cc2bd9b",
    "cachedAt": "2026-10-21T02:18:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24542/products",
    "sha256": "b82c3b051352a4206373bd2ba684b6a13e1e4f57aa025f9ec46a096734ccf518",
    "cachedAt": "2026-10-21T02:18:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24542/prices",
    "sha256": "4de8c3422858430a8c826ec6bf7df843dfb1682bf2a2f8c2684045d0ddb45aab",
    "cachedAt": "2026-10-21T02:18:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24558/products",
    "sha256": "ee295ba8de97144bedceb56f724a659decf562139654280dfc33a144a8934cd7",
    "cachedAt": "2026-10-21T02:18:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24558/prices",
    "sha256": "b245e6b3f93354a83e26d2b9a471e8fad23a8c7ab37b3afd948a9e6956c98263",
    "cachedAt": "2026-10-21T02:18:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24486/products",
    "sha256": "46d1c7c245ddb556f08763f7bbfd9f92da5e2a015471e975229ab24196d549b4",
    "cachedAt": "2026-10-21T02:18:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24486/prices",
    "sha256": "9f459aa4e7ca1afb676c4ce5023f7aa27d447f2c9d2a18d1d63c4eda0ac6f2e0",
    "cachedAt": "2026-10-21T02:18:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24475/products",
    "sha256": "45b90686f622008923ec9cad17c349c6e09e478409ca7332287ddc87032eb108",
    "cachedAt": "2026-10-21T02:18:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24475/prices",
    "sha256": "6019e7c79654363dc02c521d4b67a3f5babd2ede691cc8093f57d8ca13d62d17",
    "cachedAt": "2026-10-21T02:18:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24396/products",
    "sha256": "1f3017bb9f230f92d868f4120575728ca9a3795b916b4318aacc1da37a46be54",
    "cachedAt": "2026-10-21T02:18:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24396/prices",
    "sha256": "9bded6713fffd4d24876888d30d3ff4a645e377815fa6f4a7d89ead990bc0b34",
    "cachedAt": "2026-10-21T02:18:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24392/products",
    "sha256": "f410686c62530f2c914fbe2d9d62fb1996f583605c1173ad51d3a3ce8866d5b3",
    "cachedAt": "2026-10-21T02:18:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24392/prices",
    "sha256": "6ee0aa1179a214c68306523639426b0b5a12e4e26aeaa36b192f536db6445bda",
    "cachedAt": "2026-10-21T02:18:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24358/products",
    "sha256": "00dffd19ae09aaa71671b19f74f5fd327ab78eedd70271834570334390cb9547",
    "cachedAt": "2026-10-21T02:18:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24358/prices",
    "sha256": "1e73abba0c5535b7dd6aa7285fc4d00f428c3e1b1d34a2d052dbaabe569b07d8",
    "cachedAt": "2026-10-21T02:18:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24506/products",
    "sha256": "ef9836ca4c0d0d9b9ca39ad1d65970a76b5ced15c19c9ad48097e9357fa24028",
    "cachedAt": "2026-10-21T02:18:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24506/prices",
    "sha256": "5d6a6667bff1eea2faaed82e1b7a0fd27ebd3f7d98fb5df27b1ea24458185ef3",
    "cachedAt": "2026-10-21T02:18:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24460/products",
    "sha256": "02bad4a8d1a5159387f553974f74f73fca202f73e324829a1222f731b3598a27",
    "cachedAt": "2026-10-21T02:18:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24460/prices",
    "sha256": "a27547c3044601e57054f75e36bff62b5098df9c850ef6fed71018a85624cadc",
    "cachedAt": "2026-10-21T02:18:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24357/products",
    "sha256": "d9a184fd08655882d84566ce9c7fa900cdfce50ea18b8c76b2b90b2b5d4193e9",
    "cachedAt": "2026-10-21T02:18:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24357/prices",
    "sha256": "7214e0ccf16003551417979ccdcdee136a76f35a92c9a2567279d6e8b11902be",
    "cachedAt": "2026-10-21T02:18:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24308/products",
    "sha256": "e23adc98d59fc4e668ae7a6f4b19199d14eef33f07ec19b834e274e84d84284d",
    "cachedAt": "2026-10-21T02:18:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24308/prices",
    "sha256": "898e688369c7a3d0285302383bc5960835a33044b20d6cd8f398faa3f2fd5dfc",
    "cachedAt": "2026-10-21T02:18:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24353/products",
    "sha256": "b9c7a4df9b4815b2efaed10ca8a2c8638e4882aba87cfa30100d8c9d1635dd45",
    "cachedAt": "2026-10-21T02:18:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24353/prices",
    "sha256": "2e9918dc76fcc6a8acce0664041b12ef0b67a4eec84785940b290a79e16d2f5c",
    "cachedAt": "2026-10-21T02:18:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24352/products",
    "sha256": "4de50cea585111051bab82bf0f552b7d491a2981803b346bb22fbea1f8bb21c9",
    "cachedAt": "2026-10-21T02:18:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24352/prices",
    "sha256": "d9cf52f54094b39809799346056bba8c80b8c1ca503c3920ccf16a0f38e47a38",
    "cachedAt": "2026-10-21T02:18:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24320/products",
    "sha256": "7375455cbf16365624e876f0217738484fd2e9c534040829f5a1266e9d55be01",
    "cachedAt": "2026-10-21T02:18:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24320/prices",
    "sha256": "ee651566891bfe92be9a1146e4b0b4a6fd233534c1ff9312f9de6f425ca1c9f9",
    "cachedAt": "2026-10-21T02:18:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24265/products",
    "sha256": "82a11a859758343b64f6e3aba0f014517b7f60a5062653141c50326bc58819ff",
    "cachedAt": "2026-10-21T02:18:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24265/prices",
    "sha256": "7015f9207f765841b885773fb5318d632735e0e4960ccccf51611316a3c91276",
    "cachedAt": "2026-10-21T02:18:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24264/products",
    "sha256": "25f46b6da42a54f1039269d7e7060393383919c38f941a2ceaa72da50d736f84",
    "cachedAt": "2026-10-21T02:18:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24264/prices",
    "sha256": "87ff547c4100db3e2c4d11977394073d9ef3bd5bc6fa6cef7938750045e0cd31",
    "cachedAt": "2026-10-21T02:19:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24263/products",
    "sha256": "1d15e2ff98f416d893c954a27601df4469a94ad4d29226d001fb3976c69f3033",
    "cachedAt": "2026-10-21T02:19:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24263/prices",
    "sha256": "482c61deaf93ba22ff91a83f25672c72004c8cdcaa3df5739df5edac95ca1c30",
    "cachedAt": "2026-10-21T02:19:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24351/products",
    "sha256": "0ecc6904144ee7f8591221debb60934aa99e2962a805df0ebbc7efcbfc4b4286",
    "cachedAt": "2026-10-21T02:19:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24351/prices",
    "sha256": "aefd9da1cb359020682177aa9db3fa9daded6412b64097e85f2d1caf14588820",
    "cachedAt": "2026-10-21T02:19:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23995/products",
    "sha256": "5de2fd5ef41383ee7d350bf2e47bb589457f557a13162cfddb827c990918d160",
    "cachedAt": "2026-10-21T02:19:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23995/prices",
    "sha256": "cc52e0b49b15de92b616dd12e93e7e308fb4a96d7bc22dad0fa832c86b60c532",
    "cachedAt": "2026-10-21T02:19:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23891/products",
    "sha256": "784ebed6f4164c97279c58b4a03775b12e2d302e08518430d58c5e573f7f0dbe",
    "cachedAt": "2026-10-21T02:19:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23891/prices",
    "sha256": "40b259eb6af22cef351f7d96733e90a2a1a4027764f990c72d1ea6eb4f18311d",
    "cachedAt": "2026-10-21T02:19:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23849/products",
    "sha256": "9a9cd26cf1ea42ad1c75c72225b7ff6340458a11a320af47bb199996888ff31a",
    "cachedAt": "2026-10-21T02:19:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23849/prices",
    "sha256": "262c06340c2bfdb43715a098b751d6f53cda58b288e8ce6016f9bc2d5265b3cb",
    "cachedAt": "2026-10-21T02:19:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24250/products",
    "sha256": "d2eab060680ccacab6560cfd77647fe6b41554dc28d1260d8a737f92ab80b045",
    "cachedAt": "2026-10-21T02:19:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24250/prices",
    "sha256": "6312224df8c95082924b0d827ce673a34991b6384dc5db66500e6fa3dfd49394",
    "cachedAt": "2026-10-21T02:19:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23786/products",
    "sha256": "a7bede41b7b8379e31c84f73768a89ca3292438d813ab57d626c659e56eb6d35",
    "cachedAt": "2026-10-21T02:19:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23786/prices",
    "sha256": "ebba67fc87f763c702260f40f0a8902da40723ab221e2f2f424bb77bdea2c805",
    "cachedAt": "2026-10-21T02:19:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23768/products",
    "sha256": "b805398908d274e833e1726eefd088e43fd1d2e94678bb9784bb638e4ef4ac77",
    "cachedAt": "2026-10-21T02:19:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23768/prices",
    "sha256": "6b43c1ca87ba5ff3a36ca187c060c745eb67a641368cfe3c3c1af44324313d70",
    "cachedAt": "2026-10-21T02:19:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23758/products",
    "sha256": "f24d765d131de537b9e1678b9560fa9e28f3083718a6b4b2d79fafc208711173",
    "cachedAt": "2026-10-21T02:19:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23758/prices",
    "sha256": "ff67f7e931fc5542b039451d96f241cab8f4e172086abd6244055b0dab27836d",
    "cachedAt": "2026-10-21T02:19:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23652/products",
    "sha256": "6800db89e17a80e3e6a8091092b893ae7172b5514d7020294b992f365382fe47",
    "cachedAt": "2026-10-21T02:19:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23652/prices",
    "sha256": "24b105dc517d5a4d6462654551952c11d656296a00c4bd2a6132878cbe83eb2e",
    "cachedAt": "2026-10-21T02:19:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23653/products",
    "sha256": "962717c0049b66c805d4748dbb2ab9b096352967c4327f585a554005b7027db9",
    "cachedAt": "2026-10-21T02:19:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23653/prices",
    "sha256": "7b76958d3e77d5f15d6c9e4780fbad90f7cfe96764c9b93692c7c5ce33f654c2",
    "cachedAt": "2026-10-21T02:19:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23656/products",
    "sha256": "f08816e13613de5e1d9a9eace471e528dc551c7e815ff0bb76f306ef28ab5e21",
    "cachedAt": "2026-10-21T02:19:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23656/prices",
    "sha256": "3d905e959f4dc37a03533f3aff8ed561dfe80bf08f7bdc252a4217141e6fbd5b",
    "cachedAt": "2026-10-21T02:19:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23657/products",
    "sha256": "422c38cfc99a5fdd002c13b250b82f34826c86fe982abcec294c09e9bfcc3f55",
    "cachedAt": "2026-10-21T02:19:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23657/prices",
    "sha256": "3c4c36d648649a5cfd387c94dc6f66c26fcd6256070f48193d87891c0fb5b5a8",
    "cachedAt": "2026-10-21T02:19:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23539/products",
    "sha256": "87b7ae109294aa612d8375a675b32a992501ac8ffb226efc4ae130d95cdbfef4",
    "cachedAt": "2026-10-21T02:19:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23539/prices",
    "sha256": "4e03631e015c8661b4c422b7ae8653c8ec1ad42934a065118e3f3e66cd2cef06",
    "cachedAt": "2026-10-21T02:19:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23481/products",
    "sha256": "73ed018dff2dca79ffc2e5db4cbc823c8cf25e04bbb36e0390c1f040c78339ac",
    "cachedAt": "2026-10-21T02:19:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23481/prices",
    "sha256": "ee875ec0b149d879140680d8cae89a6a960fcee3c80c901c208921e719b8fd72",
    "cachedAt": "2026-10-21T02:19:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23592/products",
    "sha256": "9c28bbbde117961ceccbec7e3a1e21c9f4c1ed1bf066d45ef7f43031601b936b",
    "cachedAt": "2026-10-21T02:19:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23592/prices",
    "sha256": "05f8705c040d06324ce4e67ba2117af91a06bc9f743238cd65ff41bf295c963c",
    "cachedAt": "2026-10-21T02:19:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23579/products",
    "sha256": "d950705df950e28df8bfd98cf4e7a1d08f856c19d828edf8e2369e21fab6b15c",
    "cachedAt": "2026-10-21T02:19:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23579/prices",
    "sha256": "63df7a8993d9f692801dc41650745456fdaf2b19cb6f54645677172b94aae2c7",
    "cachedAt": "2026-10-21T02:19:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23458/products",
    "sha256": "251bd01658d939a98bcc19d3c357fa3bc8e88581ec24338f911683dd275f6444",
    "cachedAt": "2026-10-21T02:19:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23458/prices",
    "sha256": "71cb45a0b71a7ed3f9d54136fbfc05b3b432f37197c4c9da9c4f4362171555e5",
    "cachedAt": "2026-10-21T02:19:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23441/products",
    "sha256": "9d3ac846e73aede653c0a02786d3f62e297a34dcddaf39beaf63ae68b6a14b21",
    "cachedAt": "2026-10-21T02:19:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23441/prices",
    "sha256": "578e57f06f7dfe52acb83f5caf719d70b4c303f2fb168c6cc60279eee1fed89a",
    "cachedAt": "2026-10-21T02:19:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23535/products",
    "sha256": "3d52c242b205fde39468037811e92e33c0e078a43c8eb73a1dd1cde0f97de412",
    "cachedAt": "2026-10-21T02:19:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23535/prices",
    "sha256": "0b34cd6b52918b2a77a022ba4548feab04ea86d9d805a80940a15c04f555999b",
    "cachedAt": "2026-10-21T02:19:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24012/products",
    "sha256": "c045289f0baae7105021d7720d4ce2a16b3b0b2ae711d45986856427655cd317",
    "cachedAt": "2026-10-21T02:19:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24012/prices",
    "sha256": "3e5cd4e6b0d504221a4107f718b5ebf320738db33bb975561ca8284d725e709d",
    "cachedAt": "2026-10-21T02:19:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23416/products",
    "sha256": "185caf26c723eae793a51675509d45c943ac7ac924541e6d632d542dca1b6f56",
    "cachedAt": "2026-10-21T02:19:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23416/prices",
    "sha256": "d03868945ddf48f142f697806d57ff477e2c9769010d576f662c90d2b128e1e7",
    "cachedAt": "2026-10-21T02:19:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23383/products",
    "sha256": "fc6c311d2cb6ac8d230e627617feaade3782442f4bf8ca7bf0db14e606d07cb4",
    "cachedAt": "2026-10-21T02:19:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23383/prices",
    "sha256": "35d0aed151fd5ac656dbcbc5b6687ab9bd6a4564f3c718bcb8e56e622177a9cf",
    "cachedAt": "2026-10-21T02:19:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23484/products",
    "sha256": "8395dd58e2f4bad318c20524a23ab2eb739739af4f60658d713fb7a6a320fdb4",
    "cachedAt": "2026-10-21T02:19:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23484/prices",
    "sha256": "69936fd18c7e3a6c266c3eb99d8b4996788bbe6eae0f6e93e81140e29c2d83f9",
    "cachedAt": "2026-10-21T02:19:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23366/products",
    "sha256": "f67b12aba3d94f6ae240223035d3adcb123f9ddc74394c73bcbcbda703f27129",
    "cachedAt": "2026-10-21T02:19:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23366/prices",
    "sha256": "be56c95846359f5babf2495b0099044e0f34f62084fc1b22f08da187b7cdf7fa",
    "cachedAt": "2026-10-21T02:19:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23355/products",
    "sha256": "0f5ebbf68edd3e271c1e0d97acf2acf8858ba7d05f1f8b98cc20f6e892d4741c",
    "cachedAt": "2026-10-21T02:19:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23355/prices",
    "sha256": "eca84116dc44a8962cf25c7c66cfd097e232f4fd51ed030e4a0434b79432dd35",
    "cachedAt": "2026-10-21T02:19:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23469/products",
    "sha256": "53dce109b9970818f02aa7a4c94c54c4b70d4721c7e69b5689d7b9ade8c09a66",
    "cachedAt": "2026-10-21T02:19:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23469/prices",
    "sha256": "313674ddf84c7988707957547b14d02594e97fb1a6723075c6ccb00995bfdbc6",
    "cachedAt": "2026-10-21T02:19:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23314/products",
    "sha256": "3a24e41ee4bf037f622bc74ad976ab0b8d3308a24e7a179ae5be76ff49423229",
    "cachedAt": "2026-10-21T02:19:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23314/prices",
    "sha256": "ef31a25c1debc19bc8c60e41c6b745bfd54c496130c25ec09dda79b3912aaabe",
    "cachedAt": "2026-10-21T02:19:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23427/products",
    "sha256": "d5cc8fb725085acb4324d029ecbf3f4fc3bc009880015cd2624a7fdc82f3b8db",
    "cachedAt": "2026-10-21T02:19:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23427/prices",
    "sha256": "dd451451a4b72cd924642a8a7503494587bb22eb462d6add6034cc3eb602d020",
    "cachedAt": "2026-10-21T02:19:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23321/products",
    "sha256": "287d2b63a2a2eb93389afca2d45f690590e31f6a130aac9902bee386e818cf0e",
    "cachedAt": "2026-10-21T02:19:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23321/prices",
    "sha256": "c2260eaaa8f02f1634e9d85be230c4bc463cfbfeba277ba2b1a86d7c4e613f06",
    "cachedAt": "2026-10-21T02:19:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23269/products",
    "sha256": "dc625421022f3aa4c2c07b1bce16b1ae6e167522a07be2611ed69a28efee0801",
    "cachedAt": "2026-10-21T02:19:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23269/prices",
    "sha256": "a2d3f3351b7848f43bcbac897982c6a85662c6bf8df1ae3d60e38c9b6bbf9b80",
    "cachedAt": "2026-10-21T02:19:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23315/products",
    "sha256": "af04c1123b63caf054f50149f514b6446172432fd031ecf3ae436688e4840cc0",
    "cachedAt": "2026-10-21T02:19:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23315/prices",
    "sha256": "721a4d92f96711dd44b056bcdf3ef3ad7803be3c2615b91fd9f3eafd0365161a",
    "cachedAt": "2026-10-21T02:19:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23310/products",
    "sha256": "5df7cb36b4631e9323803a384eccc8eefe1916be6ddf74ec3121b61006c75819",
    "cachedAt": "2026-10-21T02:19:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23310/prices",
    "sha256": "9cf89afc84cba3cedc0cacfbad514249c1a5e287c439a2fdc5ed2754c2b72836",
    "cachedAt": "2026-10-21T02:19:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23284/products",
    "sha256": "18347c64ddbb97a4a3756e373758475913551e1dd3066b6672f89c4c07330a17",
    "cachedAt": "2026-10-21T02:19:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23284/prices",
    "sha256": "a85292985dd93a2b27f40545fd51d177727432332914b9cdbd15d9bb7290fe1f",
    "cachedAt": "2026-10-21T02:19:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23233/products",
    "sha256": "25a9c4244daa85a076b9c8012127d4313935d89c06f29fffdf64ca41489dc48a",
    "cachedAt": "2026-10-21T02:19:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23233/prices",
    "sha256": "6aae1d3912f36a0e5736c1eb9dc997d50f2a129b074535e4d75cf229948bc695",
    "cachedAt": "2026-10-21T02:19:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23334/products",
    "sha256": "639b5b29e0324bd1ca3e93cc674ec0990994ee4cbcde06f5aa39e5a859c75363",
    "cachedAt": "2026-10-21T02:19:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23334/prices",
    "sha256": "44cb130326bee86aba4333d3a95f90d72487901fb10ef2510203125f3fcd8317",
    "cachedAt": "2026-10-21T02:19:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23231/products",
    "sha256": "81b537ed86de5cd0cc5b4d9e4ec7420cd1b8233d5175f4cc5a4ab84dc6fc995d",
    "cachedAt": "2026-10-21T02:19:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23231/prices",
    "sha256": "6287a2768787e72f2768c91a74c6c4d7714780d83efa25da6ffad232a04fcc01",
    "cachedAt": "2026-10-21T02:19:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23207/products",
    "sha256": "8cd2c068452981d164983b5348a9d5d7e163617296ce3e5aa3ed94a38b249e99",
    "cachedAt": "2026-10-21T02:19:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23207/prices",
    "sha256": "f117acf6510c0c64827ccfb9cd4453d0eb84e1bcd764b463fcd1c8b4555d3733",
    "cachedAt": "2026-10-21T02:19:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23110/products",
    "sha256": "23f1b1ecc39dbabf0570f903fed94d5f6e6ed9ffee2660d25a0b71d8d8130bf6",
    "cachedAt": "2026-10-21T02:19:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23110/prices",
    "sha256": "673ecd8f2914a695f3486a3858af68800c0a50fc3501146953ed3eb36b744344",
    "cachedAt": "2026-10-21T02:19:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23291/products",
    "sha256": "d0d316f71bcf3ccb2cf5d0a933c66d8c4741e01e476d475ec1b155ecdfc039fc",
    "cachedAt": "2026-10-21T02:19:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23291/prices",
    "sha256": "5da236525215c50601f721d1653532f73393dcb2e219143a5b8f26dd918bb8ba",
    "cachedAt": "2026-10-21T02:19:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23292/products",
    "sha256": "4af9cac5723581c48caeaf90cb6d3a1e0b85cba3e172f92526c8f985220178c0",
    "cachedAt": "2026-10-21T02:19:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23292/prices",
    "sha256": "56f3a6156bdc5c833265c7c00afb33536f5b3d32dfb04943e892238a82c40356",
    "cachedAt": "2026-10-21T02:19:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23068/products",
    "sha256": "10f03d17aff28540a1012d0cd23316b4a06e7553f539447b9a2d36bb177bc1e2",
    "cachedAt": "2026-10-21T02:19:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23068/prices",
    "sha256": "7fca1fe6d8b43ef1610c263ce0db41365f8a90cf4b5b40142bf405675c75f12b",
    "cachedAt": "2026-10-21T02:19:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23073/products",
    "sha256": "14c1c15638439bb0ab471304fdba33da8b02e6736381fa494d2b45d1c0346b11",
    "cachedAt": "2026-10-21T02:19:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23073/prices",
    "sha256": "58db483eee4a4791e19dc1abfd95619bec8878f247f2b916092ff3b30fc3da24",
    "cachedAt": "2026-10-21T02:19:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23111/products",
    "sha256": "2366b6f6e5f37fde3688c3563d3d5e8b131b9adfce748899a68c032fe27b6e22",
    "cachedAt": "2026-10-21T02:19:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23111/prices",
    "sha256": "9c40c285a26d093f0fb30a1c067ca57c14ace58182d3f472a95553f77758beb9",
    "cachedAt": "2026-10-21T02:19:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23086/products",
    "sha256": "78d2820d33d3a7c9eedb6d563a922ff72c1000041064dc57eea18b4a70a63a46",
    "cachedAt": "2026-10-21T02:19:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23086/prices",
    "sha256": "3c5037c3a6a545663fbd7c3ec36594c972b3ed462536f86a97d090ac4449a9b1",
    "cachedAt": "2026-10-21T02:19:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23260/products",
    "sha256": "21e8fe0daa33eaa3a68029bcb4f8ff3b781c84c34d244f1d530169c5ace765ad",
    "cachedAt": "2026-10-21T02:19:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23260/prices",
    "sha256": "d3ec24db892c27a30f74bd78f60dad278db727ba41fb432f603048e53f7baa00",
    "cachedAt": "2026-10-21T02:19:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23031/products",
    "sha256": "00029ef817734ec42c4be350253e4b4341c814bdc4d4d11ee1044e64a267c931",
    "cachedAt": "2026-10-21T02:19:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23031/prices",
    "sha256": "810c6ca6278b6c681b5d09e0ce33bad217118f337db76be0a8bb7050ae0d80c5",
    "cachedAt": "2026-10-21T02:19:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22955/products",
    "sha256": "35cf2ac9e9502a1f6270391dfa1df7d68c98c7476688150050a734957d8c041e",
    "cachedAt": "2026-10-21T02:19:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22955/prices",
    "sha256": "ca84c526b0af1ea6d24531f35b82d618423d59ce20a7cf85aa11699e857a9465",
    "cachedAt": "2026-10-21T02:19:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22896/products",
    "sha256": "c2da772ae7d439ba59284b028492072292e4e09e42a0062567a6536469004a55",
    "cachedAt": "2026-10-21T02:19:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22896/prices",
    "sha256": "19df78821df3c8ed198496dbdb575ee1be064e324bb86895f4c32719c5ab1824",
    "cachedAt": "2026-10-21T02:19:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23055/products",
    "sha256": "2d31d318e99f1cbd4f12067eebbce83f6582d20b9662e7cde10ecc570e9d3f8a",
    "cachedAt": "2026-10-21T02:19:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23055/prices",
    "sha256": "4d31431912b446258a0c064e9aa4b249354cdd51b495075658bac2638a4e4f59",
    "cachedAt": "2026-10-21T02:19:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23056/products",
    "sha256": "5e10eb5fc44ce6ecbe12ac5a330554ef3eee75bd55dc77cc1c069d2a3ef1f54d",
    "cachedAt": "2026-10-21T02:19:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23056/prices",
    "sha256": "86cc932ecb7762a9c52a42159064d06a3e0533dadaa72b8c3061cdc1199af733",
    "cachedAt": "2026-10-21T02:19:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23050/products",
    "sha256": "142fd3ad4c144bcf517b5da5be0f8aae80db5d73cfb652865508f8dd92e22b0d",
    "cachedAt": "2026-10-21T02:19:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23050/prices",
    "sha256": "db1df55666d9e374d1c66ac9508635bd14ae1a0a4c1d61aa9a964e0069f02943",
    "cachedAt": "2026-10-21T02:19:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22895/products",
    "sha256": "ae345f83bad207b10a078962145300585be6a01520db247cde65ff2460f6d8d7",
    "cachedAt": "2026-10-21T02:19:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22895/prices",
    "sha256": "b97112d009e977740b454235e6b7120e606cbd9666c4709ac662a9a7e1560aca",
    "cachedAt": "2026-10-21T02:19:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23052/products",
    "sha256": "a34e4adfe98362cc2930a89d063dbbad78af7a0c26d1851b74c03bcb62811db5",
    "cachedAt": "2026-10-21T02:19:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23052/prices",
    "sha256": "cc550a6d3e23932cc5ecc35adea362ec5aa602dc38506c72b76089842201894c",
    "cachedAt": "2026-10-21T02:19:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23054/products",
    "sha256": "b5e7efad3f94ab1bda70473204c35564bb0ebd1bbfc39f7b4ae63dd8b2956b66",
    "cachedAt": "2026-10-21T02:19:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23054/prices",
    "sha256": "9eae7f4007726b03a440c6cd2ed6809fc5ae0e2055422b97db64901d62d8fc56",
    "cachedAt": "2026-10-21T02:19:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23053/products",
    "sha256": "3d880e7f555b6dadbb88f5ce9a395e375d6e84e5492adf4ce38faac55c773339",
    "cachedAt": "2026-10-21T02:19:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23053/prices",
    "sha256": "3ead1c636aab281033a8a08d286cb7d80117c35e914621c870f4853cb8b0cf54",
    "cachedAt": "2026-10-21T02:19:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/17700/products",
    "sha256": "74ac9a8a9c280bc1c3172bff60de3fe35ca8d26cbc83d1c036e531e65f2c17d8",
    "cachedAt": "2026-10-21T02:19:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/17700/prices",
    "sha256": "83ddc2d87259c06f684aa1c301d2aed4dc9ddfec6467b3e7776a61864f5c1801",
    "cachedAt": "2026-10-21T02:19:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/17701/products",
    "sha256": "009d7ab18c077ecf44db4b7c9099a9bec07bdeef59af33fb18f2b574e7d5d9e3",
    "cachedAt": "2026-10-21T02:19:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/17701/prices",
    "sha256": "dddb8520adbccd3eb0eae3673e8110ce692607e6eef2f28ba291ee4d1d869027",
    "cachedAt": "2026-10-21T02:19:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23058/products",
    "sha256": "8d768f2d69ddc26cc59e16247b5053f3eabef0a9f8a02b9f94ee1ca020715fbe",
    "cachedAt": "2026-10-21T02:19:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23058/prices",
    "sha256": "8170dda9410987567c1b4780b2a288096b7289d25f058c56b1adb6ddd5ebc88f",
    "cachedAt": "2026-10-21T02:19:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/17682/products",
    "sha256": "b01e01ab1925187267dcbbd7cc593991d9094c2abb8db8f982ab828b35b403b7",
    "cachedAt": "2026-10-21T02:19:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/17682/prices",
    "sha256": "1fdbe0c5b9841f894e519a91a05b31ccf250df17c011f7390681c5368d09e1e8",
    "cachedAt": "2026-10-21T02:19:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/17680/products",
    "sha256": "fd3572773f8765ba35a8295cbfce2821754ac2b670bd73eec341f096d278df7e",
    "cachedAt": "2026-10-21T02:19:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/17680/prices",
    "sha256": "7613c0a2d3d7382aa260e2506a88707e5b9000d9e4d5612d2334d0a70b31389e",
    "cachedAt": "2026-10-21T02:19:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22936/products",
    "sha256": "e84fb4390ca4bb80769496b8019db7449513f5d63c2f163d2c84782727e2cea1",
    "cachedAt": "2026-10-21T02:19:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22936/prices",
    "sha256": "8c451d0ddc06106fe78a512f8bfe48d1b5a9aadca418c7ccac9cf8d1e3f8bd29",
    "cachedAt": "2026-10-21T02:19:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/17663/products",
    "sha256": "40cb7347b3d00265ea74fed762768f78461109bf700ffc1fa98dc56de9425177",
    "cachedAt": "2026-10-21T02:19:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/17663/prices",
    "sha256": "0f84155d509bea94133efc72491282fd43a48a726c506dd814d32633003736b3",
    "cachedAt": "2026-10-21T02:19:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3156/products",
    "sha256": "ab0b15f442ae31e8e60f5a15704e167fac2a6edf34e27f3733d0f41e262c37de",
    "cachedAt": "2026-10-21T02:19:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3156/prices",
    "sha256": "30f7a0854b015ce3dd172434f4695cad40f0f9a2c615324641ea8220474d2a33",
    "cachedAt": "2026-10-21T02:19:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23648/products",
    "sha256": "67799feeb9fe6dde1c3cf59b3c2fe17685cb1e3bddbb8586bfc3d5ea28785cba",
    "cachedAt": "2026-10-21T02:19:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23648/prices",
    "sha256": "15e702cf585ea27911791b5c732fa3f9a36aefc4b6872fee9db1a20fd155957a",
    "cachedAt": "2026-10-21T02:19:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3155/products",
    "sha256": "965eeef6486d79c04bfd0e5c12df26afc8ece2b5b217cb12b3bebbbd71b930b2",
    "cachedAt": "2026-10-21T02:19:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3155/prices",
    "sha256": "6e8c8b920d0587a9c9fbec88c249cddadacff15e220d258d8e66e16ea76e7edc",
    "cachedAt": "2026-10-21T02:19:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3154/products",
    "sha256": "0e4d3a220a901dd2d107382b0cccfad48dec43546779d6cba1b85e892d1be34e",
    "cachedAt": "2026-10-21T02:19:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3154/prices",
    "sha256": "afd36e0d345e569f362d562dbd36378dd9871e27b504a84dcecf682513ef4067",
    "cachedAt": "2026-10-21T02:19:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/17657/products",
    "sha256": "d3645dae2454ecfa00201a86390c22fb702fa2e3d4975b6ebc723653c2fb51a7",
    "cachedAt": "2026-10-21T02:19:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/17657/prices",
    "sha256": "33b39f52f71421627225902aa13c149c9c7b840fb7081de512b4a61221b00dde",
    "cachedAt": "2026-10-21T02:19:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3111/products",
    "sha256": "54eeac522268b9dcbde3b6bffedc60b9644f271372f4b84f3de3e314ed65122a",
    "cachedAt": "2026-10-21T02:19:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3111/prices",
    "sha256": "3681cb26199390a08a30246fa7495b73e839e8706a2edc2186e3702485e2fd05",
    "cachedAt": "2026-10-21T02:19:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3098/products",
    "sha256": "1a33682bc2de8274b34ac98cec89a8e65b84142c13d548f9cfd66e1e4f6a55ba",
    "cachedAt": "2026-10-21T02:19:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3098/prices",
    "sha256": "aeb4f383d958fa1ca320c66fb2e2a3758864ca0fb5bf0546827b9196a13ed91a",
    "cachedAt": "2026-10-21T02:19:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3096/products",
    "sha256": "6cea30b37b98e4d75efb2e21b4ce753dd0e220919acd02a1434dc024c7c34710",
    "cachedAt": "2026-10-21T02:19:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3096/prices",
    "sha256": "cf52ca2bf6d39ea23898394390cd77649f397b24c193c2cce93e4a2d4ff0b8ba",
    "cachedAt": "2026-10-21T02:19:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3180/products",
    "sha256": "a4e8545e9e37932e8dfea74977e2a14d3a1e4b1985d888422b6e6db2803c43d5",
    "cachedAt": "2026-10-21T02:19:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3180/prices",
    "sha256": "4b98107330cec5dd9a9529253fef6750c8855950c766e77f7fdbff51fd871b6a",
    "cachedAt": "2026-10-21T02:19:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3101/products",
    "sha256": "e746d246c9a93d128621d531bd892bbc5e604037401968127de6427da99f6e5a",
    "cachedAt": "2026-10-21T02:19:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3101/prices",
    "sha256": "9d9ae89b5289bd17990ee6fc9e8840bb88e760ce692b70f9127e10404fa68b76",
    "cachedAt": "2026-10-21T02:19:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3066/products",
    "sha256": "5530514744b6af744f99c36c2f3c778629582da715b1233707f9533b28bc0c2f",
    "cachedAt": "2026-10-21T02:19:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3066/prices",
    "sha256": "5e7cf44996ad788afb605838d27a89717725ec29ac288d354c4fe9e4a20b0e83",
    "cachedAt": "2026-10-21T02:19:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3104/products",
    "sha256": "78daa11ad07eb8442589b5de46c7c03b285ab65deb2e468e142ace8c525235f4",
    "cachedAt": "2026-10-21T02:19:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3104/prices",
    "sha256": "84d4cda7c849b52139e79c1aa2bdf246a6c6fffdfd9e545d33cff2cc0c487df2",
    "cachedAt": "2026-10-21T02:19:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3076/products",
    "sha256": "cd5f003cfbbcf72188ef45767e973781c5dfe16bfa5c9be9a3d59e3c4dd5d911",
    "cachedAt": "2026-10-21T02:19:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3076/prices",
    "sha256": "0602bd8d3ad755e8647ee77faee72d70ec55461276a67d841f527716083169aa",
    "cachedAt": "2026-10-21T02:19:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3013/products",
    "sha256": "b817e3230f9904cc108dc7f7166f63e8a5df80e4795e6a6b3987e74c195786b7",
    "cachedAt": "2026-10-21T02:19:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3013/prices",
    "sha256": "387a61a8c7d13d5a40a35c3a9f73f0c517d080e899adae33216debb463724e03",
    "cachedAt": "2026-10-21T02:19:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3073/products",
    "sha256": "f7d7bbaef1561110ef358190e5dbac72bc34bec8623f5adcb80361c1a238b16f",
    "cachedAt": "2026-10-21T02:19:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3073/prices",
    "sha256": "2bb53024bf52c7a27a202d77d86f58bf14f937ad8c9881c517df108f4b56ab90",
    "cachedAt": "2026-10-21T02:19:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3029/products",
    "sha256": "0feef611c761fb5ab39f9a335104f67d47fdcc8d0be9b97ed1c8e95ded839f44",
    "cachedAt": "2026-10-21T02:19:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3029/prices",
    "sha256": "06fab049ae088dd89b80152f7e113f0dd604518c894a4a91c10a5686cb3e5e8e",
    "cachedAt": "2026-10-21T02:20:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3011/products",
    "sha256": "afcab1e9a68ab610c863bb873d1a22f92aa1f6fafb29cc498a8cfb81636cbdb2",
    "cachedAt": "2026-10-21T02:20:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3011/prices",
    "sha256": "2f98f35b3a420660c38719c3b40312f424721eea70a95b7f59d23a5001e5684a",
    "cachedAt": "2026-10-21T02:20:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2961/products",
    "sha256": "a57f38a52fc89db9ef5568c81297f460ca954e6ef069757a9425bc50b422a114",
    "cachedAt": "2026-10-21T02:20:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2961/prices",
    "sha256": "7172eefe48eeebb917aef3d0d55eeaefe574b597d7130812d1c03900deced18d",
    "cachedAt": "2026-10-21T02:20:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2970/products",
    "sha256": "8244db5cef671a47b56a4ccd13a220a0abd3a898afc55d65aed1a73be85e92c1",
    "cachedAt": "2026-10-21T02:20:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2970/prices",
    "sha256": "a37e689e866a01afbd7067825776f955db1afa07ee05af98ea34a21396020a56",
    "cachedAt": "2026-10-21T02:20:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3050/products",
    "sha256": "3ed221653032de3b443534557bebc3e9db78d3e97f616a3e64ca604c51be5c27",
    "cachedAt": "2026-10-21T02:20:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3050/prices",
    "sha256": "3cd93200beb4be95d802fcff46c3613c9258c21c152ffd250131f6edc73826cf",
    "cachedAt": "2026-10-21T02:20:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2941/products",
    "sha256": "d7c261171f7d890b0d6c5c706c5b4692e2ea7af594a134a04504f456a445187f",
    "cachedAt": "2026-10-21T02:20:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2941/prices",
    "sha256": "e25c1abcf997ec9077619dd4a1477b7be0820224edbb2026209e70dd99f75116",
    "cachedAt": "2026-10-21T02:20:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3000/products",
    "sha256": "8a5375eefd66d91579f61dfa95775d77ceebc749f7d7e79569993e7cdf2dad14",
    "cachedAt": "2026-10-21T02:20:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/3000/prices",
    "sha256": "7fa5e8115cecf54492c4ae18c87286533d867496024516b276b4f4b18aceab19",
    "cachedAt": "2026-10-21T02:20:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2969/products",
    "sha256": "4b866d524d8bb6ec02b7dee57e4d2c1845cdb83822edf0d3b0fd4f63c4cfcc48",
    "cachedAt": "2026-10-21T02:20:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2969/prices",
    "sha256": "4fa0d01386ebb0da9fb7ab3e11d17e8322b06c9e8b4b1fe25867252e500f498d",
    "cachedAt": "2026-10-21T02:20:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2964/products",
    "sha256": "9f0add0165c7827363bfe0a7b5560ff56459403e7b1ecac2faaca30f7fcc110c",
    "cachedAt": "2026-10-21T02:20:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2964/prices",
    "sha256": "c15a6f7786a61684b3e6011ea29fa2d3bbdd85e8db25a000bb5b1d21ecdcf114",
    "cachedAt": "2026-10-21T02:20:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2896/products",
    "sha256": "dd8cc080acdc5ff683a3fcd655963e3197ebb278d66576b15c8c31d3e9245a9d",
    "cachedAt": "2026-10-21T02:20:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2896/prices",
    "sha256": "845cb94e3f7bda660cd276574be36d6b1d5ecbc887803d09b8562e422b75817c",
    "cachedAt": "2026-10-21T02:20:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2829/products",
    "sha256": "6f84d76963053a1aabff7910eb813a82bd14eda5f0fada76fde3025d0d29016d",
    "cachedAt": "2026-10-21T02:20:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2829/prices",
    "sha256": "82ef958bc4c6dac5d88a9f3ceb50b392a4be63c3ec08bf5b8c8da0a72609a848",
    "cachedAt": "2026-10-21T02:20:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2879/products",
    "sha256": "58f697859715b1508b57206b7ecaca90953ac8088d81d6920304d9a1cbea0d54",
    "cachedAt": "2026-10-21T02:20:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2879/prices",
    "sha256": "b73081ff0b5d1fedca3e54b7aa377b8fc6468bc98dfa8964b46857b00d8c4f06",
    "cachedAt": "2026-10-21T02:20:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2934/products",
    "sha256": "0091a0d21218d75f214fe7f491ea8200e9b297aac999a120b3875dd83b34c46d",
    "cachedAt": "2026-10-21T02:20:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2934/prices",
    "sha256": "01e8b829865a5599a9bce6ce83ca926c26e7c38e7793bce5de90ff0f59f75f5b",
    "cachedAt": "2026-10-21T02:20:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2830/products",
    "sha256": "9182f07c53a6f2525c4e153d105d069e801c1a2d831b06b4cdd660c309187c6d",
    "cachedAt": "2026-10-21T02:20:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2830/prices",
    "sha256": "5249574ee897248ca4d0b0108812ae2030197d7103c21b96c17a6f2385a89e57",
    "cachedAt": "2026-10-21T02:20:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2847/products",
    "sha256": "ab60ec390d8c537fdab445c63dfcb6b12b047a40ef5fd07d63e7d9b2e3bca34a",
    "cachedAt": "2026-10-21T02:20:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2847/prices",
    "sha256": "3c04e2a65fd6bb483174d1fe84c2943830658ee8c58aa29f646db80d062cf9c8",
    "cachedAt": "2026-10-21T02:20:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2877/products",
    "sha256": "517da9b19f707f8a2a7c1f7b36d33d677934e9d1b2faec2a963abf85cb848331",
    "cachedAt": "2026-10-21T02:20:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2877/prices",
    "sha256": "db35c6b69806d43d78efcd4c32427466a0633ddc9676cf0529cd916e738dfbcb",
    "cachedAt": "2026-10-21T02:20:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2843/products",
    "sha256": "0ac0830a83ba0595d1729a39bf5f4ef478a8bd043c0da58ce4b91a9d02a38465",
    "cachedAt": "2026-10-21T02:20:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2843/prices",
    "sha256": "bf8d351799d13133998b53bfaac70e8d84b0898dde3f93a045f53764cd191e36",
    "cachedAt": "2026-10-21T02:20:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2808/products",
    "sha256": "d46a328306535a2ac40d268cf17b1e9a36a8ddb7566442481cf7fb69699269d7",
    "cachedAt": "2026-10-21T02:20:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2808/prices",
    "sha256": "fcbcff6fff1fb7533079fb8e4e87ab03656ebb162f838a87e63ee19cb5b8ee0e",
    "cachedAt": "2026-10-21T02:20:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24189/products",
    "sha256": "12dbbaf6f257d97b04114c44f5c365cce1b28527e6c55a4899ee90b1636a2f50",
    "cachedAt": "2026-10-21T02:20:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/24189/prices",
    "sha256": "218fa28a497d3e90caa65c041ec6621bf4e39f355268b056846bfefad115344a",
    "cachedAt": "2026-10-21T02:20:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2850/products",
    "sha256": "573e6dc9b2811a87a55378f11a18ea44c83ae92124e38fc773e737f4695eab8a",
    "cachedAt": "2026-10-21T02:20:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2850/prices",
    "sha256": "7dafea0f30ad165691dd9d66d78f455c17e85133d1759287b4c4eabe39d061e9",
    "cachedAt": "2026-10-21T02:20:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2810/products",
    "sha256": "dc7155b7d8115d30ca85dabcf89b2e409ac0ae533960269f029b3e6b2c4e9282",
    "cachedAt": "2026-10-21T02:20:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2810/prices",
    "sha256": "15f2f3f6dc0ec295bace2caa4c49ae8c8e21360abe2951b2730a2ef880a059a6",
    "cachedAt": "2026-10-21T02:20:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2811/products",
    "sha256": "b505c57da80eea26f733e8555c6bdf11d291bd1586eee0257779b258e86fa829",
    "cachedAt": "2026-10-21T02:20:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2811/prices",
    "sha256": "1d65846f967eb87f257ab27bec14f31e5073297c929aec636d98189a9b64889b",
    "cachedAt": "2026-10-21T02:20:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2779/products",
    "sha256": "11612124dec217fc482dcb74eb4b37a3c8defaa69dc0f2d88c767e622e1a9cf5",
    "cachedAt": "2026-10-21T02:20:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2779/prices",
    "sha256": "1b85f583bd7660cfd0428a20d5c91dafe31b786b63a4673c458148a5880f8c97",
    "cachedAt": "2026-10-21T02:20:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2767/products",
    "sha256": "791964fe4a9374f341ac7cbf212065d12a13a262e18a0ed675b4ef3f34ee9566",
    "cachedAt": "2026-10-21T02:20:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2767/prices",
    "sha256": "e4d33538c8d7c7580949a423ac3b9c079ab849bb20f4fea2228b221e5d55a5a5",
    "cachedAt": "2026-10-21T02:20:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2752/products",
    "sha256": "4d13ee23b2d837e2c8a5d9bb91c77ccefea73807491285723ca976412c49f6de",
    "cachedAt": "2026-10-21T02:20:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2752/prices",
    "sha256": "48486b071b71baf01f684be84145e850abf0bbc16f3c17a6998a40da84f6a420",
    "cachedAt": "2026-10-21T02:20:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2751/products",
    "sha256": "81f6ccea35178840dbec59cd4423fcebeef346ccce7ae61d7da641be8fdd1af4",
    "cachedAt": "2026-10-21T02:20:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2751/prices",
    "sha256": "0324c3556588f653f1b9dadf158304857924baed19c0ecfa8e316022a99f6607",
    "cachedAt": "2026-10-21T02:20:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2790/products",
    "sha256": "e82f5aeacabb0bf5001316766a25baa486fe4f4030c094c8cde149d6054701b6",
    "cachedAt": "2026-10-21T02:20:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2790/prices",
    "sha256": "e2bdb1d967a1fdb50d137987c9701233248b262d862fa02c4e3f41470571ac28",
    "cachedAt": "2026-10-21T02:20:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2749/products",
    "sha256": "cd413a01e2f1146a7eb51e77d27b4ecbd99015ddb8253438a1ea034252eaf366",
    "cachedAt": "2026-10-21T02:20:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2749/prices",
    "sha256": "de2017ea790dbdd2df5cc858c596e19366dc3dd377bd62ce42f234de59ea7bdc",
    "cachedAt": "2026-10-21T02:20:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2743/products",
    "sha256": "5b315c597c16455175f481022d409ba7a2e93152036314e389031335da67fa0e",
    "cachedAt": "2026-10-21T02:20:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2743/prices",
    "sha256": "2ac288eb2e19e00ecc1b6b7eca22e80bd855d939f71d18b0e021a612c2bccb0c",
    "cachedAt": "2026-10-21T02:20:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2679/products",
    "sha256": "66210ccd2aacb63f3321e9d6b393f4cf1ac934200d856b7efce8fc05acc479f3",
    "cachedAt": "2026-10-21T02:20:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2679/prices",
    "sha256": "4405b0b6d266ec02ccf4f255dabd165ec8d9675cc507f0d94dc26bbbd016aeb2",
    "cachedAt": "2026-10-21T02:20:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2700/products",
    "sha256": "38fa91180790e4a5c4b2148d9dac58154027c02454713d53d2ee9af347b1444e",
    "cachedAt": "2026-10-21T02:20:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2700/prices",
    "sha256": "38986d209843fdb47a682d876260f2bd59e6cd17b95fa431992eb59469e046a1",
    "cachedAt": "2026-10-21T02:20:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2695/products",
    "sha256": "1793c01d11242d37de7967c9721dcce8374cb9bcdc7863dd43fb7bd57ccfe405",
    "cachedAt": "2026-10-21T02:20:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2695/prices",
    "sha256": "6ab62735b53b57ffd052a93bf9eab26bf2232c1a1b3e1208eff47946f8bbc12e",
    "cachedAt": "2026-10-21T02:20:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2694/products",
    "sha256": "f180134430669214762f62893678920d85d3f4d0e7625b4a00590e273ec76ecd",
    "cachedAt": "2026-10-21T02:20:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2694/prices",
    "sha256": "b43c5f59886446e94d6a30ec068c5d69291de96bd807fcf53d0c81b958c4254b",
    "cachedAt": "2026-10-21T02:20:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2693/products",
    "sha256": "0ea0890ec7e155d3a3d3444c65cb1499a65cfcd3f8c0feaaabe5741a43ef0912",
    "cachedAt": "2026-10-21T02:20:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2693/prices",
    "sha256": "071e24d8f8d794f44d2e799a3290360b369cd386a1ad18a51f65fdc61850c061",
    "cachedAt": "2026-10-21T02:20:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2723/products",
    "sha256": "f07e53549560f24d3d43cc950c812883eff16478171d32fb629bd5ee205df00c",
    "cachedAt": "2026-10-21T02:20:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2723/prices",
    "sha256": "f4db91c9eed51a9d122799ac8d21c6fa83f846f7583848b76b4fba550ae360d2",
    "cachedAt": "2026-10-21T02:20:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2690/products",
    "sha256": "b46fafa2a2462ba608ac3c133a0c20142dcd36fdbce572e70b3f6964178d6021",
    "cachedAt": "2026-10-21T02:20:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2690/prices",
    "sha256": "56d447e3acc78f4f759765627c48bf56a65e99d008b58ff36e847d22d79b55f2",
    "cachedAt": "2026-10-21T02:20:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2718/products",
    "sha256": "638ab33dee29a817f75836500acccb108db015094a4fe537dd93d7cac28e2163",
    "cachedAt": "2026-10-21T02:20:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2718/prices",
    "sha256": "14945215e920dcf2631362a0bd312fdce0d13b8f9ef0a3b09d9144d8a68e3c0e",
    "cachedAt": "2026-10-21T02:20:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2689/products",
    "sha256": "f16a61d36091c19fbab506e02ae0bf1045c519791ecfd0b6fd28c00bd70c4efb",
    "cachedAt": "2026-10-21T02:20:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2689/prices",
    "sha256": "b8e5f57769d3e79b17ef1782bed82a6f28ae3ae6b3fb26726d5038424c0522ba",
    "cachedAt": "2026-10-21T02:20:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2680/products",
    "sha256": "98a663a2914519e3dd7684f3f62c28a4f8389fb5a3c961565bd18b9dda60fe77",
    "cachedAt": "2026-10-21T02:20:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2680/prices",
    "sha256": "18e706b88dcbb967f331f71c69334b37efce8210d9aeaf4c12e0716cd09a9c20",
    "cachedAt": "2026-10-21T02:20:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2674/products",
    "sha256": "6a6e1c53e705c53df935fae757063fbf5911322f789239013e8524d7f554e5b6",
    "cachedAt": "2026-10-21T02:20:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2674/prices",
    "sha256": "875abe979d4f570587a9e167a1297472841f22210f274d43489d076a1c84d998",
    "cachedAt": "2026-10-21T02:20:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2660/products",
    "sha256": "d6d2edf47c249352309d902b6a46c3dba6e47b718e976e48e1258ea0687cb169",
    "cachedAt": "2026-10-21T02:20:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2660/prices",
    "sha256": "f61b9784c6e63c9109f27e7673c74538067b8b12633d009b29aa0d3a250e4651",
    "cachedAt": "2026-10-21T02:20:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2659/products",
    "sha256": "e7a2cbc5465a5da93abe0a1e9ecda7ee4e1a87d4b3b2b83011b3e58c68f697b3",
    "cachedAt": "2026-10-21T02:20:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2659/prices",
    "sha256": "d38975a984f96a714c32936024d76081a4e695700ef8c8d9a4be5c08dffaa0d3",
    "cachedAt": "2026-10-21T02:20:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2658/products",
    "sha256": "14dc28f32fb81c92d4782f27cf0ab6250228a2a9758ec8cf7eaab47d386e2795",
    "cachedAt": "2026-10-21T02:20:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2658/prices",
    "sha256": "534c050e4d3c29e00c02bb8c8402f72892ca5b4fa9a50f589f1dc8b653c6fdfd",
    "cachedAt": "2026-10-21T02:20:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2652/products",
    "sha256": "05ef1062a83739be0063d89035f010b4773d5b299bd6c2c6bf4a380375b4e4b6",
    "cachedAt": "2026-10-21T02:20:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2652/prices",
    "sha256": "690a7f903c05f03d27480e21bf95034c9ae45729d343ed9cf859513739e02dfe",
    "cachedAt": "2026-10-21T02:20:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2672/products",
    "sha256": "6454cb234e8d58864d9e0c665ca9986146632063967aa89408894958e2327177",
    "cachedAt": "2026-10-21T02:20:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2672/prices",
    "sha256": "acdf5c6247ac4818f2feda595cbc37f3bbecfe71c33355da940a2031f927fcdd",
    "cachedAt": "2026-10-21T02:20:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2637/products",
    "sha256": "1edc07fe01a9222b3d69a8529a7e4ad93bbf0625587cee63aefdf0807b6aac61",
    "cachedAt": "2026-10-21T02:20:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2637/prices",
    "sha256": "0f01dade5f703fd0d91a659975b5fbc6208b017d60a253549d34374e47a61ed0",
    "cachedAt": "2026-10-21T02:20:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2638/products",
    "sha256": "84be59dd9a4fd97e31e5fd8aafa864f9f4a1736033b183428b7e1fb5285997ee",
    "cachedAt": "2026-10-21T02:20:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2638/prices",
    "sha256": "ba74fe73bc6cd89307498df12cbf8755b422b30df8410e657a40516e6ff8cc66",
    "cachedAt": "2026-10-21T02:20:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2625/products",
    "sha256": "1208ab64ed7a8d565b9ae988076cf97e38211a274169321a7f8050af731e6be7",
    "cachedAt": "2026-10-21T02:20:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2625/prices",
    "sha256": "8e4ce7b34e752a02287ea28a4197a955c6afb15c7db2b157decfccc4052133e6",
    "cachedAt": "2026-10-21T02:20:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2617/products",
    "sha256": "ff1e57a6e3474b43b680ef6f1d5ffabbdee849750fe6e1b2de21121231bfd3c0",
    "cachedAt": "2026-10-21T02:20:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2617/prices",
    "sha256": "d25e07034470d28b476ba5e4083eec291a8bd9d97601793aa6fa93c8a4023fe8",
    "cachedAt": "2026-10-21T02:20:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2613/products",
    "sha256": "8e4cfa86c95324415ba4bcf2d21f17dbc3d94cad224dfc1e9f337f5866f17cc9",
    "cachedAt": "2026-10-21T02:20:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2613/prices",
    "sha256": "253d8a2f3e8853aa63389b962773b292f24fff053bdbd299deaf9ccf59f1a1dd",
    "cachedAt": "2026-10-21T02:20:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2610/products",
    "sha256": "8e3ae980c41f03bc93c23128cb1154060dc54988cd442328c5b24c2c3afa05eb",
    "cachedAt": "2026-10-21T02:20:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2610/prices",
    "sha256": "29d912751c84560fa801c77db277aa3850b662552a789aa9d3aced64b1adf6a8",
    "cachedAt": "2026-10-21T02:20:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2591/products",
    "sha256": "22702a6d7c1e0f677df8207e92234803365e614ee8dff9bca3ba3c5ff6ed2825",
    "cachedAt": "2026-10-21T02:20:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2591/prices",
    "sha256": "82de8827b8df1ca0e87065cb8d5b7dfea26f2cd8a0299ac6fc6af0fff89e4804",
    "cachedAt": "2026-10-21T02:20:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2578/products",
    "sha256": "e528c2197f5c3f9cd61e0cd71c01256b994c94c74e01df5ffab6602d00b41f4b",
    "cachedAt": "2026-10-21T02:20:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2578/prices",
    "sha256": "ceb398328433d4992f669e50de26d9ab6f8ef43e4513151ea36cf77f9df9f6fb",
    "cachedAt": "2026-10-21T02:20:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2577/products",
    "sha256": "129a58bf0c1964b1e0e2ee5da1eb7e17605697dc890da2890d1873307b0e5a7d",
    "cachedAt": "2026-10-21T02:20:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2577/prices",
    "sha256": "17f7bcfc7aa4829b4118ee72460db9bff24f326d4de437bff377ecdeab700992",
    "cachedAt": "2026-10-21T02:20:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2567/products",
    "sha256": "5efa19eee1ea47113540290a23b3b00cad7a5b24886974a878fed9b59b032b81",
    "cachedAt": "2026-10-21T02:20:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2567/prices",
    "sha256": "5292cae2041d854cc900722782c731fc1fe612041ed309d0c7116f7dba454a96",
    "cachedAt": "2026-10-21T02:20:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23225/products",
    "sha256": "cae43b8aef45525113a5810a1ab054be8079bde710458f438455a838801cb2dd",
    "cachedAt": "2026-10-21T02:20:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23225/prices",
    "sha256": "ed66c966cc4e93cef453db60dbcf4ba3ae4f71aadac69af2a816f2216ffe5d5d",
    "cachedAt": "2026-10-21T02:20:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2514/products",
    "sha256": "f969a637e76987c68b4f860638a8fcf9505b2de75244d0a4364c9df9b9c81a2b",
    "cachedAt": "2026-10-21T02:20:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2514/prices",
    "sha256": "c9d464769913728e760f832ae19e9040a63fc1d2046a041bd7bc76eb51dc1314",
    "cachedAt": "2026-10-21T02:20:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2582/products",
    "sha256": "d8c08337b38118edd2437bf7aa0018d1000b131d2741f9a337e2bce38dd607d5",
    "cachedAt": "2026-10-21T02:20:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2582/prices",
    "sha256": "05bc19329a3a4a8276f2c6376fffda68461a419b0c454c94cf6dd07246fc59dc",
    "cachedAt": "2026-10-21T02:20:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2528/products",
    "sha256": "079c33f6382deaee40426aa3f8a4ee47921d042eec1f63e68abe0926bd849ff9",
    "cachedAt": "2026-10-21T02:20:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2528/prices",
    "sha256": "507aa411552320cec8c34e1e22d23df30dd76c40b5fceaf6ce28579fecb0eab0",
    "cachedAt": "2026-10-21T02:20:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2527/products",
    "sha256": "25c3ef4855179286819bc9b682b6ad7039e9cfa17e998f0305cc114cb294024a",
    "cachedAt": "2026-10-21T02:20:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2527/prices",
    "sha256": "df227ad8e8e64f4ad42369ff06db773a638e4a08374b09b89c64c816abcaed98",
    "cachedAt": "2026-10-21T02:20:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2505/products",
    "sha256": "79ac4d3477c5e503c92358ca4c7f56730135eef7e0c25f3bce28ee8a851a8358",
    "cachedAt": "2026-10-21T02:20:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2505/prices",
    "sha256": "61af67fc145a59ad8abe602badcb34401c30bf175c7cdfd2d8b3b1795abddf95",
    "cachedAt": "2026-10-21T02:20:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2559/products",
    "sha256": "9f732cff1d83a049d21b22bf2b02f9047bceaf861def51521f06b7d34741e6e3",
    "cachedAt": "2026-10-21T02:20:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2559/prices",
    "sha256": "cae0963c40c7463f2ff77ec8fea2b8659234dba86f32d3cfccd682989146cef1",
    "cachedAt": "2026-10-21T02:20:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2518/products",
    "sha256": "912193168a8c038bccb9eb7f2d6087482327442bcd59cc893c390990135c0a05",
    "cachedAt": "2026-10-21T02:20:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2518/prices",
    "sha256": "a7930b441b5b313d1e187bf13749aa2b6064d1d35b7dcb65fc214f0e8097c245",
    "cachedAt": "2026-10-21T02:20:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2519/products",
    "sha256": "4bb4978ce09ccd5c8fb3674816e7ec366759c6d4cdcb96a757f2231aaa532738",
    "cachedAt": "2026-10-21T02:20:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2519/prices",
    "sha256": "645331819d3bdbcb3a3ecbcab5822d3ab81dc520682ebbcbb9ff3240b56c786e",
    "cachedAt": "2026-10-21T02:20:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2488/products",
    "sha256": "0710e9c691d32c4c677c87ce9e26733a6dd25924a15f2923d4ad878718d4f890",
    "cachedAt": "2026-10-21T02:20:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2488/prices",
    "sha256": "aaba1c097eb6ff81e8efd52739f9fdaf744e9670a7061cfb88079ff1998353c0",
    "cachedAt": "2026-10-21T02:20:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2489/products",
    "sha256": "9a308e13632538264907abf70388d6053db0fc00fed3e8bfc1596c5c1946a44e",
    "cachedAt": "2026-10-21T02:20:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2489/prices",
    "sha256": "45fb1f3ea4731b2374ab506df2d09b1d0c532b956595e2a23dee8c91f4f91b87",
    "cachedAt": "2026-10-21T02:20:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2471/products",
    "sha256": "8499797c69817de8ff5be05e23b09c3b3226a78eb52bd7967804c6ea21ebff41",
    "cachedAt": "2026-10-21T02:20:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2471/prices",
    "sha256": "26319d0601c4580926cab0c72985503738fe6776e8b9fe39d58a811b55889fca",
    "cachedAt": "2026-10-21T02:20:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2470/products",
    "sha256": "53016f9f14fd1f6826aea1dd9d918fd7e5d6c9267bab57b130cc764b0e9ac726",
    "cachedAt": "2026-10-21T02:20:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2470/prices",
    "sha256": "3a5b6bf1c332f9f5e6e368864d8929ba530338a0d8754dc67f53a0f9b5d3b194",
    "cachedAt": "2026-10-21T02:20:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2512/products",
    "sha256": "2b791cd3efcb97a33972cca224cbd0297b123de03103c8c3a71a70be3e29c16d",
    "cachedAt": "2026-10-21T02:20:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2512/prices",
    "sha256": "80b5a61943e139ef0db0a882adc362d617e92d99ef713be767ef622ee28a153f",
    "cachedAt": "2026-10-21T02:20:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2469/products",
    "sha256": "ae3f70e6ce0877e681f2edbcf43485c61e5df1c52bc832fd37fafba7f2340754",
    "cachedAt": "2026-10-21T02:20:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2469/prices",
    "sha256": "8d568c6f1baba70d89140113c02b15cd8fa3a19009e2688a04b044d1c28f3e43",
    "cachedAt": "2026-10-21T02:20:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2468/products",
    "sha256": "83dabefb1ed28bef05659842b14e24fe127cf5b891d412efffe41a620cb60ddf",
    "cachedAt": "2026-10-21T02:20:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2468/prices",
    "sha256": "e3e64fe08f881a924f5b40817056ddecbe2ad228eafe652a3fff37be169ab902",
    "cachedAt": "2026-10-21T02:20:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2561/products",
    "sha256": "91c5a4f9b7a9f4120358f241272d2a7de0255d8c22c98d5d5a253de5bc991035",
    "cachedAt": "2026-10-21T02:20:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2561/prices",
    "sha256": "d941b65d88b2feb2df5d99e5dbccc9bf61d880b97cdefed47e6d13f6ae44991c",
    "cachedAt": "2026-10-21T02:20:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2462/products",
    "sha256": "39b80d35c95da17e20f0b16a28541b9d9e98dabb11ba9cd3027d51bdc299c542",
    "cachedAt": "2026-10-21T02:20:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2462/prices",
    "sha256": "35d7085fd56e9ffec978929106cd99c42a0bcd24c4a6835fff7cd998f3f44d77",
    "cachedAt": "2026-10-21T02:20:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2459/products",
    "sha256": "247eece5c0c2b1c2f7f65f19f43a917b71dd36d575c2d2e3099005b6eac276cb",
    "cachedAt": "2026-10-21T02:20:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2459/prices",
    "sha256": "0d5e932bd9bbab3c196f880c0363c542ef85c0e0ac418b4abf1f2c0bf5aa0e0e",
    "cachedAt": "2026-10-21T02:20:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2681/products",
    "sha256": "877105c863f35df3203701bba9a4e516659d35d361fa65b88aedeb31744616f0",
    "cachedAt": "2026-10-21T02:20:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2681/prices",
    "sha256": "5aeecab2e598f380a527e78ddcad89291c871463c90b905f9c2341c264cb9e8c",
    "cachedAt": "2026-10-21T02:20:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2425/products",
    "sha256": "d23ad512fae337beeebc6dee5452219daed718d7628d64cf5c6f62496eb786cf",
    "cachedAt": "2026-10-21T02:20:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2425/prices",
    "sha256": "43422a4dcdbcacfac334d7fae434b3fb5c8ebfdaedd103dc14f3b60c3d3b3b05",
    "cachedAt": "2026-10-21T02:20:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2421/products",
    "sha256": "f5eed52281c6d413b7a2c62357c2656dc7175a3925d76fed6300faa86ef870d1",
    "cachedAt": "2026-10-21T02:20:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2421/prices",
    "sha256": "cf579f9e1944a808abfb003067990ac8d48ee7c1ad0fa63fbc68e91f923053ab",
    "cachedAt": "2026-10-21T02:20:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2401/products",
    "sha256": "b3393bc2c117d0a8e4f91256cce5e6a2560279b692fc9e6e8162bbe1e4caec45",
    "cachedAt": "2026-10-21T02:20:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2401/prices",
    "sha256": "7c0069cfab5e4cae92156a42ff082866aea193fdf014ffdfae1f5df55ea450d9",
    "cachedAt": "2026-10-21T02:20:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2445/products",
    "sha256": "cd46573e51c238a96622061344605091b155b92902f42df02fc17efccb93bc08",
    "cachedAt": "2026-10-21T02:20:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2445/prices",
    "sha256": "d5bc51cb99b890955f57f6685294ac6bddd8c9a91e37fbd81d56bb0e1642303e",
    "cachedAt": "2026-10-21T02:20:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2446/products",
    "sha256": "f909e36bdff2d31cbbdc5ac12f04ee17a4eae974c7390252c4b3853cc516472c",
    "cachedAt": "2026-10-21T02:20:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2446/prices",
    "sha256": "215cbb9726a3e8a242e2e801e01f65528fd1f7f95cbb931425f9a0d95a9c476b",
    "cachedAt": "2026-10-21T02:20:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2400/products",
    "sha256": "b8ba2d3ba012470c952b841e46912d424670bfcae332c6b3a60edd2047eb25a7",
    "cachedAt": "2026-10-21T02:20:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2400/prices",
    "sha256": "4674d2cba0ede45f876b102844706b6942e6091b880cd83f74a23d0aa153a5a8",
    "cachedAt": "2026-10-21T02:20:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2399/products",
    "sha256": "ce32795d1675f95d1937d0c25beba8783e5b70457d9428d6f3546751837eef13",
    "cachedAt": "2026-10-21T02:20:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2399/prices",
    "sha256": "5932b9627247073cbf0b4bc170e6ff2a4caf6a7c617cef9f2763f72a24e918f3",
    "cachedAt": "2026-10-21T02:21:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2398/products",
    "sha256": "811e954c8c0fe46b4864fd4283897faf6f14ac735d9150c78e176784ee18a55f",
    "cachedAt": "2026-10-21T02:21:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2398/prices",
    "sha256": "9e8522c1d9e4b6ac4ee6ba194284a71d8ebfe69298003d580a5f84ab019c780f",
    "cachedAt": "2026-10-21T02:21:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2389/products",
    "sha256": "4e3ebc3cb4f0457e2aa697002d6ca97833638bd7c2b3bf121048c7be669d701a",
    "cachedAt": "2026-10-21T02:21:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2389/prices",
    "sha256": "01711652430d80b808026b20140893cf3dfa9be4a42bceedf3fa62df845bffcb",
    "cachedAt": "2026-10-21T02:21:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2380/products",
    "sha256": "d0dac2d063a12e333b6dc4d5c6ef6ebce6f7ba8b9c16e3e5920b861178c46134",
    "cachedAt": "2026-10-21T02:21:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2380/prices",
    "sha256": "dda1ee5cab223a0e38973e5221804f9c45dd1718acc9abc821cfe31747904d64",
    "cachedAt": "2026-10-21T02:21:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2372/products",
    "sha256": "de160c70ca7bc4f273916881e9cfdc64eee85f9ccea240c2cb6828d1e56c96e5",
    "cachedAt": "2026-10-21T02:21:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2372/prices",
    "sha256": "1456fad527f367ec1f7eb112f68a467657a9ca4f943c5fe680aedf727dd19df1",
    "cachedAt": "2026-10-21T02:21:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2371/products",
    "sha256": "280a2170dd0e0baad965a185a78319628c2bae41b9f13dbcd2adfa7d568ff6f3",
    "cachedAt": "2026-10-21T02:21:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2371/prices",
    "sha256": "053a1a2523790c11d13e607d02771c3740d0081a8574fa8aca35edf916efe9bb",
    "cachedAt": "2026-10-21T02:21:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2365/products",
    "sha256": "146890c1214b0e8703f1905014bf2d4e32459231ace679b35fd34f1a43e7b6ca",
    "cachedAt": "2026-10-21T02:21:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2365/prices",
    "sha256": "ec92cd7657d48659e3cbfe10f97d2d8f63fec7cf1df09e5a9e30efd61940e6dc",
    "cachedAt": "2026-10-21T02:21:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2443/products",
    "sha256": "d89b43508fda6e1e86adfa3ba89b412ed298eb132b397720a12c5b0540976e58",
    "cachedAt": "2026-10-21T02:21:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2443/prices",
    "sha256": "331ef25006e29b4d2dcfd93516491cdab49dfb9a7e34e012afec6652f1d4d729",
    "cachedAt": "2026-10-21T02:21:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2378/products",
    "sha256": "5482e15839ab10c75d9e423591d5ce8265794022753196fa01797a7d470d9bb6",
    "cachedAt": "2026-10-21T02:21:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2378/prices",
    "sha256": "c4ec359e1a51a07b21056180907aab715e160f6ed7f89e3775a3b84b0869dcc7",
    "cachedAt": "2026-10-21T02:21:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2343/products",
    "sha256": "fadf2e1a9cebdf4246c574bd5eed1a2cb092cd7dc0d0033c84e4315e006fbcaf",
    "cachedAt": "2026-10-21T02:21:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2343/prices",
    "sha256": "2d3d32a1bc951c0455795ba94ba2b710a9ab8b1f16ed07663bf44b054118a881",
    "cachedAt": "2026-10-21T02:21:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2339/products",
    "sha256": "a370ec1cd1b87ac0900abd186648bd0953b402ec6138458f9c482743ac0af0c4",
    "cachedAt": "2026-10-21T02:21:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2339/prices",
    "sha256": "d32ca113933b223bdc34d64c09214e0a9b5f45049dd3ec6ea90d79e0ead5b1fb",
    "cachedAt": "2026-10-21T02:21:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2337/products",
    "sha256": "f61fc54bc78aac96065687feab90feb839a1b2d6deef2efaf110f255b26373e3",
    "cachedAt": "2026-10-21T02:21:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2337/prices",
    "sha256": "7c5daf8cba75ce12ffbf2003fd42856fcf9b970b959f966d24fe14b2890cb630",
    "cachedAt": "2026-10-21T02:21:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2327/products",
    "sha256": "4e14a139073b5026148e9297424a7bc71a06c47c77de1f5f1b62c351d60b2596",
    "cachedAt": "2026-10-21T02:21:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2327/prices",
    "sha256": "b82af59b1824db3fd5b0cf5b84364e73685e46f6a261595fcb24187b7ad02289",
    "cachedAt": "2026-10-21T02:21:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2336/products",
    "sha256": "e13108ba7b178607b3fc177491cb35042d8b89c260dae1b73270b10ca44a0c6e",
    "cachedAt": "2026-10-21T02:21:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2336/prices",
    "sha256": "45ad49e8fa20bf9051678fd29ff75311262ab968a75c4ee98d8af47fde42dde3",
    "cachedAt": "2026-10-21T02:21:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2300/products",
    "sha256": "aa0678d0624b8d8e9e186ec7fff9cc473bd77148ac9ca77201d1523b3e47ecd6",
    "cachedAt": "2026-10-21T02:21:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2300/prices",
    "sha256": "da885761f4d694e68790ade6a5127ecf75aa2ee26c0d3b9f1e383c6367cc3c30",
    "cachedAt": "2026-10-21T02:21:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2322/products",
    "sha256": "d5e99288b903ec289f3ecda273a66550817293bb01008ddd94e39b55ab128641",
    "cachedAt": "2026-10-21T02:21:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2322/prices",
    "sha256": "b5f2e6d333cb98e95dd6cf411950b31ccd69c503bb1eaead7303ede728f7d1d5",
    "cachedAt": "2026-10-21T02:21:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2284/products",
    "sha256": "b27c6d8379b6874fe96fbc350989f2fe911dbc6f8697350246c54ed107cc3f40",
    "cachedAt": "2026-10-21T02:21:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2284/prices",
    "sha256": "348327873209cc92d917785fdc63f21a4d15708beb2011086db447f2bcb45d3e",
    "cachedAt": "2026-10-21T02:21:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2317/products",
    "sha256": "fc3c626d5206f8549350ac325618f4ce2e9b485003a8d7c69e3bf25f808017b4",
    "cachedAt": "2026-10-21T02:21:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2317/prices",
    "sha256": "c2e89dc584484da578c18ab074e0a900eac36e964f08ab84eb72a99bbe5c9999",
    "cachedAt": "2026-10-21T02:21:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2292/products",
    "sha256": "b2dd83886575997388fb89138257aa1950f9a75b60625538ecaaeb7b1b3ed170",
    "cachedAt": "2026-10-21T02:21:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2292/prices",
    "sha256": "178665448eb107e03f61000864c45c4ea4cd9a26800c2f07663eb014c41946e8",
    "cachedAt": "2026-10-21T02:21:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2312/products",
    "sha256": "0718534ba8a5db6c513de677f0cb87c13271ece5316515e59137f24a2a565f39",
    "cachedAt": "2026-10-21T02:21:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2312/prices",
    "sha256": "1832ecbfb4986575da7aab149239b3f56a9fa900065cc6b9134a2c9b6fc5559d",
    "cachedAt": "2026-10-21T02:21:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2291/products",
    "sha256": "fd9b905969ff223e29ce5bda4355cfcc690814af44e3fa4ef34b669acac97660",
    "cachedAt": "2026-10-21T02:21:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2291/prices",
    "sha256": "a50161fce4827c785ced16d62a9943aeaddf21bba55f7c8f32646d97dd2b5243",
    "cachedAt": "2026-10-21T02:21:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2267/products",
    "sha256": "e1b900f5803bf27aceac3c35a4a2870adf5c8a7cf809a8f36c1f360384080113",
    "cachedAt": "2026-10-21T02:21:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2267/prices",
    "sha256": "091c1146ef8868d660b4188befbb8ccd37d1c587052f724fcbf07aabc6ade21d",
    "cachedAt": "2026-10-21T02:21:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2266/products",
    "sha256": "d7962a38f97d3a2ce3603c55a9b658904d67a3e268cbc38b66c250d7592464a3",
    "cachedAt": "2026-10-21T02:21:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2266/prices",
    "sha256": "6a778f624e1c4529fe3a3cf833e542609a2b1d8f0764251f76fd28fbec1e9f29",
    "cachedAt": "2026-10-21T02:21:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2253/products",
    "sha256": "20b80b7eb0d8181c5943623d82f4d0b63a542084b76eb1989c9bd5d52bc79e20",
    "cachedAt": "2026-10-21T02:21:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2253/prices",
    "sha256": "9b060eb25d5e2f0487e230b308acc08d718b7d7b02a95a734437980b60a3677b",
    "cachedAt": "2026-10-21T02:21:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2231/products",
    "sha256": "0baf13d8e45ee24f2b7d2e108fa8f128a4f756f8906b0dfdd25eccde2c53f831",
    "cachedAt": "2026-10-21T02:21:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2231/prices",
    "sha256": "2265148717962dfb1d9d83ab4c91fa5e8836709fa46f2f492287d759ae518755",
    "cachedAt": "2026-10-21T02:21:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2212/products",
    "sha256": "1ca3f0e0d268f6c21cf2eb7ee49573fe302b7e784ea83d449dba8e4e5c271090",
    "cachedAt": "2026-10-21T02:21:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2212/prices",
    "sha256": "452361eb23f0c14efb06825d4cd4e6cb1ba54e6bb0cc47b9baaa83d6c2c8bb0f",
    "cachedAt": "2026-10-21T02:21:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2211/products",
    "sha256": "3ebb7f6400f794e7d136f2ddd05e5b696c4ee99b739d56aa4db4fe8dd38d5a8e",
    "cachedAt": "2026-10-21T02:21:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2211/prices",
    "sha256": "0eed1ed4f35c522ffc3996c995bd47fcdcfb8c534d975be6bb08f39a1ad06de3",
    "cachedAt": "2026-10-21T02:21:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2228/products",
    "sha256": "1228091c9bbc07610cff2ef4a168e18f80545390407bc0f36b6175fc6b54e34d",
    "cachedAt": "2026-10-21T02:21:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2228/prices",
    "sha256": "4ed3cc5833167e50281b3d4e34e491af323777b7f29bcd4613ff28276fb5f40d",
    "cachedAt": "2026-10-21T02:21:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2194/products",
    "sha256": "e9a627eac738df6d68c378af889eedb3c92a658a89083745f218e42225f1685a",
    "cachedAt": "2026-10-21T02:21:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2194/prices",
    "sha256": "3e33463b7a94f73acc4e272b63948e193acef80f5700872802ad965c5d06a20b",
    "cachedAt": "2026-10-21T02:21:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2195/products",
    "sha256": "3932cd12f50379e11350aca74afc9a97f93878619ecdc58279498e9bf56c5750",
    "cachedAt": "2026-10-21T02:21:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2195/prices",
    "sha256": "8349d8fb7f3d0689c7388d6f37c0f0313d679c063d4ca837f0aa399a6607bb80",
    "cachedAt": "2026-10-21T02:21:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2179/products",
    "sha256": "a967d01b3b7f1d4d14c8577122740d6c83d334d0907b7471a32b5468e8ae6cfb",
    "cachedAt": "2026-10-21T02:21:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2179/prices",
    "sha256": "4ea8c85483521821a32b6884f59a514f8119b994d7a70b874f3b12b0b1c61ab1",
    "cachedAt": "2026-10-21T02:21:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2151/products",
    "sha256": "4cd6574b21eab3bfb35a3735566b882142cc3f4c75399e07da6972017033b728",
    "cachedAt": "2026-10-21T02:21:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2151/prices",
    "sha256": "a602c90d4db8a64bd6c6cd6af1d157b8da11eb849c3ae85bfc45cf26d5ad5472",
    "cachedAt": "2026-10-21T02:21:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2146/products",
    "sha256": "d2e6d48c3c73c36410162c25da654869e2cea5d4934612dab70411e7639bb3a0",
    "cachedAt": "2026-10-21T02:21:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2146/prices",
    "sha256": "116054cf98aa8215d2fb104568a950b1571ed9474b21785df819c457af324f80",
    "cachedAt": "2026-10-21T02:21:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2558/products",
    "sha256": "4b2713883e847fc8a12e26a8205f0159556e01f0bd81ae5881e0f26f04d84441",
    "cachedAt": "2026-10-21T02:21:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2558/prices",
    "sha256": "32258eadd9c542bd7199de32dd2a654667745cf5b1c1d1116a0cc1f46240e649",
    "cachedAt": "2026-10-21T02:21:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2157/products",
    "sha256": "87c4c584a3fd9548b2b3f5eecaa98dab1fa05e37fbf7ea3ca0bdb25e5d8bb7e6",
    "cachedAt": "2026-10-21T02:21:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2157/prices",
    "sha256": "ac9eafd85896f443eaa8b506456793da9aa335451a3e127f5c54b61f29df4ba9",
    "cachedAt": "2026-10-21T02:21:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/163/products",
    "sha256": "8e70a23471f150afcde3b594f36a9937686ea7cec1823d31332d8f4881d5a666",
    "cachedAt": "2026-10-21T02:21:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/163/prices",
    "sha256": "4636cec239ed860f9cf38a70cafba81dc955654ade6d576fbf7904ae53cb4384",
    "cachedAt": "2026-10-21T02:21:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/243/products",
    "sha256": "96d408b173576389bc4b7d18398cc5f3bdcdcea3a0502f726200a6a243b7aaa6",
    "cachedAt": "2026-10-21T02:21:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/243/prices",
    "sha256": "d4b7a50a89cf8ec3c9a97c38b88b9805bbdb20b42804baca83f461d77209c944",
    "cachedAt": "2026-10-21T02:21:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/245/products",
    "sha256": "973b680e59308bc244f00abc62d7ec4312136c91f2d2e4dec120843fae2e5fb8",
    "cachedAt": "2026-10-21T02:21:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/245/prices",
    "sha256": "7d66604b29c1d6ae10ea2ad68086c172c714985505e55a52f76b5dd9dbc03483",
    "cachedAt": "2026-10-21T02:21:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/281/products",
    "sha256": "974725305c219ba38b3315db5ee5ef24645a8394b0f6e87fa537b6d624ef74a9",
    "cachedAt": "2026-10-21T02:21:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/281/prices",
    "sha256": "863f459bdc6ba76bd1a40d8c111e7f03f4cef11f99659e6efd88b7288dbc7934",
    "cachedAt": "2026-10-21T02:21:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2073/products",
    "sha256": "ce28ef5b536cb478977e5c47c48e5c029a7dcb57ff1336f25f51c4d0d3b7119a",
    "cachedAt": "2026-10-21T02:21:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2073/prices",
    "sha256": "c7f43f3c60654b0119019dc7cfb7d6e1eb73c29a15877253fb6bc764f79aa9ae",
    "cachedAt": "2026-10-21T02:21:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2072/products",
    "sha256": "88fc6e9be6c41b91c5256a06a303b17f182bb32bb9de4090a51cddb48e756d6a",
    "cachedAt": "2026-10-21T02:21:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2072/prices",
    "sha256": "ac5882b85f08f09ad24eeea4746f5095a3c5bfbc954a11a190c4d1e0adf7b2ab",
    "cachedAt": "2026-10-21T02:21:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2149/products",
    "sha256": "5c89f8ab0646a61263ca28ef6a04ad30636da0fbefb9b4eaec05b30db3b0f794",
    "cachedAt": "2026-10-21T02:21:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2149/prices",
    "sha256": "8426c0f154338b71dfd826dc69b7f7521994104a9b733d095523f79d706d69c4",
    "cachedAt": "2026-10-21T02:21:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2056/products",
    "sha256": "ba59cee040c0dbe1b533cdcdb6177d8f09b324955493fb085857d5f1b4fbebc5",
    "cachedAt": "2026-10-21T02:21:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2056/prices",
    "sha256": "105ce1093a18c64d3b5e069a778853448b8dae9f408d7b96ec5059c2f94bfdb9",
    "cachedAt": "2026-10-21T02:21:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2055/products",
    "sha256": "7f04a12951780e3cbdff844f40210dc09daee3b76984268eacbc6fa7949696ad",
    "cachedAt": "2026-10-21T02:21:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2055/prices",
    "sha256": "a1b9cb08ff7b9f21864bd314e1133df62fd562845ef2b7d86d0fff4ce54cbe6c",
    "cachedAt": "2026-10-21T02:21:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2052/products",
    "sha256": "c5ebb4109f637e0e237ece033d354e84acd702c9b05668f64975ae1867ae9b93",
    "cachedAt": "2026-10-21T02:21:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2052/prices",
    "sha256": "6e980c68e8daaed7fc47cf97648b79094b26b05cd3ccf3fa4962ab76a233104c",
    "cachedAt": "2026-10-21T02:21:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2049/products",
    "sha256": "10ea62ae1affe781d689b3d79b84e954edd6d3374d11746e03f30df76102848e",
    "cachedAt": "2026-10-21T02:21:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2049/prices",
    "sha256": "6ef351445bfd9d5915f84dc4e5763446bd5ee692949506a40c922891c1654c1b",
    "cachedAt": "2026-10-21T02:21:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1990/products",
    "sha256": "327d40b550250dc24f56135f0158dc63c1ac49ad95a4225088516dd998f9ac4b",
    "cachedAt": "2026-10-21T02:21:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1990/prices",
    "sha256": "fc10639a9ca493f8e939e06795fc125bdb04fe898bf3d07148396e3e95a4e570",
    "cachedAt": "2026-10-21T02:21:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1991/products",
    "sha256": "f4b114505794a05a6c35530f201d66cacb8d5eeddedaed4ce87b1bc442377d3e",
    "cachedAt": "2026-10-21T02:21:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1991/prices",
    "sha256": "d6b3af3f446795a6937707c0d4074dffe3fa5ed0b72f300d0763703be590a21b",
    "cachedAt": "2026-10-21T02:21:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1989/products",
    "sha256": "49df1a8000728f5154b93a097f108e068b7b318ecfe98b618f54f7095a4dd966",
    "cachedAt": "2026-10-21T02:21:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1989/prices",
    "sha256": "139d4d74ad2884664f435e02d366b96a5f5dd0a65ed72736bb132a63a0d1779e",
    "cachedAt": "2026-10-21T02:21:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2019/products",
    "sha256": "1874872650f51a4137bff412812c96510198c3412443dcab043b60a9949e0bab",
    "cachedAt": "2026-10-21T02:21:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2019/prices",
    "sha256": "8b870b376c5c23cbae1d2537a30278aabf8652c9d9ead7d47d3d5efad6a3a59b",
    "cachedAt": "2026-10-21T02:21:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1954/products",
    "sha256": "e3f399499548f90f0a7caebb81da81dd973e32a403a0748b39e82d5349fa10c6",
    "cachedAt": "2026-10-21T02:21:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1954/prices",
    "sha256": "f7ba09e8c4f06a0c24246f013524925998d9e3824cb403c87941293d114ca2bf",
    "cachedAt": "2026-10-21T02:21:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1948/products",
    "sha256": "2b2a5682bfae584681942193ca5b743a85587c235aaafa0b6985e43cdf2c92d8",
    "cachedAt": "2026-10-21T02:21:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1948/prices",
    "sha256": "0812f3fd799c6908bb3052464f27fdd34dceddaafb151c6db0f91a0877aa4731",
    "cachedAt": "2026-10-21T02:21:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1936/products",
    "sha256": "2b0cf94091ab058b294d63968a618378a27f2491a07262c511a4982c2fab9cd5",
    "cachedAt": "2026-10-21T02:21:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1936/prices",
    "sha256": "ae264236df08d6757a63dfc8f42a3cc32a13bb2e89429de39df0f51825246521",
    "cachedAt": "2026-10-21T02:21:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1931/products",
    "sha256": "2a7962dd5989eeedee1183c7fd7e85412c73295c14c8d9c82ea3c9e0bf19d08d",
    "cachedAt": "2026-10-21T02:21:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1931/prices",
    "sha256": "a754211846b05e42faf932c7e61fd399c745eb931291b09e24293965536499f3",
    "cachedAt": "2026-10-21T02:21:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1922/products",
    "sha256": "a9dd0ee149ce772fab868e0bc0c673cdf3c2d92752a1294781fbebab554bf53f",
    "cachedAt": "2026-10-21T02:21:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1922/prices",
    "sha256": "4e06ced51fc818f9219b0a7fd6c9abe4340e04d9b893a1906271e403ab9ff54b",
    "cachedAt": "2026-10-21T02:21:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1911/products",
    "sha256": "0e9364a2c50a3afc0fec1a411006887db6f9887077f70afeade794df88a2caa1",
    "cachedAt": "2026-10-21T02:21:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1911/prices",
    "sha256": "7f7edba5771005a287ff14756c613e2ac512627abb5d51cebe1d24cc86c0be0e",
    "cachedAt": "2026-10-21T02:21:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1912/products",
    "sha256": "88d7525683c9ef2e9cb64db6ca2e7dc6b366e4a9a0614f5622c5468265950936",
    "cachedAt": "2026-10-21T02:21:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1912/prices",
    "sha256": "d5f16bfc62d3c80f3c093bf62070438e80be2ff6ae8b27e347bc359a0174bc0e",
    "cachedAt": "2026-10-21T02:21:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1920/products",
    "sha256": "fb90266d8d532a6dc8f5bdd0986c5ec983e250b195b89749a054c2a1daa734b7",
    "cachedAt": "2026-10-21T02:21:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1920/prices",
    "sha256": "60d788661d7568608192a859e5a3933057902b423b24502c3e3b3b8ad69d1524",
    "cachedAt": "2026-10-21T02:21:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1918/products",
    "sha256": "7b59090ad581daf18ab268b9c6cbfd44601654e3921622a1e4be95ce3844553f",
    "cachedAt": "2026-10-21T02:21:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1918/prices",
    "sha256": "48af8c8af3c46b92abba98cf609909f05d8a7a87a61bbdc37e07503b240152ea",
    "cachedAt": "2026-10-21T02:21:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1917/products",
    "sha256": "9fbc8fb133daac449e4d1d5d30fd74ea8e7b72f9bd58aafe75f41efffd89fd68",
    "cachedAt": "2026-10-21T02:21:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1917/prices",
    "sha256": "35b47e204c0bd49205741150b38ba407e48f5e9f410e8717d5e684aa9fa39f88",
    "cachedAt": "2026-10-21T02:21:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1907/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:21:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1907/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:21:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1903/products",
    "sha256": "1bd702daf96578ca051d13d45b50f8914f4df1d76cbf5257f9b2fa687f14f346",
    "cachedAt": "2026-10-21T02:21:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1903/prices",
    "sha256": "7124b31101baa8cc7743b967045ea9b9aee4f300abd83afed19ebecf455503fc",
    "cachedAt": "2026-10-21T02:21:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1890/products",
    "sha256": "6775810f32fd34353cd5792acd34f8618298fddbeab95300009d8f1751b139ea",
    "cachedAt": "2026-10-21T02:21:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1890/prices",
    "sha256": "7f26a12ac167b9d6957af67be6fc6801624fa19db8806a9325bb86379e32b73d",
    "cachedAt": "2026-10-21T02:21:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1880/products",
    "sha256": "0f8e7171e5f05166516f47cb83d0c2aaa7ddc35cf09253e600f194767ab839ea",
    "cachedAt": "2026-10-21T02:21:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1880/prices",
    "sha256": "f7cdfea7742e2c6dd2fc3f5b7f8fde816fae64a3c0bf703513efbb2acc2fdbdb",
    "cachedAt": "2026-10-21T02:21:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1878/products",
    "sha256": "9355089354891401e5c8243ad8c68f996971d10faefd35721b5df052adb861bc",
    "cachedAt": "2026-10-21T02:21:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1878/prices",
    "sha256": "d535d9c383ca22c189733cda662c94414810f55001466b4927705ba29a6831af",
    "cachedAt": "2026-10-21T02:21:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1877/products",
    "sha256": "4b5baed5cb0ac1ad039ab04ac92e8601ca2b22210d6b7e106f2b34223cedd02e",
    "cachedAt": "2026-10-21T02:21:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1877/prices",
    "sha256": "95485563641b1b50a7cc09ac10b6040f3bf16f98d882f741bd65650b97a78880",
    "cachedAt": "2026-10-21T02:21:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1860/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:21:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1860/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:21:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1854/products",
    "sha256": "cbb7ecb7ee763cae22d90368dd749952231ed405cf668366c2e51836a03f19c6",
    "cachedAt": "2026-10-21T02:21:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1854/prices",
    "sha256": "ef03dc596e1d5761281987b17ec215c541bb25941fbb53325aec2bad37d6f834",
    "cachedAt": "2026-10-21T02:21:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1855/products",
    "sha256": "c3a7c90fb79a3711660d375f3704bd4ac2150a7ed8359d2fc6f97866276ce1e1",
    "cachedAt": "2026-10-21T02:21:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1855/prices",
    "sha256": "414fa05ef2df742e638e4d7eea67cde0a84469c8b0c19ae6aba9096ce7a76ddf",
    "cachedAt": "2026-10-21T02:21:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1849/products",
    "sha256": "6743e63ffc99d3f519f359b05999ade787b5f629b4c5356aeef42c89d44a0fb2",
    "cachedAt": "2026-10-21T02:21:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1849/prices",
    "sha256": "1c3734f1ab67deaee035724482956df533882c3d11a43ba79b201e7ba783621e",
    "cachedAt": "2026-10-21T02:21:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1845/products",
    "sha256": "dc11b083d46ff2b59466e7e5a6dba3bcc158d97f6bf9af595794af9b82546295",
    "cachedAt": "2026-10-21T02:21:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1845/prices",
    "sha256": "73f33e61d158c6e753c1eb5de535a6c20598c3f1a385899ac482cb770c3c5753",
    "cachedAt": "2026-10-21T02:21:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1846/products",
    "sha256": "641c766a39b9756082380156d4ae89021dfd29faac50b6591e691c2cf2554c68",
    "cachedAt": "2026-10-21T02:21:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1846/prices",
    "sha256": "1bfd592d104f42534f5d08724b3467fc028f711476e9d2844c3a66f3ee0cd91d",
    "cachedAt": "2026-10-21T02:21:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1844/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:21:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1844/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:21:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1841/products",
    "sha256": "1a670962da106ee08d7e7695ab3450b9cba112074c28f5a4d40ab6f98068a8c7",
    "cachedAt": "2026-10-21T02:21:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1841/prices",
    "sha256": "fa7143fded0ef22c2cbf961bb1eac3df969d63e825b4b95825c170001aba662b",
    "cachedAt": "2026-10-21T02:21:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1838/products",
    "sha256": "a77818881d5a10dfedf67f68d03bfedfa3f8cd9f8f624f4e676d0c655b5adc92",
    "cachedAt": "2026-10-21T02:21:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1838/prices",
    "sha256": "617dacafe42019b6f4d77d8af8e9e2a1c73928cc409484406bd0cca31d952c87",
    "cachedAt": "2026-10-21T02:21:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1833/products",
    "sha256": "99d24befa6c1e1a32cc1a561c7625143f5300f620ea8a558b32b513348ac9c84",
    "cachedAt": "2026-10-21T02:21:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1833/prices",
    "sha256": "746bc0645354e9f693204bedbed7ac4ac6202fa245968d47ab3444a9fbdd2556",
    "cachedAt": "2026-10-21T02:21:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1834/products",
    "sha256": "6f9fc80de653c531a74650f9d681425012f9fb8ed3e829ce91054f4f979a61e5",
    "cachedAt": "2026-10-21T02:21:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1834/prices",
    "sha256": "cd2581b0477ff93c6e7e22af6890fd1a6765cee0f367a4932a2c955813ab9f87",
    "cachedAt": "2026-10-21T02:21:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1828/products",
    "sha256": "e5300b906cd9f94462efda4a42c4d4eb9c949fc95f19790e9384451120abe5e6",
    "cachedAt": "2026-10-21T02:21:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1828/prices",
    "sha256": "f55e81087e3ad8804348a9e08a2bd1d17f400bd888413e5d72e9a554829fb2c7",
    "cachedAt": "2026-10-21T02:21:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1807/products",
    "sha256": "51e53435262c45754cac43840e2bb4a28ca3543d2f707c24764d811ef4d97dea",
    "cachedAt": "2026-10-21T02:21:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1807/prices",
    "sha256": "b979e3fc1743b25c7e4bfc40ec58d9884fc78d63c07751b90fdb8f24879e1b66",
    "cachedAt": "2026-10-21T02:21:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1822/products",
    "sha256": "fe2361693f1a497ac314fbaeab5ab3542c4daec55703dca337b97c9caf2b76ed",
    "cachedAt": "2026-10-21T02:21:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1822/prices",
    "sha256": "ebe98c2824ef546dd703f8926603b699939b88b4c4d9d425a7c6ae10612deffe",
    "cachedAt": "2026-10-21T02:21:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1820/products",
    "sha256": "5684cae82d74bebcef6f474eed4c57c2cbbeac12eb93bfbda36f9d9de734a83f",
    "cachedAt": "2026-10-21T02:21:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1820/prices",
    "sha256": "4968db99c65eeca98bd1f9f1e22d32cc10e6e0968cc855a01ebed5c0a83e2afb",
    "cachedAt": "2026-10-21T02:21:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1802/products",
    "sha256": "ef055e927b6df9f7c040072c135d3d581902231163062ff71e2e26f5d4c4fee7",
    "cachedAt": "2026-10-21T02:21:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1802/prices",
    "sha256": "fcbddf5ebd64ca98017b8fa0e1cc4cad66f817ec19af16c27c1d3e8b3ff1696f",
    "cachedAt": "2026-10-21T02:21:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1803/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:21:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1803/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:22:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1795/products",
    "sha256": "9eb727e9182ccfa0eef4a1e2db2dfb0c6fe84591859f145702fe9dbc9877cfad",
    "cachedAt": "2026-10-21T02:22:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1795/prices",
    "sha256": "d5ca54ccf390c9b5c4240cd57c7f77dad139c0f626527547c5622f6eaac6e757",
    "cachedAt": "2026-10-21T02:22:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1761/products",
    "sha256": "10e3e2c3ede4536d1527e747761b6e92432e2a2d4b8aba00b68aa9106c0027a1",
    "cachedAt": "2026-10-21T02:22:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1761/prices",
    "sha256": "dfcf78207d5868e7373466d6bd704942577a6de61a943cc611f0bfb9105b4e9c",
    "cachedAt": "2026-10-21T02:22:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1760/products",
    "sha256": "b92dfa36e31333ce913fa1e653508fdf4bf53184c3fbba26964c50d5573f171f",
    "cachedAt": "2026-10-21T02:22:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1760/prices",
    "sha256": "47236c682b744347ef6b7c3109b9494600502d5cfc3616fa7f6e7dc26a3f6c52",
    "cachedAt": "2026-10-21T02:22:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1759/products",
    "sha256": "44c25c34820246ffd03b965256ce4282499ffa8b731e3710c8d48f91efcfa598",
    "cachedAt": "2026-10-21T02:22:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1759/prices",
    "sha256": "416b03c09cc4e58476d3729fb7fc3758d6276367b2255b6c2f21c67bcfabe285",
    "cachedAt": "2026-10-21T02:22:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1745/products",
    "sha256": "20d3bd4bf686a7e961777546f87ba3cff9337459f60dc3023e11694a0f5d2163",
    "cachedAt": "2026-10-21T02:22:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1745/prices",
    "sha256": "fb8241cf92eb510465540eecd31cdd6ee4f22380f7ebcbb362b23b1edae7ce40",
    "cachedAt": "2026-10-21T02:22:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1743/products",
    "sha256": "49a552c790b270b211dac78c55a8343ebd68101a51d121f1f67cbefa0cc598ef",
    "cachedAt": "2026-10-21T02:22:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1743/prices",
    "sha256": "6add7ea086769c4d6b11e6f307cfd2b9e18d44b4b534f7ea4627d397726e6835",
    "cachedAt": "2026-10-21T02:22:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1736/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:22:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1736/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:22:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1707/products",
    "sha256": "a2de5ba4cf46c78e66478633d994acae988aa94ded234a8b5be5df977fc44e01",
    "cachedAt": "2026-10-21T02:22:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1707/prices",
    "sha256": "8410af22ea38c04f2047d8f5d9ce017bdb0dbbc6ef56a6f7e44e14dc5a2ce10a",
    "cachedAt": "2026-10-21T02:22:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1704/products",
    "sha256": "70207e7c7ea220b0bcaa015ee5563fbe8287d5aea012b9e87a62797b174f99b7",
    "cachedAt": "2026-10-21T02:22:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1704/prices",
    "sha256": "c49d7b87cb6ead575a77f9ca0ecb86c64254144de41f9bd6282a28d542226145",
    "cachedAt": "2026-10-21T02:22:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2682/products",
    "sha256": "8f5c1f6dfeef79740437db529aabad03d9e6650001b6beffa1dc6588a22ea36c",
    "cachedAt": "2026-10-21T02:22:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2682/prices",
    "sha256": "a0a99ae483cb3bc27dafd0896d51e1332ebab789d394389e542209443f5e71e7",
    "cachedAt": "2026-10-21T02:22:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1698/products",
    "sha256": "dd2461063192e3ed0584aedfd9596ab306ca77af6051af5fa16877831c7d81a1",
    "cachedAt": "2026-10-21T02:22:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1698/prices",
    "sha256": "5b9dde693a4b71391837ab1f03a0524b833ee95cb3ff412dfa93ad40775171a7",
    "cachedAt": "2026-10-21T02:22:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1695/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:22:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1695/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:22:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1674/products",
    "sha256": "dcc9824ce7e28f46025874f51a6aa2b02842a25a57ef24306bd14ca03530f649",
    "cachedAt": "2026-10-21T02:22:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1674/prices",
    "sha256": "d867773ed686c3d39c71513439341c60d8a12983b50d5d841192a3440c0be1b0",
    "cachedAt": "2026-10-21T02:22:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1660/products",
    "sha256": "815d7044a06b0caf147995f8aa5c9fa001d6bd9d19714371d162e3f5005f46c0",
    "cachedAt": "2026-10-21T02:22:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1660/prices",
    "sha256": "5e150798f51c4d6e7ceaa4c212d877e47584e33ee1bc4da8c42d25f43e1b0708",
    "cachedAt": "2026-10-21T02:22:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1672/products",
    "sha256": "15271b7a71e044768b05d5d1737dc6a6f0b35aafb792aab7d60b9cbacabd63a6",
    "cachedAt": "2026-10-21T02:22:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1672/prices",
    "sha256": "5a291bbe9b4ee42161ce7bb0271b7abf24b41275cf18041a0e52f580e000ca7f",
    "cachedAt": "2026-10-21T02:22:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1671/products",
    "sha256": "16e37f1f3d420e8ecb2e4da0e628cbf221122c8b4d6f5b970ac5e4834a7af5fd",
    "cachedAt": "2026-10-21T02:22:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1671/prices",
    "sha256": "916dc43fea1861c8eaaf3bba0e1eeefeb91db3cee5711e5e609b5c9163041b78",
    "cachedAt": "2026-10-21T02:22:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1659/products",
    "sha256": "597be8c771f85011ae45f896f07f6aca944fb4a5b5892868952675d1c5cd20a0",
    "cachedAt": "2026-10-21T02:22:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1659/prices",
    "sha256": "26b6beea06ddbb61b97f00bf61951ea4485c50a6093f7129ef0b7c2976ada589",
    "cachedAt": "2026-10-21T02:22:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1652/products",
    "sha256": "fda1c325c42e75f0bf13ac92af3f08eb4fec109a3569a0a87abd277e80ae8a54",
    "cachedAt": "2026-10-21T02:22:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1652/prices",
    "sha256": "2acbfb663c8b5f614c9fb8891cf0eca8e5e0ca37fcd73a8fe946b1fa5ce77943",
    "cachedAt": "2026-10-21T02:22:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1653/products",
    "sha256": "756500df8aaf9e15a35d14e73fbb2a02156335edbada5b2cdb0a944786595d48",
    "cachedAt": "2026-10-21T02:22:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1653/prices",
    "sha256": "00359d8918fb3fb27c262e1085ec707d17c707141934e0140936692b56f8ecbe",
    "cachedAt": "2026-10-21T02:22:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1648/products",
    "sha256": "f06177510dd95f5e247a45223224662f9e073da0272501c44ba2683a6c054670",
    "cachedAt": "2026-10-21T02:22:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1648/prices",
    "sha256": "80a71a01bf70476274c70e682512f8e1078d18e289cf34e6428baab43451a627",
    "cachedAt": "2026-10-21T02:22:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1600/products",
    "sha256": "ef04929f2aaf65c037714792922c57a02720663c3c7528bbd4d798de59204db9",
    "cachedAt": "2026-10-21T02:22:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1600/prices",
    "sha256": "598b4cab32c3314682e4986407fc2dbc948e6eabf1fff039433ea8c31f762886",
    "cachedAt": "2026-10-21T02:22:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1574/products",
    "sha256": "686c75626321dcd3b7243841e8a8ee7f64689a1499f6cb2bf1160234bc0dca69",
    "cachedAt": "2026-10-21T02:22:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1574/prices",
    "sha256": "d116452a906435fc1ac61092f876eec9211b58f8fb2aa7735709721a6a57424e",
    "cachedAt": "2026-10-21T02:22:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1592/products",
    "sha256": "6bd3cb7cd502241fd5bb3f552c140625fc666c570bcc5608de2193adf4150f0e",
    "cachedAt": "2026-10-21T02:22:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1592/prices",
    "sha256": "8ae9c0f65cae6282a7fa1394a91d5ad27d375bd9944d0c3eeed8f1a6cac177c9",
    "cachedAt": "2026-10-21T02:22:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1550/products",
    "sha256": "ebafa588f13c5b277dc57044686419fc1b893ad8b41da376b2ddbf5876a691ca",
    "cachedAt": "2026-10-21T02:22:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1550/prices",
    "sha256": "58a0b414bc3b579030b821f7754e3d2436287245d93bfe819b7560d852ba7ca6",
    "cachedAt": "2026-10-21T02:22:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1547/products",
    "sha256": "e4e7191963df14cfd849fb6913c50fe5b621ef445196becf1e2e7ee651de610e",
    "cachedAt": "2026-10-21T02:22:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1547/prices",
    "sha256": "f8cf926e0b288347e8191bb4998fe1fc934380aee39947370c9714564da72630",
    "cachedAt": "2026-10-21T02:22:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1572/products",
    "sha256": "77982277cae4312c60f61da3dd7f661271bb33cc65fbc36a9b70aee41a0dc136",
    "cachedAt": "2026-10-21T02:22:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1572/prices",
    "sha256": "5516bd77b3b82c7d4ed67f4665ea5dad3959cc6cddd53b1e5acf7ea1891c31cf",
    "cachedAt": "2026-10-21T02:22:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1544/products",
    "sha256": "02076dceb6c0cc46e1d78403ea70d3605d6de192bd50657bd98f3e52a5b0f26e",
    "cachedAt": "2026-10-21T02:22:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1544/prices",
    "sha256": "ee96d38a2beb35265e99fb24b066cda274e6ebb3726612dd04ada96360880467",
    "cachedAt": "2026-10-21T02:22:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1545/products",
    "sha256": "f4d5a798b5b54303a9c504cf53c1db75757c8971ae357d4894c2aff5f3d6e5db",
    "cachedAt": "2026-10-21T02:22:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1545/prices",
    "sha256": "2e898c40d2406da3a9f58f7ce0903f1c87999d62584ac41df54ab49007d1336a",
    "cachedAt": "2026-10-21T02:22:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1537/products",
    "sha256": "8db9ddf07dd07ec746ffd49e21157b566adad46867339bb11cf89851866370c0",
    "cachedAt": "2026-10-21T02:22:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1537/prices",
    "sha256": "796691576f771ad7cfc0cd31a7f8bb262ff9c8fb1401ab19afbc591d18525575",
    "cachedAt": "2026-10-21T02:22:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1529/products",
    "sha256": "f7087b28bbcdee46a08e4e600655883544011671e382431149ee9debf976d04c",
    "cachedAt": "2026-10-21T02:22:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1529/prices",
    "sha256": "64aaf91727748ecdf72b58b59e5c7b6fb1dad4e45bccfad6c6bab8e1a7a4220e",
    "cachedAt": "2026-10-21T02:22:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2051/products",
    "sha256": "4581d7759ea383d62be9b12b144a7de75c55e5acb7c784ebe6790657c9c56e05",
    "cachedAt": "2026-10-21T02:22:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2051/prices",
    "sha256": "63d9a96bb8b0eba693ef5549700662d14e7e80a4e7a79c867e2a4473489151c9",
    "cachedAt": "2026-10-21T02:22:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1523/products",
    "sha256": "ada9b88904c5c8e636d29f6e39502917144e9e8808cf24246415dfc9c01d6533",
    "cachedAt": "2026-10-21T02:22:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1523/prices",
    "sha256": "93e1bd627a4b07d94f15069fe9412666377fbdd725cf079275b4139ff9f2613f",
    "cachedAt": "2026-10-21T02:22:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1513/products",
    "sha256": "6cd41439600b5dbf09d4bb10df927123d05341a9d6f1ac1c15543d683a832725",
    "cachedAt": "2026-10-21T02:22:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1513/prices",
    "sha256": "28c2e9e191305f14f9ea6eb41379697fea6e1594b055b1098e2053ec21e3ef53",
    "cachedAt": "2026-10-21T02:22:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1495/products",
    "sha256": "589bff88f9ada4b4b89c8ca11d9d327be50d2c0e56f943ad2ab733788252e69d",
    "cachedAt": "2026-10-21T02:22:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1495/prices",
    "sha256": "49c1f8f1d1c5847cf9db75c146a5f0bb43bc72d4eb4073380be58ba83448ec1b",
    "cachedAt": "2026-10-21T02:22:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1505/products",
    "sha256": "12d9ff1e06d8a2049f8c69892c7a079c798053ce371b20669f86e7543eecd235",
    "cachedAt": "2026-10-21T02:22:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1505/prices",
    "sha256": "d7c20f0329dd2cb4ca54de3904a65c65cb0241fda60e9884f34310af0b67aeb6",
    "cachedAt": "2026-10-21T02:22:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1506/products",
    "sha256": "719990ac6696f2794cd13f8f9af366f386be7fdc77ee92bd224d7078b6fd0a37",
    "cachedAt": "2026-10-21T02:22:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1506/prices",
    "sha256": "0a74586278fbc81b5625dd9adee4e3aa507a13a737ed341b2ecc95e99847896d",
    "cachedAt": "2026-10-21T02:22:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1510/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:22:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1510/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:22:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1492/products",
    "sha256": "bb1e8c71f414d168ac6a1e7d0f2018d8624116f27edebd1ee8bdc4e7ca5bdcc1",
    "cachedAt": "2026-10-21T02:22:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1492/prices",
    "sha256": "b1308d3cb3375944d1fe86b1ff21940f47b9f553ec9b3bc92fc0c2e2ad42f3a5",
    "cachedAt": "2026-10-21T02:22:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1493/products",
    "sha256": "ec1ca9015d157bed5c6bcbb309355bfe959df5c4258170c49c73dbf960e00bcc",
    "cachedAt": "2026-10-21T02:22:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1493/prices",
    "sha256": "213454390a5b405f0f52a557fbe5eee862db8f6a29432f58cc964562dc35a3ac",
    "cachedAt": "2026-10-21T02:22:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1491/products",
    "sha256": "e4a545c09b540f7ccd2cd59dd649d344802a4dc760ab90bf6ffa418216ad88b0",
    "cachedAt": "2026-10-21T02:22:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1491/prices",
    "sha256": "2f8da4d472a0678b824b5766b6ea0dd05ace7ab1448b4107586aaf30fc49d181",
    "cachedAt": "2026-10-21T02:22:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1489/products",
    "sha256": "faf2c19f74acd3cdbfd1b7f24f6d1e4b403e9366e408f1bb9987b35beebf8dad",
    "cachedAt": "2026-10-21T02:22:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1489/prices",
    "sha256": "70497718eb3986e91c8d590665b05d08b457c61f54d80c2726f4bfacf169bb32",
    "cachedAt": "2026-10-21T02:22:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23186/products",
    "sha256": "55dd129d3164d0de888dfdee7b249ca84a8d4bd850ce9f7e373b773a831b9300",
    "cachedAt": "2026-10-21T02:22:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23186/prices",
    "sha256": "c716c933564b631b670d710e4a930b11c8dd36348f8d39001f1715625ce53666",
    "cachedAt": "2026-10-21T02:22:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1488/products",
    "sha256": "285b79f377d11800aef009e2463f2f6b02970b23207190c7104370cb33db8e5f",
    "cachedAt": "2026-10-21T02:22:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1488/prices",
    "sha256": "463518ffd38a1f34f18445c16a64037696b63969fe156418c79f6507ea0a0b79",
    "cachedAt": "2026-10-21T02:22:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1484/products",
    "sha256": "f7e7e43e6b56a3bef665eff538281bab7030b5d7835d25874a0cde4a5a292413",
    "cachedAt": "2026-10-21T02:22:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1484/prices",
    "sha256": "f48fc256a685a1ac4004a0500db82592332987bc5578ee7dbd60eedc78c88d10",
    "cachedAt": "2026-10-21T02:22:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1485/products",
    "sha256": "82380d29e8f3078b8d60b89e405ac99022c85efdb0a75d525f79611ecbc0b96c",
    "cachedAt": "2026-10-21T02:22:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1485/prices",
    "sha256": "c995f8fe68339cee066d3fa2fc5365dfc6bc0adfc1128ffca735ca62805f7a15",
    "cachedAt": "2026-10-21T02:22:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1480/products",
    "sha256": "8e52df89deb4cd6328dc2edccc93d096157a202b1a093c4edd7cd820a469bc26",
    "cachedAt": "2026-10-21T02:22:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1480/prices",
    "sha256": "885b50ad6655b254324e8dad919419f6f59880608afcf659558559b68ec012e0",
    "cachedAt": "2026-10-21T02:22:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1470/products",
    "sha256": "91f26df54d1e4fcea775dd7d70d85dc93ef7aab7ccdda9ca1163de96646ffcda",
    "cachedAt": "2026-10-21T02:22:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1470/prices",
    "sha256": "0a7be3283f8b7bf4b5bff5eb6df839c45bc05e7dfd6c0457a161f7f0bc51c3e6",
    "cachedAt": "2026-10-21T02:22:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1479/products",
    "sha256": "47965007a022064451ba16270e18abb5bc7867f121bbe8d3ed984c9708c0f28f",
    "cachedAt": "2026-10-21T02:22:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1479/prices",
    "sha256": "b5e3cdcb09a015874692f7381084d5fbd977b2f592fc06666a5e3ffb015f3528",
    "cachedAt": "2026-10-21T02:22:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1466/products",
    "sha256": "ec942bdfe263e485a718b887f2fb9a1d5d505ddd9f4657f38a2df96e0cc9d39a",
    "cachedAt": "2026-10-21T02:22:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1466/prices",
    "sha256": "60ac5da8d1fe7c96c6ed1e7e99140b10e65c5693b9c694c5b9eb1ee944337b24",
    "cachedAt": "2026-10-21T02:22:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1467/products",
    "sha256": "cea36aad49249571c2040121c8817c331f7276e6a8c5322739b8d35862a150d9",
    "cachedAt": "2026-10-21T02:22:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1467/prices",
    "sha256": "ef71cff8ff6f1f19faa8e2a6ce2812b08f2fcb1995f8e8ea650677dda8ddf74e",
    "cachedAt": "2026-10-21T02:22:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1462/products",
    "sha256": "d12bf52b31ff4ea92a70793099e68ac29b3943252afb70dd6f28d72dff5a1fb6",
    "cachedAt": "2026-10-21T02:22:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1462/prices",
    "sha256": "e0b875c17f1563fcccfaa9596abb5b6555e09ea6fecf84c8aa679d72cd41cd3e",
    "cachedAt": "2026-10-21T02:22:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1353/products",
    "sha256": "8c2f12c213ebdea2d9f23255a458a2757ecd75fb5be6d09606a6ac998754ecf5",
    "cachedAt": "2026-10-21T02:22:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1353/prices",
    "sha256": "90fd384acffcd10039e8d1cfc925bd30b38d8b7db452c118562e3f12e08b28d3",
    "cachedAt": "2026-10-21T02:22:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1354/products",
    "sha256": "39fa149d525f7403f8797a3ea2a95fb71bb5f0eca2d2c8836934e010cb93df8e",
    "cachedAt": "2026-10-21T02:22:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1354/prices",
    "sha256": "17a863298fff006086ba09ae2954627231d2a700be0086df0c07751536679585",
    "cachedAt": "2026-10-21T02:22:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1339/products",
    "sha256": "534d9c7b6d94d129be479bcb595694c401cfccfd78fd73f26db7f83fd7e084fc",
    "cachedAt": "2026-10-21T02:22:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1339/prices",
    "sha256": "bdadbf7950c38dd8fbfc467325889bb5df4c60b022dd68a97d1b48ff5cc14e8b",
    "cachedAt": "2026-10-21T02:22:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1310/products",
    "sha256": "d09bc1dd040f3b739eb7fb0b640ecaa542c1f95f0206998b47bd7d4a1a1879e5",
    "cachedAt": "2026-10-21T02:22:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1310/prices",
    "sha256": "b43333ba0194e7b1714c90b42e60647ea6ae6d0d793e570ce3f439678e8b5625",
    "cachedAt": "2026-10-21T02:22:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1319/products",
    "sha256": "995bb482096ca765ad74bc77733a14ff32c6d272d6c630481e6b88340db22e35",
    "cachedAt": "2026-10-21T02:22:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1319/prices",
    "sha256": "deeb39eb7c4c337c4fb5f2f81bf1fd5762758a97cb75db97160ac21aedcfd40f",
    "cachedAt": "2026-10-21T02:22:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1309/products",
    "sha256": "4c3d82d8aaec3352c59fddf51e035799ab26e13132a9cdd5710d4bbeae626e19",
    "cachedAt": "2026-10-21T02:22:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1309/prices",
    "sha256": "bc3b43aad03e8a8ea31328e0de0d24d1ce57fbcbe1c578727b1315d6d7bbea4e",
    "cachedAt": "2026-10-21T02:22:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1307/products",
    "sha256": "50b9282b664dafd474d9c9b10f8e6a607559b054b076fb1d9b288564bebfb14f",
    "cachedAt": "2026-10-21T02:22:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1307/prices",
    "sha256": "5c30311b6b7afdd53b50f1d90ac99bf2ebc2947a4248667bf8e2e396060ff8f4",
    "cachedAt": "2026-10-21T02:22:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1286/products",
    "sha256": "0deb4dc557008b965474be5d38e1970489a7692e7e7b0a6b49a82d787ad598b3",
    "cachedAt": "2026-10-21T02:22:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1286/prices",
    "sha256": "4aad9df13f515038cec7724ea3ac4b28afc50b92935a873ebaba910e78bf1f74",
    "cachedAt": "2026-10-21T02:22:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1300/products",
    "sha256": "882c1f6b7b881898a7396545ffd1204288bdffd68b1e0ab20e6f3c9255d35310",
    "cachedAt": "2026-10-21T02:22:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1300/prices",
    "sha256": "edeafa99ff7e5c9ee8600b2543f6b824188ab93142eda5a6726501bae50a5a95",
    "cachedAt": "2026-10-21T02:22:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1158/products",
    "sha256": "9edf3826ff6f2ca7c5c5237979987bbec6cddd60563f64acc4bc0a60fa801049",
    "cachedAt": "2026-10-21T02:22:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1158/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:22:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1282/products",
    "sha256": "ae681c5a01730b8eed598f7170aec6cc6fe11cf4853d94eacb1fa0ca1cb331ca",
    "cachedAt": "2026-10-21T02:22:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1282/prices",
    "sha256": "056b15f4a1e519742a9a65be3e719a97746469aa32715f87edc14aaf1b7ba013",
    "cachedAt": "2026-10-21T02:22:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1283/products",
    "sha256": "8ce594e9def7e82fb5ba8c786d7a9348323bf331458dc812e353261f6f7a8a2e",
    "cachedAt": "2026-10-21T02:22:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1283/prices",
    "sha256": "a6667fee5771981645162e3ed34c0bb8ba50ed0658777c35bc9243e924da7b14",
    "cachedAt": "2026-10-21T02:22:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1156/products",
    "sha256": "7fc943f55e9c8f40e004eecb31e7bb778ef90247f7ac2a954aaa8b95183ea0d4",
    "cachedAt": "2026-10-21T02:22:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1156/prices",
    "sha256": "706311a8ed4186115598dabf2d84d88a2e727c5002976562b2b9f68802be329e",
    "cachedAt": "2026-10-21T02:22:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1157/products",
    "sha256": "e7cf5e74f50f85686f9edc719e7fa79cdf9bf628d2668fff5dff99900927264f",
    "cachedAt": "2026-10-21T02:22:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1157/prices",
    "sha256": "241aeb776ab261ab6324c82cd70937950105121c844fed114fc7861a6cd82d93",
    "cachedAt": "2026-10-21T02:22:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1162/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:22:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1162/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:22:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1155/products",
    "sha256": "872dbcd77b3cdf000981bcc4d79bc40437bbb903c657c6b3766b8c2294553b79",
    "cachedAt": "2026-10-21T02:22:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1155/prices",
    "sha256": "2d599e5e7e64ff823482d63504603b1bd01ab4c727dbd7fa5458588bf2a03ebb",
    "cachedAt": "2026-10-21T02:22:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1289/products",
    "sha256": "5240917efff01b6ddb03468e0da36b8d6b4f496601dc8b7622816e70885c0543",
    "cachedAt": "2026-10-21T02:22:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1289/prices",
    "sha256": "79e449b2d44ad9d6e6ec1e2d3ebf6c44adc48a061f3bb486aea88c3d8d4728e6",
    "cachedAt": "2026-10-21T02:22:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1154/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:22:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1154/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:22:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1153/products",
    "sha256": "bbf9e93311915cb116e1710cf541306e058838fce80aa3b8ca4111de6abe9b20",
    "cachedAt": "2026-10-21T02:22:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1153/prices",
    "sha256": "583ad6a32c640eca916a35ecc06117a608d9c5df01a79d37a52fb6727411a668",
    "cachedAt": "2026-10-21T02:22:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1149/products",
    "sha256": "c5c2582084e33e9204cdbbb4d9edef93489dcfe4f821c09178e0914f9abea11e",
    "cachedAt": "2026-10-21T02:22:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1149/prices",
    "sha256": "f018834d9cd689462dd01f33aba84bdb5c40adf2c538cb66741fb11db69e0b8d",
    "cachedAt": "2026-10-21T02:22:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1142/products",
    "sha256": "45e2dfea7e1566e8cd7aecdb9f2fb1467e17d34333e2141533274a00626b6478",
    "cachedAt": "2026-10-21T02:22:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1142/prices",
    "sha256": "9b869b2e0f19146f28e6a52bcefb23dbc6e1e2a10722554c4e432c404f2db8b9",
    "cachedAt": "2026-10-21T02:22:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1130/products",
    "sha256": "1b65425b1714a716aed6fdf47d06088a1583404d016fa8500758028989d47dff",
    "cachedAt": "2026-10-21T02:22:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1130/prices",
    "sha256": "34c0fe78e135068649c4c521cd67a00dfdc882ba5653ff6400bd6c684d1fc766",
    "cachedAt": "2026-10-21T02:22:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1131/products",
    "sha256": "bf23a0381262a5e449dc85b7d04869da346b10d260804c0e9666604e86d56ddf",
    "cachedAt": "2026-10-21T02:22:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1131/prices",
    "sha256": "cb21546e08111f42c18b8f7aa4b8e00c5c345b7fe74d972270b2c314db680274",
    "cachedAt": "2026-10-21T02:22:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1128/products",
    "sha256": "9c0355f42ce1d2c9769a81c62464ecc0823e3dc9accf6f9ba948a413f200235f",
    "cachedAt": "2026-10-21T02:22:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1128/prices",
    "sha256": "e64206522bc9494a0f0404ba85245add1373865ab22f200ed0e640facdbbe941",
    "cachedAt": "2026-10-21T02:22:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1129/products",
    "sha256": "d2864e11123158f7649a3107d94e7468d0dd889b540603cb4f4e1ba77907963d",
    "cachedAt": "2026-10-21T02:22:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1129/prices",
    "sha256": "cd1a026e620c31440c19caf13ae6d416e8bde55670472556f4320e0ec6e7efc7",
    "cachedAt": "2026-10-21T02:22:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1112/products",
    "sha256": "2f6f776eb09a52c2310906bf1ba708ee09ff52a62070c4549e313038b405d7dc",
    "cachedAt": "2026-10-21T02:22:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1112/prices",
    "sha256": "430747d87889b7803f3abb8323c2fc7e8e2c071aa68052113e1ada989b67bece",
    "cachedAt": "2026-10-21T02:22:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1110/products",
    "sha256": "b82384090614048a77c726dee5a00b0862cc12d4430b5485484d0a380252e0dd",
    "cachedAt": "2026-10-21T02:22:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1110/prices",
    "sha256": "4c4fe48d93a385986aab3c81f88792364f5a5560a0b18695fda143b676ec3a75",
    "cachedAt": "2026-10-21T02:22:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1288/products",
    "sha256": "6d94db192a0428b2625a3d4bb6f99067f20f0fd38eb1b3d50b2bb697ea74422f",
    "cachedAt": "2026-10-21T02:22:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1288/prices",
    "sha256": "bc71c420fc03531a427b99b595cdf08425a600b862d9d253b0e76f8f35ba4bdc",
    "cachedAt": "2026-10-21T02:22:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/572/products",
    "sha256": "bef5da02ae2d8ccf90b573c77810ecfaff05b6fb13c2e9370e08559032c8a35d",
    "cachedAt": "2026-10-21T02:22:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/572/prices",
    "sha256": "07be44fe2bee4bca1a651893f4f84f1c11d650c049366586efa6c2734ad99c75",
    "cachedAt": "2026-10-21T02:22:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1281/products",
    "sha256": "b01a13559e54c7e05dfb26f9913a673b0af583e618f27ba6dc209db1269b672d",
    "cachedAt": "2026-10-21T02:22:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1281/prices",
    "sha256": "fba7ae3d32ffc03c03e95bebf663483ee4e3644bf8a271a7a980f5faaae8134b",
    "cachedAt": "2026-10-21T02:22:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/590/products",
    "sha256": "9e0b842e4c3d247f483a10de2dcf427103f7eb5a1080280c676caf8521e09b7f",
    "cachedAt": "2026-10-21T02:22:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/590/prices",
    "sha256": "7eb8884c1d6606b94b369b4bceef5ea324b94b12f5a54403e1447be0d1edc8e5",
    "cachedAt": "2026-10-21T02:22:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/576/products",
    "sha256": "87a93675873a7c75a9aa18f0f07e82c153492c0151f1f8fa3571f1e3915acdd3",
    "cachedAt": "2026-10-21T02:23:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/576/prices",
    "sha256": "a06deb43fa17f002cbb36ef6fed6c32da6b1c2993c29c35f43b694a5ecb3644b",
    "cachedAt": "2026-10-21T02:23:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/577/products",
    "sha256": "89c5f8f39fa8ff062fa7bda04024b0b0ab18cb1e58831ca97f84b1ce8a337343",
    "cachedAt": "2026-10-21T02:23:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/577/prices",
    "sha256": "747acafe886e6ffe8ad2b702d9f11b9a9204376742b9d8be4296cd28ae8847e4",
    "cachedAt": "2026-10-21T02:23:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1287/products",
    "sha256": "51d2b31eb8cf03c5db39e709c335a33c4036c0bb48cee213c6f8e894925e7be0",
    "cachedAt": "2026-10-21T02:23:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1287/prices",
    "sha256": "5f005ced5ed2e084eccf8b71184b0c89c3d9fa502e920246dd9eed9a87f1e6c3",
    "cachedAt": "2026-10-21T02:23:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/573/products",
    "sha256": "6d4f465077740b0d975e8e574be5bc5f180e288a54ce4f46ccda0427a45ad9e6",
    "cachedAt": "2026-10-21T02:23:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/573/prices",
    "sha256": "e3b6f2d41b0e63eb76d925d26fba573dac45eb8f79537e58658029b04a058464",
    "cachedAt": "2026-10-21T02:23:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/574/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/574/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/591/products",
    "sha256": "22b4560af24ac1a1b970b9ef2b172dce7330ee8677e349ba0e888cd42643c7e2",
    "cachedAt": "2026-10-21T02:23:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/591/prices",
    "sha256": "1e012fc90ef9f21a2105b3d3e773430e47cc58448dd918935de09f45b00c31db",
    "cachedAt": "2026-10-21T02:23:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/584/products",
    "sha256": "596ada465f689e7cfcb8db373c6e9093dd8d1ede279892288e56b77d13c574e3",
    "cachedAt": "2026-10-21T02:23:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/584/prices",
    "sha256": "f87bbb8c3d3ccfb755a692fc3cc08b5fbe864533eb99ebe17e2fe4fdcb3b3f4a",
    "cachedAt": "2026-10-21T02:23:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1333/products",
    "sha256": "c77d3006cf193d9a2a98764faf792b7c70a5d181b117776f9e1b434fc93321d3",
    "cachedAt": "2026-10-21T02:23:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1333/prices",
    "sha256": "1563a6caffd1e5e0632e4cde6dadd6375d145c13a665ba7938923d0f24a10104",
    "cachedAt": "2026-10-21T02:23:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/587/products",
    "sha256": "34404d96eec3a9608dd4a0ad518bb6544597a6fb1c357eb31a8568d51fd0b5e7",
    "cachedAt": "2026-10-21T02:23:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/587/prices",
    "sha256": "0d835bd006057b69bdf2313defe6d99e649b95884164384a7b0d08da2ea5747c",
    "cachedAt": "2026-10-21T02:23:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/588/products",
    "sha256": "9a9fda7d3c717878223dc9b05b5b02cc53e9261fdd628f06086697098065335e",
    "cachedAt": "2026-10-21T02:23:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/588/prices",
    "sha256": "6fda435ddf9452b23789a5a83e235153b407b4aaeb70be06cb2696343096b2c2",
    "cachedAt": "2026-10-21T02:23:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/571/products",
    "sha256": "ca7320402adc7ca67be150474f4f5d29b6ba6382569b91bde67acaa1205d5a3a",
    "cachedAt": "2026-10-21T02:23:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/571/prices",
    "sha256": "a58a40d9af09cf6ed7cee94c19c70393a4afe482274b426c70c9b3d2ac9bb688",
    "cachedAt": "2026-10-21T02:23:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/581/products",
    "sha256": "d9981faeff420a1c869d711615fe1a15b152b99d68f06ad3c97edb738a440ad4",
    "cachedAt": "2026-10-21T02:23:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/581/prices",
    "sha256": "fb7317a328fd8e2568dba1d0260c192b8f81214b319a4bc8783396241cfab82c",
    "cachedAt": "2026-10-21T02:23:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/592/products",
    "sha256": "bace0b591c8a3498b09d748cdbc6528f0c58d24a8a24a9c74ec942d4652fb8a0",
    "cachedAt": "2026-10-21T02:23:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/592/prices",
    "sha256": "c4a86923e81ee50b6af6e73bee3e59f757cb6ebcee6d8c5622303bf71314178c",
    "cachedAt": "2026-10-21T02:23:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/586/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/586/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/580/products",
    "sha256": "617d3d2b04cfaba6fd7f5a2d233b58f7770cb3da88e6930763eabdd3b5b3c268",
    "cachedAt": "2026-10-21T02:23:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/580/prices",
    "sha256": "3647e75155f1946cfaa00c3e3d1ac36d80e2c31a3c5eac369c81a5691cb854c4",
    "cachedAt": "2026-10-21T02:23:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/600/products",
    "sha256": "3801cbb96723ba3f8b283ce0131aff24d5377d6374a4869151d129f03ddc2107",
    "cachedAt": "2026-10-21T02:23:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/600/prices",
    "sha256": "fa47a3e0c379eadaefb7ba45e2c75e219812589372c38d452b2074797ec2a253",
    "cachedAt": "2026-10-21T02:23:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/593/products",
    "sha256": "ff08f759125523b5c60d99872ebed9264759d9f60ed7343517f7e9795fefd597",
    "cachedAt": "2026-10-21T02:23:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/593/prices",
    "sha256": "f8fd18679b8ac1fea854b6e37d516d36e80a75c093a4a01d82205b4b308d9d5a",
    "cachedAt": "2026-10-21T02:23:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1340/products",
    "sha256": "24ed234e6b23d1af8690cd981f1fa96520f990696b1af9a69d354f6ef886230d",
    "cachedAt": "2026-10-21T02:23:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1340/prices",
    "sha256": "a338b282475ea9539f5adcb48396b2277cd3b21e3e1c0a6c8ec37d682c1766a2",
    "cachedAt": "2026-10-21T02:23:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/575/products",
    "sha256": "e88ff2b7d79e677e412885b97767cb8f48d25bf6d5b55d2f67c90ec11ab2c692",
    "cachedAt": "2026-10-21T02:23:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/575/prices",
    "sha256": "cb2507b20830fe60d5f648692a8c45c806532cad609b6b02a0d75fa064fdf555",
    "cachedAt": "2026-10-21T02:23:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/578/products",
    "sha256": "5f68f38b4034d68545ca43846200467e4ad36746f4d2da19c7d16b860fd0a5eb",
    "cachedAt": "2026-10-21T02:23:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/578/prices",
    "sha256": "f032354afcb2bdb463131c7b914a2e96ec239dd3c4a292f364cf92d22587790d",
    "cachedAt": "2026-10-21T02:23:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/589/products",
    "sha256": "d5d87dfec094432b4ed8aaa9fe6cdde0a55a60140cc222fbc8470af8bea7d3e7",
    "cachedAt": "2026-10-21T02:23:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/589/prices",
    "sha256": "efd236df703c01e5d7ebd1832fe6e2760c619bd82968d7747709d883498c7adc",
    "cachedAt": "2026-10-21T02:23:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/137/products",
    "sha256": "f07fe94ea878db51912b0a636cc6938ace2ef9f7543bcbcdeed3052ee9b72ed2",
    "cachedAt": "2026-10-21T02:23:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/137/prices",
    "sha256": "25890104ea5a4bc6af06a8f7e6dc0baeffa1d3a8aedc047fdc4df6ef614b4b3c",
    "cachedAt": "2026-10-21T02:23:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/269/products",
    "sha256": "a304529ca3983465ac46fc78db8a2d2a49eebf1a78885645b9afd13e80cde9cd",
    "cachedAt": "2026-10-21T02:23:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/269/prices",
    "sha256": "b490a729f9272dde37557444a198bd6fc7c3fd209092ebd5b896aca5475ba587",
    "cachedAt": "2026-10-21T02:23:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1332/products",
    "sha256": "293c4098d21e6d0489b0151c0c937bfc1981c64e0ce214e8b903720737d36da2",
    "cachedAt": "2026-10-21T02:23:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1332/prices",
    "sha256": "443206c4673654d6d9ece03f368f6fd08b3813c6b56bc8ec4029d26f1d077420",
    "cachedAt": "2026-10-21T02:23:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/316/products",
    "sha256": "e50ca2ac9b0a950dbf063058e44a2605df38d9c8e7e651a70cdc14dc83f16748",
    "cachedAt": "2026-10-21T02:23:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/316/prices",
    "sha256": "0ed9fe8b6527b394d73bf26bf1e764d93a999cfe7b0d7a620561b9e48baa0bb6",
    "cachedAt": "2026-10-21T02:23:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/257/products",
    "sha256": "940e472a72b8c758163327358738d4871903ccc5f070bef60e49fcf8f73c4b5c",
    "cachedAt": "2026-10-21T02:23:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/257/prices",
    "sha256": "15660ebaab30af0862ec7af7de700779245b203444a219622a2e56ea27d55494",
    "cachedAt": "2026-10-21T02:23:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/585/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/585/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/595/products",
    "sha256": "829ec1d2f090e596d95d4aa63c63b2112f6683033f8fcce546d8dd7ce1bf5de6",
    "cachedAt": "2026-10-21T02:23:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/595/prices",
    "sha256": "609d022ab48423c705c435a25ce46d0c4b7352b4a7b268be143803579b89393a",
    "cachedAt": "2026-10-21T02:23:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/228/products",
    "sha256": "045ee16b396af6e090ddc126bb9578ffc6d146ea0be6473807237e03d35fee5d",
    "cachedAt": "2026-10-21T02:23:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/228/prices",
    "sha256": "6e7b0fab6e80ff3da1b298dc5267558e2a76e13e9b7bdda94134b8011b3031cf",
    "cachedAt": "2026-10-21T02:23:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/229/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/229/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/276/products",
    "sha256": "7687d455e793e04004288a7f0649fa7af16b9ad936bb8dff0b9e283ab05eb502",
    "cachedAt": "2026-10-21T02:23:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/276/prices",
    "sha256": "5ebdc57dc1db5a54202739fa4001125db0c9329f998d4d3f5d5f0a60432e9b03",
    "cachedAt": "2026-10-21T02:23:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/261/products",
    "sha256": "402926d8eb665b2c00ab14b7264283d40f76b3930fdc0f62d2cd6c7f87e3909a",
    "cachedAt": "2026-10-21T02:23:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/261/prices",
    "sha256": "1718fc9d3979d72aee8ecdfaae8bbd0546801f8f993176f34722fc02e7129f11",
    "cachedAt": "2026-10-21T02:23:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2373/products",
    "sha256": "54b486fd9707f52342640ad99994d867aef34c48803c1538e28a4874ef8fab40",
    "cachedAt": "2026-10-21T02:23:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2373/prices",
    "sha256": "c2e28e01c19ddca229799fa1a80a64c1f9be741337fb7d9e35c45934e318b56d",
    "cachedAt": "2026-10-21T02:23:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/318/products",
    "sha256": "768b73c773d9481cab87fed224c1d6180341663dcbb910d6d87e7f89fd0fcdd1",
    "cachedAt": "2026-10-21T02:23:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/318/prices",
    "sha256": "77bc28cefac14586b237941e19f0a1054f666c692653c0c49d0498ef60d2ebef",
    "cachedAt": "2026-10-21T02:23:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2937/products",
    "sha256": "0063445679ada880958059b06389b5a8b9bb99a65fb2ff43044496d6d749acd4",
    "cachedAt": "2026-10-21T02:23:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2937/prices",
    "sha256": "6803d782b3fe96562a0528465e10f72a5b9cb55b4925fc76f5ed7341d939fe7c",
    "cachedAt": "2026-10-21T02:23:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/135/products",
    "sha256": "dbca5ac6a6074cabb5a1bdb9bbacedc8491dbdb59c33d5d711b5cae1304c26d8",
    "cachedAt": "2026-10-21T02:23:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/135/prices",
    "sha256": "8289fa4bff54332dffab0b0c9962e00ed9f017fd7f0dff8d07f83f874cea7c1d",
    "cachedAt": "2026-10-21T02:23:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/209/products",
    "sha256": "e0c6bf3a5ac1e043f38e9f008c27b276a6eb7d90e03fb2fd999a3f9637a83188",
    "cachedAt": "2026-10-21T02:23:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/209/prices",
    "sha256": "ef9ee6f896f9c99c351572d7b92fdef93e2079c13a6ec68f5dca2c5ba5352338",
    "cachedAt": "2026-10-21T02:23:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/579/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/579/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1929/products",
    "sha256": "b844bb10318ead1bce93ba782ab70335c3dec20c69a6867af09e22e65d47a28b",
    "cachedAt": "2026-10-21T02:23:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1929/prices",
    "sha256": "16c4b42d14f124e8594970646b5a1315dc52ad215d382f54ffb8db1654479639",
    "cachedAt": "2026-10-21T02:23:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/596/products",
    "sha256": "5408e70146d43a82415ad8837701baa93b84114604473244acfdc0d86d436bab",
    "cachedAt": "2026-10-21T02:23:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/596/prices",
    "sha256": "2cc4ee6860ba4252fc8598005a78c98b581ff2b80ea64ae2fcd60ebadc12bd03",
    "cachedAt": "2026-10-21T02:23:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/231/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/231/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/300/products",
    "sha256": "07e801725c88d365818f73c561a7107987a05cf3df529f70f832d08abedb04d6",
    "cachedAt": "2026-10-21T02:23:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/300/prices",
    "sha256": "5b1b33716df2d6a657417f824f3df4e7ea53f1a139ac4e1fd1e4bda9724c8759",
    "cachedAt": "2026-10-21T02:23:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/352/products",
    "sha256": "5a46d2a6f386ccc74d7b0a3bc1fbb18b47e3a746d0d8e259229f8b09ddaf745e",
    "cachedAt": "2026-10-21T02:23:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/352/prices",
    "sha256": "a4cbc5151765609aabf66bd6c0ac493f210b26f8536360253c5f6a764db3f408",
    "cachedAt": "2026-10-21T02:23:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/217/products",
    "sha256": "cbd01ee185df0d1c55ec3b6a084be9090b3effcef5c73fa57c997fbbd1245ed4",
    "cachedAt": "2026-10-21T02:23:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/217/prices",
    "sha256": "d37105b37cdcdaaa93323ad74c637643543aa5bbe242f462906cbadda398303c",
    "cachedAt": "2026-10-21T02:23:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/319/products",
    "sha256": "0e3e70491dc2a97ef2298af299b4963f7c7da406f92eaceb367648df17c72389",
    "cachedAt": "2026-10-21T02:23:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/319/prices",
    "sha256": "4f2ecbd93da8a2e8989b5c47759cd4d12d9f9d15224e5db223fb88377c7ad412",
    "cachedAt": "2026-10-21T02:23:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/186/products",
    "sha256": "543c0f20f9d53414d311abf5eb415df1abd8c6635b17f09970d77c2e8b9b91ef",
    "cachedAt": "2026-10-21T02:23:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/186/prices",
    "sha256": "09f2c404e275643ddef4d0f9aa49be9a8991f7252371a75dc8e4e39d1fed257b",
    "cachedAt": "2026-10-21T02:23:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1331/products",
    "sha256": "043e1e7f5c26cd9297f77b095c173933578ca6f61cf10a09b20f482fee47882f",
    "cachedAt": "2026-10-21T02:23:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1331/prices",
    "sha256": "9c3640797107f6422f21abe89af8e0ae7c86f13a8fa79b960a6cd5cfda00ab91",
    "cachedAt": "2026-10-21T02:23:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/203/products",
    "sha256": "bf0fe63e186991ea66049ccb0c496930cbf81f6f092d6f07576e51c0d49a2d1f",
    "cachedAt": "2026-10-21T02:23:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/203/prices",
    "sha256": "dad7b5c5ce8793dcb520508edf6025b1d02d3edb5c3e506701cc710f9f9298e6",
    "cachedAt": "2026-10-21T02:23:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1363/products",
    "sha256": "ced82e7d48f0d8593906ee55c32252ea2dd432d20e8dc4f4c080babe13103e14",
    "cachedAt": "2026-10-21T02:23:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1363/prices",
    "sha256": "888d0c86c34d6e9bda49b46bcc27496b4ece60d627a6eab5ec399e6a89eedeb1",
    "cachedAt": "2026-10-21T02:23:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/227/products",
    "sha256": "ab9e2243d05ab7379363caa6cd5c8c82d1d9e6148caa089e6d6781ae6b76e455",
    "cachedAt": "2026-10-21T02:23:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/227/prices",
    "sha256": "c60143095202c9983cbe9e64e18c233b432d87d6f1128716404192fc46ef58bd",
    "cachedAt": "2026-10-21T02:23:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/594/products",
    "sha256": "e6462c75cc05e0ddcb5159fe379264a45dc8e595198857013b6bf83b2a61e532",
    "cachedAt": "2026-10-21T02:23:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/594/prices",
    "sha256": "12e75174707bd88c3a388ad25700ec7cad42a75f1fdf25f21f66d08c402b9b6e",
    "cachedAt": "2026-10-21T02:23:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/136/products",
    "sha256": "4d9db346862d0f58d3b422bbc16b40761659bf31da454f0fa265ceec933ac823",
    "cachedAt": "2026-10-21T02:23:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/136/prices",
    "sha256": "805b66498fa9e6ca240960b8d6c225bb9c2fe1a456dd3e9e4be50ce615917c9f",
    "cachedAt": "2026-10-21T02:23:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/303/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/303/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/317/products",
    "sha256": "3cdd83f9a92113d31a5c8500243360aa6b86bb92587285190799eb91859ef126",
    "cachedAt": "2026-10-21T02:23:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/317/prices",
    "sha256": "d13f639a4d2856678cc504af4e02f0c29ba951fff603cdeb2081069bfd585652",
    "cachedAt": "2026-10-21T02:23:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/147/products",
    "sha256": "7b8fa4b49ea453bae54789e3a90193fd48231d65386571d0595457acc0776437",
    "cachedAt": "2026-10-21T02:23:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/147/prices",
    "sha256": "a0f2e024c18c7da6f9ea58458c9f4af61a4759f3c6e7504b6dcdeaa7c0ceaacb",
    "cachedAt": "2026-10-21T02:23:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1474/products",
    "sha256": "e0ee5f2b783f8c20aa464bcd7118601ee6196e778cb9cdf13d6c3d31de420d21",
    "cachedAt": "2026-10-21T02:23:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1474/prices",
    "sha256": "75b1f7ab631186bfeeb7045d11d906acd1a1ad2c51b9e6502938a3abbabd7e9b",
    "cachedAt": "2026-10-21T02:23:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/302/products",
    "sha256": "b7131d8891d15e2991082f4f691c1a54d6467c379b873bfd0586f0c7da3ca648",
    "cachedAt": "2026-10-21T02:23:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/302/prices",
    "sha256": "ee62f276d59093df5c51df8b8f008e35e0c922ad4947945793722fcd73e4f7c8",
    "cachedAt": "2026-10-21T02:23:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1330/products",
    "sha256": "c7660557d3226387ea39a9c33a25ffa50378c220170c85fcca7cb181d44eb2f1",
    "cachedAt": "2026-10-21T02:23:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1330/prices",
    "sha256": "accf8b6a0b22da2a0fc42ea09f6241d9857a9d7e86e250754c4bb14b1fd3a615",
    "cachedAt": "2026-10-21T02:23:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/185/products",
    "sha256": "0fcb76804d15423be21e17be3beeaf4da9d02971b220b6a0b15b8b2aaf380dd2",
    "cachedAt": "2026-10-21T02:23:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/185/prices",
    "sha256": "1816dd943d34f06922cb137b297e0f271896d36aa02422d3bbe53293dd3618c9",
    "cachedAt": "2026-10-21T02:23:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/226/products",
    "sha256": "88a65f1a6f55e15b5b80b882f654d9ab9039eb2f9390393be56187a721e40435",
    "cachedAt": "2026-10-21T02:23:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/226/prices",
    "sha256": "fb1744ea7f946f3411452c3d136cd33c8e42dc4f0dd5b29ddbb7ef90a782e51a",
    "cachedAt": "2026-10-21T02:23:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1320/products",
    "sha256": "ad4c52820ad67acf0fcd16fcfee4a026a89f857b20fa0fed8ab0ae38bc751a62",
    "cachedAt": "2026-10-21T02:23:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1320/prices",
    "sha256": "2447eecd4f38755de74d48d9fef889f0fe96833727d766a18ee6f1045b3b48a2",
    "cachedAt": "2026-10-21T02:23:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/290/products",
    "sha256": "54b533f9f03cad5b044c94d6eaa72a88058e0b876eaf78f05f7d43aea8e5d6ad",
    "cachedAt": "2026-10-21T02:23:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/290/prices",
    "sha256": "2426074b95fb3eaae846b76ae430f2a1bbfca47c74f337a53a6f1e8e870c77aa",
    "cachedAt": "2026-10-21T02:23:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/342/products",
    "sha256": "92a308f7d99f4c9234e0731046d48afe83586e504370991337454482d25654f5",
    "cachedAt": "2026-10-21T02:23:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/342/prices",
    "sha256": "690c7210e059e05897360ff96c75f8448d9245ab55a1255ece1e7d8a1e1b212f",
    "cachedAt": "2026-10-21T02:23:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/321/products",
    "sha256": "3302dc34b03da1c81492d44a71a076d3018f27954330335fdeff70ae21edeaf6",
    "cachedAt": "2026-10-21T02:23:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/321/prices",
    "sha256": "43d1b93da55833e09ec7d22bf41f9d5881f850a4f2785e3076d92b7c75e0dcf0",
    "cachedAt": "2026-10-21T02:23:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1290/products",
    "sha256": "50b6b8646489e0966413d5d9a6a2248468e6e6ad0e02079ca8e572819592f8ab",
    "cachedAt": "2026-10-21T02:23:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1290/prices",
    "sha256": "8e41d2864f5e45b240f91c54f4403e4621468d09db4fc8bf4ef33ff7a392fbb4",
    "cachedAt": "2026-10-21T02:23:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1329/products",
    "sha256": "edb4dfe183b27e0322906cb5181777c96eabc9e3167a94bce381f298e0a07e9e",
    "cachedAt": "2026-10-21T02:23:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1329/prices",
    "sha256": "bf7aee13f54ba8b3cd5875d2286b5e5c4486ef2e1eb31f33060dd18183f0f9bd",
    "cachedAt": "2026-10-21T02:23:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/133/products",
    "sha256": "dbde4d2bd73abe1f8b8cf4914d42865ddf67c54d382229cbd9105f7cd761da97",
    "cachedAt": "2026-10-21T02:23:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/133/prices",
    "sha256": "13c7429855221a235734b6f6528dcdc9602db765365d7c41ed50e749f7b18303",
    "cachedAt": "2026-10-21T02:23:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2227/products",
    "sha256": "2695503d6a5d590392b18c421b5636fecd32245b656d8efe42649f636db650bb",
    "cachedAt": "2026-10-21T02:23:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2227/prices",
    "sha256": "91737de4d7a0b1a53eb0c2276e36a7c593c2368ab45d61c814494cc5e112a5b8",
    "cachedAt": "2026-10-21T02:23:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/225/products",
    "sha256": "a2cc2a359e9abd8233f4f429f1793476f760cd3c6023d1e4708a3cc1fca00228",
    "cachedAt": "2026-10-21T02:23:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/225/prices",
    "sha256": "25df988bf7e7f0d7130727c0bf562e7149c919fb43b89f21cd8327db462f038a",
    "cachedAt": "2026-10-21T02:23:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/597/products",
    "sha256": "4ec67435e2991380436147cdbad67861c8b57825049bdc640527facd17d52335",
    "cachedAt": "2026-10-21T02:23:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/597/prices",
    "sha256": "af01a076276fc315dec8d994cbb9b43893511d67bdf1aaa558a36229095fd4f3",
    "cachedAt": "2026-10-21T02:23:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/216/products",
    "sha256": "f3ec23e47125329e2cb1e89b6b034a4b7dded7a597c709814d4344d6a3d926bd",
    "cachedAt": "2026-10-21T02:23:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/216/prices",
    "sha256": "30614228eb9137d354b641ae39fd9500f16790a4aa517ba8ee0506ec5de7f2c8",
    "cachedAt": "2026-10-21T02:23:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/301/products",
    "sha256": "b08d39ac7924b83a969788d2c541023446331318eee2b15fbf11e44ed9033743",
    "cachedAt": "2026-10-21T02:23:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/301/prices",
    "sha256": "375a7cc13d3107948939a94856d81d7ac99afe2dc142d0b676c8156dc092adf4",
    "cachedAt": "2026-10-21T02:23:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1328/products",
    "sha256": "d64758337bdecf628bc521dbb9d2fa2daa7ac941241826c79e07aee97e7da541",
    "cachedAt": "2026-10-21T02:23:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1328/prices",
    "sha256": "182bfcc54e105907cac109e97941f6b013ccf16e4a9ff0dee966cbc4855c61cc",
    "cachedAt": "2026-10-21T02:23:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1347/products",
    "sha256": "4fee8655cfc7214ac5e084be51d40de7587e149c4d41f602a19e66dfc65a9c33",
    "cachedAt": "2026-10-21T02:23:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1347/prices",
    "sha256": "ae0c6a1ab88fef0cef81a3ec108c59597a453ff3fba83be2ba17322480efba60",
    "cachedAt": "2026-10-21T02:23:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/332/products",
    "sha256": "268bdd300fb6cb787c310fb7589521793a323ce14fc62341063ff0f7fcb6c7c1",
    "cachedAt": "2026-10-21T02:23:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/332/prices",
    "sha256": "fc35994d79dafdb766f81e0a11d8097d3ff3137f3655313692f39ac4da85c266",
    "cachedAt": "2026-10-21T02:23:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/198/products",
    "sha256": "4b311e6946adece34a4545007127db5f78e263189491a98bbc5327362e6930fd",
    "cachedAt": "2026-10-21T02:23:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/198/prices",
    "sha256": "13f581887bc451a7714158a6b82edeb4ca8abe20f9088127d999081f30bb1bd1",
    "cachedAt": "2026-10-21T02:23:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/199/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/199/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/197/products",
    "sha256": "8cb07a487de5cbb6a9c76c75a3e0920715cb938b5852ca2fc03f70abcb70ccba",
    "cachedAt": "2026-10-21T02:23:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/197/prices",
    "sha256": "ffdcef5bbff0c36c2eb6970136c26de708e89dc8a426fb050f26b596cbb4c43b",
    "cachedAt": "2026-10-21T02:23:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/134/products",
    "sha256": "7cfed5830848e7965fcd2668575ea30d701233555b94c55ad8d34eb46eeaadd0",
    "cachedAt": "2026-10-21T02:23:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/134/prices",
    "sha256": "3ca3cc577fd3085b34d6eb99bcb87f7e908c3f9efc9e68aff778d07230fcfc66",
    "cachedAt": "2026-10-21T02:23:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/320/products",
    "sha256": "7bb9e3016e807860ac547ee0640e8d3026b73897047b05cb7e0d60a1fc90d430",
    "cachedAt": "2026-10-21T02:23:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/320/prices",
    "sha256": "7c908a9ad3a0f292f85e1b4627f9b390b687ca68485bcdb89e8bd1a9c02a4f7e",
    "cachedAt": "2026-10-21T02:23:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/141/products",
    "sha256": "d8c6d0d313f6c8926b95d950297a221c9f7c7ece2bc81099a3d89e8a5cbef976",
    "cachedAt": "2026-10-21T02:23:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/141/prices",
    "sha256": "f4f5b1e8b8bd85957db0d7525c5c59164789e15d967f2fe9e21153a50ce76af3",
    "cachedAt": "2026-10-21T02:23:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/142/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/142/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:23:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1327/products",
    "sha256": "d06ca566203b7055382cd7b3ddbaff0f26cffeff1b006df0c044cd8c9d777a68",
    "cachedAt": "2026-10-21T02:23:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1327/prices",
    "sha256": "abc46830bc6a4f46d66b471b47a079111706b12651244fba4dbe619ebd0a4c5b",
    "cachedAt": "2026-10-21T02:24:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/189/products",
    "sha256": "10da0b18851a5ae5e2428db7e908dc90dabe42cef85bc8a3baed3afa6db28d5e",
    "cachedAt": "2026-10-21T02:24:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/189/prices",
    "sha256": "2ed8232d7fdf5111f53bcb00c23d3131d9286d7236a496705407930ade17d9ba",
    "cachedAt": "2026-10-21T02:24:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/598/products",
    "sha256": "a5a4dcb50cab8293abdcd985b71ebe109dd80d84c4d8a0a5ccbef8c7121599f7",
    "cachedAt": "2026-10-21T02:24:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/598/prices",
    "sha256": "93b87c4f6a1947f35f1676e92b58fad4b5d244a9dbcb21d9d6b0d589f5feabb3",
    "cachedAt": "2026-10-21T02:24:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1285/products",
    "sha256": "566a92757166dec722b73dff22411a546cf4dbf47676da678c4d8ca54f915a6d",
    "cachedAt": "2026-10-21T02:24:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1285/prices",
    "sha256": "764490d4f78943dddc698f706670c79398afb7880a0c708db0e1157f0eb737cd",
    "cachedAt": "2026-10-21T02:24:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1343/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:24:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1343/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:24:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/289/products",
    "sha256": "c5e05017e4a8e3f1c09f01c4a642faacc924349f5f7b2402eb72fbdc3cefc691",
    "cachedAt": "2026-10-21T02:24:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/289/prices",
    "sha256": "dd04210995f2ebec852d34f8f2407d79b63aec3a48a24d0eb47b815324b02db4",
    "cachedAt": "2026-10-21T02:24:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/353/products",
    "sha256": "f4b73d458f0095d36dd289fece3a6adf98b041d56ff3a499b981f867e70c9e53",
    "cachedAt": "2026-10-21T02:24:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/353/prices",
    "sha256": "ace8547884371f013ef7151f9cc6e9767c47331c6fcb7aa23509f5f0018f7c48",
    "cachedAt": "2026-10-21T02:24:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/224/products",
    "sha256": "285835ad0ad2de9f863caae6ed0e75c0800858c07d961e2952588ea107c23576",
    "cachedAt": "2026-10-21T02:24:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/224/prices",
    "sha256": "c3b33fbd462e2c6b1b06ae5c5d4503960373a65ddc4660be307aeb1b6909d1ca",
    "cachedAt": "2026-10-21T02:24:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/323/products",
    "sha256": "3fd7a4fb9239cbc21d4b54db463d97211ed67e6747ab6a467bb32f94d5624ebf",
    "cachedAt": "2026-10-21T02:24:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/323/prices",
    "sha256": "c5e00c21fd5950cd975444798f9d4a39154e62eed8a8aa7fa18729ca8056f001",
    "cachedAt": "2026-10-21T02:24:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/358/products",
    "sha256": "7d59be3fda0f4d7348428289ce5fc2f802993ea6b7456976a9bfdd86ddedb877",
    "cachedAt": "2026-10-21T02:24:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/358/prices",
    "sha256": "c8bcdf4541a27d12fbdd84936a5f104240a90dc572eb18993191a4bbba5efa65",
    "cachedAt": "2026-10-21T02:24:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/341/products",
    "sha256": "79c19a820c6ce3de25a25646eb8d6f751c57ffa86607a446dded38a414729fd2",
    "cachedAt": "2026-10-21T02:24:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/341/prices",
    "sha256": "00c5e6deca082a6a51e6a0e988ce42b26395377772b973d60df87e2ba21705ec",
    "cachedAt": "2026-10-21T02:24:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/144/products",
    "sha256": "2a969750e060277d8ff37ecf1401fb9de362487039de16996e06880220f9aad8",
    "cachedAt": "2026-10-21T02:24:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/144/prices",
    "sha256": "e2f980a96e6505f66705687936398a0638f86fd4250435f643de3acf48a744aa",
    "cachedAt": "2026-10-21T02:24:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/145/products",
    "sha256": "66250877232cd313de7d56d775346a1242d8c9cbe70434691deb3a7035c69983",
    "cachedAt": "2026-10-21T02:24:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/145/prices",
    "sha256": "1b33fd60d5696dc6cd123d43079777f063679a58ad0abf28cff8c4195d7bd0c8",
    "cachedAt": "2026-10-21T02:24:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/132/products",
    "sha256": "aa12d6d2ca1def46887710ae91c695e57f76cc9ae384d710519b0287b7cb82cd",
    "cachedAt": "2026-10-21T02:24:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/132/prices",
    "sha256": "7ca4a63a459efe76e41652397bc7bda7eeaa6601f91eb510426c87ff6d248ba9",
    "cachedAt": "2026-10-21T02:24:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1684/products",
    "sha256": "381d1d216dc7e7c85199805770886c9b9b4c1d04b48680d16ba1d76e6466c930",
    "cachedAt": "2026-10-21T02:24:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1684/prices",
    "sha256": "3acf683c2c0f92d665ddb27a33eff58f3d9bf3091b94164340a254d62876cf5f",
    "cachedAt": "2026-10-21T02:24:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1292/products",
    "sha256": "34168deb32c1af3553f6ddf626663d0d856f22b3ac9e56eabb6ca3d1c67ee422",
    "cachedAt": "2026-10-21T02:24:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1292/prices",
    "sha256": "98b7d427bf3a8fc8d67d9aaf914372605d3ebea849543baf859144120030fe8e",
    "cachedAt": "2026-10-21T02:24:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/184/products",
    "sha256": "7351c963d7f5295eb11a45491d19d07e4e27bb6d5da10a52c1a7eaa6dc5a4bc7",
    "cachedAt": "2026-10-21T02:24:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/184/prices",
    "sha256": "b0d7affb2af48108e6ad0fb8362f9a01ac68341778f0c3ff2e23b2af5983ee02",
    "cachedAt": "2026-10-21T02:24:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/179/products",
    "sha256": "49847db4be57bccfdce5d2ae170a9b00f4a59f2f40c7dea7dd11bded6213bf74",
    "cachedAt": "2026-10-21T02:24:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/179/prices",
    "sha256": "9e88f71994e59b575875d3130f825eecf9afad52d4b20512e7f30fa2277bda09",
    "cachedAt": "2026-10-21T02:24:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/140/products",
    "sha256": "572e9a92c02ad3c2654c736eb1500cd40d22c51d00eca50a7d5247357977f0ee",
    "cachedAt": "2026-10-21T02:24:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/140/prices",
    "sha256": "1b1396b044b4835e68dcc889e8fa1498f2684ab0979c772ecf53db66102a1bff",
    "cachedAt": "2026-10-21T02:24:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/288/products",
    "sha256": "6450681d65c825c443d2f21788348e7239b6d26f43c0f4dddd49564453bbfbed",
    "cachedAt": "2026-10-21T02:24:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/288/prices",
    "sha256": "850b650dcdf4b908d056cafc88019f316b91984a8f7c5be24d60d4299b1284b2",
    "cachedAt": "2026-10-21T02:24:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1337/products",
    "sha256": "cf176e36145d28cedbdf430081f0dd7dd5f494d734ddf71c6c9941b346225075",
    "cachedAt": "2026-10-21T02:24:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1337/prices",
    "sha256": "b856c4ecc94b959b0c097f7e4bda2c57f352f54b104d42026af07a5cc41ffc94",
    "cachedAt": "2026-10-21T02:24:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/270/products",
    "sha256": "69fb7107596dc8fb3d55afa51b105149f54db36d0def1f9eb97a24236371ec45",
    "cachedAt": "2026-10-21T02:24:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/270/prices",
    "sha256": "422c9e9b09800892245f6c38b37b5acccc2b3a31f97a1557586debdec7144942",
    "cachedAt": "2026-10-21T02:24:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/271/products",
    "sha256": "76d48927204ce99d6c7abb303435daa6e7111cfb6d3ed99bba3e1f44ef6bfac7",
    "cachedAt": "2026-10-21T02:24:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/271/prices",
    "sha256": "acb3c0b72dff55b3bdcd88f67d302cd6332a99f37ec5eaa55430cbbdf08e7d15",
    "cachedAt": "2026-10-21T02:24:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1315/products",
    "sha256": "47472ef1e8300dd5624d193558c1023f5f6f04ec17c99c4837a9036c5157449e",
    "cachedAt": "2026-10-21T02:24:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1315/prices",
    "sha256": "005951a497bf179da90828bf934a0149d0e7a36d8ab848630eaba9808eb791a5",
    "cachedAt": "2026-10-21T02:24:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/213/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:24:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/213/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:24:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/215/products",
    "sha256": "c2e85fcddbc9c435557d2340ba6b3277fbc0f13ff7a46f1d361fc1c0927efa19",
    "cachedAt": "2026-10-21T02:24:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/215/prices",
    "sha256": "fa33cb265aa5ba7ddc41a21f18eb2e99ae6576e2de64b29534bbd2b8a4cce686",
    "cachedAt": "2026-10-21T02:24:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/286/products",
    "sha256": "3f6456801b0da6d97a52879285dd2e6f015f7074b3d99419d76b33802c833871",
    "cachedAt": "2026-10-21T02:24:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/286/prices",
    "sha256": "cde4307f414c34052ebbb93d18efab22ac87c5e8d79023d1e4e38aeec8411836",
    "cachedAt": "2026-10-21T02:24:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22964/products",
    "sha256": "60844de4fd67cd5b855dd13198d831449df2b582715066e7ede72fad5673e267",
    "cachedAt": "2026-10-21T02:24:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22964/prices",
    "sha256": "5a0aa6d155058f355bddd5220be98fc55229e3fb1bcfddda40d388a15c15a9fb",
    "cachedAt": "2026-10-21T02:24:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/157/products",
    "sha256": "a90b0299f1093b213c82f5debb4b8b790155cfc7d261c72280563870e07e0d82",
    "cachedAt": "2026-10-21T02:24:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/157/prices",
    "sha256": "66e7ac386edd2fd937cee3b7c7ff3082fafd0a235e69fb92b5d2e41cca0183cd",
    "cachedAt": "2026-10-21T02:24:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1344/products",
    "sha256": "24f9e2a1a0e487275f559a4f68a537ee8a05fb9e2785f15adcb0e00e21554bc4",
    "cachedAt": "2026-10-21T02:24:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1344/prices",
    "sha256": "75618c3c2ea8a8b5975c58b491a81b02251824fef4b7b0effc51dc68b0e94b9c",
    "cachedAt": "2026-10-21T02:24:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/188/products",
    "sha256": "f1df1ab992284ccbb082d15b1dbd8a4ddf0071240ff406dae01a6f8c7e967579",
    "cachedAt": "2026-10-21T02:24:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/188/prices",
    "sha256": "50f275c8f769172256257110058d1625eaafffd181ef9871b2a843080b941fb4",
    "cachedAt": "2026-10-21T02:24:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/156/products",
    "sha256": "cdbd7d2832791fe3e9453a5bfcb87324141234f9ca59d1adf56db378037e0f65",
    "cachedAt": "2026-10-21T02:24:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/156/prices",
    "sha256": "89f87ad1e375ab41d4b6735f9d63d379eeff6393bd02eafc51fd44b2fdcc3dcb",
    "cachedAt": "2026-10-21T02:24:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1304/products",
    "sha256": "76c5f141eae30fae52a45d991ee75e6ba0741c3bab0283fc4635314cfda64109",
    "cachedAt": "2026-10-21T02:24:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1304/prices",
    "sha256": "549d913a307094b7daba2bc43abe11803c33c5c1c7c4fd90816fb3d7adb5c88d",
    "cachedAt": "2026-10-21T02:24:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/167/products",
    "sha256": "bcfba9a41bddd8194152a0bf50b14ebc15553aca45873dd0908a675e914a474e",
    "cachedAt": "2026-10-21T02:24:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/167/prices",
    "sha256": "2194b38935a68f3435b3e42eaef783ecedf299b5f9f3b9d5c704b660e75b4f49",
    "cachedAt": "2026-10-21T02:24:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/168/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:24:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/168/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:24:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/158/products",
    "sha256": "e589b049f8bbeb7cad36f83cf2b5c978e615b7cfe755df8819e66c70f7133321",
    "cachedAt": "2026-10-21T02:24:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/158/prices",
    "sha256": "1a4c97c2301030702907f46ff7674183de2db9bb1c801cfddf4901e3518fd802",
    "cachedAt": "2026-10-21T02:24:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/324/products",
    "sha256": "f2f96409d76095e416498d55542c2fb9cb6714218949c6323680578658a2460c",
    "cachedAt": "2026-10-21T02:24:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/324/prices",
    "sha256": "88a7023b20b989031b859f932932fa76d257996633665cc60a4e46190a62aa39",
    "cachedAt": "2026-10-21T02:24:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/328/products",
    "sha256": "243c28ee17ded1b7a5d1e910342cdb099f27be29deec813e81b4ea0ac856195e",
    "cachedAt": "2026-10-21T02:24:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/328/prices",
    "sha256": "47002c824fd5d7d8515ea1535f69ac0488f1a30cbcc4bd4a710a88450e3ecbb3",
    "cachedAt": "2026-10-21T02:24:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/155/products",
    "sha256": "dab07833efe4089daf691beeb509668adbe767295a09ba11a79a3c96a61258f9",
    "cachedAt": "2026-10-21T02:24:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/155/prices",
    "sha256": "35930418df55ce8aef9482939c781cb504ae3705fe7dde210268b1a243c8fb1b",
    "cachedAt": "2026-10-21T02:24:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/131/products",
    "sha256": "2fb2ae29174ac5cb31260255998dede69452e017e7b575594337ff792e2f4740",
    "cachedAt": "2026-10-21T02:24:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/131/prices",
    "sha256": "9885b1c6701c8e7715dc216ea0b684d53612d83e1e4aec05adacb404278966d4",
    "cachedAt": "2026-10-21T02:24:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/138/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:24:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/138/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:24:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/139/products",
    "sha256": "8be35e30a7b92f2a22faa7e792e93896187f2c476b78b07fc51a9af988d79441",
    "cachedAt": "2026-10-21T02:24:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/139/prices",
    "sha256": "127127aa26550848ec7de0eaa9039b7122d4c88f114fe1d64e68ad33cb4601d5",
    "cachedAt": "2026-10-21T02:24:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/360/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:24:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/360/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:24:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/267/products",
    "sha256": "c7e15ef106b4106ca30cc49ac73bc191b1009642fcde0af3a07622931e3482f4",
    "cachedAt": "2026-10-21T02:24:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/267/prices",
    "sha256": "90070f175c12eabef02a246b282e0ab1f720c424ebec48e01be55a258cc85052",
    "cachedAt": "2026-10-21T02:24:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1325/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:24:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1325/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:24:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1291/products",
    "sha256": "4a7a0f28ffecb5b4e4b09031a754aaad13c1dab8fc312cdfd36d13ac59d7c799",
    "cachedAt": "2026-10-21T02:24:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1291/prices",
    "sha256": "74b6f8165ed44107863496e37b65a1d91bf9a63bc9ac20eff93a3f50cee4de4c",
    "cachedAt": "2026-10-21T02:24:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/583/products",
    "sha256": "ca647d0af015755308b08e2ee2ae48b5eda00203a82dfbbc70f8d7f1dace2db1",
    "cachedAt": "2026-10-21T02:24:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/583/prices",
    "sha256": "ab974736e5cbb308ad8d7dc379f2fa6971f8e681dfd40af6c37ee31534b023d9",
    "cachedAt": "2026-10-21T02:24:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/154/products",
    "sha256": "1fa36cc5b847b2b29ba9845d98736ddd57c9a95f2e8ff45e8abb53e06cbc7531",
    "cachedAt": "2026-10-21T02:24:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/154/prices",
    "sha256": "838d1f0b6f9429cb3f2cd18dcb37cc84f735e168968a2f470d69732f2626a848",
    "cachedAt": "2026-10-21T02:24:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/214/products",
    "sha256": "5dddeb1ff9fb9978de70250542cd16874202c54744ae48c5244ac823c479f7ef",
    "cachedAt": "2026-10-21T02:24:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/214/prices",
    "sha256": "f7a7634c07f942f314cc6cf4d69d499af56590758a4c3421ab9a3d1a0000b806",
    "cachedAt": "2026-10-21T02:24:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/322/products",
    "sha256": "d80084a932d67a6bae722f295227747f43ac3c2cc7fe646c504525e749460105",
    "cachedAt": "2026-10-21T02:24:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/322/prices",
    "sha256": "3b79043679984954593b070cab00becc572cfa1b4708ca4205b98ae4faa71a3d",
    "cachedAt": "2026-10-21T02:24:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/192/products",
    "sha256": "058ffe54bd44eae826ad9fe320ff4744643a20e9ad36e17ed9284c0b3a4e7a93",
    "cachedAt": "2026-10-21T02:24:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/192/prices",
    "sha256": "71460e9f6c9ab6559772957f08c484cc86de37624317149869cc194c4453497c",
    "cachedAt": "2026-10-21T02:24:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/247/products",
    "sha256": "172f81cecb559213e29574c9e1a521893c1f771029de34f027e4494bfd7c6b98",
    "cachedAt": "2026-10-21T02:24:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/247/prices",
    "sha256": "c08a1115fef6bd82f63801df97e477053e085146f4b3b3cac8ce4b945fd949ea",
    "cachedAt": "2026-10-21T02:24:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/258/products",
    "sha256": "d4bd27d5d78ec01294dd73fa7e806904bae549a810289a57afeeef6d597dfe03",
    "cachedAt": "2026-10-21T02:24:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/258/prices",
    "sha256": "ad7c3d57eb7e059258456d301fcfc77d0a6b6974df3dc07fa121bcdaac494807",
    "cachedAt": "2026-10-21T02:24:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/238/products",
    "sha256": "98f4e9e1d317f258744ff7cfd7d0ce528dae64f0fe978ac6dda3974065d6ca9d",
    "cachedAt": "2026-10-21T02:24:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/238/prices",
    "sha256": "fb92b7a3710cb8f8acf2fadb6ad5ae69eb3bb46570469db545115de26f7d08e2",
    "cachedAt": "2026-10-21T02:24:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/239/products",
    "sha256": "4c94878d3ecc4fc8e3753aa9554a7eed65457d74bbd4f9e28268739d6b9f4e6e",
    "cachedAt": "2026-10-21T02:24:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/239/prices",
    "sha256": "0485ce18f3684aa6de8145cf965299496fd64462485e4aa80869f731be4e8766",
    "cachedAt": "2026-10-21T02:24:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/582/products",
    "sha256": "7fb5901d20a18153eb984628b695d0aded039474c3d6462f4bd725f720e08df8",
    "cachedAt": "2026-10-21T02:24:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/582/prices",
    "sha256": "a4e23207e2002bf0cdcbb47e957783e5aa6ef3854bd8db2728ad64972f62e513",
    "cachedAt": "2026-10-21T02:24:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/153/products",
    "sha256": "6fb07f0dcc0059e49b3dbd0502fb7e6ece63b55c5a1b23b286956e9050229621",
    "cachedAt": "2026-10-21T02:24:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/153/prices",
    "sha256": "cde67d3100949f02903614f4232668a82c51c10856d44db2d7152363529f2d15",
    "cachedAt": "2026-10-21T02:24:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/268/products",
    "sha256": "34161b4982d936a3b830702aa32aca670bf25cef1547c9f9b9f15d7801dff335",
    "cachedAt": "2026-10-21T02:24:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/268/prices",
    "sha256": "ce92833c98a7adcb973211a3089de67e7ad9ea5227ffa7c6547d7297ba838732",
    "cachedAt": "2026-10-21T02:24:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2889/products",
    "sha256": "a1352c54c7be94258c100d812753b8b4d5dd066a0421ae0e30d2b3da8683c276",
    "cachedAt": "2026-10-21T02:24:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2889/prices",
    "sha256": "0ad488cce2a45784f96af8eaa14d50bff2e0e2234b0ae6ba24dcb3505aaf2262",
    "cachedAt": "2026-10-21T02:24:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22886/products",
    "sha256": "78b77783d3d2f00945cfa2f1b2bbd834812f31db27af83f5a9d166de51bbb592",
    "cachedAt": "2026-10-21T02:24:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22886/prices",
    "sha256": "9e36a3dcebc195f563d44e95c744d68bbf586cf85fdc15087520e24d8dbc30c1",
    "cachedAt": "2026-10-21T02:24:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/349/products",
    "sha256": "4aeb4e2de728a67691172ed5987cf7b896037bd56e9c0133c2651d4e8c1edaf6",
    "cachedAt": "2026-10-21T02:24:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/349/prices",
    "sha256": "a622ce792558758a98000d6d792762ebe63f2c4de2b0c5249978fa6d78d27791",
    "cachedAt": "2026-10-21T02:24:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1279/products",
    "sha256": "ba3c8b710f865d5dd062dc35abd14405ed8f69db62678e0ae3d4d018c833c135",
    "cachedAt": "2026-10-21T02:24:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1279/prices",
    "sha256": "9a2af1452e38db17bb99001ac58a781e6192ff808bd86a91edb7961f1866f600",
    "cachedAt": "2026-10-21T02:24:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/210/products",
    "sha256": "cf950a7c4cff81917ed129f1f30359879498d03a80af04c7e25877577750b8b6",
    "cachedAt": "2026-10-21T02:24:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/210/prices",
    "sha256": "48305488e8b3de78af67f3ff09e905c88fa6fae8e9461f595d9456b042389a80",
    "cachedAt": "2026-10-21T02:24:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/211/products",
    "sha256": "e175fdd9099fc56dcc1d97177b69ccfef5fedce304bc98435c33763934f71b20",
    "cachedAt": "2026-10-21T02:24:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/211/prices",
    "sha256": "4c991ad9d0a6425461d836b68f6b2fe8a90a804a51b2fa8579123179fb977f87",
    "cachedAt": "2026-10-21T02:24:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1302/products",
    "sha256": "a04f3d879259f4b00cd4b573273ab1731f9e7f6bed7da0f1f671948daa204a5e",
    "cachedAt": "2026-10-21T02:24:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1302/prices",
    "sha256": "6a4937baa733648530da15acf64d011008d7c23cad464dbccfeb8478270ef89e",
    "cachedAt": "2026-10-21T02:24:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1303/products",
    "sha256": "f56bc43cc85a6b91502c562b42ed4b0fdb4c99595efc8075c1e90a26101c112c",
    "cachedAt": "2026-10-21T02:24:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1303/prices",
    "sha256": "e05b9d967c32e709816721fa9644d984767a3ab4beeddfd8c195bece3b71b5d3",
    "cachedAt": "2026-10-21T02:24:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1280/products",
    "sha256": "ca5058bb1ae98efd7feb53172c301b32cdc40fabde4740b46a853bbed2add9f0",
    "cachedAt": "2026-10-21T02:24:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1280/prices",
    "sha256": "cf953bcd2a04a7bcd6d8dd1c68122bab3daa2d963c93a673c72ec902b0c373b1",
    "cachedAt": "2026-10-21T02:24:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/312/products",
    "sha256": "a6e0d627cba01f5c264335e66ddb06bacff0a322a2d0af16e09d15986e0a4203",
    "cachedAt": "2026-10-21T02:24:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/312/prices",
    "sha256": "e4ae295aed66012be44c79d982524c5070482a28b157151514727512dd870c9f",
    "cachedAt": "2026-10-21T02:24:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/165/products",
    "sha256": "6cc3595646e33694544f780a027749394a4c024a67ec4576f9ca1aa7eca5bee4",
    "cachedAt": "2026-10-21T02:24:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/165/prices",
    "sha256": "8a6b9022716ac98d5390f30e2942111f72980ec716bd084609cbd31c250a973a",
    "cachedAt": "2026-10-21T02:24:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/266/products",
    "sha256": "375a9e2716bed3d5e6e8098ae206a3214eef61ba56113b4b1b4340c66197d135",
    "cachedAt": "2026-10-21T02:24:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/266/prices",
    "sha256": "1a5e02c3e268ba4f46104487e222773d068876eb158a33576e5b6c520a65ea56",
    "cachedAt": "2026-10-21T02:24:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/326/products",
    "sha256": "8afdde56fb0a1a83381dd496dbbb2aebdeacc4455dddf4d1746ba6ef81d09299",
    "cachedAt": "2026-10-21T02:24:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/326/prices",
    "sha256": "2398dea97c2ed05a87e98f12eb00d4dae2fee3a5b20154eec3f5e244fab57ece",
    "cachedAt": "2026-10-21T02:24:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/152/products",
    "sha256": "9f12c2e8d12bd8577fd2c2740d84562da3d6aa24a3157a14e3270f49e0335abc",
    "cachedAt": "2026-10-21T02:24:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/152/prices",
    "sha256": "5a2be72f7a92a04fcb8f4787fb2015488c681f2eb4364c398d65e623bac9dcbd",
    "cachedAt": "2026-10-21T02:24:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/130/products",
    "sha256": "dc64d6c0e560ac57083be5ab493f2f66954b546234dc72f52d8cb16eb4c243d1",
    "cachedAt": "2026-10-21T02:24:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/130/prices",
    "sha256": "35d019a0b473859e9a69584993e0fbc46c9988e2569f52f9765c1ee1e17d9a98",
    "cachedAt": "2026-10-21T02:24:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/325/products",
    "sha256": "58153d63e63273f71b3cc12c1d275977a83523d1eb4b3c4e18618835853436bf",
    "cachedAt": "2026-10-21T02:24:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/325/prices",
    "sha256": "3c0234a9b7b6c69441b3cef55b60dec3c3251d2220e9d2f0c8a2b59d2d967682",
    "cachedAt": "2026-10-21T02:24:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/292/products",
    "sha256": "4cc6045846e1be8b58ee543d94036830f535eb309214843cb31f910925d7478a",
    "cachedAt": "2026-10-21T02:24:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/292/prices",
    "sha256": "1b64a68565e89caad4868f3558ee03901cb0fdfba4b52e287ef54cb72b9d3908",
    "cachedAt": "2026-10-21T02:24:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/297/products",
    "sha256": "2ace1788ccae5f76f9dd9b536c22260c95b9fefbf1d9111ae2911bbe7c35c310",
    "cachedAt": "2026-10-21T02:24:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/297/prices",
    "sha256": "845d9f8a1fa1456f2906da71d91baf964c8a5a297fd619b9b5b34c956afe3cd1",
    "cachedAt": "2026-10-21T02:24:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/236/products",
    "sha256": "b6c4b38949eff9203d9a5019752297a7debb40363e38130ccb94aa7e49d98082",
    "cachedAt": "2026-10-21T02:24:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/236/prices",
    "sha256": "b99f1049a1bdb8c23d58fe8cfe66d60f9aae6dcb13f5336ae5304cdcf88a6cc0",
    "cachedAt": "2026-10-21T02:24:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/237/products",
    "sha256": "5d0ef99e5060d48a7d41d55726e98720936823e3d42c025c5df690edce43c8e7",
    "cachedAt": "2026-10-21T02:24:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/237/prices",
    "sha256": "f343c6fde492fa558f44f93a537df28b409a34a7c710d0504ae84a23ecae4900",
    "cachedAt": "2026-10-21T02:24:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22887/products",
    "sha256": "8b490eb38df36c58d3bcf4726f9ffbf856c07c8102c5729abf90960c6bfd00a1",
    "cachedAt": "2026-10-21T02:24:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22887/prices",
    "sha256": "0e4ef549430c5b958b9403f9c12564d12511aa3c60286a6a6426cd424bc1240a",
    "cachedAt": "2026-10-21T02:24:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/208/products",
    "sha256": "5157def27a384beec88e7011ecc44e2cbc24397fd5ed42ef1344ca3733a7e812",
    "cachedAt": "2026-10-21T02:24:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/208/prices",
    "sha256": "953f4a18a6265f6c192ca4fd203ae5f14f4e545fc32e9b0a06bb9933beb32dac",
    "cachedAt": "2026-10-21T02:24:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/151/products",
    "sha256": "226d63cf8307c09518cda1157f50628dc571a734a35ac7fd93c1ca829b90da94",
    "cachedAt": "2026-10-21T02:24:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/151/prices",
    "sha256": "7c3f2ecbf08cdf4a8d7c1bd2a649c413a23a53d363b0ada8b680c944e42aca85",
    "cachedAt": "2026-10-21T02:24:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1159/products",
    "sha256": "bae58893e246bd9c3860965b1b0d1c3f99edee5d77fa19216de2d3803b299f1f",
    "cachedAt": "2026-10-21T02:24:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1159/prices",
    "sha256": "46821ac4c8b57592063323a266b802b40443ed74dcfa0cbc8de8d25decfdc44f",
    "cachedAt": "2026-10-21T02:24:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/235/products",
    "sha256": "e882707ed666511da9d4e14bb0fe02e147bb582ce85c35e956a9e50e1305ec17",
    "cachedAt": "2026-10-21T02:24:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/235/prices",
    "sha256": "bc2c0e7824690e1be98a6f47199c2c6776f19a28d1cd76fdec0f082c35ca609f",
    "cachedAt": "2026-10-21T02:24:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/348/products",
    "sha256": "6d372fd4c2327bddef99a6f48712fdbae643235e2fc54b2cf071d3d933d249b6",
    "cachedAt": "2026-10-21T02:24:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/348/prices",
    "sha256": "87e8a89a3e1872969b97ce550a75b82245c0a6918349e80ebeb669a20c2410e9",
    "cachedAt": "2026-10-21T02:25:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/196/products",
    "sha256": "9da3e1f7398ebfd40cc1b3b62bc9a0ab4f67e323e847042503efc452e9ab966e",
    "cachedAt": "2026-10-21T02:25:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/196/prices",
    "sha256": "dfe407535598230607e8ffb9f066b95737d77c1b73c7b0e50affc276a5771406",
    "cachedAt": "2026-10-21T02:25:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/304/products",
    "sha256": "b841c174eb0c7e81d6d99c54b2dfc74f83d4ea83ac18f80a0f38800ef1463b29",
    "cachedAt": "2026-10-21T02:25:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/304/prices",
    "sha256": "68c0eede1d36f11a5c26998233a8cee2bfacf616cd759c5a47bd94b151ddf5ff",
    "cachedAt": "2026-10-21T02:25:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/194/products",
    "sha256": "a31acc470bdd71c6fb0e4c9b5b2c884d6ec137a8c9952f7bc2236665aba906c1",
    "cachedAt": "2026-10-21T02:25:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/194/prices",
    "sha256": "ea29114c087c2ff8eeba60f65cb64cd67b541e6a7ab633c0a1a98a2842586c2d",
    "cachedAt": "2026-10-21T02:25:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/190/products",
    "sha256": "14bd4df449f93979c21ac7dd22141ce8e1b3060a70d26b1c4a366bd61c3dee5c",
    "cachedAt": "2026-10-21T02:25:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/190/prices",
    "sha256": "b6475e8e14a0adcc80649338bd25da46fe473792c2b2367ab77cc15a7d938c0f",
    "cachedAt": "2026-10-21T02:25:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/150/products",
    "sha256": "2e47cfa1f34cd9ef8f5aa5b693741a3f62c2ec214b194bfef926a04d1b0f3fef",
    "cachedAt": "2026-10-21T02:25:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/150/prices",
    "sha256": "b24aba76392e6b07eac85b7bb7d3d3694d14118b1d94765517a7b98c1d29f9de",
    "cachedAt": "2026-10-21T02:25:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/311/products",
    "sha256": "7f946ca0e49ec63e12f09038b37525a75ba61333e33cf0449a8652fcd51edb60",
    "cachedAt": "2026-10-21T02:25:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/311/prices",
    "sha256": "9ffa1756025c8839a8bd4e74df3c06df7ada411dc27cafdc0abf21caf982e6bf",
    "cachedAt": "2026-10-21T02:25:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/220/products",
    "sha256": "495be3b17d2e8ff56fe2b761aeee2f50db17ab65f70c9100064fa5601e7dc6b8",
    "cachedAt": "2026-10-21T02:25:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/220/prices",
    "sha256": "dd51c8c2888b699f37a75d5093b008602e9c145bb7ff528a0ad1ae8ad170013d",
    "cachedAt": "2026-10-21T02:25:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/254/products",
    "sha256": "7898d1c1db359a259711ad11d16284d485cacd6dc11a0f5fa9393f7792b9e86b",
    "cachedAt": "2026-10-21T02:25:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/254/prices",
    "sha256": "bf79e48917767ef50f7d1945accc2ce1917580fa0266cf8937559fd06e56ae88",
    "cachedAt": "2026-10-21T02:25:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/174/products",
    "sha256": "4ceb2d3baadbd99cd4321ec57fb74c48e19e333b671d561b389276107dfbcd5c",
    "cachedAt": "2026-10-21T02:25:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/174/prices",
    "sha256": "5855946b623378eb1b2db7dc29fc9082fbd4b446ff4bad0e2ed94320c4be7e31",
    "cachedAt": "2026-10-21T02:25:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/222/products",
    "sha256": "bc6d17977d9883dbd4376159416fc8de7b2e19c65f02583d6b52b514dc20e0d7",
    "cachedAt": "2026-10-21T02:25:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/222/prices",
    "sha256": "929f1c4a6a61995fc11b35156fc82ff3b961d35f5302f7d8cbd678dc246f6a50",
    "cachedAt": "2026-10-21T02:25:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/265/products",
    "sha256": "27ca1ee881e69e0483e79723f170b14013dd89bd0af2339f9b77f582d53658b5",
    "cachedAt": "2026-10-21T02:25:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/265/prices",
    "sha256": "69a01210085252f00b783a214b95b5ff84bc190292e136318fd651ef27a89212",
    "cachedAt": "2026-10-21T02:25:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/159/products",
    "sha256": "7b92ba13e6e96166dae584f4df391388b24cf7818f36e9ba64dd5f90a027071d",
    "cachedAt": "2026-10-21T02:25:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/159/prices",
    "sha256": "de5524632926e22a34c9ddf991deb24c046349136fb4b5a6826fdc4549444b2e",
    "cachedAt": "2026-10-21T02:25:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1338/products",
    "sha256": "e7e1113856c91b1b1b6d57990a431ad76fc74287fa6a549df08fa79e17168cb5",
    "cachedAt": "2026-10-21T02:25:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1338/prices",
    "sha256": "bbff16e007d7002d1de7a25273d2f90d3f43671bad62e72309609892fd31af77",
    "cachedAt": "2026-10-21T02:25:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/356/products",
    "sha256": "4bca174406b238b60af7dc1597f2f9a0d1bcb9ac172698d3858e9284fa5479ef",
    "cachedAt": "2026-10-21T02:25:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/356/prices",
    "sha256": "a91ad1a75a26d38c94549f7cc9248be5d5346afd1b7ca0fc27c5ddf6155734d8",
    "cachedAt": "2026-10-21T02:25:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/149/products",
    "sha256": "865213e9f68fb8dc07eed4b55ceab49a3c71ee8fb64730d0b1faebe60345cbb2",
    "cachedAt": "2026-10-21T02:25:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/149/prices",
    "sha256": "56a61d51fec9adb1c765455016a43840ec77c557e930bea00ce97e64a45953f3",
    "cachedAt": "2026-10-21T02:25:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/343/products",
    "sha256": "7682bde14a2621de7fd47d7418b63a88ce6064a19635f6d940a4b625e05246da",
    "cachedAt": "2026-10-21T02:25:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/343/prices",
    "sha256": "9955b4760fe8cb1fed3c1691116a58c21992e9eca46d2ed15e44b573c91b4ae6",
    "cachedAt": "2026-10-21T02:25:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/306/products",
    "sha256": "ea23546d42b808ad81edcf0e78c56add57c7ec623aab413dee4cd2d9407d3ff8",
    "cachedAt": "2026-10-21T02:25:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/306/prices",
    "sha256": "e8bd41f6b55c8c08ee2d26aec88966b585a559d665661b84074e9c3769614baa",
    "cachedAt": "2026-10-21T02:25:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/129/products",
    "sha256": "4ad33551536d94d2d1bf802f3f732811679caca8519bab9059ecd6416077f871",
    "cachedAt": "2026-10-21T02:25:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/129/prices",
    "sha256": "eb7c6fb7432722b0d2273a613a78717b880172b3abb3dd932891c0bf2ad06653",
    "cachedAt": "2026-10-21T02:25:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1317/products",
    "sha256": "339e9e47300bab057b6edce7c6c8f6990b1a76ce8540158ca5a16897c05f9692",
    "cachedAt": "2026-10-21T02:25:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1317/prices",
    "sha256": "02c7534a3a4f494b690ac44721c7b7c8af9060c785f7c8780a2eaa7a5ddfdd27",
    "cachedAt": "2026-10-21T02:25:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1322/products",
    "sha256": "459f0b23ce442f18aa5411c19366843d618d1407830e6fc01382e4c40907eff4",
    "cachedAt": "2026-10-21T02:25:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1322/prices",
    "sha256": "c79c6fe4160eb1a42ffef414803ae591635ad3a968d75b346483dedbf12da273",
    "cachedAt": "2026-10-21T02:25:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/223/products",
    "sha256": "909a7a96b36de1a288a310ee7a775d0fcf606227d27e8fac5713d4a02d2464d1",
    "cachedAt": "2026-10-21T02:25:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/223/prices",
    "sha256": "7f0c8b84437619db0be341be45f952a1d0d17cf2337c4a4fb929db3b0e3979f3",
    "cachedAt": "2026-10-21T02:25:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/310/products",
    "sha256": "bdc84e6a89076394e715871f0bdf45f7076a952bdd8cd4d80cdfe4fb5bb2a15c",
    "cachedAt": "2026-10-21T02:25:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/310/prices",
    "sha256": "662bbfdffd219095d94e9c8504f01e4b5ea57177cf51f37fb8a8026db9828422",
    "cachedAt": "2026-10-21T02:25:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/234/products",
    "sha256": "f2cbd3b37d4e2aae6bf6d0168a8fa79025de43bc0ddc680d74d286ff2873e968",
    "cachedAt": "2026-10-21T02:25:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/234/prices",
    "sha256": "b656423eb6d17211adfbdf6763c17d1c5de7c061c058dda1c5aee6c813d6c70a",
    "cachedAt": "2026-10-21T02:25:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/201/products",
    "sha256": "d5a9bf3b888a36d1d42e72e206f520e730c4335e16ff901af6a13eaa2f46fc43",
    "cachedAt": "2026-10-21T02:25:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/201/prices",
    "sha256": "8018743da622eca7d7daa1675467d4ffd46feeb380034f647ca7dcc7f58fae0d",
    "cachedAt": "2026-10-21T02:25:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/309/products",
    "sha256": "48974fdcba47fbcef08cc70947bb094dbe1313d862a07ca28625504d81ed3f52",
    "cachedAt": "2026-10-21T02:25:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/309/prices",
    "sha256": "0af2b10924f6f75185c530dd5b0373c0e2a4c7198c79dd9d7685bf6b5fbef25b",
    "cachedAt": "2026-10-21T02:25:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/340/products",
    "sha256": "7382cea0642e548da23740aef5fd9e46b4965db2ceed2f43f0665d4545e27592",
    "cachedAt": "2026-10-21T02:25:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/340/prices",
    "sha256": "8ec6f2b5a4b110ad7efa7d6490dfab7eec6acf47d728161d84532f841154ea4d",
    "cachedAt": "2026-10-21T02:25:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/291/products",
    "sha256": "c397d6dc2408acecaef9a065cd8fc6f21eee9bf7ebabfa995e4920335c291165",
    "cachedAt": "2026-10-21T02:25:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/291/prices",
    "sha256": "58bd03239f4bb9654cb13263b38191c7f7ddcbb0eab74f2672c0bdabe799b812",
    "cachedAt": "2026-10-21T02:25:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/347/products",
    "sha256": "2f9617ff0094b420244a702a81c74289c88acce44cb9fdf8e995938f519c53d7",
    "cachedAt": "2026-10-21T02:25:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/347/prices",
    "sha256": "703eb5e027b0c6a86b5d873e80cbcb43729f67f709942386a89791e999ef0f24",
    "cachedAt": "2026-10-21T02:25:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/195/products",
    "sha256": "2cae7f3273a2c25c206ba9b14a453a8225f7baf34b464fcb69679451dca4f821",
    "cachedAt": "2026-10-21T02:25:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/195/prices",
    "sha256": "d02e835c48311a5ac666dec1bfe1c62111fc4b2c2a1325c618ab548144cb0f3f",
    "cachedAt": "2026-10-21T02:25:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/284/products",
    "sha256": "006b5b8951ca7a87062911b0b0947ab2a3ed5b92427723ce86f553d5e951c5b6",
    "cachedAt": "2026-10-21T02:25:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/284/prices",
    "sha256": "4ed521f0640369223be8efa2d5a62dff326329522711b97139144f5f650bd304",
    "cachedAt": "2026-10-21T02:25:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/277/products",
    "sha256": "369cac78891af4f6cfd29b049c41451bea504e0697bad55ef4e9165d1582b92a",
    "cachedAt": "2026-10-21T02:25:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/277/prices",
    "sha256": "596bab378a8a04765bb211a70632b580f019e359504b7616b8028bf364676cd3",
    "cachedAt": "2026-10-21T02:25:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/283/products",
    "sha256": "cbbd49a0f6fca8237a578487947cf1ba7452d38cace63bb5b7d416ea0ae09260",
    "cachedAt": "2026-10-21T02:25:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/283/prices",
    "sha256": "7f29dc075fce43d869da643b6f3d3e2f83e80f6ba4ab6251ae3e60ee8bc4c7d9",
    "cachedAt": "2026-10-21T02:25:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/193/products",
    "sha256": "bfc5bda1afa7695a8235b2ae6a987fb4281a1d6290677612d4033c25aef84329",
    "cachedAt": "2026-10-21T02:25:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/193/prices",
    "sha256": "aaad7dfc92b213441a4702051122ea287f0d2d3fbd33a4c54e6eef93c74f559d",
    "cachedAt": "2026-10-21T02:25:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/191/products",
    "sha256": "bb52daa0606d674f2d30f5de26aaa794fcd363ab3df10572a9524488dafea275",
    "cachedAt": "2026-10-21T02:25:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/191/prices",
    "sha256": "2463a8506d04f0eb15e274d81b1e55f973c1dee843417b6f68a7205a5388a6f5",
    "cachedAt": "2026-10-21T02:25:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/313/products",
    "sha256": "4fac728285d5fb50812745ee8d679a89c2ae31a84184af29a4c3795a7c81e7cb",
    "cachedAt": "2026-10-21T02:25:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/313/prices",
    "sha256": "8bcc2f163f7bbe24a54c1aae281e06c0e6171e14feb1a2b61f057d1ec75804fb",
    "cachedAt": "2026-10-21T02:25:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/218/products",
    "sha256": "04b526f6199dde52e12d2779d46440b6d8ffdd2fd531180e756458d087b603f4",
    "cachedAt": "2026-10-21T02:25:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/218/prices",
    "sha256": "ea4db0baf04ec2886c8fc03c48db291486768c396a4e07f344f4080b33834599",
    "cachedAt": "2026-10-21T02:25:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/233/products",
    "sha256": "39483d7a59ff82126dac377f2b6c93da7cf8c1324eab76098ba46ecfcb8eab70",
    "cachedAt": "2026-10-21T02:25:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/233/prices",
    "sha256": "3bce2334b6cffce581f30724d7388108530925651a478513ff4e9053652d8ffc",
    "cachedAt": "2026-10-21T02:25:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1323/products",
    "sha256": "7e43349212f8c6278b062ef90e6fc902eba32feaf67f20338b4cc2a3c1665b5b",
    "cachedAt": "2026-10-21T02:25:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1323/prices",
    "sha256": "432ba117eaef2c1e72b6364abb2e3876b20143434416d8f91207c6c8957d10fc",
    "cachedAt": "2026-10-21T02:25:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/599/products",
    "sha256": "68e391e6b5784d86369f454680166f7c33eb140b45a262b47dd6790cef109ed9",
    "cachedAt": "2026-10-21T02:25:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/599/prices",
    "sha256": "ebe1b15e4b786466abc1ac0c6988367caecb4924b763b63f32bebd859df2c5cf",
    "cachedAt": "2026-10-21T02:25:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/200/products",
    "sha256": "7b7df3d2ccfa98e747f9203e3cfa7f2ea4117774888c6e8d0e5128c613e652e4",
    "cachedAt": "2026-10-21T02:25:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/200/prices",
    "sha256": "238c19d5a6c14dc21beb9fb7e65c05c32d0f69ac06bf8571684348151d52ad31",
    "cachedAt": "2026-10-21T02:25:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/339/products",
    "sha256": "1879b3440d611851326d61e7057563565429434744b5efb9d418202a9aecc218",
    "cachedAt": "2026-10-21T02:25:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/339/prices",
    "sha256": "aa404a4b1cadb5f49d0899e0f38ae13b11657686b4e68d3267ea0b218602db43",
    "cachedAt": "2026-10-21T02:25:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/314/products",
    "sha256": "4d165fb84dbe40eb5c0519a25f8a4ba289e75f0d15dbfd999adc316cdece8269",
    "cachedAt": "2026-10-21T02:25:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/314/prices",
    "sha256": "2b1d49a20ab35c0e1c2cc3a6a80e282a5b16a053a8af37b6c805cef618873e73",
    "cachedAt": "2026-10-21T02:25:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/173/products",
    "sha256": "d476d7785289c4c4d85702bdc393334ff5eb327ff4bc26942a79aa84911748d2",
    "cachedAt": "2026-10-21T02:25:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/173/prices",
    "sha256": "ebd38225a69731b25d92d79ec8b86d1d1bb84e72b2211281d01f70e74ba9769b",
    "cachedAt": "2026-10-21T02:25:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/252/products",
    "sha256": "f924e61c189e811594e52febea576c2e807c9c5380a5a71a9628257719e87884",
    "cachedAt": "2026-10-21T02:25:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/252/prices",
    "sha256": "a9e7c9cafc0e243e7b43dee1808219c8eaecfe0e6a5ddaa990b42e86f9355d9d",
    "cachedAt": "2026-10-21T02:25:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22881/products",
    "sha256": "f2900443d333d78e65a5e468c27591121837cd5e87f93038dbd9394f3bd35386",
    "cachedAt": "2026-10-21T02:25:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22881/prices",
    "sha256": "ba5b1adc186407afe01d46f8a5b78128b228b97b4d00ed35cf75c1fcd6426af8",
    "cachedAt": "2026-10-21T02:25:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/205/products",
    "sha256": "37f0edc768f68b83733dc9c9bc3e41ffb5172cecd4b3f573b9adad9efccce76a",
    "cachedAt": "2026-10-21T02:25:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/205/prices",
    "sha256": "e4fa060033dc9d443cb793a4bb1b753a7912cf04c5c5852890ba4e811d03cdca",
    "cachedAt": "2026-10-21T02:25:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/128/products",
    "sha256": "1ef5adf10fd7f0df969ca666696798029ce3ac782a5471f05188f121e2f6e27a",
    "cachedAt": "2026-10-21T02:25:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/128/prices",
    "sha256": "7d74288c50cbb3ae9eaf94d34b1ae59975f2c45774ae2b3c0c2bf030c4b9b5b4",
    "cachedAt": "2026-10-21T02:25:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/256/products",
    "sha256": "6600cfd5bd3787e97a57a9c74c73dad7fa8affbd2be18b84f0505ef1a1cdfbc4",
    "cachedAt": "2026-10-21T02:25:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/256/prices",
    "sha256": "c39bb6aa75e820aa397ada9c23c4b8308ec293f0bc7410bdbbe56ba7b03c9880",
    "cachedAt": "2026-10-21T02:25:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/160/products",
    "sha256": "9b543d0ac5de97b87f1448a7b9857bdd3737ccd573a8ead910cb64dbbff6fe36",
    "cachedAt": "2026-10-21T02:25:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/160/prices",
    "sha256": "2b568c168fbd981c6edac96cb990387ec9519ff7afff5950f41e1274c5071c0d",
    "cachedAt": "2026-10-21T02:25:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/164/products",
    "sha256": "10d0a26c2ea5e40862d462dba579acb13a9b723e002d02433623bbf0c9bc1c57",
    "cachedAt": "2026-10-21T02:25:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/164/prices",
    "sha256": "2e6c7e8975e33966cd78add746e2ab39dc94b490bf88913593ee1d5c23a6f5d9",
    "cachedAt": "2026-10-21T02:25:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/248/products",
    "sha256": "d0ed1bab9ac3cc6a1e90b3c133aace9494066ea2307a6e5234e31db9fa000d4d",
    "cachedAt": "2026-10-21T02:25:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/248/prices",
    "sha256": "5c26ebb44aa8da00270dbdc4dcfe5b76dad22d26038cd43f447190d70614b350",
    "cachedAt": "2026-10-21T02:25:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/338/products",
    "sha256": "ede2f47329d14ab486febc8f9f1f8c162d6a8b97f3909425203187adcb5ecc2f",
    "cachedAt": "2026-10-21T02:25:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/338/prices",
    "sha256": "d430efe2710b9eede307d0d63ee3f3fc2409aa48e8218801273d85321371f68f",
    "cachedAt": "2026-10-21T02:25:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/305/products",
    "sha256": "299b949fd93c649ae0247511253d2657556b0dbb403252146844aa046af3a166",
    "cachedAt": "2026-10-21T02:25:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/305/prices",
    "sha256": "e93f1f533511137e946f94dbc8469481351b587e25a00d5b69c7fae71b9f9ada",
    "cachedAt": "2026-10-21T02:25:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/308/products",
    "sha256": "62960ec6260cc3fbc769efa5b36f5e38d6431efae04dec90376ed13d0418cfb3",
    "cachedAt": "2026-10-21T02:25:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/308/prices",
    "sha256": "f49597d6e7adea30e0149e91296e44d9633ba5bea4b08e8733b371b61012f731",
    "cachedAt": "2026-10-21T02:25:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/172/products",
    "sha256": "9449b65d1415de6ad50bd2aa55400586930ed7ab08b6d0bab978be5ffeb1bc96",
    "cachedAt": "2026-10-21T02:25:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/172/prices",
    "sha256": "8e8e6685e9375e553551b91d131f3b7ce9becd3656dbe44dba6895c5310bad21",
    "cachedAt": "2026-10-21T02:25:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/251/products",
    "sha256": "3fcccb8668526caf08f23b4a1093c3663b7acc91912f5dca6a515e71e9905b64",
    "cachedAt": "2026-10-21T02:25:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/251/prices",
    "sha256": "afcfdd71c98dc94c75439659268b77a5a398b1e76d91c28690278c43c04f91c9",
    "cachedAt": "2026-10-21T02:25:40+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/204/products",
    "sha256": "9ec351dbf97707c995c4e60331cda2a7bfc38a83d3c7a98747d518e9f4d4568d",
    "cachedAt": "2026-10-21T02:25:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/204/prices",
    "sha256": "9f2d11b6b68a13c7a7590144a0d54929af2a39d20e62ba4269f4b120df77a17d",
    "cachedAt": "2026-10-21T02:25:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/282/products",
    "sha256": "05706d12b37f107baac7b1246d27ad7831539e83afd2781ad2d77fbf748a7497",
    "cachedAt": "2026-10-21T02:25:41+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/282/prices",
    "sha256": "baca8bf1dd3c2b836cb62ac396e4dcbce21f5b4861c27ab76fb88fd546101940",
    "cachedAt": "2026-10-21T02:25:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/346/products",
    "sha256": "2c03cb19c1f1b7631186080afbbd6a49b39de4813432e9fb0c6c94b0b208dcec",
    "cachedAt": "2026-10-21T02:25:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/346/prices",
    "sha256": "de4b321785167d46459467c6dd2c4ed63b35c80666d8c712881a27213bcc5729",
    "cachedAt": "2026-10-21T02:25:42+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/275/products",
    "sha256": "91a5ce422fee1138dfa8deab4b5dd5d9941af82ceffb4770b9ecb66e56743aca",
    "cachedAt": "2026-10-21T02:25:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/275/prices",
    "sha256": "2349e040b5531f2e5b8010a79dae3be74bbf682697806c50929f02b290d6038e",
    "cachedAt": "2026-10-21T02:25:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1655/products",
    "sha256": "ef6aefccca81f02162306252672d1cc7caafd6d2a58ba993dbd247041e2fc5f9",
    "cachedAt": "2026-10-21T02:25:43+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1655/prices",
    "sha256": "6948883004e195a8fb37cbe21e9cfd9bceca0e3c0865333f5aa8a3e0a9adcd72",
    "cachedAt": "2026-10-21T02:25:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/307/products",
    "sha256": "84696f156a2ebacacc63575d69d623272609c4d29eb3db987d5f9b7a4a3b688b",
    "cachedAt": "2026-10-21T02:25:44+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/307/prices",
    "sha256": "73048f67012699030bc9bd144c03a957858e8a3c6d2095674a10c384cb27eb05",
    "cachedAt": "2026-10-21T02:25:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/315/products",
    "sha256": "ce5b94876c70c822a2538c022c04630e2afb23a19821a4157d4b4647d6fc7433",
    "cachedAt": "2026-10-21T02:25:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/315/prices",
    "sha256": "5a3552a10719054cb306726c7d1e246d8524616686f01abc7423b63f4f8a65b6",
    "cachedAt": "2026-10-21T02:25:45+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/280/products",
    "sha256": "307a75e9c74a388a5809dc901f214b705035a8a496ec82f4e4e87108fd0ce977",
    "cachedAt": "2026-10-21T02:25:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/280/prices",
    "sha256": "7f5c1eef3883bb89a449f4eb02653c53264c83a24edace9a4ec410ed1521bd8c",
    "cachedAt": "2026-10-21T02:25:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/274/products",
    "sha256": "3deca7f4fecd454f96b9b31f4e12ea7c050a7ffd181bb51581ed15ee09e18705",
    "cachedAt": "2026-10-21T02:25:46+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/274/prices",
    "sha256": "0312e70aadfe31fd584fa56b747c3010cbb5444f2effc2d28b4812d9183cc570",
    "cachedAt": "2026-10-21T02:25:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/241/products",
    "sha256": "b6de2eef2159dc63a2c1ffd2b456f9307e702b3062d4b8f541f3dc3cbcae6796",
    "cachedAt": "2026-10-21T02:25:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/241/prices",
    "sha256": "417ac7ce0759419e2bae99e04e714928a58fb533520d657bc2800c4a6c28eb45",
    "cachedAt": "2026-10-21T02:25:47+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22885/products",
    "sha256": "7c11e115a269b11828faeaa714abb25cdd35c2e7b25bfa14b9e5967098f28964",
    "cachedAt": "2026-10-21T02:25:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22885/prices",
    "sha256": "c8664c0cf3b513d78f1846676dca0c87bc6f3b5e621af118e2018b59e8aa1e52",
    "cachedAt": "2026-10-21T02:25:48+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/255/products",
    "sha256": "e71ed23148530647e5ebabbf77c69d038e600257675b87a5c5eb52a669da3f2c",
    "cachedAt": "2026-10-21T02:25:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/255/prices",
    "sha256": "3f1ee8fccf49f5e220c0e39297a7ac1e50fc906ee8bc87aec23ad1c353c3bdb1",
    "cachedAt": "2026-10-21T02:25:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22882/products",
    "sha256": "5c6a14542bcab7342c64fca5cf472d3f16479aad669eb24c1d984036c635cc28",
    "cachedAt": "2026-10-21T02:25:49+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22882/prices",
    "sha256": "6a74b1a7cdb871a5de5b52eb59bdcce0715fc9725fb9379e4b9e33fbd8b50a18",
    "cachedAt": "2026-10-21T02:25:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/259/products",
    "sha256": "76c89a63c7d536f1ce5177377ab9a17cdc4413286f48a056f2f022b2f4608812",
    "cachedAt": "2026-10-21T02:25:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/259/prices",
    "sha256": "11f85f23b7fb956a2e7c0f5ab6de2ec4d402dac16a00688af4b22278a7d35528",
    "cachedAt": "2026-10-21T02:25:50+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22905/products",
    "sha256": "933758faa66a072ffa7f903a57d13fc1eef8b44d95aedb2c3f16158ff188d8c1",
    "cachedAt": "2026-10-21T02:25:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22905/prices",
    "sha256": "638e690797d855622e4be51b66d3e57c3c733431391e840dd000e68d8c786720",
    "cachedAt": "2026-10-21T02:25:51+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/148/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:25:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/148/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:25:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1686/products",
    "sha256": "50e8f09efafecf9646cec1285f455c18fd2acee976288d060e2fa1b2e1be3c0e",
    "cachedAt": "2026-10-21T02:25:52+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1686/prices",
    "sha256": "cdd779bf4c648fa04ecf413f86a45919ce9779dab5724f155d1d72a852a0334e",
    "cachedAt": "2026-10-21T02:25:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/337/products",
    "sha256": "f9d8772d84296740908b08996cb6e67ffeb4c95046e01bcc3f0434e63e26787e",
    "cachedAt": "2026-10-21T02:25:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/337/prices",
    "sha256": "c95a7e1af44809c8d636ec117ef4bfc8db90a9ff6271459a5225008401dbb104",
    "cachedAt": "2026-10-21T02:25:53+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/232/products",
    "sha256": "6684d569d340dcdb6308c646e1fbc37cdd2361bbf9c2819efc33625dda4f075f",
    "cachedAt": "2026-10-21T02:25:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/232/prices",
    "sha256": "e3e31c9f94d9b906d5512d8c6957c11f610224c34530ddf80bbcce5fd786331f",
    "cachedAt": "2026-10-21T02:25:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/285/products",
    "sha256": "27dcd4dbfc26ed51fa32c775f094dc25faf53b1bc7669dc9a3d589cdcde3d5dc",
    "cachedAt": "2026-10-21T02:25:54+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/285/prices",
    "sha256": "2bbb43753878aa304e02290d2a667b2a755429f0c4133c19e814f354cc679d11",
    "cachedAt": "2026-10-21T02:25:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/176/products",
    "sha256": "b2b5b21074b50315aeb6a7bc522b9463a3b55242a5ecb11c3fdb4b2727528ed9",
    "cachedAt": "2026-10-21T02:25:55+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/176/prices",
    "sha256": "66a2b1fe834e7089d6d7a9bd1bd15c87a7d51596be45fa446b1ebeae844da2ac",
    "cachedAt": "2026-10-21T02:25:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/127/products",
    "sha256": "6ebc9fca02e37f8a806b39ff39677f058730639e7007e73b8876e93f58a82df1",
    "cachedAt": "2026-10-21T02:25:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/127/prices",
    "sha256": "0aaea89ceda2c6d07212041980e6ed3d4bf3da1f3f3916dfe0b4d0972bab9617",
    "cachedAt": "2026-10-21T02:25:56+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/279/products",
    "sha256": "6b5ef68f94fa544fb0c37516604360ccaa81c5dd386a1b47167d154ffca0c9d2",
    "cachedAt": "2026-10-21T02:25:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/279/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:25:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/359/products",
    "sha256": "9cc0ddf3b525e364a82e3184d52f18741063567b870d01ea5f3eacd56ab9506c",
    "cachedAt": "2026-10-21T02:25:57+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/359/prices",
    "sha256": "8aafca820f4e23f9bc2adc2cc882cd01e3a54aaaf39939a34246942dee61ed4c",
    "cachedAt": "2026-10-21T02:25:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/357/products",
    "sha256": "142cd9af4a27751bc55b73df9f2fb3f50ada36564267ff1d4746ec24e806f154",
    "cachedAt": "2026-10-21T02:25:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/357/prices",
    "sha256": "a663cb14c3bf28f299521d55d13b1a03c7c3a32593f239ba18e50a3de60cc00b",
    "cachedAt": "2026-10-21T02:25:58+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/262/products",
    "sha256": "8b02112216785610c25451e1e3fe9899e686f6d26fb8ec22c7489cd09851098d",
    "cachedAt": "2026-10-21T02:25:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/262/prices",
    "sha256": "015b1270a2edb9786303d780053bb74734c684b702fbf2625e9f2be4c199f8b6",
    "cachedAt": "2026-10-21T02:25:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/272/products",
    "sha256": "2660b86a667c085518384b77bcd39efe49e486bd651625dcb4b8dea46853500b",
    "cachedAt": "2026-10-21T02:25:59+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/272/prices",
    "sha256": "a8b75a0cd00df5bf84dea5a3ed8c5fbcb04c1e2e25166ebba064791fdb994d21",
    "cachedAt": "2026-10-21T02:26:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/146/products",
    "sha256": "609e56dc7d60057285853db5c3aefa5f87921a01bd1f2333ba5c957233a4d778",
    "cachedAt": "2026-10-21T02:26:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/146/prices",
    "sha256": "dcfb07dbb10506a78d705723f4bae135d2f257cb552d549984e910b879f8bcd6",
    "cachedAt": "2026-10-21T02:26:00+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/263/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/263/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:01+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/175/products",
    "sha256": "fbebd1270247b7a7f46bd3110485d97320be629979e239ae35e9991bd67a739a",
    "cachedAt": "2026-10-21T02:26:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/175/prices",
    "sha256": "74b75728fc3a64887ea1f276fd1edfaa0fd64445dfbba4338360d28ea283542d",
    "cachedAt": "2026-10-21T02:26:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/295/products",
    "sha256": "414e4193484868864934f2b08896fe7f4be6a7d3c2e92dfdfa43a02d3cdd1edb",
    "cachedAt": "2026-10-21T02:26:02+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/295/prices",
    "sha256": "cb073d009ee2baf66c6d969e21619f8de25e8bfaffb9159e81395d93cf4ef0f1",
    "cachedAt": "2026-10-21T02:26:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/299/products",
    "sha256": "0e0817c3e13f72071abe9dad6f2ff9e89eb36da7dbe1d53c4a9ac5f55ced6f9e",
    "cachedAt": "2026-10-21T02:26:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/299/prices",
    "sha256": "d0f571142523bc3e44babbc381e12e3cd4e316ce362aef4782ee86f84879f30e",
    "cachedAt": "2026-10-21T02:26:03+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/345/products",
    "sha256": "b718219a0c57f4fe79043ff0b1a5140e4b8dc44c332871582c2ec7bd3e35601c",
    "cachedAt": "2026-10-21T02:26:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/345/prices",
    "sha256": "ae2bca9af41dc953e796395afb27b3257cd977dbc88a7cb01516363c6dd9ac6a",
    "cachedAt": "2026-10-21T02:26:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/264/products",
    "sha256": "aa0bcb5730fe1df95ab9ef6fc7e621c5ab01c34ea4c7b1e87f4cb4d32aa11443",
    "cachedAt": "2026-10-21T02:26:04+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/264/prices",
    "sha256": "a0d5e3fc65be837e4fc6722651ddd8c9a960299260bd66fc86aa079654c3df75",
    "cachedAt": "2026-10-21T02:26:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/329/products",
    "sha256": "db133c70b3892b7fbc4294a3d204f929f04044dd5cba80e782eaa6b09ac56d6f",
    "cachedAt": "2026-10-21T02:26:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/329/prices",
    "sha256": "7fce40bb02af4e6f62983d5be843f44f560e789447d806b55f0bed1970ef7d0d",
    "cachedAt": "2026-10-21T02:26:05+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/178/products",
    "sha256": "28fb7b736c95a478601b5d2f15e98807db8d56371b7417630f0f20cab62605f5",
    "cachedAt": "2026-10-21T02:26:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/178/prices",
    "sha256": "d221d20809dc1edafc3784148ef19276a9a5c3ab54d8ea583cd30150fcba48cc",
    "cachedAt": "2026-10-21T02:26:06+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/250/products",
    "sha256": "49bc5c3523f873d57d84a3d55410c64a76e84ef3999b25a914cf0bcbdd821f9f",
    "cachedAt": "2026-10-21T02:26:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/250/prices",
    "sha256": "68628f47680365dfbef7618b7e29eec8c9e60de504259419aa60778d7ef70b27",
    "cachedAt": "2026-10-21T02:26:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/336/products",
    "sha256": "63fe68c82218bf7101e2ca9ba4ce6c64b7a19842a1f2b1fd79a52de2aaf64024",
    "cachedAt": "2026-10-21T02:26:07+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/336/prices",
    "sha256": "434465d0beee5b85337feb539423babe77d55385d47ee04875f2127d5225c20a",
    "cachedAt": "2026-10-21T02:26:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/126/products",
    "sha256": "7068e99581db5949d55fc093e09f8737d9ba7acf1c703d8c802580a665298894",
    "cachedAt": "2026-10-21T02:26:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/126/prices",
    "sha256": "14120f2de66c122612270b064996740cf146d63784a7bc979abb880863ffaf1d",
    "cachedAt": "2026-10-21T02:26:08+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/260/products",
    "sha256": "20d47a2e015f08dc531a012224e1e8388d22755c5d346f4d8a6d14fd4cbfea31",
    "cachedAt": "2026-10-21T02:26:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/260/prices",
    "sha256": "69bc48b4e4cb230ca93f25fce1147430813d05b47fb386d8ee2e98c7abc48a16",
    "cachedAt": "2026-10-21T02:26:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/351/products",
    "sha256": "9bb3950a7318305658437e368973958166e0c0cdb43014b318ae5ab73fc74a5e",
    "cachedAt": "2026-10-21T02:26:09+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/351/prices",
    "sha256": "f658adbe08d75e3c9138deca40e2d9e55efe4fd4f6f0c3c5679777e570efcf58",
    "cachedAt": "2026-10-21T02:26:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/143/products",
    "sha256": "af34fe9d74f9e8d8fac4ac6131a170de3417a207ee54c1671febc8293b39ce8c",
    "cachedAt": "2026-10-21T02:26:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/143/prices",
    "sha256": "06dc76380dd56920e99e4a76114a5309ba11c2c179040c81a6bdfed3811f9a6e",
    "cachedAt": "2026-10-21T02:26:10+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/287/products",
    "sha256": "fece5b2f138bb368b336caf24a6252a4c8578adad8a0d47467ab066482f45e97",
    "cachedAt": "2026-10-21T02:26:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/287/prices",
    "sha256": "c829c908296e354547fb8ffc0279e5078d537d76658213cfd9c47e770599da9f",
    "cachedAt": "2026-10-21T02:26:11+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/293/products",
    "sha256": "d4e534b8f1ed3f2034a546e1c002cedf7fb4b8fe0d9ce0863d1f0f00664bf74a",
    "cachedAt": "2026-10-21T02:26:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/293/prices",
    "sha256": "2fb1505951411b10dd3d684589e44bb9661eb6d7e963f83ff2c60080a0dbc8b1",
    "cachedAt": "2026-10-21T02:26:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/296/products",
    "sha256": "0a447550e290cdfe8f22d59dbc00ed14b59fdc955a5059b7a252536fe74c1e63",
    "cachedAt": "2026-10-21T02:26:12+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/296/prices",
    "sha256": "9e44e57489d1f75ec1408c4714d135eac4513d2fe7543ad74e8b77fb923b255a",
    "cachedAt": "2026-10-21T02:26:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22884/products",
    "sha256": "c1da68095d2f3ba78832b1d8b89f349568bcef0da6de764d826eedc2c8aed91a",
    "cachedAt": "2026-10-21T02:26:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22884/prices",
    "sha256": "20b1b68a7da2ac1b9a9b20777489f8b95ad83fbc19173516b45248614fa88c20",
    "cachedAt": "2026-10-21T02:26:13+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/335/products",
    "sha256": "83ea419b221a914aabe20ddd2833aaecd0ffda2a4c7be17fe4ad52e570fa0f24",
    "cachedAt": "2026-10-21T02:26:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/335/prices",
    "sha256": "a45c9a12b0c1acc1c6c833ffa1491de096f1c4bb9474ae83154ee24a2a1a2ac9",
    "cachedAt": "2026-10-21T02:26:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/183/products",
    "sha256": "de6a37cbd312074db1bac7ba60662fd187381183427c26d0dcfc85192eba9846",
    "cachedAt": "2026-10-21T02:26:14+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/183/prices",
    "sha256": "da01f8c5144dbfe60eb2064965c092e31dd5321a002b1bb913e1084e09af47e7",
    "cachedAt": "2026-10-21T02:26:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/182/products",
    "sha256": "e07ff45893d5740892896a41333e960438c458f80e7dcbf03e3f8c8a88c9cdc5",
    "cachedAt": "2026-10-21T02:26:15+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/182/prices",
    "sha256": "1f6f8950ebc5214bc36f2a95c33494815fb4a04b2e7ee42f01569851898b21e4",
    "cachedAt": "2026-10-21T02:26:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/253/products",
    "sha256": "cb59df389d4dfdbe29e6d1e18ff5f3333a13151b9b2fb7499e44667369679763",
    "cachedAt": "2026-10-21T02:26:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/253/prices",
    "sha256": "345b8851954c2da30c43c38c3f5e85f60d7de3b3c7c72db8a910467e2065c1aa",
    "cachedAt": "2026-10-21T02:26:16+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22883/products",
    "sha256": "b668cf883c84063cfe37b6ddbd8fc1f9e822737234e1f8a4b10240e4b4f4980c",
    "cachedAt": "2026-10-21T02:26:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/22883/prices",
    "sha256": "4e4d9f0bda5e5b0d86e14b730a75095624524ff1c335686ccfa2fe0514de55d8",
    "cachedAt": "2026-10-21T02:26:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/202/products",
    "sha256": "d875db82ecba3225bac2cc9af59bd1f3132cf4cf849687efa12cff049180ceab",
    "cachedAt": "2026-10-21T02:26:17+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/202/prices",
    "sha256": "4b100e6161055a8976c57a3b78af6cb2ab1a455565be23cbe9517b9182787b81",
    "cachedAt": "2026-10-21T02:26:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1341/products",
    "sha256": "242be4414181544cb1701493d607f629d3ddf7e6ab82944a26fb7d6561d2ca09",
    "cachedAt": "2026-10-21T02:26:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1341/prices",
    "sha256": "a1e25ce96e88a9a030608cd13cc1f8dbed24bfd8862e8f14ce0c15eea6d7a2e0",
    "cachedAt": "2026-10-21T02:26:18+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1313/products",
    "sha256": "f8b3c66ba028d75fbc4fdf73577ea08867f63ed693dc449ab5d81a7d7a483315",
    "cachedAt": "2026-10-21T02:26:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1313/prices",
    "sha256": "cdbd87df67f7d925f79c5b90b7455b4afb80506ba3fc65ff0663f53f2aa85d86",
    "cachedAt": "2026-10-21T02:26:19+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/334/products",
    "sha256": "96c894e6160d42371db80a9b668dcc917b3fd237d41e23376d1f72467401a8f8",
    "cachedAt": "2026-10-21T02:26:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/334/prices",
    "sha256": "da02b316002bcb9702ebca2aa91946d1a3faa10bfc44f48f637ab5bac8215e6c",
    "cachedAt": "2026-10-21T02:26:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/249/products",
    "sha256": "8d5049ddcc757b8e4bd42ef851bf0455ae2cafe7f8db2749151511f0ed913aae",
    "cachedAt": "2026-10-21T02:26:20+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/249/prices",
    "sha256": "53517b13f9d1559b3adf3d6a780e0f3d4d2d27919a44dcf8e4d859c0f860bda6",
    "cachedAt": "2026-10-21T02:26:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1819/products",
    "sha256": "97aba6f0d5b255b0312136cb4784ef35e8649952a6408ea0a3dc2d90a7b8c2f6",
    "cachedAt": "2026-10-21T02:26:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1819/prices",
    "sha256": "48159afb1808ec6af4715790344e125915462b74eed7429f42255aaaefb37db6",
    "cachedAt": "2026-10-21T02:26:21+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/333/products",
    "sha256": "35c27c8e5f6c91e33d91032054a682829120c82653ae5454cb8eeab19670e084",
    "cachedAt": "2026-10-21T02:26:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/333/prices",
    "sha256": "ce45a08e6b3c74471f1e8ea168e80f03d3f288ce36618e5231f6f92edb9026a9",
    "cachedAt": "2026-10-21T02:26:22+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/294/products",
    "sha256": "9cef7f5b988288dee0dd5a1864d0777c5c5df2801f5979aabd90a4f64c34bbc1",
    "cachedAt": "2026-10-21T02:26:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/294/prices",
    "sha256": "9fb4ce1affd5e560663ace93114fa0cb2aa0b3d0029f590b825df0c9b175eeb1",
    "cachedAt": "2026-10-21T02:26:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/298/products",
    "sha256": "e824883dc833dbfdce07e00cbe15dd2a948a811fc5f7e4fc0c34fa71f307e7b3",
    "cachedAt": "2026-10-21T02:26:23+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/298/prices",
    "sha256": "015bdace1c8a139153c8dacc55cb608fec91a004163e46200d2f7f0a8dc3b4c3",
    "cachedAt": "2026-10-21T02:26:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/207/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/207/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:24+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/166/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/166/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/330/products",
    "sha256": "57d9a01c22c0223fe49bff4c30fb3bda9415fd40885e39b228008bb78cbed23c",
    "cachedAt": "2026-10-21T02:26:25+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/330/prices",
    "sha256": "9b3534786f28467d0c753e7d2c3784c29ea88c00fac302f929e6b704b56974a5",
    "cachedAt": "2026-10-21T02:26:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/180/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:26+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/180/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/181/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/181/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:27+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/187/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/187/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1301/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:28+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1301/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/206/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/206/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:29+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/221/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/221/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/240/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:30+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/240/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/242/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:31+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/242/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23984/products",
    "sha256": "57f85e2b247731077548b138b97827c48be8e2400d4cdc68e565d2f110c7bffd",
    "cachedAt": "2026-10-21T02:26:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/23984/prices",
    "sha256": "4a178a3d824c94f20927e11b2ab791ddb519f4703eefacd3b5aef584d2fb916a",
    "cachedAt": "2026-10-21T02:26:32+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/246/products",
    "sha256": "6935aabb4710a3d907ff951d122cdd2ec9fbf448a5105cdc26a41f9e2044928e",
    "cachedAt": "2026-10-21T02:26:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/246/prices",
    "sha256": "f867e5b2efacccba6194a7d033a3a0b3317c79fd571a0dff3befd692a4fbecae",
    "cachedAt": "2026-10-21T02:26:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1342/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:33+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1342/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/331/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/331/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:34+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1318/products",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1318/prices",
    "sha256": "358d666e27b62a22b30bd0b958b8802a650f42a0defdd3e568f3c8e26a7637ad",
    "cachedAt": "2026-10-21T02:26:35+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2197/products",
    "sha256": "90bea9a1eeaa7904b6cab1fe1aacda3acfee0f85cbd55d131c4a8fd6da824693",
    "cachedAt": "2026-10-21T02:26:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2197/prices",
    "sha256": "415832fa4cd6dc9d0f8956407e6c74fd018410d7ebaca9a3480fcd6752480444",
    "cachedAt": "2026-10-21T02:26:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2215/products",
    "sha256": "fd6c5b521b4e3d3ebbc484f48d01ad288d6f0b661743fcd57b7aed41e7577a82",
    "cachedAt": "2026-10-21T02:26:36+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2215/prices",
    "sha256": "6b426308177bb5c218642ba8dfe3da7058b271a546cfc451099e69e6a6e4fefc",
    "cachedAt": "2026-10-21T02:26:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2196/products",
    "sha256": "c856805c7ee3028f88fcd9274381d2e3b8ab73b6bcc82563bc3d809a9125a6a2",
    "cachedAt": "2026-10-21T02:26:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2196/prices",
    "sha256": "b0b9b057cc354e630b836ab215b0071cc26392d54ba949954d754c250303c4c9",
    "cachedAt": "2026-10-21T02:26:37+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2353/products",
    "sha256": "1b3e954bab3e04895e9811094ab5d7ab23dfd08f0ea751febd5d854f7501f264",
    "cachedAt": "2026-10-21T02:26:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/2353/prices",
    "sha256": "d33674412a12962c3eed71f907b9241bd984fe106ac07c1514bade1684c7188a",
    "cachedAt": "2026-10-21T02:26:38+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1921/products",
    "sha256": "01d81170b45356c628daee766a9fa8a87719dfd157d1ce266b044e8b3bcd56f6",
    "cachedAt": "2026-10-21T02:26:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://tcgcsv.com/tcgplayer/2/1921/prices",
    "sha256": "e600c059bbceddb990f2f71aad07c19f83f7c48fcf13efe361a43b53a3a104cd",
    "cachedAt": "2026-10-21T02:26:39+00:00",
    "sourceUpdatedAt": null
  },
  {
    "url": "https://db.ygoprodeck.com/api/v7/cardinfo.php?misc=yes",
    "sha256": "e276b59b36c34d9f2a4c26db6460c62a3997805e02a3e8e3bf8e785f3b0181ea",
    "cachedAt": "2026-10-21T02:26:40+00:00",
    "sourceUpdatedAt": null
  }
]
```
