import Foundation

/// The system iCloud account state used by the collection-storage policy.
///
/// The fingerprint is an opaque, device-local hash. It is deliberately not a
/// CloudKit record name or any other account identifier that could identify a
/// person outside the device.
enum CloudAccountAvailability: Equatable, Sendable {
    case available(fingerprint: String)
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
}

enum StoreMigrationState: String, Codable, Equatable, Sendable {
    case notStarted
    case copying
    case validating
    case committed
}

enum CloudAttachmentState: String, Codable, Equatable, Sendable {
    case neverAttached
    case attached
    case suspended
    case conflict
}

struct CloudRestoreCheckpoint: Codable, Equatable, Sendable {
    var storeID: UUID
    var accountFingerprint: String
    var storeFileIdentity: String
    var mechanismVersion: Int
    var readiness: CloudRestoreCheckpointReadiness
    var confirmedAt: Date

    init(
        storeID: UUID,
        accountFingerprint: String,
        storeFileIdentity: String,
        mechanismVersion: Int,
        readiness: CloudRestoreCheckpointReadiness = .unknown,
        confirmedAt: Date
    ) {
        self.storeID = storeID
        self.accountFingerprint = accountFingerprint
        self.storeFileIdentity = storeFileIdentity
        self.mechanismVersion = mechanismVersion
        self.readiness = readiness
        self.confirmedAt = confirmedAt
    }

    private enum CodingKeys: String, CodingKey {
        case storeID
        case accountFingerprint
        case storeFileIdentity
        case mechanismVersion
        case readiness
        case confirmedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        storeID = try values.decode(UUID.self, forKey: .storeID)
        accountFingerprint = try values.decode(String.self, forKey: .accountFingerprint)
        storeFileIdentity = try values.decode(String.self, forKey: .storeFileIdentity)
        mechanismVersion = try values.decode(Int.self, forKey: .mechanismVersion)
        // Older checkpoints remain readable but cannot authorize readiness
        // because they do not record whether the proven remote state was empty.
        readiness = try values.decodeIfPresent(
            CloudRestoreCheckpointReadiness.self,
            forKey: .readiness
        ) ?? .unknown
        confirmedAt = try values.decode(Date.self, forKey: .confirmedAt)
    }
}

enum CloudRestoreCheckpointReadiness: String, Codable, Equatable, Sendable {
    case unknown
    case empty
    case populated
}

enum CollectionStoreIdentityStatus: Equatable, Sendable {
    case matching
    case missing
    case mismatched
}

/// Durable metadata for the one local collection identity.
///
/// `storeFileIdentity` is an opaque local token, not a path, inode, content
/// digest, or CloudKit identifier. It is optional at decode time so manifests
/// written by the first implementation can be upgraded without inventing a
/// new collection identity.
struct CollectionStoreManifest: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var storeID: UUID
    var storeFileIdentity: String
    var lastAttachedAccountFingerprint: String?
    var attachmentState: CloudAttachmentState
    var migrationState: StoreMigrationState
    var cloudRestoreCheckpoint: CloudRestoreCheckpoint?

    init(
        formatVersion: Int = CollectionStoreManifest.currentFormatVersion,
        storeID: UUID,
        lastAttachedAccountFingerprint: String? = nil,
        attachmentState: CloudAttachmentState = .neverAttached,
        migrationState: StoreMigrationState = .notStarted,
        cloudRestoreCheckpoint: CloudRestoreCheckpoint? = nil,
        storeFileIdentity: String = ""
    ) {
        self.formatVersion = formatVersion
        self.storeID = storeID
        self.storeFileIdentity = storeFileIdentity
        self.lastAttachedAccountFingerprint = lastAttachedAccountFingerprint
        self.attachmentState = attachmentState
        self.migrationState = migrationState
        self.cloudRestoreCheckpoint = cloudRestoreCheckpoint
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case storeID
        case storeFileIdentity
        case lastAttachedAccountFingerprint
        case attachmentState
        case migrationState
        case cloudRestoreCheckpoint
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        storeID = try values.decode(UUID.self, forKey: .storeID)
        // The first manifest revision did not carry this sidecar identity.
        // Decode that revision without minting a new collection identity; the
        // manifest store fills the opaque file token before the next write.
        storeFileIdentity = try values.decodeIfPresent(String.self, forKey: .storeFileIdentity) ?? ""
        lastAttachedAccountFingerprint = try values.decodeIfPresent(String.self, forKey: .lastAttachedAccountFingerprint)
        attachmentState = try values.decodeIfPresent(CloudAttachmentState.self, forKey: .attachmentState) ?? .neverAttached
        migrationState = try values.decodeIfPresent(StoreMigrationState.self, forKey: .migrationState) ?? .notStarted
        cloudRestoreCheckpoint = try values.decodeIfPresent(CloudRestoreCheckpoint.self, forKey: .cloudRestoreCheckpoint)
    }
}

