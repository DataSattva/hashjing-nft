// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title HashJing Oracle (Randao Version)
/// @author DataSattva
/// @notice Lightweight seed oracle using block.prevrandao for randomness.
contract HashJingOracleRandao {
    /// @dev Mapping from tokenId to requestId.
    mapping(uint256 => uint256) public requestIdByToken;

    /// @dev Mapping from requestId to tokenId.
    mapping(uint256 => uint256) public tokenByRequest;

    /// @dev Mapping from tokenId to generated seed.
    mapping(uint256 => uint256) public seedByToken;

    /// @dev Last used requestId (incremental counter).
    uint256 public requestIdCounter;

    /// @notice Address of the main NFT contract that can call request/reveal
    address public mainContract;

    /// @notice Lock flag to prevent reassignment of mainContract
    bool public locked;

    /// @dev Errors
    error NotAuthorized();
    error AlreadyInitialized();

    /// @dev Access restricted to the assigned NFT contract
    modifier onlyMain() {
        if (msg.sender != mainContract) revert NotAuthorized();
        _;
    }

    event SeedRequested(uint256 indexed tokenId, uint256 requestId);
    event SeedRevealed(uint256 indexed tokenId, uint256 seed);

    /// @notice One-time setup of the NFT contract address
    function setMainContract(address _main) external {
        if (locked) revert AlreadyInitialized();
        mainContract = _main;
        locked = true;
    }

    /// @notice Triggers a pseudo-random seed request using block.prevrandao.
    /// @param tokenId The token for which the seed is requested.
    function requestSeed(uint256 tokenId) external onlyMain {
        require(seedByToken[tokenId] == 0, "Already revealed");

        uint256 requestId = ++requestIdCounter;
        requestIdByToken[tokenId] = requestId;
        tokenByRequest[requestId] = tokenId;

        emit SeedRequested(tokenId, requestId);
    }

    /// @notice Reveals and stores the seed for a given tokenId.
    /// @param tokenId The token ID to reveal the seed for.
    function revealSeed(uint256 tokenId) external onlyMain {
        require(seedByToken[tokenId] == 0, "Already revealed");

        // ⚠️ Not secure for games, but sufficient for onchain art
        uint256 seed = uint256(keccak256(
            abi.encodePacked(block.prevrandao, tokenId, address(this))
        ));

        seedByToken[tokenId] = seed;

        emit SeedRevealed(tokenId, seed);
    }

    /// @notice Returns the seed for a given tokenId.
    function getSeed(uint256 tokenId) external view returns (uint256) {
        return seedByToken[tokenId];
    }
}
