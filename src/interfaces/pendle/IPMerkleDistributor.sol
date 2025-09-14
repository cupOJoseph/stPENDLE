// SPDX-License-Identifier: MIT
// Acknowledgment: Interface derived from Pendle V2 (pendle-core-v2-public).
// Source: https://github.com/pendle-finance/pendle-core-v2-public
pragma solidity ^0.8.26;

interface IPMerkleDistributor {
    function claim(
        address receiver,
        uint256 totalAccrued,
        bytes32[] calldata proof
    ) external returns (uint256 amountOut);

    function claimVerified(address receiver) external returns (uint256 amountOut);

    function verify(
        address user,
        uint256 totalAccrued,
        bytes32[] calldata proof
    ) external returns (uint256 amountVerified);

    function token() external view returns (address);
}