struct CloudCollectionAnchor: Equatable, Sendable {
    var storeID: UUID
    var formatVersion: Int
}

enum LocalStorageReason: String, Equatable, Sendable {
    case noAccount
    case restricted
    case temporarilyUnavailable
    case attachmentSuspended
}

enum CollectionStorageDecision: Equatable, Sendable {
    case openCloud(storeID: UUID, accountFingerprint: String)
    case openProvenLocal(storeID: UUID, reason: LocalStorageReason)
    case requireAttachmentConfirmation(storeID: UUID, newAccountFingerprint: String)
    case adoptRemoteCollection(storeID: UUID, accountFingerprint: String)
    case restoreMissingLocalReplica(storeID: UUID, accountFingerprint: String)
    case claimCloudAnchor(storeID: UUID, accountFingerprint: String)
    case blockDifferentRemoteCollection(localStoreID: UUID, remoteStoreID: UUID)
    case retryAccountCheck
    case blockUnprovenTransition
}

/// Explicit local facts supplied to the policy after a store probe.
///
/// A zero-row SwiftData fetch is intentionally not represented as a freshness
/// signal. `structuredStoreFilePresent`, `manifest`, and `localHasUserData`
/// are independent facts so an in-flight cloud import cannot look like a new
/// installation.
struct CollectionStorageLocalFacts: Equatable, Sendable {
    var manifest: CollectionStoreManifest?
    var manifestIsCorrupt: Bool
    var structuredStoreFilePresent: Bool
    var structuredStoreBaseFilePresent: Bool
    var localHasUserData: Bool
    var proposedFreshStoreID: UUID?
    var storeFileIdentityStatus: CollectionStoreIdentityStatus
    var localOnlyTransitionProven: Bool

    init(
        manifest: CollectionStoreManifest? = nil,
        manifestIsCorrupt: Bool = false,
        structuredStoreFilePresent: Bool,
        structuredStoreBaseFilePresent: Bool? = nil,
        localHasUserData: Bool,
        proposedFreshStoreID: UUID? = nil,
        storeFileIdentityStatus: CollectionStoreIdentityStatus = .matching,
        localOnlyTransitionProven: Bool = true
    ) {
        self.manifest = manifest
        self.manifestIsCorrupt = manifestIsCorrupt
        self.structuredStoreFilePresent = structuredStoreFilePresent
        self.structuredStoreBaseFilePresent = structuredStoreBaseFilePresent ?? structuredStoreFilePresent
        self.localHasUserData = localHasUserData
        self.proposedFreshStoreID = proposedFreshStoreID
        self.storeFileIdentityStatus = storeFileIdentityStatus
        self.localOnlyTransitionProven = localOnlyTransitionProven
    }

    var hasDurableLocalPresence: Bool {
        manifest != nil || manifestIsCorrupt || structuredStoreFilePresent || localHasUserData
    }

    var isGenuinelyFresh: Bool {
        !hasDurableLocalPresence && proposedFreshStoreID != nil
    }

    var hasUnverifiedStore: Bool {
        guard manifest != nil else { return false }
        return !structuredStoreBaseFilePresent || storeFileIdentityStatus != .matching
    }
}

