import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ERROR: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: validate-sparkle-key.swift SUPublicEDKey")
}

guard let expected = Data(base64Encoded: CommandLine.arguments[1]), expected.count == 32 else {
    fail("SUPublicEDKey is not valid base64")
}

let secretInput = FileHandle.standardInput.readDataToEndOfFile()
let secretString = String(decoding: secretInput, as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let secret = Data(base64Encoded: secretString) else {
    fail("Sparkle private key is not valid base64")
}

let derived: Data
do {
    switch secret.count {
    case 32:
        derived = try Curve25519.Signing.PrivateKey(rawRepresentation: secret)
            .publicKey.rawRepresentation
    case 96:
        derived = secret.suffix(32)
    default:
        fail("Sparkle private key must decode to 32 or 96 bytes")
    }
} catch {
    fail("Sparkle private key is invalid")
}

guard derived == expected else {
    fail("Sparkle private key does not match SUPublicEDKey")
}
