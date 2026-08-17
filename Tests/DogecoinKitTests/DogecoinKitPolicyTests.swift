import BitcoinCore
@testable import DogecoinKit
import Foundation
import HdWalletKit
import XCTest

final class DogecoinKitPolicyTests: XCTestCase {
    func testMainnetParametersAndFeePolicyMatchDogecoin() {
        let network = MainNet()

        XCTAssertEqual(network.port, 22_556)
        XCTAssertEqual(network.magic, 0xc0c0_c0c0)
        XCTAssertEqual(network.pubKeyHash, 30)
        XCTAssertEqual(network.scriptHash, 22)
        XCTAssertEqual(network.coinType, 3)
        XCTAssertEqual(network.maxBlockSize, 1_000_000)
        XCTAssertEqual(network.maxMessagePayloadSize, 4_000_000)
        XCTAssertEqual(Kit.recommendedFeeRate, 1_000)
        XCTAssertEqual(Kit.minimumFeeRate, 100)
        XCTAssertEqual(Kit.softDustLimit, 1_000_000)
        XCTAssertEqual(Kit.hardDustLimit, 100_000)
    }

    func testDogecoinAddressVersionsAcceptP2PKHAndP2SHOnly() {
        XCTAssertTrue(Kit.validateAddress("DLSSSUS3ex7YNDACJDxMER1ZMW579Vy8Zy"))
        XCTAssertTrue(Kit.validateAddress("AETZJzedcmLM2rxCM6VqCGF3YEMUjA3jMw"))
        XCTAssertFalse(Kit.validateAddress("1BoatSLRHtKNngkdXEeobR76b53LETtpyT"))
        XCTAssertTrue(Kit.validateWatchAddress("DLSSSUS3ex7YNDACJDxMER1ZMW579Vy8Zy"))
        XCTAssertFalse(Kit.validateWatchAddress("AETZJzedcmLM2rxCM6VqCGF3YEMUjA3jMw"))
    }

    func testBip44CoinTypeThreeMatchesIndependentAddressVector() throws {
        let words = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split(separator: " ").map(String.init)
        let seed = try XCTUnwrap(Mnemonic.seed(mnemonic: words))

        XCTAssertEqual(
            try Kit.firstAddress(seed: seed, networkType: .mainNet).stringValue,
            "DBus3bamQjgJULBJtYXpEzDWQRwF5iwxgC"
        )
    }

    func testGenesisBaseHeaderHashesToCanonicalMainnetBlockId() throws {
        let encoded = "01000000" + String(repeating: "00", count: 32)
            + "696ad20e2dd4365c7459b4a4a5af743d5e92c6da3229e6532cd605f6533f2a5b"
            + "24a6a152f0ff0f1e67860100"
        let hash = DoubleShaHasher().hash(data: try XCTUnwrap(Data(hex: encoded)))

        XCTAssertEqual(
            hash.reversedData.hexString,
            "1a91e3dace36e2be3bf030a65679fe821aa1d6ef92e7c9902eb318182c355691"
        )
    }

    func testCheckpointResourcesLoadAtPinnedHeights() {
        let mainnet = MainNet()
        let testnet = TestNet()

        XCTAssertEqual(mainnet.bip44Checkpoint.block.height, 145_000)
        XCTAssertEqual(mainnet.lastCheckpoint.block.height, 5_050_000)
        XCTAssertEqual(mainnet.bip44Checkpoint.additionalBlocks.count, 10)
        XCTAssertEqual(mainnet.lastCheckpoint.additionalBlocks.count, 10)
        XCTAssertEqual(testnet.bip44Checkpoint.block.height, 0)
        XCTAssertEqual(testnet.lastCheckpoint.block.height, 0)
    }

    func testFullSyncStartIsAvailableAtBothPublicSpellings() {
        let topLevel: DogecoinKit.FullSyncStart = .recentPinned
        let nested: DogecoinKit.Kit.FullSyncStart = .recentPinned

        XCTAssertEqual(topLevel, nested)
    }

    func testTestnetRejectsApiBackendsThatHaveNoConfiguredEndpoint() throws {
        let seed = Data(repeating: 4, count: 32)

        for syncMode in [BitcoinCore.SyncMode.api, .blockchair] {
            XCTAssertThrowsError(
                try Kit(seed: seed, walletId: "unsupported-testnet-api", syncMode: syncMode, networkType: .testNet)
            ) { error in
                XCTAssertEqual(error as? Kit.ConfigurationError, .unsupportedSyncModeForTestNet)
            }
        }
    }

    func testFirstAddressRejectsPublicMasterExtendedKey() {
        let master = HDPrivateKey(
            seed: Data(repeating: 1, count: 32),
            xPrivKey: MainNet().xPrivKey
        )

        XCTAssertThrowsError(
            try Kit.firstAddress(extendedKey: .public(key: master.publicKey()), networkType: .mainNet)
        ) { error in
            XCTAssertEqual(error as? Kit.ExtendedKeyError, .publicMasterNotSupported)
        }
    }

