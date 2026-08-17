import BigInt
import BitcoinCore
import Foundation
import HdWalletKit
import HsToolKit

public enum FullSyncStart: String, CaseIterable, Equatable {
    case recentPinned
    case bip44
}

public final class Kit: AbstractKit {
    /// Compatibility spelling for callers that prefer the type namespaced by
    /// the kit. The canonical declaration remains module-level.
    public typealias FullSyncStart = DogecoinKit.FullSyncStart

    public static let recommendedFeeRate = 1_000
    public static let minimumFeeRate = 100
    public static let softDustLimit = 1_000_000
    public static let hardDustLimit = 100_000

    private static let name = "DogecoinKit"

    public enum NetworkType: String, CaseIterable {
        case mainNet
        case testNet

        var network: INetwork {
            switch self {
            case .mainNet: return MainNet()
            case .testNet: return TestNet()
            }
        }
    }

    public enum ConfigurationError: Error, Equatable {
        case unsupportedSyncModeForTestNet
    }

    public weak var delegate: BitcoinCoreDelegate? {
        didSet { bitcoinCore.delegate = delegate }
    }

    private init(
        extendedKey: HDExtendedKey?,
        watchAddressPublicKey: WatchAddressPublicKey?,
        walletId: String,
        syncMode: BitcoinCore.SyncMode,
        networkType: NetworkType,
        confirmationsThreshold: Int,
        fullSyncStart: FullSyncStart,
        logger: Logger?
    ) throws {
        guard networkType != .testNet || syncMode == .full else {
            throw ConfigurationError.unsupportedSyncModeForTestNet
        }
        let network = networkType.network
        let logger = logger ?? Logger(minLogLevel: .verbose)
        let databaseFilePath = try DirectoryHelper.directoryURL(for: Self.name)
            .appendingPathComponent(Self.databaseFileName(walletId: walletId, networkType: networkType, syncMode: syncMode, fullSyncStart: fullSyncStart)).path
        let storage = try GrdbStorage(
            databaseFilePath: databaseFilePath,
            requiredSchema: .dogecoinCoinbaseSafe
        )
        let checkpoint = Self.resolveCheckpoint(syncMode: syncMode, network: network, storage: storage, fullSyncStart: fullSyncStart)
        let apiState = ApiSyncStateManager(storage: storage, restoreFromApi: network.syncableFromApi && syncMode != .full)
        let blockchairApi = BlockchairApi(chainId: network.blockchairChainId, logger: logger)
        let apiProvider: IApiTransactionProvider
        switch networkType {
        case .mainNet:
            apiProvider = BlockchairTransactionProvider(blockchairApi: blockchairApi, blockHashFetcher: BlockchairBlockHashFetcher(blockchairApi: blockchairApi))
        case .testNet:
            apiProvider = BCoinApi(url: "", logger: logger)
        }

        let blockHelper = BlockValidatorHelper(storage: storage)
        let validators = BlockValidatorSet()
        validators.add(blockValidator: DogecoinProofOfWorkValidator())
        validators.add(blockValidator: DogecoinCheckpointValidator(checkpoints: networkType == .mainNet ? DogecoinConsensus.mainNetCheckpoints : DogecoinConsensus.testNetCheckpoints))
        validators.add(blockValidator: DogecoinActivationValidator(auxPowHeight: networkType == .mainNet ? DogecoinConsensus.mainNetAuxPowHeight : DogecoinConsensus.testNetAuxPowHeight))
        validators.add(blockValidator: DogecoinDifficultyValidator(helper: blockHelper, testNet: networkType == .testNet))
        validators.add(blockValidator: DogecoinContextualValidator(helper: blockHelper, activations: networkType == .mainNet ? .mainNet : .testNet))

        let base58 = Base58AddressConverter(addressVersion: network.pubKeyHash, addressScriptVersion: network.scriptHash)
        let builder = BitcoinCoreBuilder(logger: logger)
        builder.addressConverter.prepend(addressConverter: base58)
        _ = try builder.set(peerSize: 10)
        _ = builder
            .set(network: network)
            .set(apiTransactionProvider: apiProvider)
            .set(checkpoint: checkpoint)
            .set(apiSyncStateManager: apiState)
            .set(extendedKey: extendedKey)
            .set(watchAddressPublicKey: watchAddressPublicKey)
            .set(paymentAddressParser: PaymentAddressParser(validScheme: "dogecoin", removeScheme: true))
            .set(walletId: walletId)
            .set(confirmationsThreshold: confirmationsThreshold)
            .set(syncMode: syncMode)
            .set(sendType: .p2p)
            .set(storage: storage)
            .set(blockValidator: validators)
            .set(blockHeaderParser: DogecoinBlockHeaderParser(strictChainId: networkType == .mainNet))
            .set(fixedDustThreshold: Self.softDustLimit)
            .set(minimumFeeRate: Self.minimumFeeRate)
            .set(witnessRecordPolicy: .acceptAndNormalizeEmpty)
            .set(utxoSpendabilityPolicy: DogecoinCoinbaseMaturityPolicy())
            .set(broadcastFailurePolicy: .retainPending)
            .set(minimumVerifiedBlockHeight: syncMode == .full ? (networkType == .mainNet ? DogecoinConsensus.minimumVerifiedMainNetHeight : DogecoinConsensus.minimumVerifiedTestNetHeight) : 0)
            .set(purpose: .bip44)

        if syncMode != .blockchair {
            _ = builder.set(forkChoice: CumulativeWorkForkChoice(powLimit: DogecoinConsensus.powLimit))
        }
        let core = try builder.build()
        core.add(restoreKeyConverter: Bip44RestoreKeyConverter(addressConverter: base58))
        super.init(bitcoinCore: core, network: network)
    }

