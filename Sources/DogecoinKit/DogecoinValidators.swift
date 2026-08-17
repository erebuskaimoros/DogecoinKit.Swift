import BigInt
import BitcoinCore
import Foundation

public struct DogecoinVersionActivations {
    public let bip66Height: Int
    public let bip65Height: Int
    public static let mainNet = Self(bip66Height: 1_034_383, bip65Height: 3_464_751)
    public static let testNet = Self(bip66Height: 708_658, bip65Height: 1_854_705)
}

public enum DogecoinConsensusError: Error, Equatable {
    case invalid(String)
}

public final class DogecoinProofOfWorkValidator: IBlockValidator {
    public init() {}

    public func validate(block: Block, previousBlock _: Block) throws {
        guard !block.auxPow || block.auxPowValidated else {
            throw DogecoinConsensusError.invalid("AuxPoW was not structurally validated")
        }
        guard block.proofOfWorkHash.count == 32 else { throw BitcoinCoreErrors.BlockValidation.invalidProofOfWork }
        let target = DifficultyEncoder().decodeCompact(bits: block.bits)
        let proof = BigInt(BigUInt(block.proofOfWorkHash))
        guard target > 0, target <= DogecoinConsensus.powLimit, proof <= target else {
            throw BitcoinCoreErrors.BlockValidation.invalidProofOfWork
        }
    }
}

public final class DogecoinActivationValidator: IBlockValidator {
    private let auxPowHeight: Int
    public init(auxPowHeight: Int) { self.auxPowHeight = auxPowHeight }

    public func validate(block: Block, previousBlock _: Block) throws {
        if block.height < auxPowHeight, block.auxPow {
            throw DogecoinConsensusError.invalid("AuxPoW block before activation")
        }
        if block.height >= auxPowHeight, DogecoinConsensus.isLegacy(version: block.version) {
            throw DogecoinConsensusError.invalid("legacy block after AuxPoW activation")
        }
    }
}

public final class DogecoinCheckpointValidator: IBlockValidator {
    private let checkpoints: [Int: Data]
    public init(checkpoints: [Int: Data]) { self.checkpoints = checkpoints }

    public func validate(block: Block, previousBlock _: Block) throws {
        if let expected = checkpoints[block.height], expected != block.headerHash {
            throw DogecoinConsensusError.invalid("block does not match fixed checkpoint at \(block.height)")
        }
    }
}

public final class DogecoinContextualValidator: IBlockValidator {
    private let helper: IBlockValidatorHelper
    private let activations: DogecoinVersionActivations
    private let now: () -> Int

    public init(helper: IBlockValidatorHelper, activations: DogecoinVersionActivations, now: @escaping () -> Int = { Int(Date().timeIntervalSince1970) }) {
        self.helper = helper
        self.activations = activations
        self.now = now
    }

    public func validate(block: Block, previousBlock: Block) throws {
        let baseVersion = DogecoinConsensus.baseVersion(version: block.version)
        if (block.height >= activations.bip66Height && baseVersion < 3) ||
            (block.height >= activations.bip65Height && baseVersion < 4)
        {
            throw DogecoinConsensusError.invalid("obsolete Dogecoin base block version")
        }
        let count = min(11, previousBlock.height + 1)
        var timestamps = [previousBlock.timestamp]
        if count > 1 {
            for stepBack in 2 ... count {
                guard let ancestor = helper.previous(for: block, count: stepBack) else {
                    throw DogecoinConsensusError.invalid("missing checkpoint history for median time past")
                }
                timestamps.append(ancestor.timestamp)
            }
        }
        timestamps.sort()
        guard block.timestamp > timestamps[timestamps.count / 2] else {
            throw DogecoinConsensusError.invalid("block timestamp is not above median time past")
        }
        guard block.timestamp <= now() + 2 * 60 * 60 else {
            throw DogecoinConsensusError.invalid("block timestamp is more than two hours in the future")
        }
    }
}

public final class DogecoinDifficultyValidator: IBlockValidator {
    private let helper: IBlockValidatorHelper
    private let testNet: Bool

    public init(helper: IBlockValidatorHelper, testNet: Bool) {
        self.helper = helper
        self.testNet = testNet
    }

    public func validate(block: Block, previousBlock: Block) throws {
        guard try expectedBits(block: block, previousBlock: previousBlock) == block.bits else {
            throw BitcoinCoreErrors.BlockValidation.notDifficultyTransitionEqualBits
        }
    }

    public func expectedBits(block: Block, previousBlock: Block) throws -> Int {
        let digiShield = block.height >= DogecoinConsensus.digiShieldHeight
        if testNet,
           block.height >= DogecoinConsensus.testNetMinDifficultyHeight,
           previousBlock.height >= DogecoinConsensus.testNetMinDifficultyHeight,
           block.timestamp > previousBlock.timestamp + 2 * DogecoinConsensus.targetSpacing
        {
            return DogecoinConsensus.maxTargetBits
        }

        let newProtocol = previousBlock.height >= DogecoinConsensus.digiShieldHeight
        let parameterInterval = digiShield ? 1 : DogecoinConsensus.legacyDifficultyInterval
        let interval = newProtocol ? 1 : parameterInterval
        if block.height % interval != 0 {
            if !testNet || digiShield { return previousBlock.bits }
            if block.timestamp > previousBlock.timestamp + 2 * DogecoinConsensus.targetSpacing {
                return DogecoinConsensus.maxTargetBits
            }
            return lastNonMinimumDifficulty(previousBlock)
        }

        var blocksToGoBack = interval - 1
        if block.height != interval { blocksToGoBack = interval }
        guard let first = helper.previous(for: block, count: blocksToGoBack + 1) else {
            throw BitcoinCoreErrors.BlockValidation.noCheckpointBlock
        }
        return DogecoinDifficulty.calculateNextWorkRequired(
            previousHeight: previousBlock.height,
            previousTimestamp: previousBlock.timestamp,
            previousBits: previousBlock.bits,
            firstBlockTimestamp: first.timestamp,
            digiShield: digiShield,
            targetTimespan: digiShield ? DogecoinConsensus.targetSpacing : DogecoinConsensus.legacyTargetTimespan
        )
    }

    private func lastNonMinimumDifficulty(_ previousBlock: Block) -> Int {
        var cursor = previousBlock
        while cursor.height % DogecoinConsensus.legacyDifficultyInterval != 0,
              cursor.bits == DogecoinConsensus.maxTargetBits
        {
            guard let previous = helper.previous(for: cursor, count: 1) else { return DogecoinConsensus.maxTargetBits }
            cursor = previous
        }
        return cursor.bits
    }
}
