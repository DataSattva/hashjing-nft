// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title   CrownLib — radial-symmetry analyser for HashJing seeds
 * @author  DataSattva
 * @notice  Given a 256-bit seed, detects circular palindromes (symmetries) in
 *          the 4 × 64 bit grid and returns the *maximal* rank (length) plus the
 *          number of figures of that rank, e.g.  (rank=5, qty=2) → "5:2".
 * @dev     Pure library: no storage, no external calls.
 */
library CrownLib {
    /*────────────────── Public API ─────────────────*/

    /**
     * @notice Returns the crown descriptor "rank:qty" as UTF-8 string.
     * @dev    rank = longest palindrome length (2…64),
     *         qty  = how many such maximal figures exist.
     */
    function crownString(bytes32 seed) internal pure returns (string memory) {
        (uint8 rank, uint8 qty) = crown(seed);
        return string(
            abi.encodePacked(_twoDigit(rank), ":", _twoDigit(qty))
        );
    }

    /**
     * @notice Core routine: finds longest circular palindromes.
     * @return rank  Longest length   (2…64, never 0).
     * @return qty   How many figures of that length.
     */
    function crown(bytes32 seed) internal pure returns (uint8 rank, uint8 qty) {
        bool[64][4] memory grid = _toBitGrid(seed);

        uint8 maxLen   = 0;
        uint8 maxCount = 0;

        /* brute-force every start / length (circular) */
        for (uint8 s = 0; s < 64; ++s) {
            for (uint8 len = 2; len <= 64; ++len) {
                if (len < maxLen) continue;               // no chance to beat current max
                if (_isCircularPal(grid, s, len)) {
                    if (len > maxLen) {
                        maxLen   = len;
                        maxCount = 1;
                    } else {                              // len == maxLen
                        maxCount += 1;
                    }
                }
            }
        }
        rank = maxLen;
        qty  = maxCount;
    }

    /*────────────────── Internal helpers ─────────────────*/

    /// Converts 256-bit seed into 4 × 64 boolean grid (ring, sector).
    function _toBitGrid(bytes32 h) private pure returns (bool[64][4] memory g) {
        for (uint256 i = 0; i < 32; ++i) {
            uint8 hi = uint8(h[i]) >> 4;
            uint8 lo = uint8(h[i]) & 0x0f;
            for (uint8 r = 0; r < 4; ++r) {
                g[r][i * 2]     = (hi >> (3 - r)) & 1 == 1;
                g[r][i * 2 + 1] = (lo >> (3 - r)) & 1 == 1;
            }
        }
    }

    /// Checks if ⟨start, …, start+len-1⟩ is a circular palindrome in all rings.
    function _isCircularPal(
        bool[64][4] memory g,
        uint8 s,
        uint8 len
    ) private pure returns (bool) {
        uint8 half = len >> 1;
        for (uint8 r = 0; r < 4; ++r) {
            for (uint8 k = 0; k < half; ++k) {
                bool a = g[r][(s + k)            % 64];
                bool b = g[r][(s + len - 1 - k)  % 64];
                if (a != b) return false;
            }
        }
        return true;
    }

    /// Left-pads value 0…99 to two ASCII digits.
    function _twoDigit(uint8 v) private pure returns (bytes2) {
        return bytes2(abi.encodePacked(
            bytes1(uint8(48 + v / 10)),
            bytes1(uint8(48 + v % 10))
        ));
    }
}
