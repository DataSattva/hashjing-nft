// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
 * ──────────────────────────────────────────────────────────────────────────
 * MockMarketplace.sol
 * ------------------------------------------------------------------------
 * This ultra-lightweight contract exists **solely for the test-suite**.
 * It simulates a royalty-aware secondary-market sale so that Hardhat
 * mainnet-fork tests can verify:
 *   1) ERC-2981 royalties are paid to HashJingNFT's treasury, and
 *   2) treasury.withdraw() correctly empties the NFT contract balance.
 *
 * DO NOT use this in production. It purposefully omits access-controls,
 * order-books, signatures, reentrancy guards, etc. – everything that a
 * real marketplace like Seaport handles.
 * ──────────────────────────────────────────────────────────────────────────
 */

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 id) external;
}

interface IERC2981 {
    function royaltyInfo(uint256 id, uint256 value) external view returns (address, uint256);
}

contract MockMarketplace {
    /* Purchases a token with ETH, paying out seller and royalty receiver */
    function buyWithEth(address nft, uint256 id, address payable seller) external payable {
        (address receiver, uint256 royalty) = IERC2981(nft).royaltyInfo(id, msg.value);
        if (royalty > 0) payable(receiver).transfer(royalty);
        seller.transfer(msg.value - royalty);
        IERC721(nft).safeTransferFrom(seller, msg.sender, id);
    }
}
