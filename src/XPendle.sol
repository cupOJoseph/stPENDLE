//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC4626} from "solady/tokens/ERC4626.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "lib/solady/src/utils/ReentrancyGuard.sol";

//basic interface for vePENDLE. Some things are missing here but these are all we need.
//
interface IVEPENDLE {
    function claimFees() external;
    function lock(uint256 amount, uint256 lockDuration) external;
    function unlock(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function getLockedBalance(address account) external view returns (uint256);
    function getUnlockTime(address account) external view returns (uint256);
}

interface IMerkleDistributor {
    function claimable(address account) external view returns (uint256);
    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external returns (uint256);
}

interface IVotingController {
    function vote(uint poll, uint voteAmount) external;
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

/**
 * @title xPENDLE - ERC-4626 Vault for PENDLE Staking
 * @notice Accepts PENDLE deposits and stakes them in vePENDLE for rewards
 * @dev Fully compliant with ERC-4626 tokenized vault standard using Solady
 */
contract xPENDLE is ERC4626, Ownable, ReentrancyGuard { 
    string public constant name = "xPENDLE";
    string public constant symbol = "xPEN";
    
    using SafeTransferLib for address;
    
    bool public feeSwitchIsEnabled = false;
    uint public feeBasisPoints = 0;
    address public feeReceiver;
    bool public useUSDTForFees = false;
    address public USDT;
    
    IVEPENDLE vePendle;
    IMerkleDistributor merkleDistributor;
    IVotingController votingController;

    uint public lockDurationDefault = 0;
    
    // Withdrawal queue management
    struct WithdrawalRequest {
        uint256 amount;
        uint256 requestTime;
        bool isProcessed;
    }
    
    mapping(address => WithdrawalRequest[]) public withdrawalRequests;
    mapping(address => uint256) public pendingWithdrawals;
    uint256 public totalPendingWithdrawals;
    
    // Epoch management
    uint256 public currentEpoch;
    uint256 public epochDuration = 1 days;
    uint256 public lastEpochUpdate;
    
    // Constants
    uint256 public constant MIN_LOCK_DURATION = 1 days;
    uint256 public constant MAX_LOCK_DURATION = 365 days;

    event FeeSwitchSet(bool enabled);
    event FeeBasisPointsSet(uint basisPoints);
    event LockDurationDefaultSet(uint duration);
    event FeeReceiverSet(address feeReceiver);
    event UseUSDTForFeesSet(bool useUSDT);
    event USDTSet(address usdt);
    event WithdrawalRequested(address indexed user, uint256 amount, uint256 requestTime);
    event WithdrawalProcessed(address indexed user, uint256 amount);
    event EpochUpdated(uint256 newEpoch);
    event FeesDistributed(uint256 pendleAmount, uint256 usdtAmount);

    address public immutable underlyingAsset;
    
    constructor(address pendleTokenAddress, address merkleDistributorAddress, address vePENDLETokenAddress, address votingControllerAddress, address usdtAddress) {
        underlyingAsset = pendleTokenAddress;
        vePendle = IVEPENDLE(vePENDLETokenAddress);
        merkleDistributor = IMerkleDistributor(merkleDistributorAddress);
        votingController = IVotingController(votingControllerAddress);
        USDT = usdtAddress;
        currentEpoch = block.timestamp / epochDuration;
        lastEpochUpdate = block.timestamp;
    }
    
    /// @dev Returns the address of the underlying asset
    function asset() public view virtual override returns (address) {
        return underlyingAsset;
    }
    
    /// @dev Returns the total amount of assets managed by the vault
    /// This includes PENDLE locked in vePENDLE plus any pending withdrawals
    function totalAssets() public view virtual override returns (uint256) {
        // Get the balance of PENDLE tokens in this contract
        uint256 contractBalance = SafeTransferLib.balanceOf(underlyingAsset, address(this));
        
        // Get the total locked amount in vePENDLE (this would need to be tracked)
        // For now, we'll use the contract balance as a starting point
        // You may want to add a mapping to track total locked amounts
        
        return contractBalance + totalPendingWithdrawals;
    }

    function deposit(uint256 amount, address receiver) public override returns (uint256) {
        uint depositAmount = super.deposit(amount, receiver);

        vePendle.lock(depositAmount, lockDurationDefault);

        return depositAmount;
    }

    // @dev This function is called by the anyone to claim fees to the vault.
    // This should be done daily or more often to compound rewards.
    function claimFees() public nonReentrant {
        uint claimedAmount = merkleDistributor.claim(0, msg.sender, 0, new bytes32[](0));
        
        if (feeSwitchIsEnabled && claimedAmount > 0) {
            uint fee = (claimedAmount * feeBasisPoints) / 10000;
            
            if (useUSDTForFees && USDT != address(0)) {
                // Convert PENDLE to USDT for fee distribution
                // This would require a DEX integration or oracle price feed
                // For now, we'll distribute the PENDLE fee amount
                uint256 usdtFee = _convertPendleToUSDT(fee);
                if (usdtFee > 0) {
                    SafeTransferLib.safeTransfer(USDT, feeReceiver, usdtFee);
                    emit FeesDistributed(0, usdtFee);
                }
            } else {
                // Distribute fee in PENDLE
                SafeTransferLib.safeTransfer(address(asset()), feeReceiver, fee);
                emit FeesDistributed(fee, 0);
            }
            
            claimedAmount -= fee;
        }   

        //lock everything claimed to the vault
        if (claimedAmount > 0) {
            vePendle.lock(claimedAmount, lockDurationDefault);
        }
    }
    
    /**
     * @notice Request a withdrawal of PENDLE from the vault
     * @param amount Amount of PENDLE to withdraw
     */
    function requestWithdrawal(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        // Check if user has enough shares
        uint256 shares = previewRedeem(amount);
        require(shares > 0, "Invalid shares amount");
        
        // Create withdrawal request
        withdrawalRequests[msg.sender].push(WithdrawalRequest({
            amount: amount,
            requestTime: block.timestamp,
            isProcessed: false
        }));
        
        pendingWithdrawals[msg.sender] += amount;
        totalPendingWithdrawals += amount;
        
        emit WithdrawalRequested(msg.sender, amount, block.timestamp);
    }
    
    /**
     * @notice Process withdrawal requests for the current epoch
     * @dev Can be called by anyone to process pending withdrawals
     */
    function processWithdrawals() external nonReentrant {
        _updateEpoch();
        
        uint256 availableForWithdrawal = _getAvailableWithdrawalAmount();
        require(availableForWithdrawal > 0, "No withdrawals available this epoch");
        
        // Process withdrawal requests in FIFO order
        // This is a simplified implementation - in production you might want more sophisticated queue management
        for (uint256 i = 0; i < withdrawalRequests[msg.sender].length; i++) {
            WithdrawalRequest storage request = withdrawalRequests[msg.sender][i];
            if (!request.isProcessed && request.amount <= availableForWithdrawal) {
                // Process the withdrawal
                _processWithdrawal(msg.sender, request.amount);
                request.isProcessed = true;
                availableForWithdrawal -= request.amount;
            }
        }
    }
    
    /**
     * @notice Re-lock PENDLE after withdrawal
     * @param amount Amount of PENDLE to re-lock
     * @param lockDuration Duration to lock for
     */
    function relockPendle(uint256 amount, uint256 lockDuration) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(lockDuration >= MIN_LOCK_DURATION, "Lock duration too short");
        require(lockDuration <= MAX_LOCK_DURATION, "Lock duration too long");
        
        // Transfer PENDLE from user to vault
        SafeTransferLib.safeTransferFrom(address(asset()), msg.sender, address(this), amount);
        
        // Lock in vePENDLE
        vePendle.lock(amount, lockDuration);
        
        // Mint shares to user
        uint256 shares = previewDeposit(amount);
        _mint(msg.sender, shares);
    }
    
