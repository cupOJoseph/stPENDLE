    // SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Withdrawal queue management
struct WithdrawalRequest {
    address receiver;
    uint256 amount;
    uint256 requestTime;
    uint256 eligibleEpoch;
    bool isProcessed;
}

struct UserPosition {
    uint256 totalAmount;
    uint256 totalLockedPendle;
    uint256 lastDepositTime;
}

struct VaultPosition {
    uint256 totalPendleUnderManagement;
    uint256 totalLockedPendle;
    uint256 currentEpoch;
    uint256 epochDuration;
    uint256 lastEpochUpdate;
    uint256 firstEpochStart;
    uint256 preLockRedemptionPeriod;
}
