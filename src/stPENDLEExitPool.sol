//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
 import {OwnableRoles} from "lib/solady/src/auth/OwnableRoles.sol";
 import {ReentrancyGuard} from "lib/solady/src/utils/ReentrancyGuard.sol";
 import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
 import {IstPENDLE} from "src/interfaces/IstPENDLE.sol";
 import {IstPENDLEExitNFT} from "src/interfaces/IstPENDLEExitNFT.sol";

contract stPENDLEExitPool is OwnableRoles, ReentrancyGuard {

    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant TIMELOCK_CONTROLLER_ROLE = _ROLE_1;
    uint256 public constant ST_PENDLE_VAULT_ROLE = _ROLE_2;
    uint256 public constant ST_PENDLE_EXIT_NFT_ROLE = _ROLE_3;

    IstPENDLEExitNFT public stPENDLEExitNFT;
    IstPENDLE public stPENDLE;

    uint256 public constant DECIMAL_PRECISION = 1e18;

    uint256 public shareBalance;
    uint256 public pendleBalance;

    struct RedemptionData {
        uint256 redemptionRate;
        uint256 totalPendle;
        uint256 totalRequestedShares;
    }

    mapping(uint256 epoch => RedemptionData redemptionData) public redemptionDataByEpoch;

    error InsufficientPendleBalance();
    error InsufficientSharesBalance();

    event SharesClaimed(address indexed user, uint256 requestedShares, uint256 amountRedeemed, uint256 tokenId);


    constructor(address _stPENDLE, address _stPENDLEExitNFT, address _admin, address _timelockController) {
        _initializeOwner(address(msg.sender));
        stPENDLEExitNFT = IstPENDLEExitNFT(_stPENDLEExitNFT);
        stPENDLE = IstPENDLE(_stPENDLE);
        _grantRoles(_admin, ADMIN_ROLE);
        _grantRoles(_timelockController, TIMELOCK_CONTROLLER_ROLE);
        _grantRoles(stPENDLE, ST_PENDLE_VAULT_ROLE);
    }

    function addShares(address _user, uint256 _shares, uint256 _epoch) external nonReentrant onlyRoles(ST_PENDLE_EXIT_NFT_ROLE) {
        redemptionDataByEpoch[_epoch].totalRequestedShares += _shares;
        SafeTransferLib.safeTransferFrom(address(stPENDLE), _user, address(this), _shares);
    }

    function addPendle(uint256 _amount, uint256 _epoch) external nonReentrant onlyRoles(ST_PENDLE_VAULT_ROLE) {
        redemptionDataByEpoch[_epoch].totalPendle += _amount;
        SafeTransferLib.safeTransferFrom(address(stPENDLE), msg.sender, address(this), _amount);
    }

    function claimShares(address _to, uint256 tokenId) external nonReentrant onlyRoles(ST_PENDLE_EXIT_NFT_ROLE) returns (uint256 amountRedeemed) {
        IstPENDLEExitNFT.ExitNFTData memory exitNFT = stPENDLEExitNFT.exitNFTData(tokenId);
        _requireAvailableShares(exitNFT.requestedAmount, exitNFT.requestedEpoch);
        uint256 amount = _calcSharesToPendle(exitNFT.requestedAmount, exitNFT.requestedEpoch);
        _requireAvailablePendle(amount, exitNFT.requestedEpoch);
        // update redemption data
        redemptionDataByEpoch[exitNFT.requestedEpoch].totalRequestedShares -= exitNFT.requestedAmount;
        redemptionDataByEpoch[exitNFT.requestedEpoch].totalPendle -= amount;
        // burn redeemed shares
        amountRedeemed = stPENDLE.burn(address(this), exitNFT.requestedAmount);
        // transfer redeemed pendle to user
        SafeTransferLib.safeTransfer(address(stPENDLE), _to, amount);
        emit SharesClaimed(_to, exitNFT.requestedAmount, amountRedeemed, tokenId);
    }

    function setRedemptionRate(uint256 _epoch, uint256 _redemptionRate) external onlyRoles(ST_PENDLE_VAULT_ROLE) {
        redemptionDataByEpoch[_epoch].redemptionRate = _redemptionRate;
    }

    function getTotalRequestedShares(uint256 _epoch) external view returns (uint256) {
        return redemptionDataByEpoch[_epoch].totalRequestedShares;
    }

    function getTotalPendle(uint256 _epoch) external view returns (uint256) {
        return redemptionDataByEpoch[_epoch].totalPendle;
    }

    function _requireAvailablePendle(uint256 _amount, uint256 _epoch) internal view {
        if (redemptionDataByEpoch[_epoch].totalPendle < _amount) revert InsufficientPendleBalance();
    }

    function _requireAvailableShares(uint256 _amount, uint256 _epoch) internal view {
        if (shareBalance < _amount) revert InsufficientSharesBalance();
    }

    function _calcSharesToPendle(uint256 _shares, uint256 _epoch) internal view returns (uint256) {
        return _shares * redemptionDataByEpoch[_epoch].redemptionRate / DECIMAL_PRECISION;
    }
}