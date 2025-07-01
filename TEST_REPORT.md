# Test Report

## 1. Unit Tests

[HashJingNFT.test.ts](https://github.com/DataSattva/hashjing-nft/blob/main/test/HashJingNFT.test.ts)
```
$ npx hardhat test
```

### Overview

The following unit tests verify basic minting functionality, supply limits, metadata attributes, and access control for withdrawal:

* mint 1 token
* enforce 8192 token cap
* tokenURI includes `Balanced` and `Passages`
* ERC165 support: ERC721, Metadata, ERC2981
* treasury-only withdrawal logic

### Results

* All 6 tests passing (typical run: \~30s)
* Test runner: Hardhat + Chai (`npx hardhat test`)
* Fork-based tests disabled unless `RUN_FORK_TESTS` is set

### Gas Usage

#### Method-level

| Method       | Min Gas  | Max Gas  | Avg Gas  | Calls  |
|--------------|----------|----------|----------|--------|
| `mint`       | 78,980   | 101,368  | ~84,000  | 8196   |
| `withdraw`   | —        | —        | 28,276   | 2      |

#### Deployments

| Contract             | Avg Gas     | % of 30M limit |
|----------------------|-------------|----------------|
| HashJingNFT          | ~2,457,000  | ~8.2%          |
| FullMandalaRenderer  | ~783,000    | ~2.6%          |
| HashJingSVGStorage   | ~1,081,950  | ~3.6%          |

Total deployment cost: ~4.3M gas — safely below block limit.

---

## 2. Trait Distribution

[scripts/collectionStats.ts](https://github.com/DataSattva/hashjing-nft/blob/main/scripts/collectionStats.ts)
```
$ npx hardhat run scripts/collectionStats.ts
```

### Overview

This script performs a full collection mint (`8192` tokens) and analyzes the distribution of:

* `Balanced == true`
* `Passages` trait (values: `0–11`)

Each run deploys fresh contracts and executes full minting logic. Due to hash-based generation, results vary across runs.

### Results

<strong>Run #1</strong>

```
Tokens minted   : 8192
Balanced = true : 384 (4.69 %)

Passages distribution:
  00 : 5 (0.06 %)
  01 : 66 (0.81 %)
  02 : 317 (3.87 %)
  03 : 1065 (13.00 %)
  04 : 1957 (23.89 %)
  05 : 2148 (26.22 %)
  06 : 1560 (19.04 %)
  07 : 772 (9.42 %)
  08 : 253 (3.09 %)
  09 : 39 (0.48 %)
  10 : 8 (0.10 %)
  11 : 2 (0.02 %)

⏱ total time: 173m53.728s
```

<strong>Run #2</strong>

```
Tokens minted   : 8192
Balanced = true : 415 (5.07 %)

Passages distribution:
  00 : 3 (0.04 %)
  01 : 55 (0.67 %)
  02 : 338 (4.13 %)
  03 : 1052 (12.84 %)
  04 : 1919 (23.43 %)
  05 : 2167 (26.45 %)
  06 : 1576 (19.24 %)
  07 : 788 (9.62 %)
  08 : 244 (2.98 %)
  09 : 46 (0.56 %)
  10 : 3 (0.04 %)
  11 : 1 (0.01 %)

⏱ total time: 183m38.856s
```

<strong>Run #3</strong>

```
Tokens minted   : 8192  
Balanced = true : 421 (5.14 %)

Passages distribution:
  00 : 7 (0.09 %)
  01 : 48 (0.59 %)
  02 : 346 (4.22 %)
  03 : 1068 (13.04 %)
  04 : 1916 (23.39 %)
  05 : 2210 (26.98 %)
  06 : 1568 (19.14 %)
  07 : 739 (9.02 %)
  08 : 216 (2.64 %)
  09 : 65 (0.79 %)
  10 : 9 (0.11 %)

⏱ total time: 178m46s (approx.)
```

---

## Summary

* Minting logic and trait extraction are consistent across runs
* Balanced ≈ 5% across full collection
* `Passages` distribution peaks at 4–6, tails at 0 and 11
* Total execution time (full mint + decode): \~3 hours on 4-core VPS with 16 GB RAM

