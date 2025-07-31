// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title  HashJingNFT – Fully On-Chain Generative Mandalas
 * @author DataSattva
 * @notice Fully on-chain generative art: each token stores a 256-bit seed and deterministically
 *         renders an SVG mandala.  Two traits are derived on-chain:
 *           • Evenness  – balance of 1-bits vs 0-bits (0.0 – 1.0, step 0.1)
 *           • Passages  – number of corridors from center to edge in a 4 × 64 grid.
 * @dev    Based on OpenZeppelin ERC721, ERC2981, Ownable. Metadata & SVG are base64 data-URIs.
 * @custom:license-art CC BY-NC 4.0 + Hash Jing Commercial License v1.0
 * @custom:source     https://github.com/DataSattva/hashjing-nft
 */

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IMandalaRenderer {
    /// @notice Returns raw SVG string for a given 256-bit seed.
    function svg(bytes32 hash) external view returns (string memory);
}

contract HashJingNFT is ERC721, ERC2981, Ownable, ReentrancyGuard {
    using Strings for uint256;

    /*──────────────────── State ────────────────────*/
    IMandalaRenderer public immutable renderer;                // external SVG generator
    mapping(uint256 => bytes32) private _seed;                 // tokenId → 256-bit seed
    mapping(uint256 => uint8)   public  evenness;              // tokenId → 0-10 score

    uint256 private _nextId = 1;                               // 1-based incremental ID

    uint256 public constant GENESIS_SUPPLY = 8_192;
    uint256 public constant GENESIS_PRICE  = 0.002 ether;
    uint96  public constant MAX_ROYALTY_BPS = 1_000;           // 10 %

    bool public mintingEnabled = false;                        // one-way switch

    /*──────────────────── Events ───────────────────*/
    event HashJingNFTDeployed(string site, string social);
    event MintingEnabled();

    /*──────────────────── Errors ───────────────────*/
    error SoldOut();
    error WrongMintFee();
    error MintAlreadyEnabled();
    error MintDisabled();
    error NonexistentToken();

    /*──────────── Constructor ────────────*/

    /**
     * @notice Deploys the collection, sets renderer and default royalty (7.5 %).
     * @param rendererAddr Address of the on-chain SVG renderer contract.
     */
    constructor(address rendererAddr)
        ERC721("HashJing", "HJ")
        Ownable(msg.sender)
    {
        renderer = IMandalaRenderer(rendererAddr);
        _setDefaultRoyalty(payable(msg.sender), 750); // basis-points

        emit HashJingNFTDeployed(
            "https://datasattva.github.io/hashjing-mint",
            "https://x.com/HashJing"
        );
    }

    /*────────── View helpers ──────────*/

    /// @notice Current ether balance held by the contract.
    function contractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /*──────────── Minting ────────────*/

    /// @notice Enables public minting (irreversible).
    function enableMinting() external onlyOwner {
        if (mintingEnabled) revert MintAlreadyEnabled();
        mintingEnabled = true;
        emit MintingEnabled();
    }

    /**
     * @notice Mints one NFT to the caller.
     * @dev    Requires exact `GENESIS_PRICE` and respects the 8 192 supply cap.
     *         Stores seed & evenness, then calls `_safeMint`.
     */
    function mint() external payable nonReentrant {
        if (!mintingEnabled) revert MintDisabled();

        uint256 id = _nextId;
        if (id > GENESIS_SUPPLY) revert SoldOut();
        if (msg.value != GENESIS_PRICE) revert WrongMintFee();

        _nextId = id + 1;
        _seed[id] = _generateSeed(id);
        _storeEvenness(id, _seed[id]);
        _safeMint(msg.sender, id);
    }

    /*────────── Withdraw ───────────*/

    /// @notice Transfers entire contract balance to the owner.
    function withdraw() external onlyOwner {
        (bool ok, ) = msg.sender.call{value: address(this).balance}("");
        require(ok, "Withdraw failed");
    }

    /*──────── Ownership guard ────────*/

    /// @dev Prevent accidental lock-out by disallowing renounce.
    function renounceOwnership() public pure override {
        revert("renounceOwnership is disabled");
    }

    /*──────── Royalty ─────────*/

    /**
     * @notice Updates royalty receiver & fee (capped at 10 %).
     * @param receiver Address that will receive royalties.
     * @param feeBps   Royalty in basis points.
     */
    function setRoyalty(address receiver, uint96 feeBps) external onlyOwner {
        require(feeBps <= MAX_ROYALTY_BPS, "Max 10%");
        _setDefaultRoyalty(receiver, feeBps);
    }

    /*────────── Metadata ──────────*/

    /**
     * @notice Returns base64-encoded JSON with SVG image and on-chain traits.
     * @param id Token ID to query.
     */
    function tokenURI(uint256 id) public view override returns (string memory) {
        if (!_existsLocal(id)) revert NonexistentToken();

        bytes32 seed = _seed[id];
        string memory image = Base64.encode(bytes(renderer.svg(seed)));

        uint8 even     = evenness[id];
        uint8 passages = _countPassages(seed);

        string memory attrs = string.concat(
            '{ "trait_type":"Evenness", "value":"', _evennessLabel(even), '" },',
            '{ "trait_type":"Passages", "value":"', Strings.toString(passages), '" },',
            '{ "trait_type":"Source hash", "value":"', Strings.toHexString(uint256(seed), 32), '" }'
        );

        string memory json = Base64.encode(
            abi.encodePacked(
                '{"name":"HashJing #', id.toString(), '",',
                '"description":"HashJing is a fully on-chain mandala: entropy becomes form via deterministic SVG.",',
                '"creator":"DataSattva",',
                '"external_url":"https://github.com/DataSattva/hashjing-nft",',
                '"license":"CC BY-NC 4.0 + Hash Jing Commercial License v1.0",',
                '"image":"data:image/svg+xml;base64,', image, '",',
                '"attributes":[', attrs, ']}' )
        );
        return string.concat("data:application/json;base64,", json);
    }

    /*────────── Helpers ──────────*/

    /**
     * @notice Returns total number of minted tokens.
     * @dev    `totalSupply()` = _nextId-1 (no burn support).
     */
    function totalSupply() external view returns (uint256) {
        return _nextId - 1;
    }

    /**
     * @notice Returns all token IDs owned by `owner`.
     * @dev    Linear scan; efficient up to 8 192 tokens (~50 ms on RPC).
     */
    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(owner);
        uint256[] memory ids = new uint256[](balance);
        uint256 count;
        for (uint256 id = 1; id < _nextId; ++id) {
            if (_ownerOf(id) == owner) ids[count++] = id;
            if (count == balance) break;
        }
        return ids;
    }

    /*──────── Seed / existence ───────*/

    function _existsLocal(uint256 id) internal view returns (bool) {
        return id != 0 && id < _nextId && _ownerOf(id) != address(0);
    }

    /// @dev Pseudo-random seed: blockhash + prevrandao + contract & sender salt.
    function _generateSeed(uint256 id) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                blockhash(block.number - 1),
                block.prevrandao,
                address(this),
                id,
                msg.sender
            )
        );
    }

    /*──────── Evenness ────────*/

    /// @dev Converts score 0-10 → label "0.0" … "1.0".
    function _evennessLabel(uint8 score) internal pure returns (string memory) {
        return score == 10 ? "1.0" : string.concat("0.", Strings.toString(score));
    }

    /// @dev Brian Kernighan popcount for uint256.
    function _popcount(uint256 x) internal pure returns (uint256 c) {
        unchecked { while (x != 0) { x &= x - 1; c++; } }
    }

    /**
     * @dev Computes Evenness score (0-10) and stores it once at mint.
     * @param id   Token ID being minted.
     * @param seed 256-bit seed of the token.
     *
     *      score = floor( (128-|ones-128|) * 10 / 128 )
     *      only perfectly balanced (128 ones) yields 10 → label "1.0"
     */
    function _storeEvenness(uint256 id, bytes32 seed) internal {
        uint256 ones  = _popcount(uint256(seed));           // 0-256
        uint256 diff  = ones > 128 ? ones - 128 : 128 - ones;
        uint8 score   = uint8(((128 - diff) * 10) / 128);   // 0-10
        evenness[id]  = score;
    }

    /*──────── Passages (flood-fill on 4×64 grid) ────────*/

    /// @dev Maps 256-bit seed into 4 × 64 binary grid for flood-fill traversal.
    function _toBitGrid(bytes32 hash) internal pure returns (uint8[64][4] memory grid) {
        for (uint256 i = 0; i < 32; ++i) {
            uint8 hi = uint8(hash[i]) >> 4;
            uint8 lo = uint8(hash[i]) & 0x0f;
            for (uint8 r = 0; r < 4; ++r) {
                grid[r][i * 2]     = (hi >> (3 - r)) & 1;
                grid[r][i * 2 + 1] = (lo >> (3 - r)) & 1;
            }
        }
        return grid;
    }

    /**
     * @dev Returns number of corridors connecting center (row 0) to edge (row 3).
     * @param hash 256-bit seed.
     */
    function _countPassages(bytes32 hash) internal pure returns (uint8) {
        uint8[64][4] memory grid = _toBitGrid(hash);
        bool[64][4] memory visited;
        uint8 passages;

        for (uint8 s = 0; s < 64; ++s) {
            if (grid[0][s] != 0 || visited[0][s]) continue;
            bool[64][4] memory local;
            if (_bfs(grid, visited, local, s)) {
                passages++;
                for (uint8 r = 0; r < 4; ++r) {
                    for (uint8 c = 0; c < 64; ++c) {
                        if (local[r][c]) visited[r][c] = true;
                    }
                }
            }
        }
        return passages;
    }

    /**
     * @dev BFS queue helper — enqueue cell if empty and unvisited.
     * @return New tail index.
     */
    function _maybeEnqueue(
        uint8[64][4] memory grid,
        bool[64][4]  memory vis,
        bool[64][4]  memory loc,
        uint16[256]  memory qr,
        uint16[256]  memory qc,
        uint16 nr,
        uint16 nc,
        uint256 tail
    ) internal pure returns (uint256) {
        if (nr >= 4 || nc >= 64) return tail;
        if (loc[nr][nc] || vis[nr][nc] || grid[nr][nc] != 0) return tail;
        qr[tail] = nr;
        qc[tail] = nc;
        return tail + 1;
    }

    /**
     * @dev Breadth-first search from top row, sector `startSector`.
     * @return reached True if any path reaches outer row.
     */
    function _bfs(
        uint8[64][4] memory grid,
        bool[64][4]  memory vis,
        bool[64][4]  memory loc,
        uint8 startSector
    ) internal pure returns (bool reached) {
        uint16[256] memory qr;
        uint16[256] memory qc;
        uint256 head;
        uint256 tail;

        qr[0] = 0;
        qc[0] = startSector;
        tail  = 1;

        while (head < tail) {
            uint16 r = qr[head];
            uint16 c = qc[head];
            head++;

            if (loc[r][c] || grid[r][c] != 0) continue;
            loc[r][c] = true;
            if (r == 3) reached = true;

            uint16[4] memory nr = [r + 1, r == 0 ? 0 : r - 1, r, r];
            uint16[4] memory nc = [c, c, (c + 1) % 64, (c + 63) % 64];

            for (uint8 i = 0; i < 4; ++i) {
                tail = _maybeEnqueue(grid, vis, loc, qr, qc, nr[i], nc[i], tail);
            }
        }
    }

    /*───────── ERC-165 ─────────*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 iid)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(iid);
    }
}
