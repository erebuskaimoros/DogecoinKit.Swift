import BigInt
import BitcoinCore
import Foundation
import Scrypt

public enum AuxPowValidationError: Error, Equatable {
    case invalid(String)
}

public struct DogecoinScryptHasher {
    public init() {}

    /// scrypt_1024_1_1_256 in numeric/display (big-endian) order.
    public func hash(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        let digest = try Scrypt.scrypt(password: bytes, salt: bytes, length: 32, N: 1024, r: 1, p: 1)
        return Data(digest.reversed())
    }
}

/// Parses and validates Dogecoin's variable CBlockHeader / CAuxPow encoding.
public final class DogecoinBlockHeaderParser: IBlockHeaderParser {
    private static let maximumChainBranch = 30
    private static let maximumParentBranch = Int(ByteStream.maximumCoreVectorSize) / 32
    private static let mergedMiningHeader = Data([0xfa, 0xbe, 0x6d, 0x6d])

    private let strictChainId: Bool
    private let powLimit: BigInt
    private let scryptHasher: DogecoinScryptHasher
    private let doubleShaHasher = DoubleShaHasher()

    public init(strictChainId: Bool, powLimit: BigInt = DogecoinConsensus.powLimit, scryptHasher: DogecoinScryptHasher = .init()) {
        self.strictChainId = strictChainId
        self.powLimit = powLimit
        self.scryptHasher = scryptHasher
    }

    public func parse(byteStream: ByteStream) throws -> BlockHeader {
        let version = Int(try byteStream.readChecked(Int32.self))
        let previousHash = try byteStream.readCheckedData(count: 32)
        let merkleRoot = try byteStream.readCheckedData(count: 32)
        let timestamp = Int(try byteStream.readChecked(UInt32.self))
        let bits = Int(try byteStream.readChecked(UInt32.self))
        let nonce = Int(try byteStream.readChecked(UInt32.self))
        let baseHeader = Self.serializeHeader(version: version, previousHash: previousHash, merkleRoot: merkleRoot, timestamp: timestamp, bits: bits, nonce: nonce)
        let blockHash = doubleShaHasher.hash(data: baseHeader)
        let carriesAuxPow = DogecoinConsensus.isAuxPow(version: version)

        if strictChainId,
           !DogecoinConsensus.isLegacy(version: version),
           DogecoinConsensus.chainId(version: version) != DogecoinConsensus.chainId
        {
            throw AuxPowValidationError.invalid("block chain id does not match Dogecoin")
        }

        guard carriesAuxPow else {
            let proofHash = try scryptHasher.hash(baseHeader)
            try validateProofOfWork(hash: proofHash, bits: bits)
            return BlockHeader(version: version, headerHash: blockHash, previousBlockHeaderHash: previousHash, merkleRoot: merkleRoot, timestamp: timestamp, bits: bits, nonce: nonce, proofOfWorkHash: proofHash)
        }

        let parentCoinbase: FullTransaction
        do {
            parentCoinbase = try TransactionSerializer.deserializeChecked(
                byteStream: byteStream,
                witnessRecordPolicy: .acceptAndNormalizeEmpty
            )
        } catch {
            throw AuxPowValidationError.invalid("malformed AuxPoW parent coinbase")
        }
        _ = try byteStream.readCheckedData(count: 32)
        let parentBranch = try readHashVector(byteStream, name: "parent merkle branch", maximum: Self.maximumParentBranch)
        let parentIndex = Int(try byteStream.readChecked(Int32.self))
        let chainBranch = try readHashVector(byteStream, name: "chain merkle branch", maximum: Self.maximumChainBranch)
        let chainIndex = Int(try byteStream.readChecked(Int32.self))

        let parentVersion = Int(try byteStream.readChecked(Int32.self))
        let parentPreviousHash = try byteStream.readCheckedData(count: 32)
        let parentMerkleRoot = try byteStream.readCheckedData(count: 32)
        let parentTimestamp = Int(try byteStream.readChecked(UInt32.self))
        let parentBits = Int(try byteStream.readChecked(UInt32.self))
        let parentNonce = Int(try byteStream.readChecked(UInt32.self))
        let parentHeader = Self.serializeHeader(version: parentVersion, previousHash: parentPreviousHash, merkleRoot: parentMerkleRoot, timestamp: parentTimestamp, bits: parentBits, nonce: parentNonce)

        guard parentIndex == 0 else { throw AuxPowValidationError.invalid("AuxPoW transaction is not the parent coinbase") }
        if strictChainId, DogecoinConsensus.chainId(version: parentVersion) == DogecoinConsensus.chainId {
            throw AuxPowValidationError.invalid("AuxPoW parent uses Dogecoin chain id")
        }
        guard let firstInput = parentCoinbase.inputs.first else {
            throw AuxPowValidationError.invalid("AuxPoW parent coinbase has no inputs")
        }
        let parentRoot = Self.checkMerkleBranch(hash: parentCoinbase.header.dataHash, branch: parentBranch, index: parentIndex)
        guard parentRoot == parentMerkleRoot else {
            throw AuxPowValidationError.invalid("AuxPoW parent merkle root is incorrect")
        }

        try validateChainCommitment(childBlockHash: blockHash, branch: chainBranch, chainIndex: chainIndex, coinbaseScript: firstInput.signatureScript, childChainId: DogecoinConsensus.chainId(version: version))
        let proofHash = try scryptHasher.hash(parentHeader)
        try validateProofOfWork(hash: proofHash, bits: bits)

        return BlockHeader(version: version, headerHash: blockHash, previousBlockHeaderHash: previousHash, merkleRoot: merkleRoot, timestamp: timestamp, bits: bits, nonce: nonce, proofOfWorkHash: proofHash, auxPow: true, auxPowValidated: true)
    }

