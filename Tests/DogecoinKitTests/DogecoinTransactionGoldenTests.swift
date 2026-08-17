@testable import BitcoinCore
@testable import DogecoinKit
import Foundation
import HdWalletKit
import XCTest

/// Release gate for the exact legacy transaction shape used by a THORChain
/// DOGE deposit. This mirrors Android's independently checked golden vector.
final class DogecoinTransactionGoldenTests: XCTestCase {
    func testProductionBuilderSignsThorDepositGoldenVector() throws {
        let words = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split(separator: " ").map(String.init)
        let seed = try XCTUnwrap(Mnemonic.seed(mnemonic: words))
        let network = MainNet()
        let wallet = HDWallet(seed: seed, coinType: UInt32(network.coinType), xPrivKey: network.xPrivKey, purpose: .bip44)
        let inputPublicKey = try wallet.publicKey(account: 0, index: 0, external: true)
        let inputAddress = try Kit.firstAddress(seed: seed)
        let addressConverter = Base58AddressConverter(addressVersion: network.pubKeyHash, addressScriptVersion: network.scriptHash)
        let sizeCalculator = TransactionSizeCalculator()
        let dustCalculator = DustCalculator(
            dustRelayTxFee: network.dustRelayTxFee,
            sizeCalculator: sizeCalculator,
            fixedDustThreshold: Kit.softDustLimit
        )
        let selector = GoldenUnspentOutputSelector()
        let pluginManager = PluginManager(scriptConverter: ScriptConverter())
        let parser = NetworkMessageParser(magic: network.magic, maxPayloadLength: network.maxMessagePayloadSize)
        let factory = Factory(
            network: network,
            networkMessageParser: parser,
            networkMessageSerializer: NetworkMessageSerializer(magic: network.magic)
        )
        let sorterFactory = TransactionDataSorterFactory()

        let fundingHash = Data(repeating: 0x22, count: 32)
        let fundingOutput = Output(
            withValue: Self.inputValue,
            index: 1,
            lockingScript: inputAddress.lockingScript,
            transactionHash: fundingHash,
            type: .p2pkh,
            address: inputAddress.stringValue,
            lockingScriptPayload: inputAddress.lockingScriptPayload,
            publicKey: inputPublicKey
        )
        let fundingTransaction = Transaction(version: 1, lockTime: 0)
        fundingTransaction.dataHash = fundingHash
        let unspentOutput = UnspentOutput(
            output: fundingOutput,
            publicKey: inputPublicKey,
            transaction: fundingTransaction,
            blockHeight: nil
        )
        selector.outputs = [unspentOutput]

        let inputSetter = InputSetter(
            unspentOutputSelector: selector,
            transactionSizeCalculator: sizeCalculator,
            addressConverter: addressConverter,
            publicKeyManager: GoldenPublicKeyManager(publicKey: inputPublicKey),
            factory: factory,
            pluginManager: pluginManager,
            dustCalculator: dustCalculator,
            changeScriptType: .p2pkh,
            inputSorterFactory: sorterFactory,
            minimumFeeRate: Kit.minimumFeeRate
        )
        let builder = TransactionBuilder(
            recipientSetter: RecipientSetter(addressConverter: addressConverter, pluginManager: pluginManager),
            inputSetter: inputSetter,
            lockTimeSetter: GoldenLockTimeSetter(),
            outputSetter: OutputSetter(outputSorterFactory: sorterFactory, factory: factory)
        )
        let signer = TransactionSigner(
            ecdsaInputSigner: EcdsaInputSigner(hdWallet: wallet, network: network),
            schnorrInputSigner: SchnorrInputSigner(hdWallet: wallet)
        )
        let params = SendParameters(
            address: Self.inboundAddress,
            value: Self.inboundValue,
            feeRate: Self.liveRouteFeeRate,
            sortType: .none,
            senderPay: true,
            rbfEnabled: false,
            memo: Self.thorMemo,
            unspentOutputs: [unspentOutput.info],
            changeToFirstInput: true
        )

        let mutableTransaction = try builder.buildTransaction(params: params)
        try signer.sign(mutableTransaction: mutableTransaction)
        let transaction = mutableTransaction.build()

        XCTAssertEqual(transaction.inputs.count, 1)
        XCTAssertEqual(transaction.inputs[0].previousOutputTxHash, fundingHash)
        XCTAssertEqual(transaction.inputs[0].previousOutputIndex, 1)
        XCTAssertEqual(transaction.inputs[0].sequence, Int(0xffff_fffe))
        XCTAssertEqual(transaction.outputs.count, 3)
        XCTAssertEqual(transaction.outputs[0].value, Self.inboundValue)
        XCTAssertEqual(transaction.outputs[0].address, Self.inboundAddress)
        XCTAssertEqual(transaction.outputs[0].scriptType, .p2pkh)
        XCTAssertEqual(transaction.outputs[1].value, Self.expectedChange)
        XCTAssertEqual(transaction.outputs[1].lockingScript, inputAddress.lockingScript)
        XCTAssertEqual(transaction.outputs[1].scriptType, .p2pkh)
        XCTAssertEqual(transaction.outputs[2].value, 0)
        XCTAssertEqual(transaction.outputs[2].scriptType, .nullData)
        XCTAssertEqual(
            transaction.outputs[2].lockingScript.hex,
            "6a1c" + Data(Self.thorMemo.utf8).hex
        )

        let paidFee = Self.inputValue - transaction.outputs.reduce(0) { $0 + $1.value }
        XCTAssertEqual(paidFee, Self.expectedFee)
        XCTAssertEqual(dustCalculator.dust(type: .p2pkh), Kit.softDustLimit)

        let rawTransaction = TransactionSerializer.serialize(transaction: transaction)
        XCTAssertEqual(rawTransaction.hex, Self.expectedRawTransaction)
        XCTAssertEqual(transaction.header.dataHash.reversedData.hex, Self.expectedTransactionId)
    }