    public convenience init(
        seed: Data,
        walletId: String,
        syncMode: BitcoinCore.SyncMode = .full,
        networkType: NetworkType = .mainNet,
        confirmationsThreshold: Int = 10,
        fullSyncStart: FullSyncStart = .bip44,
        logger: Logger? = nil
    ) throws {
        let network = networkType.network
        let masterPrivateKey = HDPrivateKey(seed: seed, xPrivKey: network.xPrivKey)
        try self.init(extendedKey: .private(key: masterPrivateKey), watchAddressPublicKey: nil, walletId: walletId, syncMode: syncMode, networkType: networkType, confirmationsThreshold: confirmationsThreshold, fullSyncStart: fullSyncStart, logger: logger)
    }

    public convenience init(
        extendedKey: HDExtendedKey,
        walletId: String,
        syncMode: BitcoinCore.SyncMode = .full,
        networkType: NetworkType = .mainNet,
        confirmationsThreshold: Int = 10,
        fullSyncStart: FullSyncStart = .bip44,
        logger: Logger? = nil
    ) throws {
        try Self.validate(extendedKey: extendedKey, networkType: networkType)
        try self.init(extendedKey: extendedKey, watchAddressPublicKey: nil, walletId: walletId, syncMode: syncMode, networkType: networkType, confirmationsThreshold: confirmationsThreshold, fullSyncStart: fullSyncStart, logger: logger)
    }

    public convenience init(
        watchAddress: String,
        walletId: String,
        syncMode: BitcoinCore.SyncMode = .full,
        networkType: NetworkType = .mainNet,
        confirmationsThreshold: Int = 10,
        fullSyncStart: FullSyncStart = .bip44,
        logger: Logger? = nil
    ) throws {
        let address = try Self.addressConverter(network: networkType.network).convert(address: watchAddress)
        guard address.scriptType == .p2pkh else { throw WatchAddressError.p2pkhOnly }
        let watchKey = try WatchAddressPublicKey(data: address.lockingScriptPayload, scriptType: address.scriptType)
        try self.init(extendedKey: nil, watchAddressPublicKey: watchKey, walletId: walletId, syncMode: syncMode, networkType: networkType, confirmationsThreshold: confirmationsThreshold, fullSyncStart: fullSyncStart, logger: logger)
    }

    public enum WatchAddressError: Error { case p2pkhOnly }

    public enum ExtendedKeyError: Error, Equatable {
        case wrongNetworkVersion
        case publicMasterNotSupported
        case unsupportedDepth
    }

