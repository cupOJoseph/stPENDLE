// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPMerkleDistributor} from "src/interfaces/pendle/IPMerkleDistributor.sol";
import {IPVotingEscrowMainchain} from "src/interfaces/pendle/IPVotingEscrowMainchain.sol";
import {IPVotingController} from "src/interfaces/pendle/IPVotingController.sol";
import {IERC4626} from "lib/forge-std/src/interfaces/IERC4626.sol";

interface ISTPENDLE {
    struct VaultPosition {
        uint256 totalLockedPendle;
        uint256 currentEpoch;
        uint128 epochDuration;
        uint256 lastEpochUpdate;
        uint256 currentEpochStart;
        uint256 preLockRedemptionPeriod;
    }

    // -------- External state-changing --------
    function claimFees(uint256 totalAccrued, bytes32[] calldata proof) external;
    function startNewEpoch() external;
    function requestRedemptionForEpoch(uint256 shares, uint256 epoch) external;
    function claimAvailableRedemptionShares(uint256 shares) external returns (uint256 assetsRedeemed);
    function processRedemptions() external;

    // -------- Redemption queue  --------
    function previewVeWithdraw() external view returns (uint256);
    function totalRequestedRedemptionAmountPerEpoch(uint256 epoch) external view returns (uint256);
    function getAvailableRedemptionAmount() external view returns (uint256);
    function getUserAvailableRedemption(address user) external view returns (uint256);
    function redemptionUsersForEpoch(uint256 epoch) external view returns (address[] memory);

    // -------- Public views --------
    function ADMIN_ROLE() external view returns (uint256);
    function TIMELOCK_CONTROLLER_ROLE() external view returns (uint256);
    function merkleDistributor() external view returns (IPMerkleDistributor);
    function votingEscrowMainchain() external view returns (IPVotingEscrowMainchain);
    function votingController() external view returns (IPVotingController);
    function ASSET() external view returns (address);
    function feeSwitchIsEnabled() external view returns (bool);
    function feeBasisPoints() external view returns (uint256);
    function feeReceiver() external view returns (address);
    function paused() external view returns (bool);
    function rewardsSplit() external view returns (uint256);
    function epochDuration() external view returns (uint128);
    function preLockRedemptionPeriod() external view returns (uint256);
    function totalLockedPendle() external view returns (uint256);
    function currentEpoch() external view returns (uint256);
    function lastEpochUpdate() external view returns (uint256);

    // Auto-generated mapping getters
    function pendingRedemptionSharesPerEpoch(address user, uint256 epoch) external view returns (uint256);
    function totalPendingSharesPerEpoch(uint256 epoch) external view returns (uint256);
    function redemptionUsersPerEpoch(uint256 epoch, uint256 index) external view returns (address);

    // -------- Governance/admin --------
    function setFeeSwitch(bool enabled) external;
    function setFeeBasisPoints(uint256 basisPoints) external;
    function setFeeReceiver(address _feeReceiver) external;
    function setEpochDuration(uint128 _duration) external;
    function setRewardsSplit(uint256 _rewardsSplit) external;
    function setOwner(address _owner) external;
    function pause() external;
    function unpause() external;

    // events
    event FeeSwitchSet(bool enabled);
    event FeeBasisPointsSet(uint256 basisPoints);
    event LockDurationDefaultSet(uint256 duration);
    event FeeReceiverSet(address feeReceiver);
    event RedemptionRequested(address indexed user, uint256 amount, uint256 requestTime);
    event RedemptionProcessed(address indexed user, uint256 amount);
    event EpochUpdated(uint256 newEpoch, uint256 lastEpochUpdate);
    event NewEpochStarted(uint256 newEpoch, uint256 lastEpochUpdate, uint256 additionalTime);
    event EpochDurationSet(uint128 duration);
    event AssetPositionIncreased(uint256 amount, uint256 currentEpoch, uint256 additionalTime);
    event FeesClaimed(uint256 amount, uint256 timestamp);
    event FeesDistributed(uint256 pendleAmount, uint256 usdtAmount);
    event Paused(bool paused);
    event RedemptionExpired(address indexed user, uint256 amount);
    //test

    error InvalidPendleBalance();

    // errors
    error EpochNotEnded();
    error EpochDurationInvalid();
    error InvalidAmount();
    error InsufficientShares();
    error InvalidRedemptionAmount(uint256 withdrawnAmount, uint256 availableForRedemption);
    error InvalidFeeBasisPoints();
    error IsPaused();
    error OutsideRedemptionWindow();
    error InvalidRedemption();
    error InvalidERC4626Function();
    error InsufficientRequestedRedemptionAmount();
    error InvalidEpoch();
    error InsufficientRedemptionAmount();
    error InvalidFeeReceiver();
    error InvalidRewardsSplit();
    error InvalidReceiver();
}
