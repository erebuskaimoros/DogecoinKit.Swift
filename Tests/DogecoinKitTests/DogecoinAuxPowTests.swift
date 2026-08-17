import BitcoinCore
@testable import DogecoinKit
import Foundation
import XCTest

final class DogecoinAuxPowTests: XCTestCase {
    func testParsesAndValidatesDogecoinCoreCheckpoint5050000() throws {
        let header = try DogecoinBlockHeaderParser(strictChainId: true)
            .parse(byteStream: ByteStream(try fixture()))

        XCTAssertEqual(header.version, 6_422_788)
        XCTAssertEqual(
            header.headerHash.reversedData.hexString,
            "e7d4577405223918491477db725a393bcfc349d8ee63b0a4fde23cbfbfd81dea"
        )
        XCTAssertTrue(header.auxPow)
        XCTAssertTrue(header.auxPowValidated)
        XCTAssertEqual(
            header.proofOfWorkHash.hexString,
            "00000000000000d6574469fdfcf3f6f451a69302b46fe6db5049ac9c44820761"
        )
    }

    func testRejectsCorruptedChainCommitment() throws {
        var bytes = try fixture()
        let commitment = try XCTUnwrap(Data(hex: "e7d4577405223918491477db725a393bcfc349d8ee63b0a4fde23cbfbfd81dea"))
        let range = try XCTUnwrap(bytes.range(of: commitment))
        bytes[range.lowerBound] ^= 1

        XCTAssertThrowsError(
            try DogecoinBlockHeaderParser(strictChainId: true)
                .parse(byteStream: ByteStream(bytes))
        )
    }

    func testRejectsParentWithDogecoinChainId() throws {
        var bytes = try fixture()
        let parentHeaderOffset = bytes.count - 80
        bytes[parentHeaderOffset + 2] = 0x62

        XCTAssertThrowsError(
            try DogecoinBlockHeaderParser(strictChainId: true)
                .parse(byteStream: ByteStream(bytes))
        )
    }

    func testExpectedIndexUsesActualChildChainId() {
        XCTAssertEqual(DogecoinBlockHeaderParser.expectedIndex(nonce: 0, chainId: 7, height: 1), 1)
        XCTAssertEqual(DogecoinBlockHeaderParser.expectedIndex(nonce: 0, chainId: 98, height: 1), 0)
    }

    private func fixture() throws -> Data {
        try XCTUnwrap(Data(hex: Self.core5050000Header))
    }

    /// Serialized CBlockHeader (base header + CAuxPow) at mainnet height
    /// 5,050,000, pinned by Dogecoin Core v1.14.9 chainparams.cpp.
    private static let core5050000Header =
        "04016200c4554161067da8781dea838444895b681cc5e6b31f0a9ae61a4d10c88f18dcdf603f781b32b6ed90fa9c3ebca7a3e94f45192094fc2165d436d3cee45e9e46e7c015a6654195011a00000000" +
        "01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff5603cfea2702002f42696e616e63652f343032fabe6d6de7d4577405223918491477db725a393bcfc349d8ee63b0a4fde23cbfbfd81dea0100000000000000fc7ce3c41bdf3e1074221e7bc5fdfd370200920e22000000ffffffff02088a4125000000001976a91499ce4c0a552c646353cc9e0df4c824ba2d978de588ac0000000000000000266a24aa21a9edaaecbf83657eaa3aa1d21756bff9a3ab27fd2efc00e7474348a5d6b898b74996000000004d1171f4f76689e0cb8e75db3b2339239a168bb047396adb465662bc783f43fc051dc092ee378742ffd407c416cea5e253e4c82f6da8c540c71fd9c2926ad48e7517dbc2900e8ffd7a6e4e34698cf20760e0175a2f30f1bb4a8941df988611f477b7d8cf14f437b7fd2b55f10f6ecf34331a51607719f9304bbe5a80e14b48896867baea51b2512f4af86db0a473619b4aa4a0e4e24fb551c95cdfe6aa226b5d797ed359ed1202edb80f0b2ee15e29a1a8c981328d805932c58f9285d2d2f7885e0000000000000000000000002053e7f451130dfdb5f2a8f01755312e796ae2af09b067135e331cbab36ea846ae41da1a341f4c355d82e9ef0d99a2f50052c38bcab349cf4a8dbb45d33e402c74c115a6659387001a4a962d82"
}