/// Result of the private anchor read. Errors are never represented as
/// `.missing`; treating an unavailable database as an empty account would
/// authorize an unsafe upload.
enum CloudCollectionAnchorState: Equatable, Sendable {
    case unknown
    case missing
    case found(CloudCollectionAnchor)
    case temporarilyUnavailable
    case malformed
}

struct CollectionStoragePolicyInput: Equatable, Sendable {
    var local: CollectionStorageLocalFacts
    var account: CloudAccountAvailability
    var anchor: CloudCollectionAnchorState
    var confirmationAccepted: Bool
    var localOnlyTransitionProven: Bool

    init(
        local: CollectionStorageLocalFacts,
        account: CloudAccountAvailability,
        anchor: CloudCollectionAnchorState = .unknown,
        confirmationAccepted: Bool = false,
        localOnlyTransitionProven: Bool = true
    ) {
        self.local = local
        self.account = account
        self.anchor = anchor
        self.confirmationAccepted = confirmationAccepted
        self.localOnlyTransitionProven = localOnlyTransitionProven
    }
}

enum CollectionStoragePolicy {
    /// Decide which next storage action is safe. This function has no I/O and
    /// never generates a UUID; the caller supplies `proposedFreshStoreID` only
    /// after proving that no store, manifest, or local user data exists.
    static func decide(_ input: CollectionStoragePolicyInput) -> CollectionStorageDecision {
        let local = input.local

        // Existing bytes without trustworthy metadata are recoverable data,
        // not a fresh install. Never mint a replacement identity here.
        guard !local.manifestIsCorrupt else { return .blockUnprovenTransition }
        if local.manifest == nil && local.hasDurableLocalPresence {
            return .blockUnprovenTransition
        }
        if local.hasUnverifiedStore {
            return decideMissingLocalReplica(input)
        }

        if local.isGenuinelyFresh {
            return decideFresh(input)
        }

        guard let manifest = local.manifest else {
            // This is reachable only when the caller did not provide a fresh
            // identity. Waiting is safer than choosing a new one implicitly.
            return .blockUnprovenTransition
        }

        let storeID = manifest.storeID
        switch input.account {
        case let .available(fingerprint):
            if manifest.lastAttachedAccountFingerprint == fingerprint {
                return decideForKnownAccount(
                    input.anchor,
                    storeID: storeID,
                    accountFingerprint: fingerprint
                )
            }

            // A new account may not receive existing local data implicitly.
            // A remote collection that is already different is a hard conflict
            // even if the user has not yet seen the confirmation affordance.
            switch input.anchor {
            case .unknown, .temporarilyUnavailable, .malformed:
                return input.confirmationAccepted
                    ? .blockUnprovenTransition
                    : .retryAccountCheck
            case .missing:
                guard input.confirmationAccepted else {
                    return .requireAttachmentConfirmation(
                        storeID: storeID,
                        newAccountFingerprint: fingerprint
                    )
                }
                return .claimCloudAnchor(storeID: storeID, accountFingerprint: fingerprint)
            case let .found(anchor):
                guard anchor.storeID == storeID else {
                    return .blockDifferentRemoteCollection(
                        localStoreID: storeID,
                        remoteStoreID: anchor.storeID
                    )
                }
                guard input.confirmationAccepted else {
                    return .requireAttachmentConfirmation(
                        storeID: storeID,
                        newAccountFingerprint: fingerprint
                    )
                }
                return .openCloud(storeID: storeID, accountFingerprint: fingerprint)
            }

        case .noAccount:
            guard input.localOnlyTransitionProven else { return .blockUnprovenTransition }
            return .openProvenLocal(storeID: storeID, reason: .noAccount)
        case .restricted:
            guard input.localOnlyTransitionProven else { return .blockUnprovenTransition }
            return .openProvenLocal(storeID: storeID, reason: .restricted)
        case .temporarilyUnavailable, .couldNotDetermine:
            // A previously opened local replica may remain usable, but it must
            // remain visibly unverified rather than being treated as a cloud
            // transition or a fresh empty collection.
            guard input.localOnlyTransitionProven else { return .blockUnprovenTransition }
            return .openProvenLocal(storeID: storeID, reason: .temporarilyUnavailable)
        }
    }

