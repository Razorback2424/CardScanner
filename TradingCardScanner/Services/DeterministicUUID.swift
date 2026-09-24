import CryptoKit
import Foundation

/// Stable version-3 UUIDs shared by resumable and migration operations.
enum DeterministicUUID {
    /// `namespace` is an explicit prefix, including any desired separator.
    /// Passing the namespace and material separately preserves existing IDs.
    static func make(namespace: String, material: String) -> UUID {
        var bytes = Array(Insecure.MD5.hash(data: Data((namespace + material).utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x30
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
