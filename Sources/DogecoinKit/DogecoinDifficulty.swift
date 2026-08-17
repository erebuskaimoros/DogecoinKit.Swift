import BigInt
import BitcoinCore

public enum DogecoinDifficulty {
    /// Exact integer arithmetic from CalculateDogecoinNextWorkRequired.
    public static func calculateNextWorkRequired(
        previousHeight: Int,
        previousTimestamp: Int,
        previousBits: Int,
        firstBlockTimestamp: Int,
        digiShield: Bool,
        targetTimespan: Int,
        powLimit: BigInt = DogecoinConsensus.powLimit
    ) -> Int {
        let nextHeight = previousHeight + 1
        let actualTimespan = previousTimestamp - firstBlockTimestamp
        var modulatedTimespan = actualTimespan
        let minimumTimespan: Int
        let maximumTimespan: Int

        if digiShield {
            modulatedTimespan = targetTimespan + (modulatedTimespan - targetTimespan) / 8
            minimumTimespan = targetTimespan - targetTimespan / 4
            maximumTimespan = targetTimespan + targetTimespan / 2
        } else if nextHeight > 10_000 {
            minimumTimespan = targetTimespan / 4
            maximumTimespan = targetTimespan * 4
        } else if nextHeight > 5_000 {
            minimumTimespan = targetTimespan / 8
            maximumTimespan = targetTimespan * 4
        } else {
            minimumTimespan = targetTimespan / 16
            maximumTimespan = targetTimespan * 4
        }

        modulatedTimespan = min(max(modulatedTimespan, minimumTimespan), maximumTimespan)
        let encoder = DifficultyEncoder()
        var target = encoder.decodeCompact(bits: previousBits)
        target *= BigInt(modulatedTimespan)
        target /= BigInt(targetTimespan)
        if target > powLimit { target = powLimit }
        return encoder.encodeCompact(from: target)
    }
}
