//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IstPENDLEExitNFT
 * @notice Receiver for cross-chain transfers of stPENDLE.
 * this contract will mint stPENDLE on the destination chain and burn tokens being sent to another chain
 */
interface IstPENDLEExitNFT {

    error InvalidOwner();
    error AlreadyClaimed();

    struct ExitNFTData {
        uint256 requestedShares;
        uint256 requestedEpoch;
        bool claimed;
    }

    function createExitPosition(address _to, uint256 _shares) external;
    function redeemExitPosition(address _to, uint256 _tokenId) external returns (uint256 pendleClaimed);
    function getExitNFTData(uint256 _tokenId) external view returns (ExitNFTData memory);
    function getRequestedRedemptionAmount(uint256 _tokenId) external view returns (uint256);
    
}