// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

contract RandomSeedOracle {
    address public mainContract;
    bool public locked;

    error NotAuthorized();
    error AlreadyInitialized();

    modifier onlyMain() {
        if (msg.sender != mainContract) revert NotAuthorized();
        _;
    }

    function setMainContract(address _main) external {
        if (locked) revert AlreadyInitialized();
        mainContract = _main;
        locked = true;
    }

    /// @notice Returns a pseudo-random 256-bit seed
    /// @param id Token ID used in the entropy mix
    function generateSeed(uint256 id) external view onlyMain returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                blockhash(block.number - 1),
                block.timestamp,
                block.prevrandao,
                id,
                msg.sender
            )
        );
    }
}