    private func readHashVector(_ stream: ByteStream, name: String, maximum: Int) throws -> [Data] {
        let count = try stream.readCanonicalVarInt(maxValue: UInt64(maximum))
        guard count <= UInt64(stream.availableBytes / 32) else {
            throw AuxPowValidationError.invalid("\(name) exceeds remaining payload")
        }
        return try (0 ..< Int(count)).map { _ in try stream.readCheckedData(count: 32) }
    }

    private func validateChainCommitment(childBlockHash: Data, branch: [Data], chainIndex: Int, coinbaseScript: Data, childChainId: Int) throws {
        guard chainIndex >= 0 else { throw AuxPowValidationError.invalid("negative AuxPoW chain index") }
        let root = Self.checkMerkleBranch(hash: childBlockHash, branch: branch, index: chainIndex).reversedData
        guard let rootRange = coinbaseScript.range(of: root) else {
            throw AuxPowValidationError.invalid("missing AuxPoW chain root")
        }
        let rootOffset = coinbaseScript.distance(from: coinbaseScript.startIndex, to: rootRange.lowerBound)

        if let headerRange = coinbaseScript.range(of: Self.mergedMiningHeader) {
            let headerOffset = coinbaseScript.distance(from: coinbaseScript.startIndex, to: headerRange.lowerBound)
            let remainderStart = headerRange.upperBound
            if coinbaseScript[remainderStart...].range(of: Self.mergedMiningHeader) != nil {
                throw AuxPowValidationError.invalid("multiple merged-mining headers")
            }
            guard headerOffset + Self.mergedMiningHeader.count == rootOffset else {
                throw AuxPowValidationError.invalid("merged-mining header is not adjacent to chain root")
            }
        } else if rootOffset > 20 {
            throw AuxPowValidationError.invalid("legacy chain root occurs too late in coinbase")
        }

        let metadataOffset = rootRange.upperBound
        guard coinbaseScript.distance(from: metadataOffset, to: coinbaseScript.endIndex) >= 8 else {
            throw AuxPowValidationError.invalid("missing AuxPoW tree size and nonce")
        }
        let metadata = ByteStream(Data(coinbaseScript[metadataOffset ..< coinbaseScript.endIndex]))
        let treeSize = try metadata.readChecked(UInt32.self)
        let nonce = try metadata.readChecked(UInt32.self)
        let expectedSize = UInt32(1) << UInt32(branch.count)
        guard treeSize == expectedSize else {
            throw AuxPowValidationError.invalid("AuxPoW chain branch size does not match coinbase")
        }
        guard chainIndex == Self.expectedIndex(nonce: nonce, chainId: childChainId, height: branch.count) else {
            throw AuxPowValidationError.invalid("wrong AuxPoW chain index")
        }
    }

    private func validateProofOfWork(hash: Data, bits: Int) throws {
        let target = DifficultyEncoder().decodeCompact(bits: bits)
        guard target > 0, target <= powLimit else {
            throw AuxPowValidationError.invalid("proof target is outside Dogecoin range")
        }
        let hashValue = BigInt(BigUInt(hash))
        guard hashValue <= target else {
            throw AuxPowValidationError.invalid("scrypt proof of work does not meet target")
        }
    }

    public static func checkMerkleBranch(hash: Data, branch: [Data], index: Int) -> Data {
        guard index >= 0 else { return Data(repeating: 0, count: 32) }
        let hasher = DoubleShaHasher()
        var current = hash
        var cursor = index
        for sibling in branch {
            current = hasher.hash(data: cursor & 1 == 1 ? sibling + current : current + sibling)
            cursor >>= 1
        }
        return current
    }

    public static func expectedIndex(nonce: UInt32, chainId: Int, height: Int) -> Int {
        precondition((0 ... 30).contains(height))
        var random = nonce
        random = random &* 1_103_515_245 &+ 12_345
        random = random &+ UInt32(bitPattern: Int32(truncatingIfNeeded: chainId))
        random = random &* 1_103_515_245 &+ 12_345
        return Int(random % (UInt32(1) << UInt32(height)))
    }

    public static func serializeHeader(version: Int, previousHash: Data, merkleRoot: Data, timestamp: Int, bits: Int, nonce: Int) -> Data {
        var data = Data()
        data.appendLittleEndian(Int32(truncatingIfNeeded: version))
        data.append(previousHash)
        data.append(merkleRoot)
        data.appendLittleEndian(UInt32(truncatingIfNeeded: timestamp))
        data.appendLittleEndian(UInt32(truncatingIfNeeded: bits))
        data.appendLittleEndian(UInt32(truncatingIfNeeded: nonce))
        return data
    }
}
