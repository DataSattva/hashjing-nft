# HashJing NFT Contracts

Smart‑contract suite for **fully on‑chain** minting and rendering of [HashJing](https://github.com/DataSattva/hashjing) **mandalas**.

Each token holds a **256‑bit seed** that is deterministically transformed into an SVG mandala directly inside the EVM—no IPFS, no off‑chain servers.

---

## Key Features

| Feature                           | Why it matters                                                                                                                                                                     |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Genesis supply – 8 192 tokens** | Minting is **hard‑capped** at 8 192. This fixed, auditable limit guarantees scarcity and simplifies rarity calculations.                                                           |
| **On‑chain SVG rendering**        | The complete p5‑style drawing routine lives on‑chain; `tokenURI()` returns a `data:image/svg+xml;base64,…` string.                                                                 |
| **Compact byte‑storage**          | SVG template segments are packed via **SSTORE2** to keep deployment gas reasonable (< 350 k gas).                                                                                  |
| **Deterministic entropy**         | Seeds are derived from `keccak256(blockhash + timestamp + prevrandao + id + minter)`, guaranteeing uniqueness without oracles.                                                     |
| **Two on‑chain traits**           | `Balanced` (128 white sectors) and `Passages` (open corridors) are calculated per mint and stored in metadata.                                                                     |
| **ERC‑2981 royalties – 7.5 %**    | Signalled on‑chain; marketplaces that support ERC‑2981 automatically route **7.5 %** of secondary‑sale value (hard‑capped at **10 %**) to the creator address set in the contract. |

---

### Why exactly 8 192 Genesis tokens?

A **Sealed mandala** is one whose hash yields *zero* radial passages (`Passages = 0`).
Empirical sampling of 50 000 random 256‑bit hashes shows

`p ≈ 0.00048` (≈ 0.048 %).

Cumulative probability

`P(≥ 1 Sealed in N) = 1 – (1 – p)^N`

| N (power‑of‑two) | Chance ≥ 1 Sealed | Comment                               |
| ---------------- | ----------------- | ------------------------------------- |
| 1 024 (2¹⁰)      | 39 %              | Coin‑flip outcome                     |
| 2 048 (2¹¹)      | 63 %              | Slightly favourable                   |
| 4 096 (2¹²)      | 86 %              | 1 run out of 7 may miss               |
| **8 192 (2¹³)**  | **98 %**          | Near‑guaranteed yet still suspenseful |
| 16 384 (2¹⁴)     | 99.96 %           | Virtually certain but doubles supply  |

Thus **8 192** (`0x2000`) balances scarcity with excitement: collectors almost surely encounter at least one Sealed piece while a sliver of randomness keeps the lore alive.

> **Note** Minting stops permanently once token #8 192 is issued; any future evolutions of HashJing will deploy under a separate contract.

---

## Project Layout

```text
├── README.md                    # This file
├── LICENSE-MIT.md              # License for Solidity code
├── contracts/                  # All Solidity contracts
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
| **Balanced** | Bool   | `true` / `false`  | ✅         | `true` if exactly 128 one‑bits in the seed (perfect yin‑yang).                         |
| **Passages** | Number | `0 – 32`          | ✅         | Counts open corridors that connect the centre cell to the edge in a 4‑ring flood‑fill. |
| **Seed**     | String | `0x…` 32‑byte hex | ✅         | Raw entropy value, exposed for researchers and analytics.                              |

All other potential rarity analytics (symmetries, palindromes, etc.) are left to off‑chain explorers to keep on‑chain gas low.

---

## Entropy Generation

HashJing does **not rely on oracles** (like Chainlink VRF) to generate randomness. Instead, it uses a deterministic **on-chain entropy mix** that balances simplicity, cost-efficiency, and unpredictability.

### Generation Method

Each seed is computed on-chain at the moment of minting via:

```solidity
keccak256(
    abi.encodePacked(
        blockhash(block.number - 1),
        block.timestamp,
        block.prevrandao,
        tokenId,
        msg.sender
    )
)
```

This 256-bit hash combines:

| Component          | Purpose                                                     |
| ------------------ | ----------------------------------------------------------- |
| `blockhash(-1)`    | Commit to previous block’s state                            |
| `block.timestamp`  | Add minor entropy (helps prevent exact replay across forks) |
| `block.prevrandao` | Ethereum’s native randomness beacon (secure post-Merge)     |
| `tokenId`          | Ensure unique seeds per token                               |
| `msg.sender`       | Tie the result to the caller’s address                      |

The result is a **unique and pseudo-random seed**, fully computed within the EVM at mint time.

### Why is this secure?

* `block.prevrandao` is **inaccessible before the block is mined**, and is **not manipulable by the minter**.
* `msg.sender` and `tokenId` ensure **per-user and per-mint uniqueness**.
* `block.timestamp` adds small-time entropy, deterring brute replay attempts.
* The `keccak256` hash makes it computationally infeasible to backsolve for desired outcomes.

### Front-running resistance

A minter **cannot predict** their own seed **before** their transaction is confirmed in a block. While the `msg.sender` and `tokenId` are known, the final seed depends on **`prevrandao`**, which is only revealed **after** the block is finalized.

This **prevents gaming the system** to mint only "rare" tokens or manipulating the outcome. As a result, rarity discovery remains **surprising and fair** for all collectors.

### Why not Chainlink VRF?

While Chainlink VRF offers cryptographic randomness, it requires:

* Additional oracle dependencies
* Multiple transactions (`request/fulfill`)
* Higher gas costs

For **generative art**, especially sealed and collectible forms like mandalas, **deterministic entropy that is unpredictable until mint** is a secure and elegant solution.

---

## Deployment Notes

1. **Compile & test**

   ```bash
   npm install
   npx hardhat test
   ```
2. **Deploy renderer first**

   ```bash
   npx hardhat run scripts/deploy_renderer.ts --network sepolia
   ```
3. **Deploy `HashJingNFT.sol`** with the renderer address as constructor arg.
4. Verify & publish source on Etherscan (or fxhash‑ETH UI).

Gas snapshot (Ethereum L1, 3 Gwei):

* Renderer deployment: ≈ 350 k gas → 0.004 ETH ≈ \$12
* NFT contract deployment: ≈ 1 M gas → 0.012 ETH ≈ \$36
* Single mint: 130–160 k gas → < \$2

---

## Royalties

* **Standard**: ERC‑2981. Marketplace pays the creator address returned by `royaltyInfo()`.
* **Default rate**: **7.5 %** (750 bps) routed to `treasury`.
* **Upper bound**: hard‑capped at **10 %** to protect collectors.
* **Governance**: only the contract owner can change the receiver or percentage, and any adjustment will be announced publicly on [@DataSattva](https://x.com/DataSattva).
* **Enforcement**: platforms that ignore ERC‑2981 (e.g., zero‑royalty aggregators) rely on the buyer’s choice to honour the fee.

---

## About the Project

HashJing explores *symbolic geometry* and *cryptographic entropy*. The mandala layout references the 64 hexagrams of the **I Ching**, wrapped four times to create a 256‑sector circle that maps cleanly onto a SHA‑256‑style bitstring.

**Main concept & art direction:** *DataSattva*
**Smart‑contract engineering:** community‑driven

The full concept, white‑paper and Python notebooks live in the parent repo: [https://github.com/DataSattva/hashjing](https://github.com/DataSattva/hashjing)

---

## Test Report

Unit tests, gas metrics, and trait statistics are documented in
👉 **[TEST\_REPORT.md](https://github.com/DataSattva/hashjing-nft/blob/main/TEST_REPORT.md)**

Covers:

* minting, metadata, ERC‑interfaces
* full-collection trait analysis (`Balanced`, `Passages`)
* gas usage per method

---

## Licences

* **Smart contracts:** MIT
* **Visual assets** (SVG output) are licensed under CC BY‑NC 4.0 — see [https://github.com/DataSattva/hashjing/blob/main/LICENSE-CCBYNC.md](https://github.com/DataSattva/hashjing/blob/main/LICENSE-CCBYNC.md)

Commercial use of generated artworks requires separate permission from the artist.
