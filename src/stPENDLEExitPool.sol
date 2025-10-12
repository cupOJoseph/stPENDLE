//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
 import {OwnableRoles} from "lib/solady/src/auth/OwnableRoles.sol";
 import {ReentrancyGuard} from "lib/solady/src/utils/ReentrancyGuard.sol";
 import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
 import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
 import {IstPENDLE} from "src/interfaces/IstPENDLE.sol";
 import {IstPENDLEExitNFT} from "src/interfaces/IstPENDLEExitNFT.sol";
 import {IstPENDLEExitPool} from "src/interfaces/IstPENDLEExitPool.sol";

contract stPENDLEExitPool is OwnableRoles, ReentrancyGuard, IstPENDLEExitPool {

    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant ST_PENDLE_VAULT_ROLE = _ROLE_1;
    uint256 public constant ST_PENDLE_EXIT_NFT_ROLE = _ROLE_2;

    IstPENDLEExitNFT public stPENDLEExitNFT;
    IstPENDLE public stPENDLE;
    IERC20 public pendle;

    uint256 public constant DECIMAL_PRECISION = 1e18;

    mapping(uint256 epoch => RedemptionData redemptionData) public redemptionDataByEpoch;

    event SharesClaimed(address indexed user, uint256 requestedShares, uint256 amountRedeemed, uint256 tokenId);
    event RedemptionRateSet(uint256 epoch, uint256 redemptionRate);
    event SharesAdded(address indexed user, uint256 shares, uint256 epoch);
    event PendleAdded(uint256 amount, uint256 epoch);

    constructor(address _stPENDLE, address _stPENDLEExitNFT, address _admin, address _pendle) {
        _initializeOwner(address(msg.sender));
        stPENDLEExitNFT = IstPENDLEExitNFT(_stPENDLEExitNFT);
        stPENDLE = IstPENDLE(_stPENDLE);
        pendle = IERC20(_pendle);
        _grantRoles(_admin, ADMIN_ROLE);
        _grantRoles(_stPENDLEExitNFT, ST_PENDLE_EXIT_NFT_ROLE);
        _grantRoles(_stPENDLE, ST_PENDLE_VAULT_ROLE);
        renounceOwnership();
    }

    function addShares(address _user, uint256 _shares, uint256 _epoch) external nonReentrant onlyRoles(ST_PENDLE_EXIT_NFT_ROLE) {
        redemptionDataByEpoch[_epoch].totalRequestedShares += _shares;
        SafeTransferLib.safeTransferFrom(address(stPENDLE), _user, address(this), _shares);
        emit SharesAdded(_user, _shares, _epoch);
    }

    function addPendle(uint256 _amount, uint256 _epoch) external nonReentrant onlyRoles(ST_PENDLE_VAULT_ROLE) {
        redemptionDataByEpoch[_epoch].totalPendle += _amount;
        SafeTransferLib.safeTransferFrom(address(stPENDLE), msg.sender, address(this), _amount);
        emit PendleAdded(_amount, _epoch);
    }

    function claimShares(address _to, uint256 tokenId) external nonReentrant onlyRoles(ST_PENDLE_EXIT_NFT_ROLE) returns (uint256 amountRedeemed) {
        IstPENDLEExitNFT.ExitNFTData memory exitNFT = stPENDLEExitNFT.getExitNFTData(tokenId);
        uint256 currentEpoch = stPENDLE.currentEpoch();
        if(exitNFT.requestedEpoch > currentEpoch) revert InvalidEpoch();
        if(redemptionDataByEpoch[exitNFT.requestedEpoch].redemptionRate == 0) revert InvalidEpoch();
        _requireAvailableShares(exitNFT.requestedShares, exitNFT.requestedEpoch);
        uint256 amount = _calcSharesToPendle(exitNFT.requestedShares, exitNFT.requestedEpoch);
        _requireAvailablePendle(amount, exitNFT.requestedEpoch);
        // update redemption data
        redemptionDataByEpoch[exitNFT.requestedEpoch].totalRequestedShares -= exitNFT.requestedShares;
        redemptionDataByEpoch[exitNFT.requestedEpoch].totalPendle -= amount;
        // burn redeemed shares
        stPENDLE.finalizeClaim(address(this), exitNFT.requestedShares, amount);
        // transfer redeemed pendle to user
        SafeTransferLib.safeTransfer(address(stPENDLE), _to, amount);
        emit SharesClaimed(_to, exitNFT.requestedShares, amount, tokenId);
    }

    function setRedemptionRate(uint256 _epoch, uint256 _redemptionRate) external onlyRoles(ST_PENDLE_VAULT_ROLE) {
        redemptionDataByEpoch[_epoch].redemptionRate = _redemptionRate;
        emit RedemptionRateSet(_epoch, _redemptionRate);
    }

    function getRedemptionDataByEpoch(uint256 _epoch) external view returns (RedemptionData memory) {
        return redemptionDataByEpoch[_epoch];
    }

    function getTotalRequestedSharesPerEpoch(uint256 _epoch) external view returns (uint256) {
        return redemptionDataByEpoch[_epoch].totalRequestedShares;
    }

    function getTotalPendlePerEpoch(uint256 _epoch) external view returns (uint256) {
        return redemptionDataByEpoch[_epoch].totalPendle;
    }

    function getTotalAssets() external view override returns (uint256) {
        return pendle.balanceOf(address(this));
    }

    function getTotalShares() external view override returns (uint256) {
        return IERC20(address(stPENDLE)).balanceOf(address(this));
    }

    function _requireAvailablePendle(uint256 _amount, uint256 _epoch) internal view {
        if (redemptionDataByEpoch[_epoch].totalPendle < _amount) revert InsufficientPendleBalance();
    }

    function _requireAvailableShares(uint256 _amount, uint256 _epoch) internal view {
        if (redemptionDataByEpoch[_epoch].totalRequestedShares < _amount) revert InsufficientSharesBalance();
    }

    function _calcSharesToPendle(uint256 _shares, uint256 _epoch) internal view returns (uint256) {
        return _shares * redemptionDataByEpoch[_epoch].redemptionRate / DECIMAL_PRECISION;
    }

    function updateExitQueue(address _newExitQueue) external onlyRoles(ADMIN_ROLE) {
        address oldExitQueue = address(stPENDLEExitNFT);
        stPENDLEExitNFT = IstPENDLEExitNFT(_newExitQueue);
        _grantRoles(address(stPENDLEExitNFT), ST_PENDLE_EXIT_NFT_ROLE);
        _removeRoles(oldExitQueue, ST_PENDLE_EXIT_NFT_ROLE);
    }
}