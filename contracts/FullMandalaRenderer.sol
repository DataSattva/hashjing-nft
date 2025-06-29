// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./HashJingSVGStorage.sol";   // ← renamed storage contract
import "@openzeppelin/contracts/utils/Base64.sol";

/// @title FullMandalaRenderer – On-Chain SVG Generator for HashJing
/// @author DataSattva
/// @notice Converts a 256-bit seed into a fully assembled SVG string.
/// @dev Loads static path/text chunks from HashJingSVGStorage and assembles SVG at runtime.
contract FullMandalaRenderer {
    
    /* ───── geometry ───── */

    /// @dev Total number of mandala sectors (5.625° each).
    uint256 constant SECTORS   = 64;

    /// @dev Sector angle in millidegrees (5.625°).
    uint256 constant DPHI_MDEG = 5625;

    /* ───── static snippets ───── */

    bytes constant G_OPEN   = '<g transform="rotate(';
    bytes constant G_MID    = ' 512 512)">';
    bytes constant G_CLOSE  = '</g>';
    bytes constant PATH_END = '"/>';
    bytes constant WHITE    = "#ffffff";
    bytes constant BLACK    = "#000000";
    bytes constant TEXT_END = "</text>";

    /* ───── reference to compressed SVG chunk storage ───── */

    /// @dev Storage contract holding static SVG segments.
    HashJingSVGStorage immutable store;

    /// @param storageAddr Address of the deployed HashJingSVGStorage contract.
    constructor(address storageAddr) {
        store = HashJingSVGStorage(storageAddr);
    }

    /* ──────────────────────────────────────────────── */

    /// @notice Renders the full SVG mandala from a given 32-byte hash.
    /// @dev Called by HashJingNFT during metadata generation.
    /// @param hash 256-bit seed encoding the mandala pattern.
    /// @return A plain (non-base64) SVG string.
    function svg(bytes32 hash) external view returns (string memory) {
        ...
    }

    /* ───── helpers ───── */

    /// @dev Converts a millidegree angle into its ASCII decimal representation.
    /// @param v Angle in ‰ degrees (e.g., 5625 = "5.625").
    /// @return A UTF-8 encoded decimal string.
    function _angleBytes(uint256 v) private pure returns (bytes memory) {
        ...
    }

    /// @dev Converts an unsigned integer into its ASCII decimal string with padding.
    /// @param v Value to convert.
    /// @param width Minimum number of digits to include (zero-padded).
    /// @return UTF-8 encoded decimal string.
    function _uDecBytes(uint256 v, uint8 width)
        private pure returns (bytes memory out)
    {
        ...
    }

    /// @dev Converts an unsigned integer into its ASCII decimal string.
    /// @param v Value to convert.
    /// @return UTF-8 encoded decimal string.
    function _uDecBytes(uint256 v) private pure returns (bytes memory) {
        return _uDecBytes(v, 0);
    }

    /// @dev Extracts 16 nibbles (64 bits) from a 256-bit hash as ASCII hex.
    /// @param h 32-byte hash.
    /// @param line Line number in {0, 1, 2, 3}.
    /// @return 16-character lowercase hex string.
    function _hex16(bytes32 h, uint8 line) private pure returns (bytes memory) {
        bytes memory out = new bytes(16);
        unchecked {
            for (uint8 i; i < 16; ++i) {
                uint8 nib = uint8(uint256(h) >> ((63 - (line * 16 + i)) * 4)) & 0xF;
                out[i] = bytes1(nib + (nib < 10 ? 48 : 87));
            }
        }
        return out;
    }
}
