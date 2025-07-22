# HashJing NFT Contracts

Smart-contract suite for **fully on-chain** minting and rendering of [HashJing](https://github.com/DataSattva/hashjing) **mandalas**.

Each token holds a **256-bit seed** that is deterministically transformed into an SVG mandala directly inside the EVM—no IPFS, no off-chain servers.

---

## Key Features

| Feature                           | Why it matters                                                                                                                                                                     |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Genesis supply – 8 192 tokens** | Minting is **hard-capped** at 8 192. This fixed, auditable limit guarantees scarcity and simplifies rarity calculations.                                                           |
| **Fixed mint price – 0.002 ETH**  | Predictable cost for collectors; owner cannot raise it.                                                                                                                            |
| **On-chain SVG rendering**        | The complete p5-style drawing routine lives on-chain; `tokenURI()` returns a `data:image/svg+xml;base64,…` string.                                                                 |
| **Compact byte-storage**          | SVG template segments are packed via **SSTORE2** to keep deployment gas reasonable (< 350 k gas).                                                                                  |
| **Deterministic entropy**         | Seeds are derived from `keccak256(blockhash + prevrandao + address(this) + id + minter)`, guaranteeing uniqueness without oracles.                                                 |
| **Two on-chain traits**           | `Balanced` (128 white sectors) and `Passages` (open corridors) are calculated per mint and stored in metadata.                                                                     |
| **ERC-2981 royalties – 7.5 %**    | Signalled on-chain; marketplaces that support ERC-2981 automatically route **7.5 %** of secondary-sale value (hard-capped at **10 %**) to the creator address set in the contract. |

---

### Ownership & Administrative Controls

* **Withdraw is gated by `onlyOwner`;** transferring ownership automatically transfers the right to withdraw the mint pool.
* **Admin burn (renounce) is intentionally disabled.**
  If you wish to burn all admin rights forever, call

  ```solidity
  transferOwnership(0x000000000000000000000000000000000000dEaD);
  ```

  After that, no one will ever be able to change royalties, price, or withdraw funds.
* **No `burn()` function.** HashJing treats every mandala as a page in a “Book of Random Entropy”; even seemingly unremarkable hashes may become valuable for future experiments, so tokens are deliberately non-destructible.

---

### Why exactly 8 192 Genesis tokens?

A **Sealed mandala** is one whose hash yields *zero* radial passages (`Passages = 0`).
Empirical sampling of 50 000 random 256-bit hashes shows

`p ≈ 0.00048` (≈ 0.048 %).

Cumulative probability

`P(≥ 1 Sealed in N) = 1 – (1 – p)^N`

| N (power-of-two) | Chance ≥ 1 Sealed | Comment                               |
| ---------------- | ----------------- | ------------------------------------- |
| 1 024 (2¹⁰)      | 39 %              | Coin-flip outcome                     |
| 2 048 (2¹¹)      | 63 %              | Slightly favourable                   |
| 4 096 (2¹²)      | 86 %              | 1 run out of 7 may miss               |
| **8 192 (2¹³)**  | **98 %**          | Near-guaranteed yet still suspenseful |
| 16 384 (2¹⁴)     | 99.96 %           | Virtually certain but doubles supply  |

Thus **8 192** (`0x2000`) balances scarcity with excitement: collectors almost surely encounter at least one Sealed piece while a sliver of randomness keeps the lore alive.

> **Note** Minting stops permanently once token #8 192 is issued; any future evolutions of HashJing will deploy under a separate contract.

---

## Project Layout

```text
├── README.md                   # This file
├── LICENSE-MIT.md              # License for Solidity code
├── HASHJING_COMMERCIAL_LICENSE_v1.0.md
├── contracts/                   # All Solidity contracts
│   ├── HashJingNFT.sol          # ERC‑721 core contract (mint + traits + metadata)
│   ├── FullMandalaRenderer.sol  # Pure‑view SVG generator used by the NFT contract
│   ├── HashJingSVGStorage.sol   # Stores pre‑computed SVG path segments via SSTORE2
│   ├── SSTORE2.sol              # Library (0xSequence) for cheap calldata storage
│   └── utils/
│       └── Bytecode.sol         # Minimal helper to read SSTORE2 payloads
├── scripts/                    # Dev scripts (deployment, stats, etc.)
│   └── collectionStats.ts       # Mass minting and statistical analysis of traits
├── test/                       # Hardhat test suite
│   └── HashJingNFT.test.ts      # Unit tests: minting, metadata, ERC‑interfaces
├── hardhat.config.ts          # Hardhat configuration
├── package.json               # NPM dependencies
├── tsconfig.json              # TypeScript settings
└── .gitignore                 # Git exclusions
```

> **Note** `FullMandalaRenderer.sol` is a separate stateless contract so it can be audited and optimised independently of the NFT minting logic.

---

## Traits Explained

| Trait        | Type   | Range / Values    | On‑chain? | Notes                                                                                  |
| ------------ | ------ | ----------------- | --------- | -------------------------------------------------------------------------------------- |
| **Balanced** | Bool   | `true` / `false`  | `yes`         | `true` if exactly 128 one‑bits in the seed (perfect yin‑yang).                         |
| **Passages** | Number | `0 – 32`          | `yes`         | Counts open corridors that connect the centre cell to the edge in a 4‑ring flood‑fill. |
| **Seed**     | String | `0x…` 32‑byte hex | `yes`         | Raw entropy value, exposed for researchers and analytics.                              |

All other potential rarity analytics (symmetries, palindromes, etc.) are left to off‑chain explorers to keep on‑chain gas low.

---

## Entropy Generation

HashJing relies on a **deterministic on-chain entropy mix** rather than an external oracle.  
The seed is finalised inside the same block that mints the token, giving instant reveal without compromising fairness.

### Generation Method

A 256-bit seed is calculated at mint time:

```solidity
keccak256(
    abi.encodePacked(
        blockhash(block.number - 1),
        block.prevrandao,
        address(this),
        tokenId,
        msg.sender
    )
)
```

| Component          | Why it matters                                                                       |
| ------------------ | ------------------------------------------------------------------------------------ |
| `blockhash(-1)`    | Previous block is already sealed; no one can alter it.                               |
| `block.prevrandao` | Ethereum’s built-in randomness beacon — unknown until the block is mined.            |
| `address(this)`    | Contract-address salt, unique after deployment; blocks rainbow-table precomputation. |
| `tokenId`          | Different for every mint.                                                            |
| `msg.sender`       | Binds the seed to the minter’s wallet.                                               |

### Security & Front-Running Resistance

* **Minters and bots** do *not* know the final seed in advance because `prevrandao` only becomes public the moment the block is produced.
* Cancelling a pending tx costs only gas; the 0.002 ETH mint price is paid **once per successful mint**, so “brute-forcing” rare seeds quickly becomes expensive.
* **Block proposers** see every seed before publishing the block, but racing for a single rare mandala would mean dropping or re-ordering user transactions and risking ≈0.044 ETH in block rewards plus reputational / protocol penalties — a poor trade-off.

Overall, any attempt to bias the seed costs *more* than the potential gain, which is why commit-reveal or VRF is unnecessary for this generative-art use-case.

### Why not Chainlink VRF?

* Requires an external oracle and LINK fees
* Two transactions (`request → fulfill`) → slower UX
* Higher gas costs

For art that values on-chain purity and instant reveal, the deterministic mix above strikes the right balance between unpredictability, simplicity, and cost-efficiency.

---

## Why your wallet thumbnail might look empty — and why that’s perfectly normal

HashJing stores **everything** (JSON *and* SVG) directly inside the smart contract and serves it as a single  
`data:image/svg+xml;base64,…` string. A few wallets — most notably MetaMask (Chrome / Mobile) — still ignore  
such `data:` images and therefore show a blank square.

**This is neither an error nor a missing file.**  
Open the token in any interface that supports on-chain SVG — e.g. **OpenSea**, **fx(hash)-ETH**, **Rainbow**,  
or any custom viewer that decodes `image_data` — and your mandala will render instantly, straight from Ethereum.

Choosing full on-chain purity is a conscious design decision: you trade a bit of UX in a couple of popular  
wallets for the rock-solid guarantee that your artwork can **never** turn into a broken JPEG because a server  
went offline or an IPFS pin was lost. Immutability, perpetual availability, and the idea that **“the medium is  
part of the art itself”** outweigh the convenience of a thumbnail everywhere. A blank square in one wallet is  
simply a reminder that your piece lives entirely on-chain.

---

## Royalties

* **Standard:** ERC-2981. Marketplace pays the creator address returned by `royaltyInfo()`.
* **Default rate:** **7.5 %** (750 bps) routed to the current owner address.
* **Upper bound:** hard-capped at **10 %** to protect collectors.
* **Governance:** only the contract owner can change the receiver or percentage; any adjustment will be announced publicly on [@DataSattva](https://x.com/DataSattva).
* **Enforcement:** platforms that ignore ERC-2981 rely on the buyer’s choice to honour the fee.

---

## About the Project

HashJing explores *symbolic geometry* and *cryptographic entropy*. The mandala layout references the 64 hexagrams of the **I Ching**, wrapped four times to create a 256‑sector circle that maps cleanly onto a SHA‑256‑style bitstring.

**Main concept & art direction:** *DataSattva*
**Smart‑contract engineering:** community‑driven

The full concept, white‑paper and Python notebooks live in the parent repo: [https://github.com/DataSattva/hashjing](https://github.com/DataSattva/hashjing)

---

## Test Report

Unit tests, gas metrics, and trait statistics are documented in
[TEST\_REPORT.md](https://github.com/DataSattva/hashjing-nft/blob/main/TEST_REPORT.md)

Covers:

* minting, metadata, ERC‑interfaces
* full-collection trait analysis (`Balanced`, `Passages`)
* gas usage per method

---

## Licences

* **Smart contracts:** MIT
* **Visual assets** (SVG output) are licensed under **CC BY-NC 4.0** — see [`LICENSE-CCBYNC.md`](https://github.com/DataSattva/hashjing/blob/main/LICENSE-CCBYNC.md)  
*(for the off-chain HashJing generator).*

| Layer / artefact                | Default licence | Commercial exception | Scope |
|---------------------------------|-----------------|----------------------|-------|
| **Source code** (Solidity & TS) | MIT             | —                    | all repos |
| **SVG outputs** – *off-chain*   | CC BY-NC 4.0    | —                    | parent repo |
| **SVG outputs** – *NFT mainnet* | CC BY-NC 4.0    | **Hash Jing Commercial License v1.0**<br>(applies **only** to NFTs minted from the official main-net contracts) | this repo |

<sub>• No off-chain royalty is required. On-chain secondary-sale royalty (ERC-2981, 7.5 %) remains in force.<br>
• Only NFTs from the official main-net contracts listed above are covered.</sub>

For the full text see [`HASHJING_COMMERCIAL_LICENSE_v1.0.md`](HASHJING_COMMERCIAL_LICENSE_v1.0.md).

## Contacts and Resources

For a detailed list of HashJing contacts and resources, see the page [Contacts and Resources](https://datasattva.github.io/hashjing-res/)