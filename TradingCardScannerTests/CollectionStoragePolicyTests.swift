import XCTest
@testable import TradingCardScanner

final class CollectionStoragePolicyTests: XCTestCase {
    private let localStoreID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let remoteStoreID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func anchor(_ storeID: UUID, generation: String = "generation-a") -> CloudCollectionAnchor {
        CloudCollectionAnchor(
            storeID: storeID,
            formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
            remoteGeneration: generation
        )
    }

    private func fresh(_ proposedID: UUID? = nil) -> CollectionStorageLocalFacts {
        CollectionStorageLocalFacts(
            structuredStoreFilePresent: false,
            localHasUserData: false,
            proposedFreshStoreID: proposedID ?? localStoreID
        )
    }

    private func existing(
        attachedTo account: String? = "account-a",
        localHasUserData: Bool = true,
        storeID: UUID? = nil
    ) -> CollectionStorageLocalFacts {
        CollectionStorageLocalFacts(
            manifest: CollectionStoreManifest(
                storeID: storeID ?? localStoreID,
                lastAttachedAccountFingerprint: account,
                attachmentState: account == nil ? .neverAttached : .attached
            ),
            structuredStoreFilePresent: true,
            localHasUserData: localHasUserData
        )
    }

    func testFreshInstallWithNoAccountCreatesOneProvenLocalIdentity() {
        let decision = CollectionStoragePolicy.decide(
            CollectionStoragePolicyInput(
                local: fresh(),
                account: .noAccount,
                anchor: .missing
            )
        )
        XCTAssertEqual(
            decision,
            .openProvenLocal(storeID: localStoreID, reason: .noAccount)
        )
    }

    func testFreshEmptyInstallWithAvailableAccountAndNoAnchorOpensWithoutConfirmation() {
        let decision = CollectionStoragePolicy.decide(
            CollectionStoragePolicyInput(
                local: fresh(),
                account: .available(fingerprint: "account-a"),
                anchor: .missing
            )
        )
        XCTAssertEqual(
            decision,
            .openCloud(storeID: localStoreID, accountFingerprint: "account-a")
        )
    }

    func testFreshEmptyInstallWithRemoteAnchorAdoptsRemoteIdentity() {
        let decision = CollectionStoragePolicy.decide(
            CollectionStoragePolicyInput(
                local: fresh(),
                account: .available(fingerprint: "account-a"),
                anchor: .found(anchor(remoteStoreID))
            )
        )
        XCTAssertEqual(
            decision,
            .adoptRemoteCollection(storeID: remoteStoreID, accountFingerprint: "account-a")
        )
    }

    func testSameAccountAndMatchingAnchorOpensCloud() {
        let decision = CollectionStoragePolicy.decide(
            CollectionStoragePolicyInput(
                local: existing(),
                account: .available(fingerprint: "account-a"),
                anchor: .found(anchor(localStoreID))
            )
        )
        XCTAssertEqual(
            decision,
            .openCloud(storeID: localStoreID, accountFingerprint: "account-a")
        )
    }

    func testSameAccountAndMissingAnchorRequiresSafeClaimWithoutMintingIdentity() {
        let decision = CollectionStoragePolicy.decide(
            CollectionStoragePolicyInput(
                local: existing(),
                account: .available(fingerprint: "account-a"),
                anchor: .missing
            )
        )
        XCTAssertEqual(
            decision,
            .claimCloudAnchor(storeID: localStoreID, accountFingerprint: "account-a")
        )
    }

    func testExistingNonemptyCollectionAndNewEmptyAccountRequiresConfirmation() {
        let local = existing(attachedTo: nil)
        let decision = CollectionStoragePolicy.decide(
            CollectionStoragePolicyInput(
                local: local,
                account: .available(fingerprint: "account-b"),
                anchor: .missing
            )
        )
        XCTAssertEqual(
            decision,
            .requireAttachmentConfirmation(storeID: localStoreID, newAccountFingerprint: "account-b")
        )
    }

    func testExistingCollectionAndDifferentRemoteAnchorBlocksAutomaticMerge() {
        let decision = CollectionStoragePolicy.decide(
            CollectionStoragePolicyInput(
                local: existing(),
                account: .available(fingerprint: "account-b"),
                anchor: .found(anchor(remoteStoreID))
            )
        )
        XCTAssertEqual(
            decision,
            .blockDifferentRemoteCollection(
                localStoreID: localStoreID,
                remoteStoreID: remoteStoreID
            )
        )
    }

    func testUnsupportedRemoteAnchorFailsClosedBeforeOpeningAStore() {
        let anchors = [
            CloudCollectionAnchor(
                storeID: localStoreID,
                formatVersion: CloudCollectionAnchorSchema.currentFormatVersion - 1,
                remoteGeneration: "generation-a"
            ),
            CloudCollectionAnchor(
                storeID: localStoreID,
                formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                remoteGeneration: nil
            )
        ]

        for anchor in anchors {
            XCTAssertEqual(
                CollectionStoragePolicy.decide(
                    CollectionStoragePolicyInput(
                        local: existing(),
                        account: .available(fingerprint: "account-a"),
                        anchor: .found(anchor)
                    )
                ),
                .retryAccountCheck
            )
        }
    }

