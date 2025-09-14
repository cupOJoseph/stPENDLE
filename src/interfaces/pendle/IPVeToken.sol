// SPDX-License-Identifier: MIT
// Acknowledgment: Interface derived from Pendle V2 (pendle-core-v2-public).
// Source: https://github.com/pendle-finance/pendle-core-v2-public
pragma solidity ^0.8.26;

interface IPVeToken {
    function balanceOf(address user) external view returns (uint128);

    function positionData(address user) external view returns (uint128 amount, uint128 expiry);

    function totalSupplyStored() external view returns (uint128);

    function totalSupplyCurrent() external returns (uint128);

    function totalSupplyAndBalanceCurrent(address user) external returns (uint128, uint128);
}
