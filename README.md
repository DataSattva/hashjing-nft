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

HashJing **does not rely on external oracles** (such as Chainlink VRF) for randomness. Instead, it employs a deterministic **on-chain entropy mix** that balances simplicity, cost-efficiency, and unpredictability.

### Generation Method

A seed is computed at mint time via:

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

The mix combines:

| Component          | Purpose                                                                             |
| ------------------ | ----------------------------------------------------------------------------------- |
| `blockhash(-1)`    | Commits to the previous block’s state — the validator can no longer modify it.      |
| `block.prevrandao` | Ethereum’s built-in randomness beacon (secure since the Merge).                     |
| `address(this)`    | Contract-address salt, unique post-deployment; thwarts pre-computed rainbow tables. |
| `tokenId`          | Guarantees uniqueness for every token.                                              |
| `msg.sender`       | Binds the seed to the minter’s address.                                             |

The result is a **unique pseudo-random 256-bit seed**, fully computed within the EVM during mint.

### Why is this secure?

* `block.prevrandao` is unknown until the block is mined and **cannot be influenced** by the minter.
* `blockhash(-1)` is already sealed — the validator cannot “tweak” it.
* `address(this)` prevents rainbow-table precomputation before the contract is live.
* `tokenId` and `msg.sender` enforce per-mint uniqueness.
* `keccak256` makes back-solving for desired seeds computationally infeasible.

### Front-running Resistance

A miner **cannot predict** the final seed before including the transaction, and the minter only learns it after block confirmation. Thus, sniping for rare tokens is economically constrained: each additional attempt costs the mint fee.

### Why not Chainlink VRF?

Although VRF provides cryptographically strong randomness, it requires:

* Dependence on an external oracle
* Two transactions (`request / fulfill`)
* Higher gas costs and LINK expenditure

For **generative art**, instant, deterministic, and sufficiently unpredictable entropy is more valuable. The proposed on-chain mix meets these needs elegantly.

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

4. **Verify & publish** source on Etherscan (or fxhash-ETH UI).

Gas snapshot (Ethereum L1, 3 Gwei):

* Renderer deployment: ≈ 350 k gas → 0.004 ETH ≈ \$12
* NFT contract deployment: ≈ 1 M gas → 0.012 ETH ≈ \$36
* Single mint: 130–160 k gas → < \$2
* Contracts compile with Solidity 0.8.26 and OpenZeppelin 5.3.0.

---

### Token viewer & RPC note  

`tokenURI()` weighs ~60–80 kB of JSON + SVG.  
If a public RPC endpoint truncates large responses, query via a full node or any premium tier (Alchemy/Infura, QuickNode, Cloudflare Gateway); the on-chain data itself remains intact.  

> **Live preview:** after minting you can inspect any ID at  
> <https://datasattva.github.io/hashjing-mint-testnet/> — the page decodes `tokenURI` in-browser and shows the SVG, traits, and an OpenSea link.

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
* **Visual assets** (SVG output) are licensed under **CC BY-NC 4.0** — see [https://github.com/DataSattva/hashjing/blob/main/LICENSE-CCBYNC.md](LICENSE-CCBYNC.md)  
*(for the off-chain HashJing generator).*

| Layer / artefact                | Default licence | Commercial exception | Scope |
|---------------------------------|-----------------|----------------------|-------|
| **Source code** (Solidity & TS) | MIT             | —                    | all repos |
| **SVG outputs** – *off-chain*   | CC BY-NC 4.0    | —                    | parent repo |
| **SVG outputs** – *NFT mainnet* | CC BY-NC 4.0    | **Hash Jing Commercial License v1.0**<br>(applies **only** to NFTs minted from the official main-net contracts) | this repo |

<sub>• No off-chain royalty is required. On-chain secondary-sale royalty (ERC-2981, 7.5 %) remains in force.<br>
• Only NFTs from the official main-net contracts listed above are covered.</sub>

For the full text see [`HASHJING_COMMERCIAL_LICENSE_v1.0.md`](HASHJING_COMMERCIAL_LICENSE_v1.0.md).