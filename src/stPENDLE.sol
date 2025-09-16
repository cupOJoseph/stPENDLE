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

import {ISTPENDLE} from "src/interfaces/ISTPENDLE.sol";
import 'forge-std/console.sol';
/**
 * @title stPENDLE - ERC-4626 Vault for PENDLE Staking
 * @notice Accepts PENDLE deposits and stakes them in vePENDLE for rewards
 * @dev Fully compliant with ERC-4626 tokenized vault standard using Solady
 */
contract stPENDLE is ERC4626, OwnableRoles, ReentrancyGuard, ISTPENDLE {
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

    // this vaults current information, total pendle, total locked pendle, current epoch start, last epoch update
    VaultPosition internal _vaultPosition;

    // Redemption queue management
    // redemption requests are tracked per epoch when the epoch advances all pending redemptions are cleared
    mapping(address user => mapping(uint256 epoch => uint256 pendingRedemptionAmount)) public
        pendingRedemptionSharesPerEpoch;
    mapping(uint256 epoch => uint256 totalPendingRedemptions) public totalPendingSharesPerEpoch;
    mapping(uint256 epoch => address[] requestedUserRedemptions) public redemptionUsersPerEpoch;

    modifier whenNotPaused() {
        _whenNotPaused();
        _;
    }

    modifier beforeFirstEpoch() {
        if (_vaultPosition.currentEpoch != 0) revert InvalidEpoch();
        _;
    }

    constructor(
        address _pendleTokenAddress,
        address _merkleDistributorAddress,
        address _votingEscrowMainchain,
        address _votingControllerAddress,
        address _timelockController,
        address _admin,
        uint256 _preLockRedemptionPeriod,
        uint256 _epochDuration
    ) {
        votingEscrowMainchain = IPVotingEscrowMainchain(_votingEscrowMainchain);
        merkleDistributor = IPMerkleDistributor(_merkleDistributorAddress);
        votingController = IPVotingController(_votingControllerAddress);
        ASSET = _pendleTokenAddress;
        _vaultPosition.preLockRedemptionPeriod = _preLockRedemptionPeriod;
        _vaultPosition.epochDuration = _safeCast128(_epochDuration);

        _initializeOwner(address(msg.sender));
        _grantRoles(_admin, ADMIN_ROLE);
        _grantRoles(_timelockController, TIMELOCK_CONTROLLER_ROLE);
        transferOwnership(_admin);
    }

    /// @dev Returns the address of the underlying asset
    function asset() public view virtual override returns (address) {
        return ASSET;
    }

    /// @dev Deposit PENDLE into the vault and stake it directly in vePENDLE
    function deposit(uint256 amount, address receiver) public override whenNotPaused returns (uint256) {
        uint256 sharesMinted = super.deposit(amount, receiver);
        // increase lock position in vePENDLE
        _lockPendle(amount, 0);

        return sharesMinted;
    }

    /**
     * @notice Deposit PENDLE into the vault before the first epoch
     * @param amount Amount of PENDLE to deposit
     * @param receiver Address to receive the shares
     * @return sharesMinted Amount of shares minted
     */
    function depositBeforeFirstEpoch(uint256 amount, address receiver)
        public
        beforeFirstEpoch
        whenNotPaused
        returns (uint256)
    {
        if (amount == 0) revert InvalidAmount();
        if (receiver == address(0)) revert InvalidReceiver();

        uint256 sharesMinted = super.deposit(amount, receiver);

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
        uint256 amountClaimed = merkleDistributor.claim(address(this), totalAccrued, proof);

        emit FeesClaimed(amountClaimed, block.timestamp);

        // Maintain 1:1 invariant: mint shares equal to fees received.
        // TODO: create a fee pool to mint the fees to to be claimed by share holders
        _mint(address(this), amountClaimed);

        // If redemption window has closed, lock all currently unlocked PENDLE
        uint256 amountToLock = amountClaimed;
        if (!_isWithinRedemptionWindow()) {
            uint256 unlocked = totalSupply() - _vaultPosition.totalLockedPendle;
            amountToLock = unlocked;
        }

        if (amountToLock > 0) {
            _lockPendle(amountToLock, 0);
        }
    }

    /**
     * @notice Start the first epoch, admin only function must have pendle balance in contract or will revert
     */
    function startFirstEpoch() external beforeFirstEpoch whenNotPaused nonReentrant onlyRoles(ADMIN_ROLE) {
        if (totalSupply() == 0) revert InvalidPendleBalance();

        uint256 newEpoch = _updateEpoch();
        _lockPendle(totalSupply(), _vaultPosition.epochDuration);
        _vaultPosition.totalLockedPendle = totalSupply();
        _vaultPosition.currentEpoch = newEpoch;
        _vaultPosition.currentEpochStart = block.timestamp;

        emit NewEpochStarted(newEpoch, block.timestamp, _vaultPosition.epochDuration);
    }

    /**
     * @notice Lock PENDLE into the vault and start new epoch, can be called by anyone after epoch has ended
     * @dev Can be called by anyone after epoch has ended, will revert if contract has no expired vePENDLE position
     * @dev Will revert if epoch is not ended
     */
    function startNewEpoch() external whenNotPaused nonReentrant {
        if(_vaultPosition.currentEpochStart + _vaultPosition.epochDuration > block.timestamp) revert InvalidEpoch();
        uint256 newEpoch = _updateEpoch();
        
        // 1) Claim matured vePENDLE
        uint256(votingEscrowMainchain.withdraw());
        _vaultPosition.totalLockedPendle = 0;

        uint256 totalPendleBalance = SafeTransferLib.balanceOf(address(asset()), address(this));

        // 2) Reserve assets for redemptions in the new epoch
        uint256 pendingShares = totalPendingSharesPerEpoch[newEpoch]; // tracked in shares
        uint256 reserveAssets = 0;
        if (pendingShares != 0) {
            // 1:1 semantics: reserve exactly the pending shares (clamped)
            reserveAssets = pendingShares;
            if (reserveAssets > totalPendleBalance) reserveAssets = totalPendleBalance; // clamp
        }

        // 3) Lock all remaining available assets
        uint256 assetsToLock = totalPendleBalance - reserveAssets;
        if (assetsToLock != 0) {
           _lockPendle(assetsToLock, _vaultPosition.epochDuration);
           
        }

        // 4) Advance epoch book-keeping
        _vaultPosition.currentEpoch = newEpoch;
        _vaultPosition.currentEpochStart = block.timestamp;
        _vaultPosition.lastEpochUpdate = block.timestamp;
        emit NewEpochStarted(newEpoch, block.timestamp, _vaultPosition.epochDuration);
    }

    /**
     * @notice Request a redeem shares for PENDLE from the vault
     * @param shares Amount of shares to redeem
     */
    function requestRedemptionForEpoch(uint256 shares, uint256 requestedEpoch) external nonReentrant whenNotPaused {
        _updateEpoch();
        if (requestedEpoch < _vaultPosition.currentEpoch + 1) revert InvalidEpoch();
        if (shares == 0) revert InvalidAmount();
        if (balanceOf(msg.sender) < shares) revert InsufficientBalance();

        // Add to pending redemption shares for requested epoch
        pendingRedemptionSharesPerEpoch[msg.sender][requestedEpoch] += shares;
        totalPendingSharesPerEpoch[requestedEpoch] += shares;

        // Add to redemption users for requested epoch
        redemptionUsersPerEpoch[requestedEpoch].push(msg.sender);

        emit RedemptionRequested(msg.sender, shares, requestedEpoch);
    }

    /**
     * @notice Claim redeem shares for PENDLE from the vault
     * @dev Can be called by the user to claim their redemption requests
     * @param shares Amount of shares to claim
     */
    function claimAvailableRedemptionShares(uint256 shares) external nonReentrant whenNotPaused returns (uint256) {
        _updateEpoch();
        if (shares == 0) revert InvalidAmount();
        _requireIsWithinRedemptionWindow();
        // Process redemption requests
        return _processRedemption(msg.sender, shares);
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
        if (block.timestamp - _vaultPosition.lastEpochUpdate < _vaultPosition.epochDuration) return 0;

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
    function getUserAvailableRedemption(address user) public returns (uint256) {
        // if redemption window has closed, return 0
        if (!_isWithinRedemptionWindow()) return 0;
        _updateEpoch();
        uint256 pendingRedemptionShares = pendingRedemptionSharesPerEpoch[user][_vaultPosition.currentEpoch];
        return pendingRedemptionShares;
    }

    /**
     * @notice Get all users who have requested redemption for an epoch
     * @param epoch Epoch to get redemption users for
     * @return Array of users who have requested redemption for the epoch
     */
    function redemptionUsersForEpoch(uint256 epoch) external view returns (address[] memory) {
        return redemptionUsersPerEpoch[epoch];
    }

    function currentEpoch() external returns (uint256) {
        return _updateEpoch();
    }

    function lastEpochUpdate() external view returns (uint256) {
        return _vaultPosition.lastEpochUpdate;
    }

    function epochDuration() external view returns (uint128) {
        return _vaultPosition.epochDuration;
    }

    function preLockRedemptionPeriod() external view returns (uint256) {
        return _vaultPosition.preLockRedemptionPeriod;
    }


    function totalLockedPendle() external view returns (uint256) {
        return _vaultPosition.totalLockedPendle;
    }

    function totalRequestedRedemptionAmountPerEpoch(uint256 epoch) external view returns (uint256) {
        return totalPendingSharesPerEpoch[epoch];
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
        if (_feeReceiver == address(0)) revert InvalidFeeReceiver(); // 0 address is not allowed
        feeReceiver = _feeReceiver;
        emit FeeReceiverSet(feeReceiver);
    }

    function setEpochDuration(uint128 _duration) public onlyRoles(TIMELOCK_CONTROLLER_ROLE) {
        if (_duration < 1 days) revert EpochDurationInvalid();
        if (_duration > 730 days) revert EpochDurationInvalid();
        _vaultPosition.epochDuration = _safeCast128(_duration);
        emit EpochDurationSet(_duration);
    }

    function setRewardsSplit(uint256 _rewardsSplit) public onlyRoles(TIMELOCK_CONTROLLER_ROLE) {
        if (_rewardsSplit > 100) revert InvalidRewardsSplit();
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
        if (_calculateEpoch() != _vaultPosition.currentEpoch + 1) {
            revert EpochNotEnded();
        }
    }

    function _requireIsWithinRedemptionWindow() internal view {
        if (block.timestamp > _vaultPosition.currentEpochStart + _vaultPosition.preLockRedemptionPeriod) {
            revert OutsideRedemptionWindow();
        }
    }

    function _isWithinRedemptionWindow() internal view returns (bool) {
        return block.timestamp < _vaultPosition.currentEpochStart + _vaultPosition.preLockRedemptionPeriod;
    }

    function _calculateEpoch() internal view returns (uint256) {
        return block.timestamp / _vaultPosition.epochDuration;
    }

    function _updateEpoch() internal returns (uint256 newEpoch) {
        newEpoch = _calculateEpoch();
        if (newEpoch > _vaultPosition.currentEpoch) {
            _vaultPosition.currentEpoch = newEpoch;
            _vaultPosition.lastEpochUpdate = block.timestamp;
            emit EpochUpdated(newEpoch, _vaultPosition.lastEpochUpdate);
        }
    }

    function _getAvailableRedemptionAmount() internal view returns (uint256) {
        return SafeTransferLib.balanceOf(address(asset()), address(this));
    }

    function _getTotalRequestedRedemptionAmountPerEpoch(uint256 epoch) internal view returns (uint256) {
        return totalPendingSharesPerEpoch[epoch];
    }

    function _processRedemption(address user, uint256 shares) internal returns (uint256) {
        // assert user has shares to redeem
        if (balanceOf(user) < shares) revert InsufficientBalance();

        uint256 currentPendingRedemptionShares = getUserAvailableRedemption(user);
        if (currentPendingRedemptionShares == 0) return 0;

        // assert that the user has enough pending redemption shares
        if (currentPendingRedemptionShares < shares) revert InsufficientShares();

        // Update pending amounts
        pendingRedemptionSharesPerEpoch[user][_vaultPosition.currentEpoch] -= shares;
        totalPendingSharesPerEpoch[_vaultPosition.currentEpoch] -= shares;

        // redeem shares
        uint256 amountRedeemed = super.redeem(shares, user, user);

        if (amountRedeemed != shares) revert InvalidRedemption();
        emit RedemptionProcessed(user, shares);

        return amountRedeemed;
    }

    function _lockPendle(uint256 amount, uint128 duration) internal {
        if (amount > totalSupply()) revert InvalidPendleBalance();
        SafeTransferLib.safeApprove(address(asset()), address(votingEscrowMainchain), amount);
        votingEscrowMainchain.increaseLockPosition(_safeCast128(amount), duration);
        _vaultPosition.totalLockedPendle += amount;
        emit AssetPositionIncreased(amount, _vaultPosition.currentEpoch, duration);
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

    /// @dev Enforce 1:1 shares <-> assets semantics.
    function convertToShares(uint256 assets) public pure override returns (uint256) {
        return assets;
    }

    /// @dev Enforce 1:1 shares <-> assets semantics.
    function convertToAssets(uint256 shares) public pure override returns (uint256) {
        return shares;
    }

    function previewRedeem(uint256 shares) public pure override returns (uint256) {
        return shares;
    }

    function previewDeposit(uint256 assets) public pure override returns (uint256) {
        return assets;
    }

    function redeem(uint256, /*shares */ address, /*to */ address /*owner*/ ) public pure override returns (uint256) {
        revert InvalidERC4626Function(); // this should never be called on this contract
    }

    function mint(uint256, /*shares*/ address /*to*/ ) public pure override returns (uint256) {
        revert InvalidERC4626Function();
    }

    function withdraw(uint256, /*assets*/ address, /*to*/ address /*owner*/ ) public pure override returns (uint256) {
        revert InvalidERC4626Function();
    }
}
