# DogecoinKit.Swift

Native Dogecoin support for Thwallet, built on the MIT-licensed Horizontal
Systems `BitcoinCore.Swift` architecture.

The kit implements Dogecoin scrypt proof of work, AuxPoW validation,
DigiShield and testnet difficulty rules, fixed checkpoints, connected
cumulative-work fork choice, canonical wire parsing and payload limits, BIP44
coin type 3 P2PKH wallets, height-aware coinbase maturity, Dogecoin fee/dust
policy, and conservative ambiguous-broadcast retention.

This is an independent community project. It is not endorsed by Dogecoin
Core, Horizontal Systems, THORChain, or Nine Realms.

## Security status

Do not treat an unreviewed commit as production-ready. Release still requires
an immutable reviewed dependency pin, native XCTest under Xcode, live mainnet
tip and historical-restore checks, a practical testnet sync, adversarial reorg
testing, reproducible-build validation, and independent security review. See
`PROVENANCE.md` for the exact reviewed inputs and remaining gates.

## Public API

```swift
import DogecoinKit

let kit = try Kit(
    seed: seed,
    walletId: "primary-doge",
    syncMode: .full,
    networkType: .mainNet,
    confirmationsThreshold: 10,
    fullSyncStart: .bip44,
    logger: logger
)
kit.delegate = delegate
kit.start()
```

`Kit` subclasses `BitcoinCore.AbstractKit`. Its delegate is the existing
`BitcoinCoreDelegate` with `transactionsUpdated`, `balanceUpdated`, and
`kitStateUpdated` callbacks. Both `DogecoinKit.FullSyncStart` and the
compatibility spelling `DogecoinKit.Kit.FullSyncStart` are public.

Seed, extended-key, and single-address watch initializers all accept
`fullSyncStart`; its default is `.bip44`. `.recentPinned` anchors a new mainnet
full-sync database at height 5,050,000, while `.bip44` starts at 145,000. The
policy and sync mode are part of the database filename so incompatible starts
do not share state.

Mainnet supports `.full`, `.api`, and `.blockchair`. Every mode broadcasts over
P2P; after Blockchair history sync succeeds, the peer group starts before P2P
broadcast can become ready. API-assisted modes trust their history provider in
ways full P2P sync does not. Testnet currently supports `.full` only; API modes
fail closed because no reviewed testnet history endpoint is configured.

## Keys and addresses

- Receive and change derivation is legacy P2PKH at `m/44'/3'/account'/chain/index`.
- Sending accepts valid Dogecoin P2PKH and P2SH destinations. Watching accepts
  a single P2PKH address only.
- Private master and private account extended keys are accepted. Public account
  keys are accepted; public master and arbitrary-depth keys are rejected.
- Mainnet accepts Dogecoin `dprv`/`dpub` plus the `xprv`/`xpub` spelling used by
  Wallet-iOS for its coin-type-3 BIP44 export. Testnet accepts its testnet
  versions. Other-network versions are rejected.
- An account xpub does not encode its originating coin type. The caller must
  ensure it was derived at `m/44'/3'/account'` before import.

`Kit.clear(exceptFor:)` only operates inside the `DogecoinKit` application
support directory. Exclusions are wallet-id substrings matched against the
mode-qualified database filenames.

## Fee, dust, maturity, and broadcast policy

- Recommended fee rate: 1,000 koinu per serialized byte.
- Enforced minimum fee rate: 100 koinu per serialized byte.
- Wallet soft dust: 1,000,000 koinu; outputs below it are not created.
- Node hard dust reference: 100,000 koinu.
- Coinbase maturity is 30 blocks before height 145,000 and 240 blocks from
  height 145,000 onward; normal payments retain normal confirmation policy.
- An ambiguous API/P2P outcome never invalidates the transaction or unlocks
  its inputs. Bounded attempts leave the exact transaction pending until an
  authoritative relay, mempool, or chain result arrives.

Dogecoin storage is opened fail-closed. Startup propagates migration failures
and verifies that `transactions.isCoinbase` exists and that the `inputs`
primary key is scoped by child `transactionHash`; this prevents ordinary
coinbase null-prevout collisions across close/reopen.

## Verification

Focused tests cover parsing limits, Dogecoin Core's all-empty witness-record
normalization, scrypt/AuxPoW, difficulty and activation boundaries,
checkpoints, connected cumulative-work choice, verified-height floors,
coinbase persistence/migration, Blockchair peer startup, ambiguous P2P
retention, key/address policy, and the exact THOR deposit signing vector. The
golden transaction pays `D9EGy2TqzyLmL1PJ9K8LhoM9HuZaogDkJY`, includes memo
`=:THOR.RUNE:thor1destination`, uses 750,000 koinu/byte, pays a fee of
198,750,000 koinu, returns 39,801,250,000 koinu, and has txid
`f6d6c05a8e0311de5b4bbb5d37c1b00fbb8f2afccf4a138a30939e88726f126a`.

With full Xcode selected, run:

```sh
swift test
```

## License and attribution

MIT. Architecture and wallet plumbing derive from Horizontal Systems' MIT
projects; Android parity logic and fixtures retain its attribution. Consensus
behavior and fixtures are pinned to Dogecoin Core v1.14.9. See `LICENSE` and
`PROVENANCE.md`.