    public static func firstAddress(seed: Data, networkType: NetworkType = .mainNet) throws -> Address {
        let network = networkType.network
        return try BitcoinCore.firstAddress(seed: seed, purpose: .bip44, network: network, addressCoverter: addressConverter(network: network))
    }

    public static func firstAddress(extendedKey: HDExtendedKey, networkType: NetworkType = .mainNet) throws -> Address {
        try validate(extendedKey: extendedKey, networkType: networkType)
        let network = networkType.network
        return try BitcoinCore.firstAddress(extendedKey: extendedKey, purpose: .bip44, network: network, addressCoverter: addressConverter(network: network))
    }

    public static func validateAddress(_ address: String, networkType: NetworkType = .mainNet) -> Bool {
        (try? addressConverter(network: networkType.network).convert(address: address)) != nil
    }

    public static func validateWatchAddress(_ address: String, networkType: NetworkType = .mainNet) -> Bool {
        (try? addressConverter(network: networkType.network).convert(address: address).scriptType) == .p2pkh
    }

    public static func clear(exceptFor walletIdsToExclude: [String] = []) throws {
        try DirectoryHelper.removeAll(inDirectory: name, except: walletIdsToExclude)
    }

    static func resolveCheckpoint(syncMode: BitcoinCore.SyncMode, network: INetwork, storage: IStorage, fullSyncStart: FullSyncStart) -> Checkpoint {
        guard syncMode == .full else { return Checkpoint.resolveCheckpoint(network: network, syncMode: syncMode, storage: storage) }
        let checkpoint = fullSyncStart == .recentPinned ? network.lastCheckpoint : network.bip44Checkpoint
        if storage.lastBlock != nil {
            let activeTip = storage.block(stale: false, sortedHeight: "DESC")
            if activeTip == nil || activeTip!.height < checkpoint.block.height { return network.bip44Checkpoint }
        } else {
            storage.save(block: checkpoint.block)
            checkpoint.additionalBlocks.forEach(storage.save)
        }
        return checkpoint
    }

    private static func addressConverter(network: INetwork) -> AddressConverterChain {
        let chain = AddressConverterChain()
        chain.prepend(addressConverter: Base58AddressConverter(addressVersion: network.pubKeyHash, addressScriptVersion: network.scriptHash))
        return chain
    }

    private static func validate(extendedKey: HDExtendedKey, networkType: NetworkType) throws {
        let network = networkType.network

        switch extendedKey {
        case let .private(key):
            let acceptedVersions: Set<UInt32>
            switch networkType {
            case .mainNet:
                // Dogecoin-native dprv plus the xprv spelling used by the
                // Wallet-iOS extended-key export flow for BIP44 coin type 3.
                acceptedVersions = [network.xPrivKey, HDExtendedKeyVersion.xprv.rawValue]
            case .testNet:
                acceptedVersions = [network.xPrivKey]
            }
            guard acceptedVersions.contains(key.version) else {
                throw ExtendedKeyError.wrongNetworkVersion
            }
            switch extendedKey.derivedType {
            case .master, .account:
                break
            case .bip32:
                throw ExtendedKeyError.unsupportedDepth
            }

        case let .public(key):
            let acceptedVersions: Set<UInt32>
            switch networkType {
            case .mainNet:
                // Dogecoin-native dpub plus Wallet-iOS's BIP44 xpub export.
                acceptedVersions = [network.xPubKey, HDExtendedKeyVersion.xpub.rawValue]
            case .testNet:
                acceptedVersions = [network.xPubKey]
            }
            guard acceptedVersions.contains(key.version) else {
                throw ExtendedKeyError.wrongNetworkVersion
            }
            switch extendedKey.derivedType {
            case .account:
                break
            case .master:
                throw ExtendedKeyError.publicMasterNotSupported
            case .bip32:
                throw ExtendedKeyError.unsupportedDepth
            }
        }
    }

    private static func databaseFileName(walletId: String, networkType: NetworkType, syncMode: BitcoinCore.SyncMode, fullSyncStart: FullSyncStart) -> String {
        let mode: String
        switch syncMode {
        case .api: mode = "api"
        case .blockchair: mode = "blockchair"
        case .full: mode = "full"
        }
        return "\(walletId)-\(networkType.rawValue)-bip44-\(mode)-\(fullSyncStart.rawValue)"
    }
}
