# PRB02 unsigned revision 5

The hosted production revision 4 is the signed OP18 discovery candidate. This
candidate applies the 265 PRB02 mappings from the separate revision-3-based
candidate on top of that signed revision 4. It preserves OP18 discovery,
physical identities and existing mappings. The retained predecessor envelope
was verified against the app's production pin; its payload is byte-identical
to `production/revision-4/candidate.json`.

The mapping-only preparer used the retained group 24305 capture in
`../prb02-mapping-candidate/capture` with `--baseline-revision 4`. The publisher
validated these registry, observations and inventories inputs against the signed
predecessor's decoded payload. The gap report retains the 24 unresolved cases.
This is unsigned and requires separate signing and publication approvals.
