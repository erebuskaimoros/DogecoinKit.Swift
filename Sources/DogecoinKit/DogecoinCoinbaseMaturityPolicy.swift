import BitcoinCore

public struct DogecoinCoinbaseMaturityPolicy: IUtxoSpendabilityPolicy {
    public static let preDigiShieldMaturity = 30
    public static let postDigiShieldMaturity = 240

    public init() {}

    public func isSpendable(utxo: UnspentOutput, lastBlockHeight: Int) -> Bool {
        guard utxo.transaction.isCoinbase else { return true }
        guard let originHeight = utxo.blockHeight else { return false }
        let maturity = originHeight >= DogecoinConsensus.digiShieldHeight
            ? Self.postDigiShieldMaturity
            : Self.preDigiShieldMaturity
        return lastBlockHeight + 1 - originHeight >= maturity
    }
}
