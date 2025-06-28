// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/*──────────────────────────────  H a s h J i n g  ────────────────────────────────
Each NFT stores a 256‑bit seed. A separate on‑chain renderer converts that seed
into an SVG **mandala**. Two traits are fully derived on‑chain:

 • Balanced  – exactly 128 one‑bits in the hash
 • Passages  – number of empty “corridors” from centre to edge (flood‑fill on
               a 4 × 64 grid)

Metadata is returned as data‑URI JSON; the SVG is inlined, so the contract is
**100 % on‑chain**.
──────────────────────────────────────────────────────────────────────────────────*/

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IMandalaRenderer {
    function svg(bytes32 hash) external view returns (string memory);
}

contract HashJingNFT is ERC721, ERC2981, Ownable {
    using Strings for uint256;

    /*──────────────────────── State ─────────────────────────*/
    IMandalaRenderer public immutable renderer;
    mapping(uint256 => bytes32) private _seed;

    uint256 private _nextId = 1;

    uint256 public constant GENESIS_SUPPLY = 8_192;
    uint256 public constant GENESIS_PRICE  = 0.002 ether;
    uint96  public constant MAX_ROYALTY_BPS = 1_000;   // 10 %

    address payable public immutable treasury;

    /*──────────────────────── Errors msg ─────────────────────────*/
    error SoldOut();  
    error WrongMintFee();
    error NotTreasury();

    /*──────────────────── Constructor ───────────────────────*/
    constructor(address rendererAddr)
        ERC721("HashJing", "HJ")            // ← collection name & symbol
        Ownable(msg.sender)
    {
        renderer = IMandalaRenderer(rendererAddr);
        treasury = payable(msg.sender);

        _setDefaultRoyalty(treasury, 750);     // 7.5 %
    }

    /*──────────────────────── Mint ──────────────────────────*/
    function mint() external payable {
        uint256 id = _nextId;
        if (id > GENESIS_SUPPLY) revert SoldOut();
        if (msg.value != GENESIS_PRICE) revert WrongMintFee();
        _nextId = id + 1;
        _seed[id] = _generateSeed(id);
        _safeMint(msg.sender, id);
    }

    /*────────────────────── Withdraw ───────────────────────*/
    function withdraw() external {
        if (msg.sender != treasury) revert NotTreasury();
        (bool ok,) = treasury.call{value: address(this).balance}("");
        require(ok, "Withdraw failed");
    }

    /*────────────── Royalty management ──────────────*/
    function setRoyalty(address receiver, uint96 feeBps) external onlyOwner {
        require(feeBps <= MAX_ROYALTY_BPS, "Max 10%");
        _setDefaultRoyalty(receiver, feeBps);
    }

    /*────────────────────── Metadata ───────────────────────*/
    function tokenURI(uint256 id) public view override returns (string memory) {
        require(_existsLocal(id), "HashJingNFT: nonexistent token");

        bytes32 seed = _seed[id];
        string memory image = Base64.encode(bytes(renderer.svg(seed)));

        bool  balanced = _isBalanced(seed);
        uint8 passages = _countPassages(seed);

        string memory attrs = string.concat(
            '{ "trait_type":"Balanced", "value":"', balanced ? "true" : "false", '" },',
            '{ "trait_type":"Passages", "value":"', Strings.toString(passages), '" },',
            '{ "trait_type":"Seed", "value":"', Strings.toHexString(uint256(seed), 32), '" }'
        );

        string memory json = Base64.encode(
            abi.encodePacked(
                '{"name":"HashJing #', id.toString(), '",',
                '"description":"Fully on-chain HashJing mandala - a deterministic generative form derived from cryptographic entropy. Source hash: ',
                    Strings.toHexString(uint256(seed), 32), '",',
                '"creator":"DataSattva",',
                '"external_url":"https://github.com/DataSattva/hashjing",',
                '"license":"CC BY-NC 4.0",',
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
    function _existsLocal(uint256 id) internal view returns (bool) {
        return id != 0 && id < _nextId && _ownerOf(id) != address(0);
    }

    function _generateSeed(uint256 id) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(blockhash(block.number - 1), block.timestamp, block.prevrandao, id, msg.sender)
        );
    }

    /*──────── Balanced (exactly 128 ones) ────────*/
    function _isBalanced(bytes32 hash) internal pure returns (bool) {
        uint256 ones;
        for (uint256 i = 0; i < 32; ++i) {
            ones += _countOnes(uint8(hash[i]));
        }
        return ones == 128;
    }

    function _countOnes(uint8 b) internal pure returns (uint8 c) {
        while (b != 0) {
            c += b & 1;
            b >>= 1;
        }
    }

    /*──────── Passages (flood-fill on 4 × 64 grid) ─────────*/
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
    function supportsInterface(bytes4 iid)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(iid);
    }
}