    /**
     * @notice Get the amount of PENDLE that can be withdrawn in the next epoch
     * @return Amount available for withdrawal
     */
    function getNextEpochWithdrawalAmount() external view returns (uint256) {
        return _getAvailableWithdrawalAmount();
    }
    
    /**
     * @notice Get user's pending withdrawal amount
     * @param user Address of the user
     * @return Total pending withdrawal amount
     */
    function getUserPendingWithdrawal(address user) external view returns (uint256) {
        return pendingWithdrawals[user];
    }
    
    /**
     * @notice Get user's withdrawal requests
     * @param user Address of the user
     * @return Array of withdrawal requests
     */
    function getUserWithdrawalRequests(address user) external view returns (WithdrawalRequest[] memory) {
        return withdrawalRequests[user];
    }
    
    /**
     * @notice Check if a withdrawal request can be processed
     * @param user Address of the user
     * @param requestIndex Index of the withdrawal request
     * @return True if the request can be processed
     */
    function canProcessWithdrawal(address user, uint256 requestIndex) external view returns (bool) {
        if (requestIndex >= withdrawalRequests[user].length) return false;
        
        WithdrawalRequest storage request = withdrawalRequests[user][requestIndex];
        if (request.isProcessed) return false;
        
        uint256 availableForWithdrawal = _getAvailableWithdrawalAmount();
        return request.amount <= availableForWithdrawal;
    }

