    // SPDX-License-Identifier: MIT
    pragma solidity ^0.8.0;

    // Withdrawal queue management
    struct WithdrawalRequest {
        uint256 amount;
        uint256 requestTime;
        bool isProcessed;
    }

    struct Deposit {
        uint256 amount;
        uint256 depositTime;
    }
    
    struct UserPosition {
        uint256 totalAmount;
        uint256 totalLockedAmount;
        uint256 lastDepositTime;
        uint32 depositIndex;
        mapping(uint32 => Deposit) deposits;
    }

    struct VaultPosition {
        uint256 totalAmountUnderManagement;
        uint256 totalLockedAmount;
        uint256 currentEpoch;
        uint256 lastEpochUpdate;
    }
    