    private static let inboundAddress = "D9EGy2TqzyLmL1PJ9K8LhoM9HuZaogDkJY"
    private static let thorMemo = "=:THOR.RUNE:thor1destination"
    private static let inputValue = 50_000_000_000
    private static let inboundValue = 10_000_000_000
    private static let liveRouteFeeRate = 750_000
    private static let expectedFee = 198_750_000
    private static let expectedChange = 39_801_250_000
    private static let expectedRawTransaction =
        "02000000012222222222222222222222222222222222222222222222222222222222222222010000006a47304402204c665076b9594a5214ac486ea62ba32925379b06f1181df9b1ac27545000d19f02203f6df27e4344bcd6a8b70928cca431c4eac69352c90d3668f8fb7390f7316903012102cc6b0dc33aabcf3a23643e5e2919a80c50fb3dd2129ce409bbc5f0d4643d05e0feffffff0300e40b54020000001976a9142cdb49781141264ceb5fdb7fc5948441538eff4788acd0e05644090000001976a9144a483568665dcdfa68dd58a1f62893448a64333988ac00000000000000001e6a1c3d3a54484f522e52554e453a74686f723164657374696e6174696f6e00000000"
    private static let expectedTransactionId =
        "f6d6c05a8e0311de5b4bbb5d37c1b00fbb8f2afccf4a138a30939e88726f126a"
}

private final class GoldenUnspentOutputSelector: IUnspentOutputSelector {
    var outputs = [UnspentOutput]()

    func allSpendable(filters _: UtxoFilters) -> [UnspentOutput] { outputs }

    func select(
        params _: SendParameters,
        outputScriptType _: ScriptType,
        changeType _: ScriptType,
        pluginDataOutputSize _: Int
    ) throws -> SelectedUnspentOutputInfo {
        XCTFail("The golden vector must exercise the explicit UTXO queue")
        throw BitcoinCoreErrors.SendValueErrors.emptyOutputs
    }
}

private final class GoldenPublicKeyManager: IPublicKeyManager {
    private let publicKey: PublicKey

    init(publicKey: PublicKey) { self.publicKey = publicKey }

    func usedPublicKeys(change _: Bool) -> [PublicKey] { [] }
    func changePublicKey() throws -> PublicKey { publicKey }
    func receivePublicKey() throws -> PublicKey { publicKey }
    func fillGap() throws {}
    func addKeys(keys _: [PublicKey]) {}
    func gapShifts() -> Bool { false }
    func publicKey(byPath _: String) throws -> PublicKey { publicKey }
}

private final class GoldenLockTimeSetter: ILockTimeSetter {
    func setLockTime(to mutableTransaction: MutableTransaction) {
        mutableTransaction.transaction.lockTime = 0
    }
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