    func testTemporaryAccountStatesUseProvenLocalPathForExistingStore() {
        for account in [
            CloudAccountAvailability.temporarilyUnavailable,
            .couldNotDetermine
        ] {
            let decision = CollectionStoragePolicy.decide(
                CollectionStoragePolicyInput(
                    local: existing(),
                    account: account,
                    anchor: .unknown
                )
            )
            XCTAssertEqual(
                decision,
                .openProvenLocal(storeID: localStoreID, reason: .temporarilyUnavailable)
            )
        }
    }

    func testRestrictedAndNoAccountUseProvenLocalPath() {
        XCTAssertEqual(
            CollectionStoragePolicy.decide(
                CollectionStoragePolicyInput(
                    local: existing(),
                    account: .restricted,
                    anchor: .unknown
                )
            ),
            .openProvenLocal(storeID: localStoreID, reason: .restricted)
        )
        XCTAssertEqual(
            CollectionStoragePolicy.decide(
                CollectionStoragePolicyInput(
                    local: existing(),
                    account: .noAccount,
                    anchor: .unknown
                )
            ),
            .openProvenLocal(storeID: localStoreID, reason: .noAccount)
        )
    }

    func testMissingOrCorruptManifestBesideStoreBlocksRecovery() {
        let missingManifest = CollectionStorageLocalFacts(
            structuredStoreFilePresent: true,
            localHasUserData: true
        )
        XCTAssertEqual(
            CollectionStoragePolicy.decide(
                CollectionStoragePolicyInput(
                    local: missingManifest,
                    account: .available(fingerprint: "account-a"),
                    anchor: .missing
                )
            ),
            .blockUnprovenTransition
        )

        let corruptManifest = CollectionStorageLocalFacts(
            manifestIsCorrupt: true,
            structuredStoreFilePresent: true,
            localHasUserData: true,
            proposedFreshStoreID: UUID()
        )
        XCTAssertEqual(
            CollectionStoragePolicy.decide(
                CollectionStoragePolicyInput(
                    local: corruptManifest,
                    account: .noAccount,
                    anchor: .unknown
                )
            ),
            .blockUnprovenTransition
        )
    }

    func testConfirmedAttachmentToEmptyNewAccountClaimsExistingIdentityBeforeOpen() {
        let local = existing(attachedTo: nil)
        let decision = CollectionStoragePolicy.decide(
            CollectionStoragePolicyInput(
                local: local,
                account: .available(fingerprint: "account-b"),
                anchor: .missing,
                confirmationAccepted: true
            )
        )
        XCTAssertEqual(
            decision,
            .claimCloudAnchor(storeID: localStoreID, accountFingerprint: "account-b")
        )
    }

    func testCanceledConfirmationPreservesLocalIdentityAndDoesNotOpenCloud() {
        let local = existing(attachedTo: nil)
        let decision = CollectionStoragePolicy.decide(
            CollectionStoragePolicyInput(
                local: local,
                account: .available(fingerprint: "account-b"),
                anchor: .missing,
                confirmationAccepted: false
            )
        )
        XCTAssertEqual(
            decision,
            .requireAttachmentConfirmation(storeID: localStoreID, newAccountFingerprint: "account-b")
        )
    }

    func testZeroFetchedRowsWithExistingStoreAndManifestIsNotFresh() {
        let local = existing(localHasUserData: false)
        XCTAssertFalse(local.isGenuinelyFresh)
        XCTAssertEqual(
            CollectionStoragePolicy.decide(
                CollectionStoragePolicyInput(
                    local: local,
                    account: .available(fingerprint: "account-a"),
                    anchor: .missing
                )
            ),
            .claimCloudAnchor(storeID: localStoreID, accountFingerprint: "account-a")
        )
    }

    func testTransientFreshAccountStateNeverMintsOrAttaches() {
        for account in [
            CloudAccountAvailability.temporarilyUnavailable,
            .couldNotDetermine
        ] {
            XCTAssertEqual(
                CollectionStoragePolicy.decide(
                    CollectionStoragePolicyInput(
                        local: fresh(),
                        account: account,
                        anchor: .missing
                    )
                ),
                .retryAccountCheck
            )
        }
    }

