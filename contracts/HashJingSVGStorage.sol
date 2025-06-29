// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./SSTORE2.sol";

/// @title HashJingSVGStorage – Compressed SVG Chunks for On-Chain Mandalas
/// @author DataSattva
/// @notice Stores fixed SVG fragments used in rendering HashJing NFTs.
/// @dev Uses `SSTORE2` for efficient on-chain byte storage of repeated SVG segments.
contract HashJingSVGStorage {
    
    /* ───────── frame chunks ───────── */

    /// @notice Pointer to `<svg>...<rect>` segment stored via SSTORE2.
    address public headPtr;

    /// @notice Pointer to `</svg>` closing tag.
    address public tailPtr;

    /* ──────────── sector-ring prefixes ──────────── */

    /// @notice Array of pointers to `<path d=... fill="...">` segments for mandala rings.
    address[4] public prefixPtr;

    /* ──────────── hash-text prefixes ───────────── */

    /// @notice Array of pointers to `<text y=...>` lines (one per row).
    /// @dev Y-coordinate is hardcoded per index (465, 501, 537, 573).
    address[4] public textPrefixPtr;

    /// @dev Constructor stores static SVG segments using SSTORE2 for gas efficiency.
    constructor() {
        // <svg xmlns=...><rect ... fill="black"/>
        headPtr = SSTORE2.write(
            hex"3c73766720786d6c6e733d22687474703a2f2f7777772e77332e6f72672f323030302f737667222076696577426f783d223020302031303234203130323422207072657365727665417370656374526174696f3d22784d6964594d6964206d656574223e3c7265637420783d22302220793d2230222077696474683d223130323422206865696768743d2231303234222066696c6c3d22626c61636b222f3e"
        );

        // </svg>
        tailPtr = SSTORE2.write(hex"3c2f7376673e");

        // 4 path sector-ring prefixes with <path d=... fill="...">
        prefixPtr[0] = SSTORE2.write(hex"..."); // truncated for brevity
        prefixPtr[1] = SSTORE2.write(hex"...");
        prefixPtr[2] = SSTORE2.write(hex"...");
        prefixPtr[3] = SSTORE2.write(hex"...");

        // 4 <text> prefixes for hash display (different vertical Y positions)
        textPrefixPtr[0] = SSTORE2.write(hex"..."); // y="465"
        textPrefixPtr[1] = SSTORE2.write(hex"..."); // y="501"
        textPrefixPtr[2] = SSTORE2.write(hex"..."); // y="537"
        textPrefixPtr[3] = SSTORE2.write(hex"..."); // y="573"
    }

    /* ───────── read helpers ───────── */

    /// @notice Reads the `<svg>...<rect>` header.
    /// @return SVG header bytes.
    function head() external view returns (bytes memory) {
        return SSTORE2.read(headPtr);
    }

    /// @notice Reads the `</svg>` footer.
    /// @return SVG closing tag.
    function tail() external view returns (bytes memory) {
        return SSTORE2.read(tailPtr);
    }

    /// @notice Reads a ring prefix `<path d=... fill="...">` by index.
    /// @param i Index in [0, 3] representing one of the 4 ring layers.
    /// @return SVG path prefix bytes.
    function prefix(uint i) external view returns (bytes memory) {
        return SSTORE2.read(prefixPtr[i]);
    }

    /// @notice Reads a `<text>` line prefix by index (hash line).
    /// @param i Index in [0, 3], corresponds to Y-offset.
    /// @return SVG text prefix bytes.
    function textPrefix(uint i) external view returns (bytes memory) {
        return SSTORE2.read(textPrefixPtr[i]);
    }
}