    func testFirstAddressRejectsNonDogecoinExtendedKeyVersion() throws {
        let litecoinMaster = HDPrivateKey(
            seed: Data(repeating: 2, count: 32),
            xPrivKey: HDExtendedKeyVersion.Ltpv.rawValue
        )
        let litecoinAccount = try HDKeychain(privateKey: litecoinMaster)
            .derivedKey(path: "m/44'/2'/0'")

        XCTAssertThrowsError(
            try Kit.firstAddress(extendedKey: .private(key: litecoinAccount), networkType: .mainNet)
        ) { error in
            XCTAssertEqual(error as? Kit.ExtendedKeyError, .wrongNetworkVersion)
        }
    }

    func testFirstAddressAcceptsDogecoinAccountExtendedKey() throws {
        let master = HDPrivateKey(
            seed: Data(repeating: 3, count: 32),
            xPrivKey: MainNet().xPrivKey
        )
        let account = try HDKeychain(privateKey: master)
            .derivedKey(path: "m/44'/3'/0'")

        XCTAssertNoThrow(
            try Kit.firstAddress(extendedKey: .private(key: account), networkType: .mainNet)
        )
        XCTAssertNoThrow(
            try Kit.firstAddress(extendedKey: .public(key: account.publicKey()), networkType: .mainNet)
        )
    }

    func testDifficultyArithmeticMatchesDogecoinCoreVectors() {
        let vectors: [(Int, Int, Int, Int, Bool, Int)] = [
            (239, 1_386_475_638, 0x1e0f_fff0, 1_386_474_927, false, 0x1e00_ffff),
            (9_599, 1_386_954_113, 0x1c1a_1206, 1_386_942_008, false, 0x1c15_ea59),
            (145_000, 1_395_094_679, 0x1b49_9dfd, 1_395_094_427, true, 0x1b67_1062),
            (145_107, 1_395_101_360, 0x1b34_39cd, 1_395_100_835, true, 0x1b4e_56b3),
            (149_423, 1_395_380_447, 0x1b44_6f21, 1_395_380_517, true, 0x1b33_5358),
            (145_001, 1_395_094_727, 0x1b67_1062, 1_395_094_679, true, 0x1b65_58a4),
        ]

        for (height, timestamp, bits, firstTimestamp, digiShield, expected) in vectors {
            XCTAssertEqual(
                DogecoinDifficulty.calculateNextWorkRequired(
                    previousHeight: height,
                    previousTimestamp: timestamp,
                    previousBits: bits,
                    firstBlockTimestamp: firstTimestamp,
                    digiShield: digiShield,
                    targetTimespan: digiShield ? 60 : 14_400
                ),
                expected
            )
        }
    }

    func testCoinbaseMaturityChangesAtDigiShieldActivation() throws {
        let policy = DogecoinCoinbaseMaturityPolicy()
        let legacyCoinbase = try unspentOutput(originHeight: 144_999, coinbase: true)
        let digiShieldCoinbase = try unspentOutput(originHeight: 145_000, coinbase: true)
        let payment = try unspentOutput(originHeight: 5_000_000, coinbase: false)

        XCTAssertFalse(policy.isSpendable(utxo: legacyCoinbase, lastBlockHeight: 145_027))
        XCTAssertTrue(policy.isSpendable(utxo: legacyCoinbase, lastBlockHeight: 145_028))
        XCTAssertFalse(policy.isSpendable(utxo: digiShieldCoinbase, lastBlockHeight: 145_238))
        XCTAssertTrue(policy.isSpendable(utxo: digiShieldCoinbase, lastBlockHeight: 145_239))
        XCTAssertTrue(policy.isSpendable(utxo: payment, lastBlockHeight: 5_000_000))
    }

    private func unspentOutput(originHeight: Int, coinbase: Bool) throws -> UnspentOutput {
        let master = HDPrivateKey(seed: Data(repeating: 9, count: 32), xPrivKey: MainNet().xPrivKey)
        let publicKey = try PublicKey(
            withAccount: 0,
            index: 0,
            external: true,
            hdPublicKeyData: master.publicKey().raw
        )
        let transaction = Transaction(version: 1)
        transaction.dataHash = Data(repeating: UInt8(truncatingIfNeeded: originHeight), count: 32)
        transaction.isCoinbase = coinbase
        let output = Output(
            withValue: 100_000_000,
            index: 0,
            lockingScript: Data(repeating: 0, count: 25),
            transactionHash: transaction.dataHash,
            type: .p2pkh
        )
        return UnspentOutput(
            output: output,
            publicKey: publicKey,
            transaction: transaction,
            blockHeight: originHeight
        )
    }
}
