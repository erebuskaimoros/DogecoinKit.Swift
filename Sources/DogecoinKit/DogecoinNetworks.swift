import BitcoinCore
import Foundation

enum DogecoinCheckpointResource {
    enum LoadError: Error {
        case missing(String)
        case malformed(String)
    }

    static func load(_ name: String) throws -> Checkpoint {
        guard let url = Bundle.module.url(forResource: name, withExtension: "checkpoint") else {
            throw LoadError.missing(name)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let blocks = try text.split(whereSeparator: \.isNewline).map { line -> Block in
            guard let data = Data(hex: String(line)), data.count == 116 else {
                throw LoadError.malformed(name)
            }
            let serializedHeader = Data(data.prefix(80))
            let stream = ByteStream(data)
            let version = Int(try stream.readChecked(Int32.self))
            let previousHash = try stream.readCheckedData(count: 32)
            let merkleRoot = try stream.readCheckedData(count: 32)
            let timestamp = Int(try stream.readChecked(UInt32.self))
            let bits = Int(try stream.readChecked(UInt32.self))
            let nonce = Int(try stream.readChecked(UInt32.self))
            let height = Int(try stream.readChecked(UInt32.self))
            let headerHash = try stream.readCheckedData(count: 32)
            try stream.requireFullyConsumed()
            guard DoubleShaHasher().hash(data: serializedHeader) == headerHash else {
                throw LoadError.malformed(name)
            }
            return Block(withHeader: BlockHeader(version: version, headerHash: headerHash, previousBlockHeaderHash: previousHash, merkleRoot: merkleRoot, timestamp: timestamp, bits: bits, nonce: nonce), height: height)
        }
        guard let first = blocks.first else { throw LoadError.malformed(name) }
        // Checkpoint resources start at the anchor and then carry its direct
        // ancestors in descending-height order for locator exclusion.
        for (child, parent) in zip(blocks, blocks.dropFirst()) {
            guard parent.height == child.height - 1,
                  child.previousBlockHash == parent.headerHash
            else {
                throw LoadError.malformed(name)
            }
        }
        return Checkpoint(block: first, additionalBlocks: Array(blocks.dropFirst()))
    }
}

public final class MainNet: INetwork {
    public let bundleName = "Dogecoin"
    public let pubKeyHash: UInt8 = 30
    public let privateKey: UInt8 = 158
    public let scriptHash: UInt8 = 22
    public let bech32PrefixPattern = ""
    public let xPubKey: UInt32 = 0x02fa_cafd
    public let xPrivKey: UInt32 = 0x02fa_c398
    public let magic: UInt32 = 0xc0c0_c0c0
    public let port = 22_556
    public let coinType: UInt32 = 3
    public let sigHash: SigHashType = .bitcoinAll
    public let syncableFromApi = true
    public let blockchairChainId = "dogecoin"
    public let maxBlockSize: UInt32 = 1_000_000
    public let maxMessagePayloadSize = 4_000_000
    public let dustRelayTxFee = 100_000
    public let dnsSeeds = ["seed.multidoge.org", "seed2.multidoge.org"]
    public var bip44Checkpoint: Checkpoint { try! DogecoinCheckpointResource.load("MainNetDogecoin-bip44") }
    public var lastCheckpoint: Checkpoint { try! DogecoinCheckpointResource.load("MainNetDogecoin") }

    public init() {}
}

public final class TestNet: INetwork {
    public let bundleName = "Dogecoin"
    public let pubKeyHash: UInt8 = 113
    public let privateKey: UInt8 = 241
    public let scriptHash: UInt8 = 196
    public let bech32PrefixPattern = ""
    public let xPubKey: UInt32 = 0x0435_87cf
    public let xPrivKey: UInt32 = 0x0435_8394
    public let magic: UInt32 = 0xdcb7_c1fc
    public let port = 44_556
    public let coinType: UInt32 = 1
    public let sigHash: SigHashType = .bitcoinAll
    public let syncableFromApi = false
    public let blockchairChainId = ""
    public let maxBlockSize: UInt32 = 1_000_000
    public let maxMessagePayloadSize = 4_000_000
    public let dustRelayTxFee = 100_000
    public let dnsSeeds = ["testseed.jrn.me.uk"]
    public var bip44Checkpoint: Checkpoint { try! DogecoinCheckpointResource.load("TestNetDogecoin-bip44") }
    public var lastCheckpoint: Checkpoint { try! DogecoinCheckpointResource.load("TestNetDogecoin") }

    public init() {}
}
