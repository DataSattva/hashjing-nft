// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title HashJingNFT – Fully On-Chain Generative Mandalas
 * @author DataSattva
 * @notice This contract implements a fully on-chain NFT collection where each token encodes a
 *         256-bit seed and renders a deterministic SVG mandala. Traits like `Balanced` and
 *         `Passages` are derived directly from the hash.
 * @dev Uses OpenZeppelin ERC721, ERC2981, Ownable. Royalty info is encoded via ERC2981.
 *      Metadata and SVG image are inlined as data-URIs and stored entirely on-chain.
 * @custom:license-art CC BY-NC 4.0 + Hash Jing Commercial License v1.0
 * @custom:source https://github.com/DataSattva/hashjing-nft
 */

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IMandalaRenderer {
    function svg(bytes32 hash) external view returns (string memory);
}

contract HashJingNFT is ERC721, ERC2981, Ownable, ReentrancyGuard {
    using Strings for uint256;

    /*──────────────────────── State ─────────────────────────*/
    IMandalaRenderer public immutable renderer;
    mapping(uint256 => bytes32) private _seed;

    uint256 private _nextId = 1;

    uint256 public constant GENESIS_SUPPLY = 8_192;
    uint256 public constant GENESIS_PRICE  = 0.002 ether;
    uint96  public constant MAX_ROYALTY_BPS = 1_000;   // 10 %

    bool public mintingEnabled = false;  

    /*──────────────────────── Events ─────────────────────────*/
    event HashJingNFTDeployed(string site, string social);
    
    /*──────────────────────── Errors msg ─────────────────────────*/
    error SoldOut();  
    error WrongMintFee();
    error MintAlreadyEnabled();
    error MintDisabled(); 
    error NonexistentToken();

    /*──────────────────── Constructor ───────────────────────*/

    /// @notice Initializes the NFT contract with renderer and default royalty.
    /// @dev The deployer becomes the initial owner and default royalty receiver.
    constructor(address rendererAddr)
        ERC721("HashJing", "HJ")
        Ownable(msg.sender)
    {
        renderer = IMandalaRenderer(rendererAddr);
        _setDefaultRoyalty(payable(msg.sender), 750); // 7.5 %

        // first-wave marketing links (explorer bots will display them)
        emit HashJingNFTDeployed(
            "https://datasattva.github.io/hashjing-mint",
            "https://x.com/HashJing"
        );
    }

    /*──────────────────── View helpers ───────────────────*/

    /// @notice Current ether balance of this contract.
    /// @dev Convenience helper for the front-end.
    function contractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /*──────────────────────── Mint ──────────────────────────*/

    event MintingEnabled();                   

    /// @notice Enables public minting of HashJing NFTs.
    /// @dev Callable only once and only by the contract owner. Cannot be undone.
    function enableMinting() external onlyOwner {
        if (mintingEnabled) revert MintAlreadyEnabled();
        mintingEnabled = true;
        emit MintingEnabled();
    }

    /// @notice Mints a new HashJing NFT to the caller.
    /// @dev Requires exact payment and respects the 8 192 supply cap.
    function mint() external payable nonReentrant {
        if (!mintingEnabled) revert MintDisabled();

        uint256 id = _nextId;
        if (id > GENESIS_SUPPLY) revert SoldOut();
        if (msg.value != GENESIS_PRICE) revert WrongMintFee();

        _nextId = id + 1;
        _seed[id] = _generateSeed(id);
        _safeMint(msg.sender, id);
    }

    /*────────────────────── Withdraw ───────────────────────*/

    /// @notice Sends the entire contract balance to the owner.
    /// @dev Callable only by the contract owner.
    function withdraw() external onlyOwner {
        (bool ok, ) = msg.sender.call{value: address(this).balance}("");
        require(ok, "Withdraw failed");
    }

    /*────────────── Ownership ─ renounce permanently disabled ──────────────*/

    /// @notice Disables renouncing ownership to prevent accidental lockout.
    /// @dev Overrides OpenZeppelin `Ownable` behavior.
    function renounceOwnership() public pure override {
    revert("renounceOwnership is disabled");
    }

    /*────────────── Royalty management ──────────────*/

    /// @notice Updates royalty recipient and fee.
    /// @dev Only callable by the contract owner. Enforces max fee of 10%.
    /// @param receiver Address to receive royalties.
    /// @param feeBps Royalty fee in basis points (e.g., 750 = 7.5%).
    function setRoyalty(address receiver, uint96 feeBps) external onlyOwner {
        require(feeBps <= MAX_ROYALTY_BPS, "Max 10%");
        _setDefaultRoyalty(receiver, feeBps);
    }

    /*────────────────────── Metadata ───────────────────────*/

    /// @notice Returns base64-encoded metadata for a given token.
    /// @dev Metadata includes SVG image and fully on-chain traits.
    /// @param id Token ID to query.
    /// @return A base64-encoded data URI JSON string.
    function tokenURI(uint256 id) public view override returns (string memory) {
        if (!_existsLocal(id)) revert NonexistentToken();

        bytes32 seed = _seed[id];
        string memory image = Base64.encode(bytes(renderer.svg(seed)));

        bool  balanced = _isBalanced(seed);
        uint8 passages = _countPassages(seed);

        string memory attrs = string.concat(
            '{ "trait_type":"Balanced", "value":"', balanced ? "Yes" : "No", '" },',
            '{ "trait_type":"Passages", "value":"', Strings.toString(passages), '" },',
            '{ "trait_type":"Source hash", "value":"', Strings.toHexString(uint256(seed), 32), '" }'
        );

        string memory json = Base64.encode(
            abi.encodePacked(
                '{"name":"HashJing #', id.toString(), '",',
                '"description":"HashJing is a fully on-chain mandala: a deterministic glyph where entropy becomes form. A 256-bit cryptographic seed unfolds into self-contained SVG art, following the visual principles of the I Ching. No IPFS. No servers. Only Ethereum.",',
                '"creator":"DataSattva",',
                '"external_url":"https://github.com/DataSattva/hashjing-nft",',
                '"license":"CC BY-NC 4.0 + Hash Jing Commercial License v1.0",'
                '"image":"data:image/svg+xml;base64,', image, '",',
                '"attributes":[', attrs, ']}'
            )
        );
        return string.concat("data:application/json;base64,", json);
    }

    function totalSupply() external view returns (uint256) {
        return _nextId - 1;
    }

    /*───────────────────── Helpers ─────────────────────────*/

    /// @dev Checks if a token exists (minted and not burned).
    /// @param id Token ID to check.
    /// @return True if token exists.
    function _existsLocal(uint256 id) internal view returns (bool) {
        return id != 0 && id < _nextId && _ownerOf(id) != address(0);
    }

    /// @dev Generates a 256-bit pseudo-random seed for a given tokenId.
    ///      The mix is fully on-chain and does not rely on external oracles.
    /// @param id Token ID used as part of the entropy mix.
    /// @return 32-byte seed unique to this mint.
    function _generateSeed(uint256 id) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                blockhash(block.number - 1),   // fixed hash of the previous block (validator cannot modify)
                block.prevrandao,              // post-Merge randomness beacon revealed only when the block is sealed
                address(this),                 // contract address as deploy-time salt (prevents pre-compute rainbow tables)
                id,                            // tokenId guarantees per-token uniqueness
                msg.sender                     // ties entropy to the minter’s address
            )
        );
    }

    /*──────── Balanced (exactly 128 ones) ────────*/

    /// @dev Determines if the 256-bit seed has exactly 128 one-bits.
    /// @param hash The 32-byte seed to analyze.
    /// @return True if the seed is perfectly balanced.
    function _isBalanced(bytes32 hash) internal pure returns (bool) {
        uint256 ones;
        for (uint256 i = 0; i < 32; ++i) {
            ones += _countOnes(uint8(hash[i]));
        }
        return ones == 128;
    }

    /// @dev Counts the number of one-bits in a byte.
    /// @param b Input byte.
    /// @return c Number of set bits in the byte.
    function _countOnes(uint8 b) internal pure returns (uint8 c) {
        while (b != 0) {
            c += b & 1;
            b >>= 1;
        }
    }

    /*──────── Passages (flood-fill on 4 × 64 grid) ─────────*/

    /// @dev Converts a 256-bit hash into a 4×64 binary grid for flood-fill.
    /// @param hash The seed to convert.
    /// @return grid A binary matrix representing the mandala sectors.
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

    /// @dev Counts the number of unbroken paths (passages) from center to edge.
    /// @param hash The seed used to build the grid.
    /// @return Number of traversable corridors in the mandala.
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

    /*──────── BFS helpers ────────*/

    /// @dev Enqueues a cell for BFS traversal if it's a valid empty tile.
    /// @param grid Binary occupancy map.
    /// @param vis Global visited matrix.
    /// @param loc Local visited matrix.
    /// @param qr BFS row queue.
    /// @param qc BFS column queue.
    /// @param nr Row index to enqueue.
    /// @param nc Column index to enqueue.
    /// @param tail Current queue tail index.
    /// @return Updated tail index.
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

    /// @dev Runs BFS from a sector in the first row to detect passage to edge.
    /// @param grid The mandala grid.
    /// @param vis Global visited matrix (to avoid recounting).
    /// @param loc Local visited state for current run.
    /// @param startSector Column index in row 0 to start from.
    /// @return reached True if there's a path to row 3 (edge).
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
        tail = 1;

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
        return reached;
    }

    /*────────── ERC-165 support ──────────*/
    /// @notice Returns true if this contract implements a given interface.
    /// @dev Supports ERC721 and ERC2981.

    function supportsInterface(bytes4 iid)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(iid);
    }
}