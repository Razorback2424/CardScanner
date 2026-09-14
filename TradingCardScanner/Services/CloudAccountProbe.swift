import CloudKit
import CryptoKit
import Foundation
import Security

protocol CloudAccountClient: Sendable {
    func accountStatus() async throws -> CKAccountStatus
    func userRecordName() async throws -> String
}
struct CloudKitAccountClient: CloudAccountClient, @unchecked Sendable {
    let container: CKContainer

    init(container: CKContainer = CKContainer(identifier: CloudAccountProbe.containerIdentifier)) {
        self.container = container
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    func userRecordName() async throws -> String {
        try await container.userRecordID().recordName
    }
}

enum CloudAccountFingerprintError: LocalizedError, Equatable {
    case keychainReadFailed
    case keychainWriteFailed
    case randomGenerationFailed

    var errorDescription: String? {
        switch self {
        case .keychainReadFailed:
            return "The local iCloud account fingerprint salt could not be read."
        case .keychainWriteFailed:
            return "The local iCloud account fingerprint salt could not be saved."
        case .randomGenerationFailed:
            return "The local iCloud account fingerprint salt could not be generated."
        }
    }
}

struct CloudAccountFingerprintSaltStore: Sendable {
    static let service = "com.seankeller.CardScanner.cloud-account-fingerprint"
    static let account = "salt"

    var service: String = CloudAccountFingerprintSaltStore.service

    func loadOrCreate() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count >= 16 {
            return data
        }
        guard status == errSecItemNotFound else {
            throw CloudAccountFingerprintError.keychainReadFailed
        }

        var salt = Data(repeating: 0, count: 32)
        guard salt.withUnsafeMutableBytes({ buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!) == errSecSuccess
        }) else {
            throw CloudAccountFingerprintError.randomGenerationFailed
        }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: salt
        ]
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw CloudAccountFingerprintError.keychainWriteFailed
        }
        if addStatus == errSecDuplicateItem {
            return try loadOrCreate()
        }
        return salt
    }
}

struct CloudAccountProbe: Sendable {
    static let containerIdentifier = "iCloud.com.seankeller.CardScanner"

    let client: any CloudAccountClient
    let fingerprintSalt: Data

    init(client: any CloudAccountClient, fingerprintSalt: Data) {
        self.client = client
        self.fingerprintSalt = fingerprintSalt
    }

    static func production(
        saltStore: CloudAccountFingerprintSaltStore = .init()
    ) throws -> Self {
        Self(
            client: CloudKitAccountClient(),
            fingerprintSalt: try saltStore.loadOrCreate()
        )
    }

    func availability() async -> CloudAccountAvailability {
        let status: CKAccountStatus
        do {
            status = try await client.accountStatus()
        } catch {
            return .couldNotDetermine
        }

        switch status {
        case .available:
            do {
                let recordName = try await client.userRecordName()
                return .available(fingerprint: Self.fingerprint(recordName: recordName, salt: fingerprintSalt))
            } catch {
                return .couldNotDetermine
            }
        case .noAccount:
            return .noAccount
        case .restricted:
            return .restricted
        case .temporarilyUnavailable:
            return .temporarilyUnavailable
        case .couldNotDetermine:
            return .couldNotDetermine
        @unknown default:
            return .couldNotDetermine
        }
    }

    static func fingerprint(recordName: String, salt: Data) -> String {
        var input = Data()
        input.append(salt)
        input.append(0)
        input.append(contentsOf: recordName.utf8)
        return SHA256.hash(data: input)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