    func testRestoreCheckpointRequiresEveryIdentityComponentToMatch() {
        let checkpoint = CloudRestoreCheckpoint(
            storeID: localStoreID,
            accountFingerprint: "account-a",
            storeFileIdentity: "file-a",
            mechanismVersion: 1,
            readiness: .populated,
            remoteGeneration: "generation-a",
            confirmedAt: Date(timeIntervalSince1970: 100)
        )
        XCTAssertTrue(
            CollectionStoragePolicy.acceptsRestoreCheckpoint(
                checkpoint,
                storeID: localStoreID,
                accountFingerprint: "account-a",
                storeFileIdentity: "file-a",
                mechanismVersion: 1,
                currentRemoteGeneration: "generation-a"
            )
        )
        XCTAssertFalse(
            CollectionStoragePolicy.acceptsRestoreCheckpoint(
                checkpoint,
                storeID: remoteStoreID,
                accountFingerprint: "account-a",
                storeFileIdentity: "file-a",
                mechanismVersion: 1
            )
        )
        XCTAssertFalse(
            CollectionStoragePolicy.acceptsRestoreCheckpoint(
                checkpoint,
                storeID: localStoreID,
                accountFingerprint: "account-b",
                storeFileIdentity: "file-a",
                mechanismVersion: 1
            )
        )
        XCTAssertFalse(
            CollectionStoragePolicy.acceptsRestoreCheckpoint(
                checkpoint,
                storeID: localStoreID,
                accountFingerprint: "account-a",
                storeFileIdentity: "file-b",
                mechanismVersion: 1
            )
        )
        XCTAssertFalse(
            CollectionStoragePolicy.acceptsRestoreCheckpoint(
                checkpoint,
                storeID: localStoreID,
                accountFingerprint: "account-a",
                storeFileIdentity: "file-a",
                mechanismVersion: 2,
                currentRemoteGeneration: "generation-a"
            )
        )
        XCTAssertFalse(
            CollectionStoragePolicy.acceptsRestoreCheckpoint(
                checkpoint,
                storeID: localStoreID,
                accountFingerprint: "account-a",
                storeFileIdentity: "file-a",
                mechanismVersion: 1,
                currentRemoteGeneration: "generation-b"
            )
        )
    }

    func testEmptyRestoreCheckpointNeverAuthorizesStartupEvenWhenGenerationMatches() {
        let checkpoint = CloudRestoreCheckpoint(
            storeID: localStoreID,
            accountFingerprint: "account-a",
            storeFileIdentity: "file-a",
            mechanismVersion: CloudRestorationReadinessContract.currentMechanismVersion,
            readiness: .empty,
            remoteGeneration: "generation-a",
            confirmedAt: .now
        )
        XCTAssertFalse(
            CollectionStoragePolicy.acceptsRestoreCheckpoint(
                checkpoint,
                storeID: localStoreID,
                accountFingerprint: "account-a",
                storeFileIdentity: "file-a",
                mechanismVersion: CloudRestorationReadinessContract.currentMechanismVersion,
                currentRemoteGeneration: "generation-a"
            )
        )
    }

    func testManifestWithoutVerifiedStoreCannotOpenReplacementWithoutCloudProof() {
        let local = CollectionStorageLocalFacts(
            manifest: CollectionStoreManifest(
                storeID: localStoreID,
                lastAttachedAccountFingerprint: "account-a",
                attachmentState: .attached,
                storeFileIdentity: "file-a"
            ),
            structuredStoreFilePresent: false,
            localHasUserData: false,
            storeFileIdentityStatus: .missing
        )
        XCTAssertEqual(
            CollectionStoragePolicy.decide(
                CollectionStoragePolicyInput(
                    local: local,
                    account: .noAccount,
                    anchor: .unknown
                )
            ),
            .blockUnprovenTransition
        )
        XCTAssertEqual(
            CollectionStoragePolicy.decide(
                CollectionStoragePolicyInput(
                    local: local,
                    account: .available(fingerprint: "account-a"),
                    anchor: .found(anchor(localStoreID))
                )
            ),
            .restoreMissingLocalReplica(
                storeID: localStoreID,
                accountFingerprint: "account-a"
            )
        )
    }

    func testLocalAvailabilityPathsOpenFreshOrExistingStore() {
        for local in [fresh(), existing()] {
            XCTAssertEqual(
                CollectionStoragePolicy.decide(
                    CollectionStoragePolicyInput(
                        local: local,
                        account: .noAccount,
                        anchor: .unknown
                    )
                ),
                .openProvenLocal(storeID: localStoreID, reason: .noAccount)
            )
        }
    }

    func testPolicyDescriptionsDoNotContainRawAccountRecordNames() {
        let rawRecordName = "private-user-record-name-123"
        let availability = CloudAccountAvailability.available(fingerprint: "opaque-fingerprint")
        XCTAssertFalse(String(describing: availability).contains(rawRecordName))
        XCTAssertFalse(String(describing: CollectionStoragePolicy.decide(
            CollectionStoragePolicyInput(
                local: existing(attachedTo: nil),
                account: availability,
                anchor: .missing
            )
        )).contains(rawRecordName))
    }
}
