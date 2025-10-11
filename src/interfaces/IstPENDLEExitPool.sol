// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPMerkleDistributor} from "src/interfaces/pendle/IPMerkleDistributor.sol";
import {IPVotingEscrowMainchain} from "src/interfaces/pendle/IPVotingEscrowMainchain.sol";
import {IPVotingController} from "src/interfaces/pendle/IPVotingController.sol";

interface ISTPENDLEExitPool {
    struct RedemptionData {
        uint256 redemptionRate;
        uint256 totalPendle;
        uint256 totalRequestedShares;
    }

    function redemptionDataByEpoch(uint256 epoch) external view returns (RedemptionData memory);
    function getTotalRequestedShares(uint256 epoch) external view returns (uint256);
    function getTotalPendle(uint256 epoch) external view returns (uint256);
    function setRedemptionRate(uint256 epoch, uint256 redemptionRate) external;
    function addShares(address user, uint256 shares, uint256 epoch) external;
    function addPendle(uint256 amount, uint256 epoch) external;
    function claimShares(address to, uint256 tokenId) external returns (uint256 amountRedeemed);
}