//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC4626} from "lib/solady/src/tokens/ERC4626.sol";
import {OwnableRoles} from "lib/solady/src/auth/OwnableRoles.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "lib/solady/src/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "lib/solady/src/utils/FixedPointMathLib.sol";

import {IPMerkleDistributor} from "src/interfaces/pendle/IPMerkleDistributor.sol";
import {IPVotingEscrowMainchain} from "src/interfaces/pendle/IPVotingEscrowMainchain.sol";
import {IPVotingController} from "src/interfaces/pendle/IPVotingController.sol";

import {VaultPosition} from "src/dependencies/VaultStructs.sol";

/**
 * @title stPENDLE - ERC-4626 Vault for PENDLE Staking
 * @notice Accepts PENDLE deposits and stakes them in vePENDLE for rewards
 * @dev Fully compliant with ERC-4626 tokenized vault standard using Solady
 */
contract stPENDLE is ERC4626, OwnableRoles, ReentrancyGuard {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant TIMELOCK_CONTROLLER_ROLE = _ROLE_1;

    // interfaces
    IPMerkleDistributor public merkleDistributor;
    IPVotingEscrowMainchain public votingEscrowMainchain;
    IPVotingController public votingController;

    address public immutable ASSET;
    // settings
    bool public feeSwitchIsEnabled = false;
    uint256 public feeBasisPoints = 0;
    address public feeReceiver;
    bool public paused = false;
    uint256 public rewardsSplit = 0;

    // Epoch management

    uint128 public epochDuration = 30 days;
    // the amount of time before an epoch ends and a new epoch starts that the user can still withdraw their PENDLE
    uint128 public preLockRedemptionPeriod = 7 days;

    // this vaults current information, total pendle, total locked pendle, current epoch start, last epoch update
    VaultPosition public vaultPosition;

    // Redemption queue management
    // redemption requests are tracked per epoch when the epoch advances all pending redemptions are cleared
    mapping(address user => mapping(uint256 epoch => uint256 pendingRedemptionAmount)) public
        pendingRedemptionSharesPerEpoch;
    mapping(uint256 epoch => uint256 totalPendingRedemptions) public totalPendingSharesPerEpoch;
    mapping(uint256 epoch => address[] requestedUserRedemptions) public redemptionUsersPerEpoch;

    // events
    event FeeSwitchSet(bool enabled);
    event FeeBasisPointsSet(uint256 basisPoints);
    event LockDurationDefaultSet(uint256 duration);
    event FeeReceiverSet(address feeReceiver);
    event RedemptionRequested(address indexed user, uint256 amount, uint256 requestTime);
    event RedemptionProcessed(address indexed user, uint256 amount);
    event EpochUpdated(uint256 newEpoch, uint256 lastEpochUpdate);
    event EpochDurationSet(uint128 duration);
    event FeesDistributed(uint256 pendleAmount, uint256 usdtAmount);
    event Paused(bool paused);
    event RedemptionExpired(address indexed user, uint256 amount);

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
    error InvalidMint();
    error InsufficientRequestedRedemptionAmount();
    error InvalidEpoch();
    error InsufficientRedemptionAmount();

    modifier whenNotPaused() {
        _whenNotPaused();
        _;
    }

    constructor(
        address _pendleTokenAddress,
        address _merkleDistributorAddress,
        address _votingEscrowMainchain,
        address _votingControllerAddress,
        address _timelockController,
        address _admin,
        uint256 _firstEpochStartTime
    ) {
        votingEscrowMainchain = IPVotingEscrowMainchain(_votingEscrowMainchain);
        merkleDistributor = IPMerkleDistributor(_merkleDistributorAddress);
        votingController = IPVotingController(_votingControllerAddress);
        ASSET = _pendleTokenAddress;
        // we anchor the first epoch to the timestamp where we begin the first epoch
        vaultPosition.firstEpochStart = _firstEpochStartTime;
        vaultPosition.preLockRedemptionPeriod = 20 days;
        _initializeOwner(address(msg.sender));
        _grantRoles(_admin, ADMIN_ROLE);
        _grantRoles(_timelockController, TIMELOCK_CONTROLLER_ROLE);
        transferOwnership(_admin);
    }

    /// @dev Returns the address of the underlying asset
    function asset() public view virtual override returns (address) {
        return ASSET;
    }

    /// @dev Returns the total amount of assets managed by the vault
    /// This includes locked PENDLE, PENDLE locked in vePENDLE
    function totalAssets() public view virtual override returns (uint256) {
        return vaultPosition.totalPendleUnderManagement;
    }

    /// @dev Deposit PENDLE into the vault and stake it directly in vePENDLE
    function deposit(uint256 amount, address receiver) public override whenNotPaused returns (uint256) {
        uint256 sharesMinted = super.deposit(amount, receiver);
        // update vault position
        vaultPosition.totalPendleUnderManagement += amount;
        vaultPosition.totalLockedPendle += amount;
        
        // increase lock position in vePENDLE
        SafeTransferLib.safeApprove(address(asset()), address(votingEscrowMainchain), amount);
        votingEscrowMainchain.increaseLockPosition(_safeCast128(amount), 0);

        return sharesMinted;
    }

    /**
     * @dev This function is called by the anyone to claim fees to the vault and lock them in the current epoch.
     * @param totalAccrued The total amount of fees accrued to the vault
     * @param proof The proof for the merkle root
     * This should be done daily or more often to compound rewards.
     */
    function claimFees(uint256 totalAccrued, bytes32[] calldata proof) public nonReentrant whenNotPaused {
        if (totalAccrued == 0) revert InvalidAmount();
        // will revert if proof or totalAccrued is invalid
        uint256 claimedAmount = merkleDistributor.claim(address(this), totalAccrued, proof);

        //lock everything claimed back into current escrow epoch
        if (claimedAmount > 0) {
            // lock fees without increasing the lock duration
            votingEscrowMainchain.increaseLockPosition(_safeCast128(claimedAmount), 0);
        }
    }

    /**
     * @notice Lock PENDLE into the vault
     * @dev Can be called if epoch has ended to lock PENDLE
     */
    function startNewEpoch() external whenNotPaused nonReentrant {
        uint256 newEpoch = _calculateEpoch();
        if (newEpoch <= vaultPosition.currentEpoch) revert InvalidEpoch();

        // 1) Claim matured vePENDLE
        uint256 claimed = uint256(votingEscrowMainchain.withdraw());
        vaultPosition.totalLockedPendle -= claimed;

        // 2) Reserve assets for redemptions in the new epoch
        uint256 pendingShares = totalPendingSharesPerEpoch[newEpoch]; // tracked in shares
        uint256 reserveAssets = 0;
        if (pendingShares != 0) {
            uint256 ts = totalSupply();
            if (ts != 0) {
                uint256 ta = totalAssets();
                reserveAssets = FixedPointMathLib.fullMulDivUp(pendingShares, ta, ts);
                if (reserveAssets > claimed) reserveAssets = claimed; // clamp
            }
        }

        // 3) Lock all remaining available assets
        uint256 assetsToLock = claimed - reserveAssets;
        if (assetsToLock != 0) {
            votingEscrowMainchain.increaseLockPosition(_safeCast128(assetsToLock), epochDuration);
            vaultPosition.totalLockedPendle += assetsToLock;
        }

        // 4) Advance epoch book-keeping
        vaultPosition.currentEpoch = newEpoch;
        vaultPosition.lastEpochUpdate = block.timestamp;
        emit EpochUpdated(newEpoch, block.timestamp);
    }

    /**
     * @notice Request a redeem shares for PENDLE from the vault
     * @param shares Amount of shares to redeem
     */
    function requestRedemptionForEpoch(uint256 shares, uint256 epoch) external nonReentrant whenNotPaused {
        if (epoch == 0) {
            epoch = vaultPosition.currentEpoch + 1;
        }
        if (epoch < vaultPosition.currentEpoch + 1) revert InvalidEpoch();
        if (shares == 0) revert InvalidAmount();
        if (balanceOf(msg.sender) < shares) revert InsufficientBalance();

        // Check if user has enough shares to redeem
        uint256 amount = previewRedeem(shares);
        if (amount == 0) revert InsufficientShares();

        // Add to pending redemption shares for requested epoch
        pendingRedemptionSharesPerEpoch[msg.sender][epoch] += shares;
        totalPendingSharesPerEpoch[epoch] += shares;

        // Add to redemption users for requested epoch
        redemptionUsersPerEpoch[epoch].push(msg.sender);

        emit RedemptionRequested(msg.sender, shares, epoch);
    }

    /**
     * @notice Claim redeem shares for PENDLE from the vault
     * @dev Can be called by the user to claim their redemption requests
     * @param shares Amount of shares to claim
     */
    function claimAvailableRedemptionShares(uint256 shares) external nonReentrant whenNotPaused {
        if (shares == 0) revert InvalidAmount();
        _requireIsWithinRedemptionWindow();
        // Process redemption requests
        _processRedemption(msg.sender, shares);
    }

    /**
     * @notice Process redemption requests for the current epoch can be called by any kind user who wants to pay for everyone's redemption gas
     * @dev Can be called by anyone to process pending redemptions
     */
    function processRedemptions() external nonReentrant whenNotPaused {
        _updateEpoch();
        // Only allow processing in day 0-20 of the current epoch
        _requireIsWithinRedemptionWindow();

        uint256 availableForRedemption = _getAvailableRedemptionAmount();
        uint256 totalPendingRedemptions = totalPendingSharesPerEpoch[vaultPosition.currentEpoch];
        if (availableForRedemption < totalPendingRedemptions) {
            revert InvalidRedemptionAmount(totalPendingRedemptions, availableForRedemption);
        }
        // withdraw from voting escrow
        uint256 withdrawnAmount = votingEscrowMainchain.withdraw();
        if (withdrawnAmount < availableForRedemption) {
            revert InvalidRedemptionAmount(withdrawnAmount, availableForRedemption);
        }
        // Process redemption requests in FIFO order
        address[] memory users = redemptionUsersPerEpoch[vaultPosition.currentEpoch];

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 userRedemptionShares = pendingRedemptionSharesPerEpoch[user][vaultPosition.currentEpoch];

            if (userRedemptionShares > 0) {
                uint256 amountRedeemed = _processRedemption(user, userRedemptionShares);
                availableForRedemption -= amountRedeemed;
                if (availableForRedemption == 0) break;
            }
        }
    }

    /// ============ View Functions ================ ///

    function name() public pure override returns (string memory) {
        return "stPENDLE";
    }

    function symbol() public pure override returns (string memory) {
        return "stPEN";
    }

    /**
     * @notice Preview the amount of PENDLE that can be withdrawn immediately from the pendle voting escrow vault position must be expired
     * @return Amount available for redemption
     */
    function previewVeWithdraw() public view returns (uint256) {
        if (block.timestamp - vaultPosition.lastEpochUpdate < vaultPosition.epochDuration) return 0;

        (bool success, bytes memory data) =
            address(votingEscrowMainchain).staticcall(abi.encodeWithSelector(votingEscrowMainchain.withdraw.selector));
        return success ? abi.decode(data, (uint128)) : 0;
    }

    function getTotalRequestedRedemptionAmountPerEpoch(uint256 epoch) external view returns (uint256) {
        return _getTotalRequestedRedemptionAmountPerEpoch(epoch);
    }

    /**
     * @notice Get the amount of PENDLE that can currently be redeemed
     * @return Amount available for redemption
     */
    function getAvailableRedemptionAmount() external view returns (uint256) {
        return _getAvailableRedemptionAmount();
    }

    /**
     * @notice Get user's pending redemption amount for the current epoch
     * @param user Address of the user
     * @return Total pending redemption shares for the user in the current epoch
     */
    function getUserAvailableRedemption(address user) public view returns (uint256) {
        uint256 pendingRedemptionShares = pendingRedemptionSharesPerEpoch[user][vaultPosition.currentEpoch];
        if (block.timestamp > vaultPosition.lastEpochUpdate + vaultPosition.preLockRedemptionPeriod) return 0; // if redemption window has closed, return 0
        return pendingRedemptionShares;
    }

    /**
     * @notice Get all users who have requested redemption for an epoch
     * @param epoch Epoch to get redemption users for
     * @return Array of users who have requested redemption for the epoch
     */
    function getRedemptionUsersForEpoch(uint256 epoch) external view returns (address[] memory) {
        return redemptionUsersPerEpoch[epoch];
    }

    function getCurrentEpoch() external view returns (uint256) {
        return vaultPosition.currentEpoch;
    }

    function getLastEpochUpdate() external view returns (uint256) {
        return vaultPosition.lastEpochUpdate;
    }

    function getFirstEpochStart() external view returns (uint256) {
        return vaultPosition.firstEpochStart;
    }

    function getEpochDuration() external view returns (uint256) {
        return vaultPosition.epochDuration;
    }

    function getPreLockRedemptionPeriod() external view returns (uint256) {
        return vaultPosition.preLockRedemptionPeriod;
    }

    function getTotalPendleUnderManagement() external view returns (uint256) {
        return vaultPosition.totalPendleUnderManagement;
    }

    function gettotalLockedPendle() external view returns (uint256) {
        return vaultPosition.totalLockedPendle;
    }

    /// =========== Governance Council Functions ================ ///

    function setFeeSwitch(bool enabled) public onlyRoles(ADMIN_ROLE) {
        feeSwitchIsEnabled = enabled;
        emit FeeSwitchSet(enabled);
    }

    function setFeeBasisPoints(uint256 basisPoints) public onlyRoles(ADMIN_ROLE) {
        if (basisPoints > 1000) revert InvalidFeeBasisPoints();
        feeBasisPoints = basisPoints;
        emit FeeBasisPointsSet(basisPoints);
    }

    function setFeeReceiver(address _feeReceiver) public onlyRoles(ADMIN_ROLE) {
        require(_feeReceiver != address(0), "Invalid fee receiver");
        feeReceiver = _feeReceiver;
        emit FeeReceiverSet(feeReceiver);
    }

    function setEpochDuration(uint128 _duration) public onlyRoles(TIMELOCK_CONTROLLER_ROLE) {
        require(_duration >= 1 days, "Epoch duration too short");
        require(_duration <= 730 days, "Epoch duration too long");
        vaultPosition.epochDuration = _duration;
        emit EpochDurationSet(_duration);
    }

    function setRewardsSplit(uint256 _rewardsSplit) public onlyRoles(TIMELOCK_CONTROLLER_ROLE) {
        require(_rewardsSplit <= 100, "Rewards split cannot exceed 100%");
        rewardsSplit = _rewardsSplit;
    }

    function setOwner(address _owner) public onlyOwner {
        _setOwner(_owner);
    }

    function pause() public onlyOwner {
        _setPause(true);
    }

    function unpause() public onlyOwner {
        _setPause(false);
    }

    /// =========== Internal Functions ================ ///
    function _requireNextEpoch() internal view {
        if (_calculateEpoch() != vaultPosition.currentEpoch + 1) {
            revert EpochNotEnded();
        }
    }

    function _calculateEpoch() internal view returns (uint256) {
        return block.timestamp - vaultPosition.firstEpochStart / vaultPosition.epochDuration;
    }

    function _updateEpoch() internal {
        uint256 newEpoch = _calculateEpoch();
        if (newEpoch > vaultPosition.currentEpoch) {
            vaultPosition.currentEpoch = newEpoch;
            vaultPosition.lastEpochUpdate = block.timestamp;
            emit EpochUpdated(newEpoch, vaultPosition.lastEpochUpdate);
        }
    }

    function _getAvailableRedemptionAmount() internal view returns (uint256) {
        // the amount of pendle currently available to withdraw (unlocked in this contract)
        uint256 available = vaultPosition.totalPendleUnderManagement - vaultPosition.totalLockedPendle;

        return available;
    }

    function _getTotalRequestedRedemptionAmountPerEpoch(uint256 epoch) internal view returns (uint256) {
        return totalPendingSharesPerEpoch[epoch];
    }

    function _requireIsWithinRedemptionWindow() internal view {
        if (block.timestamp > vaultPosition.lastEpochUpdate + vaultPosition.preLockRedemptionPeriod) {
            revert OutsideRedemptionWindow();
        }
    }

    function _processRedemption(address user, uint256 shares) internal returns (uint256) {
        // assert user has shares to redeem
        if (balanceOf(user) < shares) revert InsufficientBalance();

        uint256 currentPendingRedemptionShares = getUserAvailableRedemption(user);
        if (currentPendingRedemptionShares == 0) return 0;

        // assert that the user has enough pending redemption shares
        if (currentPendingRedemptionShares < shares) revert InsufficientShares();

        // convert to underlying PENDLE
        uint256 pendleToReceive = FixedPointMathLib.fullMulDivUp(shares, totalAssets(), totalSupply());

        // assert that vault has enough balance
        if (SafeTransferLib.balanceOf(address(asset()), address(this)) < pendleToReceive) revert InsufficientBalance();

        // Update pending amounts
        pendingRedemptionSharesPerEpoch[user][vaultPosition.currentEpoch] -= shares;
        totalPendingSharesPerEpoch[vaultPosition.currentEpoch] -= shares;

        // redeem shares
        uint256 amountRedeemed = super.redeem(shares, user, user);

        // update vault position
        vaultPosition.totalPendleUnderManagement -= amountRedeemed;

        if (amountRedeemed > pendleToReceive) revert InvalidRedemption();
        emit RedemptionProcessed(user, pendleToReceive);

        return amountRedeemed;
    }

    function _safeCast128(uint256 value) internal pure returns (uint128) {
        if (value > type(uint128).max) revert InvalidAmount();
        // casting to 'uint128' is safe because value is less than type(uint128).max
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint128(value);
    }

    function _whenNotPaused() internal view {
        if (paused) revert IsPaused();
    }

    function _setPause(bool _paused) internal {
        paused = _paused;
        emit Paused(_paused);
    }

    // ERC 4626 overrides

    function redeem(uint256, /*shares */ address, /*to */ address /*owner*/ ) public override returns (uint256) {
        revert InvalidRedemption(); // this should never be called on this contract
    }

    function mint(uint256, /*shares*/ address /*to*/ ) public override returns (uint256) {
        revert InvalidMint();
    }
}
