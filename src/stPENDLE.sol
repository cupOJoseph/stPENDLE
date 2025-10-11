//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC4626} from "lib/solady/src/tokens/ERC4626.sol";
import {OwnableRoles} from "lib/solady/src/auth/OwnableRoles.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "lib/solady/src/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "lib/solady/src/utils/FixedPointMathLib.sol";
import {VeBalanceLib} from "src/dependencies/pendle/VeBalanceLib.sol";
import {IPMerkleDistributor} from "src/interfaces/pendle/IPMerkleDistributor.sol";
import {IPVotingEscrowMainchain} from "src/interfaces/pendle/IPVotingEscrowMainchain.sol";
import {IPVotingController} from "src/interfaces/pendle/IPVotingController.sol";
import {IstPENDLECrossChain} from "src/interfaces/IstPENDLECrossChain.sol";
import {IstPENDLE} from "src/interfaces/IstPENDLE.sol";
import {IstPENDLEExitNFT} from "src/interfaces/IstPENDLEExitNFT.sol";
import {IstPENDLEExitPool} from "src/interfaces/IstPENDLEExitPool.sol";

// cross chain
import {CCIPReceiver} from "lib/chainlink-ccip/chains/evm/contracts/applications/CCIPReceiver.sol";
import {Client} from "lib/chainlink-ccip/chains/evm/contracts/libraries/Client.sol";
import {IRouterClient} from "lib/chainlink-ccip/chains/evm/contracts/interfaces/IRouterClient.sol";
// import "forge-std/console.sol";
/**
 * @title stPENDLE - ERC-4626 Vault for PENDLE Staking
 * @notice Accepts PENDLE deposits and stakes them in vePENDLE for rewards
 * @dev Fully compliant with ERC-4626 tokenized vault standard using Solady
 */

