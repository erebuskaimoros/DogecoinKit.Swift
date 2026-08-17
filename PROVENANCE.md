# Consensus and dependency provenance

## Trust anchors

- `BitcoinCore.Swift` baseline: Horizontal Systems tag `3.2.0`, commit
  `5b49f424f495904cf06519b1a7b861ef37b45b50`.
- Reviewed Thwallet `BitcoinCore.Swift` fork revision:
  `74331848b91ae39e90781872e2006665d3c4abf7`.
- Dogecoin consensus reference: Dogecoin Core v1.14.9, full commit
  `e0a1c157791544e818c901bd9341896965afbf9d`. The reviewed primary files are
  `src/auxpow.{h,cpp}`, `src/pow.cpp`, `src/dogecoin.cpp`,
  `src/chainparams.cpp`, and `src/primitives/transaction.h`.
- Android parity reference: `erebuskaimoros/bitcoin-kit-android` commit
  `5252973e174ee622f430b31235c21634975f2c1c`.
- Scrypt implementation: `greymass/swift-scrypt` release `1.0.2`, commit
  `631f21c36bff63e33ad13353ee801b4a032dda15`.

Dogecoin Core v1.14.9 consumes witness marker/flag `00 01` even when every
input's witness stack is empty, then reports `HasWitness() == false` and
canonically serializes the transaction without witness framing. The forked
core exposes this as a Dogecoin-only parser policy; existing Bitcoin-family
callers retain rejection of a superfluous witness record.

## Swift architecture review

The following Horizontal Systems references were audited rather than assumed
interchangeable:

- `BitcoinKit.Swift` commit `9b19462d06347c3fe7f3ad8221a1868306e3b125`.
- `LitecoinKit.Swift` commit `15178c7a5ab27f3c6283b4e0fadaecc648f53068`.
- `DashKit.Swift` commit `25bef76b18986e7831073986c935f5e1e00a7629`.

Other serious open-source wallets were reviewed for reuse boundaries. Trust
Wallet Core at `cf4d0ad2344bdb4412004bbdcedf502d4c4d4f17` provides low-level
Dogecoin derivation/address/signing but not the SPV, AuxPoW, history, RPC, or UI
layer required here. Vultisig and Gem use wallet-core/shared-Rust plus
service-backed architectures; no source was copied from them. Gem's GPL-family
components were treated as license-incompatible with an MIT code port.

## Checkpoint resources

The four resources are byte-identical to the Android parity commit above. The
Android source method retrieved raw Dogecoin block headers from Blockchair,
recomputed every double-SHA256 block hash locally, verified contiguous parent
links, and cross-checked both anchors against BlockCypher. Swift independently
recomputes each 80-byte base-header hash at load time and verifies that each
anchor is followed by its ten direct ancestors in descending-height order.

SHA-256 file digests:

```text
b5c8d629877c7eb8396459f09b4ea808ad578de476f1aebedb55e050dd9073a3  MainNetDogecoin-bip44.checkpoint
2353974768a328e5f4f30b507f6f53cb497e67c49fe206ec20b50c72963e7bd6  MainNetDogecoin.checkpoint
e69b889ddb31f93446130785c9aa0aa2bb87b9b1e4e693ab489fe2ece1ee993c  TestNetDogecoin-bip44.checkpoint
e69b889ddb31f93446130785c9aa0aa2bb87b9b1e4e693ab489fe2ece1ee993c  TestNetDogecoin.checkpoint
```

Mainnet BIP44 anchors at 145,000. The recent anchor is Dogecoin Core's
height-5,050,000 `defaultAssumeValid` block
`e7d4577405223918491477db725a393bcfc349d8ee63b0a4fde23cbfbfd81dea`.
Testnet resources intentionally start at genesis; a practical testnet sync to
tip remains a release gate.

## Signing vector

The deterministic release vector comes from
`dogecoinkit/src/test/.../ThorStyleDogecoinTransactionTest.kt` at Android parity
commit `5252973e174ee622f430b31235c21634975f2c1c`. It uses the public BIP39
`abandon ... about` test mnemonic, BIP44 coin type 3, funding outpoint
`22...22:1`, 50,000,000,000 koinu input value, a 10,000,000,000-koinu inbound
payment, the memo `=:THOR.RUNE:thor1destination`, and 750,000 koinu/byte.

Swift constructs and signs the transaction through the production
`TransactionBuilder`, fee/dust calculator, ECDSA signer, serializer, and txid
path. The 264 serialized bytes have SHA-256
`1b1e892cfb233926cbc0133db1fc2060d7bca2a0a8481876b978320654ac63cf`.
Their internal double-SHA256 is
`6a126f72889e93308a134acffc2a8fbb0fb0c1375dbb4b5bde11038e5ac0d6f6`;
byte reversal yields txid
`f6d6c05a8e0311de5b4bbb5d37c1b00fbb8f2afccf4a138a30939e88726f126a`.

## Immutable package pin

DogecoinKit pins the reviewed BitcoinCore fork directly:

```swift
.package(
    url: "https://github.com/erebuskaimoros/BitcoinCore.Swift.git",
    revision: "74331848b91ae39e90781872e2006665d3c4abf7"
)
```

WalletCore must direct-pin that identical fork revision. Because existing
BitcoinKit/LitecoinKit/DashKit
manifests spell the upstream URL with `.git` while WalletCore currently omits
it, commit SwiftPM mirrors for both upstream URL spellings to the fork. This
single-revision graph was resolver-proved; URL substitution without the direct
pin and both mirrors is not the trust anchor.

DogecoinKit's other direct dependencies deliberately match Wallet's existing
graph: BigInt `5.3.0`, HdWalletKit `1.3.1`, HsToolKit `2.0.5`, and swift-scrypt
`1.0.2`. Do not replace exact releases with branch or floating revision pins.

## Remaining release gates

- Run native XCTest with full Xcode selected; this host only had Command Line
  Tools, so focused suites were also executed through a temporary local runner.
- Sync mainnet from both start policies to current tip and compare independently.
- Exercise restore/history, mempool broadcast, and connected reorg behavior on
  live peers, including restart during a pending broadcast.
- Establish a practical testnet checkpoint/sync and rotate its start resources.
- Prove the final Wallet dependency graph and reproducible archive using the
  immutable BitcoinCore SHA above.
- Obtain an independent security review before shipping funds.
