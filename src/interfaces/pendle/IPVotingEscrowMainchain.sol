// SPDX-License-Identifier: MIT
// Acknowledgment: Interface derived from Pendle V2 (pendle-core-v2-public).
// Source: https://github.com/pendle-finance/pendle-core-v2-public
pragma solidity ^0.8.26;

import "./IPVeToken.sol";
import {Checkpoint} from "src/dependencies/pendle/VeHistoryLib.sol";

interface IPVotingEscrowMainchain is IPVeToken {
    function increaseLockPosition(uint128 additionalAmountToLock, uint128 expiry) external returns (uint128);

    function increaseLockPositionAndBroadcast(
        uint128 additionalAmountToLock,
        uint128 newExpiry,
        uint256[] calldata chainIds
    ) external returns (uint128 newVeBalance);

    function withdraw() external returns (uint128);

    function totalSupplyAt(uint128 timestamp) external view returns (uint128);

    function getUserHistoryLength(address user) external view returns (uint256);

    function getUserHistoryAt(address user, uint256 index) external view returns (Checkpoint memory);
}