contract stPENDLE is ERC4626, OwnableRoles, ReentrancyGuard, IstPENDLE, IstPENDLECrossChain, CCIPReceiver {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant TIMELOCK_CONTROLLER_ROLE = _ROLE_1;
    uint256 public constant ST_PENDLE_EXIT_POOL_ROLE = _ROLE_2;

    uint256 public constant FEE_BASIS_POINTS = 1e18; // 1e18 = 100%

    // interfaces
    IPMerkleDistributor public merkleDistributor;
    IPVotingEscrowMainchain public votingEscrowMainchain;
    IPVotingController public votingController;

    // exit queue
    IstPENDLEExitNFT public stPENDLEExitNFT;
    IstPENDLEExitPool public stPENDLEExitPool;

    address public immutable ASSET;
    // settings
    address public feeReceiver;
    bool public paused = false;

    // Fee split using 1e18 precision (holders + LP + protocol <= 1e18)
    uint256 public rewardsSplitHolders = 1e18; // default: 100% to holders (AUM)
    uint256 public rewardsSplitLp;

    address public lpFeeReceiver;

    // Epoch management
    // this vaults current information, total pendle, total locked pendle, current epoch start, last epoch update
    VaultPosition internal _vaultPosition;


    // Redemption queue management
    // redemption requests are tracked per epoch when the epoch advances all pending redemptions are cleared
    // mapping(address user => mapping(uint256 epoch => uint256 pendingRedemptionAmount)) public
    //     pendingRedemptionSharesPerEpoch;
    // mapping(uint256 epoch => uint256 totalPendingRedemptions) public totalPendingSharesPerEpoch;
    // mapping(uint256 epoch => RedemptionSnapshot redemptionSnapshot) public redemptionSnapshotPerEpoch;

    // cross chain
    mapping(uint64 chainId => address crossChainGateway) public crossChainGatewayByChainId;
    mapping(uint64 chainId => bytes extraArgs) public extraArgsByChainId;
    address public feeToken;

    modifier whenNotPaused() {
        _whenNotPaused();
        _;
    }

    modifier beforeFirstEpoch() {
        _beforeFirstEpoch();
        _;
    }

    constructor(VaultConfig memory config) CCIPReceiver(config.ccipRouter) {
        if (config.lpFeeReceiver == address(0)) revert InvalidFeeReceiver();
        if (config.feeReceiver == address(0)) revert InvalidFeeReceiver();
        if (config.admin == address(0)) revert InvalidAdmin();
        if (config.timelockController == address(0)) revert InvalidTimelockController();
        if (config.pendleTokenAddress == address(0)) revert InvalidPendleToken();
        if (config.merkleDistributorAddress == address(0)) revert InvalidMerkleDistributor();
        if (config.votingEscrowMainchain == address(0)) revert InvalidVotingEscrowMainchain();
        if (config.votingControllerAddress == address(0)) revert InvalidVotingController();
        if (config.preLockRedemptionPeriod == 0) revert InvalidPreLockRedemptionPeriod();
        if (config.epochDuration == 0) revert InvalidEpochDuration();
        if (config.ccipRouter == address(0)) revert InvalidCCIPRouter();

        votingEscrowMainchain = IPVotingEscrowMainchain(config.votingEscrowMainchain);
        merkleDistributor = IPMerkleDistributor(config.merkleDistributorAddress);
        votingController = IPVotingController(config.votingControllerAddress);
        ASSET = config.pendleTokenAddress;
        _vaultPosition.preLockRedemptionPeriod = config.preLockRedemptionPeriod;
        _vaultPosition.epochDuration = _safeCast128(config.epochDuration);
        lpFeeReceiver = config.lpFeeReceiver;
        feeReceiver = config.feeReceiver;
        feeToken = config.feeToken;
        stPENDLEExitNFT = IstPENDLEExitNFT(config.stPENDLEExitNFTAddress);
        stPENDLEExitPool = IstPENDLEExitPool(config.stPENDLEExitPoolAddress);

        _initializeOwner(address(msg.sender));
        _grantRoles(config.admin, ADMIN_ROLE);
        _grantRoles(config.timelockController, TIMELOCK_CONTROLLER_ROLE);
        transferOwnership(config.admin);
    }

    /// @dev Returns the address of the underlying asset
    function asset() public view virtual override returns (address) {
        return ASSET;
    }

    /// @dev Deposit PENDLE into the vault and stake it directly in vePENDLE
    function deposit(uint256 amount, address receiver) public override whenNotPaused returns (uint256) {
        uint256 sharesMinted = super.deposit(amount, receiver);
        _vaultPosition.aumPendle += amount;
        // increase lock position in vePENDLE
        // TODO: decide if we want to immediatly lock pendle or not
         _lockPendle(amount, 0);

        return sharesMinted;
    }

    function depositAndBridge(uint64 destChainId, address receiver, uint256 amount)
        public
        whenNotPaused
        returns (uint256, bytes32)
    {
        uint256 sharesMinted = super.deposit(amount, receiver);
        _vaultPosition.aumPendle += amount;
        // increase lock position in vePENDLE
        _lockPendle(amount, 0);
        // bridge to destination chain
        bytes32 messageId = _bridgeStPendle(destChainId, receiver, amount);
        return (sharesMinted, messageId);
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
        _vaultPosition.aumPendle += amount;
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

        // Split fees (1e18 precision): holders (AUM), LP (transfer), protocol (transfer)
        uint256 holdersAmount = FixedPointMathLib.fullMulDiv(amountClaimed, rewardsSplitHolders, FEE_BASIS_POINTS);
        uint256 lpAmount = FixedPointMathLib.fullMulDiv(amountClaimed, rewardsSplitLp, FEE_BASIS_POINTS);
        uint256 protocolAmount = amountClaimed - holdersAmount - lpAmount; // remainder to protocol

        if (holdersAmount != 0) {
            _vaultPosition.aumPendle += holdersAmount;
        }

        if (lpAmount != 0) {
            SafeTransferLib.safeTransfer(asset(), lpFeeReceiver, lpAmount);
        }

        if (protocolAmount != 0) {
            SafeTransferLib.safeTransfer(asset(), feeReceiver, protocolAmount);
        }

        // Lock behavior
        uint256 amountToLock = holdersAmount; // lock the portion kept by holders by default
        if (!_isWithinRedemptionWindow()) {
            // Lock all currently unlocked PENDLE
            amountToLock = SafeTransferLib.balanceOf(asset(), address(this));
        }

        if (amountToLock != 0) {
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
        // get expiration timestamp from voting escrow mainchain
        uint128 expirationTimestamp = votingEscrowMainchain.positionData(address(this)).expiry;
        _vaultPosition.currentExpirationTimestamp = expirationTimestamp;

        emit NewEpochStarted(newEpoch, block.timestamp, _vaultPosition.epochDuration);
    }

    /**
     * @notice Lock PENDLE into the vault and start new epoch, can be called by anyone after epoch has ended
     * @dev Can be called by anyone after epoch has ended, will revert if contract has no expired vePENDLE position
     * @dev Will revert if epoch is not ended
     */
    function startNewEpoch() external whenNotPaused nonReentrant {
        _requireNextEpoch();
        uint256 newEpoch = _updateEpoch();
        // check that there is a vePENDLE to claim
        if (votingEscrowMainchain.balanceOf(address(this)) == 0) revert InsufficientBalance();

        // 1) Claim matured vePENDLE
        uint256(votingEscrowMainchain.withdraw());
        _vaultPosition.totalLockedPendle = 0;

        uint256 totalPendleBalance = SafeTransferLib.balanceOf(address(asset()), address(this));

        // transfer requested withdrawal pendle to exit pool
        uint256 totalRequestedRedemptionAmount = stPENDLEExitPool.getTotalRequestedShares(newEpoch);
        // calculate redemption rate for the epoch
        uint256 assets = convertToAssets(totalRequestedRedemptionAmount);
        uint256 redemptionRate = assets * FEE_BASIS_POINTS / totalRequestedRedemptionAmount;
        totalPendleBalance -= assets;

        stPENDLEExitPool.setRedemptionRate(newEpoch, redemptionRate);

        stPENDLEExitPool.addPendle(assets, newEpoch);

        // lock remaining pendle
        uint128 newExpiry = _lockPendle(totalPendleBalance, _vaultPosition.epochDuration);
        _vaultPosition.currentExpirationTimestamp = newExpiry;

        // 4) Advance epoch book-keeping
        _vaultPosition.currentEpoch = newEpoch;
        _vaultPosition.currentEpochStart = block.timestamp;
        _vaultPosition.lastEpochUpdate = block.timestamp;
        emit NewEpochStarted(newEpoch, block.timestamp, _vaultPosition.epochDuration);
    }

    /**
     * @notice Request a redeem shares for PENDLE from the vault
     * @param shares Amount of shares to redeem
     * @param to Address to mint the exit NFT to
     */
    function requestRedemption(address to, uint256 shares) external nonReentrant whenNotPaused returns (uint256 _tokenId) {
        if (shares == 0) revert InvalidAmount();
        if (balanceOf(msg.sender) < shares) revert InsufficientBalance();

        _tokenId = stPENDLEExitNFT.redeemExitPosition(msg.sender, to, shares);
        emit RedemptionRequested(msg.sender, shares);
    }

    /**
     * @notice Claim redeem shares for PENDLE from the vault
     * @dev Can be called by the user to claim their redemption requests
     * @param shares Amount of shares to claim
     */
    function claimAvailableRedemptionShares(uint256 _tokenId) external nonReentrant whenNotPaused returns (uint256) {
        _updateEpoch();
        _requireIsWithinRedemptionWindow();
        // Process redemption requests
        return _processRedemption(msg.sender, _tokenId);
    }

    /**
     * @notice Bridge stPENDLE to destination chain
     * @param destChainId Destination chain ID
     * @param receiver Receiver address on destination chain
     * @param amount Amount of stPENDLE to bridge
     * @return messageId Message ID
     */
    function bridgeStPendle(uint64 destChainId, address receiver, uint256 amount) external returns (bytes32) {
        return _bridgeStPendle(destChainId, receiver, amount);
    }

    function _bridgeStPendle(uint64 destChainId, address receiver, uint256 amount) internal returns (bytes32) {
        if (amount > balanceOf(msg.sender)) revert InsufficientBalance();
        if (destChainId == 0) revert InvalidDestChainId();
        if (crossChainGatewayByChainId[destChainId] == address(0)) revert InvalidCrossChainGateway();
        if (amount == 0) revert InvalidAmount();

        // lock shares in this contract
        SafeTransferLib.safeTransferFrom(address(this), msg.sender, address(this), amount);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(crossChainGatewayByChainId[destChainId]),
            extraArgs: extraArgsByChainId[destChainId],
            feeToken: feeToken,
            tokenAmounts: tokenAmounts,
            data: abi.encode(BridgeStPendleData({receiver: receiver, sender: msg.sender, amount: amount}))
        });

        uint256 fee = IRouterClient(i_ccipRouter).getFee(destChainId, message);
        bytes32 messageId;

        if (feeToken == address(0)) {
            if (address(this).balance < fee) revert InsufficientBalance();
            messageId = IRouterClient(i_ccipRouter).ccipSend{value: fee}(destChainId, message);
        } else {
            if (SafeTransferLib.balanceOf(feeToken, msg.sender) < fee) revert InsufficientBalance();
            messageId = IRouterClient(i_ccipRouter).ccipSend(destChainId, message);
        }

        emit MessageSent(messageId);
        return messageId;
    }

    /// ============ View Functions ================ ///

    function name() public pure override returns (string memory) {
        return "stPENDLE";
    }

    function symbol() public pure override returns (string memory) {
        return "stPEN";
    }

    /**
     * @notice Get the total requested redemption amount for the given epoch
     * @param epoch Epoch to get the total requested redemption amount for
     * @return Total requested redemption amount for the given epoch
     */
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
     * @dev Will return 0 if redemption window has closed or if a new epoch has not been started
     * @param user Address of the user
     * @return Total pending redemption shares for the user in the current epoch
     */
    function getUserAvailableRedemption(address user) public view returns (uint256) {
        // if redemption window has closed, return 0
        uint256 pendingRedemptionShares = pendingRedemptionSharesPerEpoch[user][_vaultPosition.currentEpoch];
        return pendingRedemptionShares;
    }

    /**
     * @notice Get the current epoch and update the epoch if it has changed
     * @return Current epoch
     */
    function currentEpoch() external returns (uint256) {
        return _updateEpoch();
    }

    /**
     * @notice Get the last epoch update
     * @return Last epoch update
     */
    function lastEpochUpdate() external view returns (uint256) {
        return _vaultPosition.lastEpochUpdate;
    }

    function epochDuration() external view returns (uint128) {
        return _vaultPosition.epochDuration;
    }

    function currentExpirationTimestamp() external view returns (uint128) {
        return _vaultPosition.currentExpirationTimestamp;
    }

    function currentEpochStart() external view returns (uint256) {
        return _vaultPosition.currentEpochStart;
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

    function feeBasisPoints() external pure returns (uint256) {
        return FEE_BASIS_POINTS;
    }

    function rewardsSplit() external view returns (uint256, uint256) {
        return (rewardsSplitHolders, rewardsSplitLp);
    }

    function getCurrentLockedPosition() external view returns (uint128 _amount, uint128 _expiry) {
        VeBalanceLib.LockedPosition memory lockedPosition = votingEscrowMainchain.positionData(address(this));
        return (lockedPosition.amount, lockedPosition.expiry);
    }

    /**
     * @notice Convenience function to preview the amount of PENDLE that can be redeemed for the given shares according to the current values
     * @param shares Amount of shares to redeem
     * @return Amount of PENDLE that can be redeemed
     */
    function previewRedeemWithCurrentValues(uint256 shares) public view returns (uint256) {
        return shares * _vaultPosition.aumPendle / totalSupply();
    }

    /// =========== Governance Council Functions ================ ///

    function setFeeReceiver(address _feeReceiver) public onlyRoles(ADMIN_ROLE) {
        if (_feeReceiver == address(0)) revert InvalidFeeReceiver(); // 0 address is not allowed
        feeReceiver = _feeReceiver;
        emit FeeReceiverSet(feeReceiver);
    }

    function setLpFeeReceiver(address _lpFeeReceiver) public onlyRoles(ADMIN_ROLE) {
        if (_lpFeeReceiver == address(0)) revert InvalidFeeReceiver(); // 0 address is not allowed
        lpFeeReceiver = _lpFeeReceiver;
        emit LpFeeReceiverSet(lpFeeReceiver);
    }

    function setFeeToken(address _feeToken) public onlyRoles(ADMIN_ROLE) {
        feeToken = _feeToken;
        emit FeeTokenSet(feeToken);
    }

    /**
     * @notice Vote on a proposal on in the voting controller
     * @param pools Pools to vote on
     * @param weights Weights for each pool
     */
    function vote(address[] calldata pools, uint64[] calldata weights) public onlyRoles(ADMIN_ROLE) {
        votingController.vote(pools, weights);
    }

    function setEpochDuration(uint128 _duration) public onlyRoles(TIMELOCK_CONTROLLER_ROLE) {
        if (_duration < 1 days) revert EpochDurationInvalid();
        // 732 days is the max duration of 2 years in days (if there is a leap year)
        if (_duration > 732 days) revert EpochDurationInvalid();
        _vaultPosition.epochDuration = _safeCast128(_duration);
        emit EpochDurationSet(_duration);
    }

    function setRewardsSplit(uint256 holders, uint256 lp) public onlyRoles(TIMELOCK_CONTROLLER_ROLE) {
        if (holders + lp > 1e18) revert InvalidrewardsSplit();
        rewardsSplitHolders = holders;
        rewardsSplitLp = lp;
        emit rewardsSplitSet(holders, lp);
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
        if (block.timestamp < _vaultPosition.currentEpochStart + _vaultPosition.epochDuration) {
            revert EpochNotEnded();
        }
    }

    function _requireIsWithinRedemptionWindow() internal view {
        if (!_isWithinRedemptionWindow()) {
            revert OutsideRedemptionWindow();
        }
    }

    function _isWithinRedemptionWindow() internal view returns (bool) {
        return block.timestamp < _vaultPosition.currentEpochStart + _vaultPosition.preLockRedemptionPeriod;
    }

    function _calculateEpoch(uint256 timestamp) internal view returns (uint256) {
        return timestamp / _vaultPosition.epochDuration;
    }

    function _updateEpoch() internal returns (uint256 newEpoch) {
        newEpoch = _calculateEpoch(block.timestamp);
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


    /**
     * @notice convenience wrapper to just call redeem on the exit nft contract
     * must be called by owner of exit nft
     * @param _tokenId Token ID of the exit NFT
     * @return Amount of PENDLE redeemed
     */
    function _processRedemption(uint256 _tokenId) internal returns (uint256) {
        uint256 amountRedeemed = stPENDLEExitNFT.redeemExitPosition(msg.sender, _tokenId);
        emit RedemptionProcessed(msg.sender, _tokenId, amountRedeemed);

        return amountRedeemed;
    }

    function _lockPendle(uint256 amount, uint128 duration) internal returns (uint128 _newExpiry) {
        // Ensure sufficient unlocked PENDLE in the vault to lock
        if (amount > SafeTransferLib.balanceOf(address(asset()), address(this))) revert InvalidPendleBalance();
        SafeTransferLib.safeApprove(address(asset()), address(votingEscrowMainchain), amount);
        votingEscrowMainchain.increaseLockPosition(_safeCast128(amount), duration);
        _vaultPosition.totalLockedPendle += amount;
        emit AssetPositionIncreased(amount, _vaultPosition.currentEpoch, duration);
        // get expiry from voting escrow mainchain
        _newExpiry = votingEscrowMainchain.positionData(address(this)).expiry;
    }

    /**
     * @notice Receive stPENDLE from destination chain
     * @dev since tokens can only get to other chains by bridging from this contract we should
     * always have locked shares equivalent to the amount of stPENDLE that has been bridged
     */
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override onlyRouter {
        if (crossChainGatewayByChainId[message.sourceChainSelector] == address(0)) revert InvalidCrossChainGateway();

        BridgeStPendleData memory bridgeData = abi.decode(message.data, (BridgeStPendleData));

        // send shares locked in this contract to receiver
        SafeTransferLib.safeTransfer(asset(), bridgeData.receiver, bridgeData.amount);

        emit CrossChainMint(message.sourceChainSelector, bridgeData.sender, bridgeData.receiver, bridgeData.amount);
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

    function _beforeFirstEpoch() internal view {
        if (_vaultPosition.currentEpoch != 0) revert InvalidEpoch();
    }

    // ERC 4626 overrides

    function totalAssets() public view override returns (uint256) {
        return _vaultPosition.aumPendle;
    }

    /**
     * @notice Preview the amount of PENDLE that can be redeemed for the given shares according to the current redemption snapshot
     * @dev Will return 0 if redemption window has closed or if a new epoch has not been started
     * @param shares Amount of shares to redeem
     * @return Amount of PENDLE that can be redeemed
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        // epoch has not been updated, return 0
        if (_calculateEpoch(block.timestamp) != _vaultPosition.currentEpoch) return 0;
        if (!_isWithinRedemptionWindow()) return 0;

        RedemptionSnapshot memory redemptionSnapshot = redemptionSnapshotPerEpoch[_vaultPosition.currentEpoch];
        // if no snapshot exists, return 0
        if (redemptionSnapshot.totalSupplyAtEpochStart == 0) return 0;
        return FixedPointMathLib.fullMulDiv(
            shares, redemptionSnapshot.aumPendleAtEpochStart + 1, redemptionSnapshot.totalSupplyAtEpochStart + 1
        );
    }

    // exit pool can burn redeemed shares
    function burn(address to, uint256 shares) public override onlyRoles(ST_PENDLE_EXIT_POOL_ROLE) returns (uint256) {
        return _burn(to, shares);
    }

    /**
     * @notice override to revert so redeeming happens through redemption queue
     */
    function redeem(uint256 /*shares */, address /*to */, address /*owner*/ ) public pure override returns (uint256) {
        revert InvalidERC4626Function(); // this should never be called on this contract
    }

    /**
     * @notice override to revert so minting happens through deposit flow
     */
    function mint(uint256 /*shares*/, address /*to*/ ) public pure override returns (uint256) {
        revert InvalidERC4626Function();
    }

    /**
     * @notice override to revert so withdrawals happen through withdrawal queue
     */
    function withdraw(uint256 /*assets*/, address /*to*/, address /*owner*/ ) public pure override returns (uint256) {
        revert InvalidERC4626Function();
    }
}
