// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./SSTORE2.sol";

/// @title HashJingSVGStorage – Compressed SVG Chunks for On-Chain Mandalas
/// @author DataSattva
/// @notice Stores static SVG fragments (head, tail, rings, text) used by FullMandalaRenderer.
/// @dev Uses SSTORE2 to optimize gas cost for storing large, reusable SVG segments.
contract HashJingSVGStorage {
    
    /* ───────── frame chunks ───────── */

    /// @notice Pointer to `<svg>…<rect>` header chunk.
    address public headPtr;

    /// @notice Pointer to `</svg>` closing tag.
    address public tailPtr;

    /* ──────────── sector-ring prefixes ──────────── */

    /// @notice 4 pointers to ring layer SVG `<path>` prefixes with open fill attributes.
    address[4] public prefixPtr;

    /* ──────────── hash-text prefixes ───────────── */

    /// @notice 4 pointers to SVG `<text>` elements for displaying 64-digit hash.
    /// @dev Each corresponds to a different Y position (465, 501, 537, 573).
    address[4] public textPrefixPtr;

    /// @dev Constructor writes static SVG chunks to SSTORE2 for efficient read access.
    constructor() {
        /* 0) <svg …><rect …/> */
        headPtr = SSTORE2.write(
            // <svg xmlns="http://www.w3.org/2000/svg"
            //      viewBox="0 0 1024 1024"
            //      preserveAspectRatio="xMidYMid meet">
            // <rect x="0" y="0" width="1024" height="1024" fill="black"/>
            hex"3c73766720786d6c6e733d22687474703a2f2f7777772e77332e6f72672f323030302f737667222076696577426f783d223020302031303234203130323422207072657365727665417370656374526174696f3d22784d6964594d6964206d656574223e3c7265637420783d22302220793d2230222077696474683d223130323422206865696768743d2231303234222066696c6c3d22626c61636b222f3e"
        );

        /* 1) </svg> */
        tailPtr = SSTORE2.write(hex"3c2f7376673e");

        /* ───── 4 ring prefixes (sector path outlines) ───── */
        prefixPtr[0] = SSTORE2.write(
            hex"3c7061746820643d224d203531322031313220412034303020343030203020302031203535312e32303638353631333138323433203131332e3932363130393333313132313237204c203535392e303438323237333538313839312033342e33313133333131393733343535312041203438302034383020302030203020353132203332205a22207374726f6b653d22626c61636b22207374726f6b652d77696474683d2231222066696c6c3d22"
        );
        prefixPtr[1] = SSTORE2.write(
            hex"3c7061746820643d224d203531322031393220412033323020333230203020302031203534332e33363534383439303534353934203139332e3534303838373436343839373033204c203535312e32303638353631333138323433203131332e3932363130393333313132313237204120343030203430302030203020302035313220313132205a22207374726f6b653d22626c61636b22207374726f6b652d77696474683d2231222066696c6c3d22"
        );
        prefixPtr[2] = SSTORE2.write(
            hex"3c7061746820643d224d203531322032373220412032343020323430203020302031203533352e35323431313336373930393436203237332e31353536363535393836373237204c203534332e33363534383439303534353934203139332e3534303838373436343839373033204120333230203332302030203020302035313220313932205a22207374726f6b653d22626c61636b22207374726f6b652d77696474683d2231222066696c6c3d22"
        );
        prefixPtr[3] = SSTORE2.write(
            hex"3c7061746820643d224d203531322033353220412031363020313630203020302031203532372e36383237343234353237323937203335322e37373034343337333234343835204c203533352e35323431313336373930393436203237332e31353536363535393836373237204120323430203234302030203020302035313220323732205a22207374726f6b653d22626c61636b22207374726f6b652d77696474683d2231222066696c6c3d22"
        );

        /* ───── 4 <text> prefixes for 64-hex display ───── */
        textPrefixPtr[0] = SSTORE2.write(
            hex"3c7465787420783d223531322220793d223436352220666f6e742d73697a653d223232222066696c6c3d2277686974652220746578742d616e63686f723d226d6964646c652220666f6e742d66616d696c793d226d6f6e6f7370616365223e"
        ); // y = "465"
        textPrefixPtr[1] = SSTORE2.write(
            hex"3c7465787420783d223531322220793d223530312220666f6e742d73697a653d223232222066696c6c3d2277686974652220746578742d616e63686f723d226d6964646c652220666f6e742d66616d696c793d226d6f6e6f7370616365223e"
        ); // y = "501"
        textPrefixPtr[2] = SSTORE2.write(
            hex"3c7465787420783d223531322220793d223533372220666f6e742d73697a653d223232222066696c6c3d2277686974652220746578742d616e63686f723d226d6964646c652220666f6e742d66616d696c793d226d6f6e6f7370616365223e"
        ); // y = "537"
        textPrefixPtr[3] = SSTORE2.write(
            hex"3c7465787420783d223531322220793d223537332220666f6e742d73697a653d223232222066696c6c3d2277686974652220746578742d616e63686f723d226d6964646c652220666f6e742d66616d696c793d226d6f6e6f7370616365223e"
        ); // y = "573"
    }

    /* ───────── read helpers ───────── */

    /// @notice Reads the `<svg>…<rect>` header chunk.
    /// @return Raw SVG header as bytes.
    function head() external view returns (bytes memory) {
        return SSTORE2.read(headPtr);
    }

    /// @notice Reads the closing `</svg>` tag.
    /// @return Raw SVG footer as bytes.
    function tail() external view returns (bytes memory) {
        return SSTORE2.read(tailPtr);
    }

    /// @notice Gets the sector `<path>` prefix at given index.
    /// @param i Index of ring layer ∈ [0,3].
    /// @return Raw SVG path prefix.
    function prefix(uint i) external view returns (bytes memory) {
        return SSTORE2.read(prefixPtr[i]);
    }

    /// @notice Gets the hash-line `<text>` prefix at given index.
    /// @param i Index of text line ∈ [0,3], determines vertical Y-offset.
    /// @return Raw SVG text-line prefix.
    function textPrefix(uint i) external view returns (bytes memory) {
        return SSTORE2.read(textPrefixPtr[i]);
    }
}