    /// Convenience overload for callers whose anchor lookup has already
    /// proven that an absent value means “record not found.”
    static func decide(
        local: CollectionStorageLocalFacts,
        account: CloudAccountAvailability,
        remoteAnchor: CloudCollectionAnchor?,
        confirmationAccepted: Bool = false
    ) -> CollectionStorageDecision {
        decide(
            CollectionStoragePolicyInput(
                local: local,
                account: account,
                anchor: remoteAnchor.map(CloudCollectionAnchorState.found) ?? .missing,
                confirmationAccepted: confirmationAccepted
            )
        )
    }

    static func acceptsRestoreCheckpoint(
        _ checkpoint: CloudRestoreCheckpoint?,
        storeID: UUID,
        accountFingerprint: String,
        storeFileIdentity: String,
        mechanismVersion: Int
    ) -> Bool {
        guard let checkpoint else { return false }
        return checkpoint.storeID == storeID
            && checkpoint.accountFingerprint == accountFingerprint
            && checkpoint.storeFileIdentity == storeFileIdentity
            && checkpoint.mechanismVersion == mechanismVersion
            && checkpoint.readiness != .unknown
    }

    private static func decideFresh(
        _ input: CollectionStoragePolicyInput
    ) -> CollectionStorageDecision {
        guard let freshStoreID = input.local.proposedFreshStoreID else {
            return .blockUnprovenTransition
        }

        switch input.account {
        case let .available(fingerprint):
            switch input.anchor {
            case .missing:
                return .openCloud(storeID: freshStoreID, accountFingerprint: fingerprint)
            case let .found(anchor):
                return .adoptRemoteCollection(
                    storeID: anchor.storeID,
                    accountFingerprint: fingerprint
                )
            case .unknown, .temporarilyUnavailable, .malformed:
                return .retryAccountCheck
            }
        case .noAccount, .restricted:
            guard input.localOnlyTransitionProven else { return .blockUnprovenTransition }
            return .openProvenLocal(
                storeID: freshStoreID,
                reason: input.account == .noAccount ? .noAccount : .restricted
            )
        case .temporarilyUnavailable, .couldNotDetermine:
            // Do not mint a local identity while the system account answer is
            // transient. The caller can retry with the same proposed ID.
            return .retryAccountCheck
        }
    }

    private static func decideForKnownAccount(
        _ anchor: CloudCollectionAnchorState,
        storeID: UUID,
        accountFingerprint: String
    ) -> CollectionStorageDecision {
        switch anchor {
        case .missing:
            return .claimCloudAnchor(
                storeID: storeID,
                accountFingerprint: accountFingerprint
            )
        case let .found(remote) where remote.storeID == storeID:
            return .openCloud(storeID: storeID, accountFingerprint: accountFingerprint)
        case let .found(remote):
            return .blockDifferentRemoteCollection(
                localStoreID: storeID,
                remoteStoreID: remote.storeID
            )
        case .unknown, .temporarilyUnavailable, .malformed:
            return .retryAccountCheck
        }
    }

    private static func decideMissingLocalReplica(
        _ input: CollectionStoragePolicyInput
    ) -> CollectionStorageDecision {
        guard let manifest = input.local.manifest else {
            return .blockUnprovenTransition
        }

        switch input.account {
        case let .available(fingerprint):
            switch input.anchor {
            case let .found(anchor) where anchor.storeID == manifest.storeID:
                return .restoreMissingLocalReplica(
                    storeID: manifest.storeID,
                    accountFingerprint: fingerprint
                )
            case let .found(anchor):
                return .blockDifferentRemoteCollection(
                    localStoreID: manifest.storeID,
                    remoteStoreID: anchor.storeID
                )
            case .unknown, .temporarilyUnavailable, .malformed:
                return .retryAccountCheck
            case .missing:
                return .blockUnprovenTransition
            }
        case .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine:
            return .blockUnprovenTransition
        }
    }
}
