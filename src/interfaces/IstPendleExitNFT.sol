//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IstPendleExitNFT
 * @notice Receiver for cross-chain transfers of stPENDLE.
 * this contract will mint stPENDLE on the destination chain and burn tokens being sent to another chain
 */
interface IstPendleExitNFT {
    struct ExitNFT {
        uint256 tokenId;
        uint256 stakedPendle;
        uint256 epoch;
        uint256 amount;
        bool claimed;
        uint256 claimableAt;
    }
}