    /// =========== Governance Council Functions ================ ///

    function setFeeSwitch(bool enabled) public onlyOwner {
        feeSwitchIsEnabled = enabled;
        emit FeeSwitchSet(enabled);
    }

    function setFeeBasisPoints(uint basisPoints) public onlyOwner {
        require(basisPoints <= 1000, "Fee cannot exceed 10%");
        feeBasisPoints = basisPoints;
        emit FeeBasisPointsSet(basisPoints);
    }

    function setLockDurationDefault(uint duration) public onlyOwner {
        require(duration >= MIN_LOCK_DURATION, "Duration too short");
        require(duration <= MAX_LOCK_DURATION, "Duration too long");
        lockDurationDefault = duration;
        emit LockDurationDefaultSet(duration);
    }
    
    function setFeeReceiver(address _feeReceiver) public onlyOwner {
        require(_feeReceiver != address(0), "Invalid fee receiver");
        feeReceiver = _feeReceiver;
        emit FeeReceiverSet(feeReceiver);
    }
    
    function setUseUSDTForFees(bool _useUSDT) public onlyOwner {
        useUSDTForFees = _useUSDT;
        emit UseUSDTForFeesSet(_useUSDT);
    }
    
    function setUSDT(address _usdt) public onlyOwner {
        require(_usdt != address(0), "Invalid USDT address");
        USDT = _usdt;
        emit USDTSet(_usdt);
    }
    
    function setEpochDuration(uint256 _duration) public onlyOwner {
        require(_duration >= 1 hours, "Epoch duration too short");
        require(_duration <= 7 days, "Epoch duration too long");
        epochDuration = _duration;
    }

    /// =========== Internal Functions ================ ///
    
    function _updateEpoch() internal {
        uint256 newEpoch = block.timestamp / epochDuration;
        if (newEpoch > currentEpoch) {
            currentEpoch = newEpoch;
            lastEpochUpdate = block.timestamp;
            emit EpochUpdated(newEpoch);
        }
    }
    
    function _getAvailableWithdrawalAmount() internal view returns (uint256) {
        // This is a simplified calculation - in production you'd want more sophisticated logic
        // based on vePENDLE unlock schedules and vault liquidity
        uint256 totalLocked = vePendle.balanceOf(address(this));
        uint256 available = totalLocked / 10; // Allow 10% of locked amount per epoch
        
        // Ensure we don't exceed pending withdrawals
        if (available > totalPendingWithdrawals) {
            available = totalPendingWithdrawals;
        }
        
        return available;
    }
    
    function _processWithdrawal(address user, uint256 amount) internal {
        // Unlock from vePENDLE
        vePendle.unlock(amount);
        
        // Update pending amounts
        pendingWithdrawals[user] -= amount;
        totalPendingWithdrawals -= amount;
        
        // Transfer PENDLE to user
        SafeTransferLib.safeTransfer(address(asset()), user, amount);
        
        emit WithdrawalProcessed(user, amount);
    }
    
    function _convertPendleToUSDT(uint256 pendleAmount) internal view returns (uint256) {
        // This is a placeholder - in production you'd integrate with a DEX or oracle
        // For now, return a simple conversion (1 PENDLE = 1 USDT)
        // In reality, you'd want to use Uniswap V3, Chainlink oracle, or similar
        return pendleAmount;
    }
}