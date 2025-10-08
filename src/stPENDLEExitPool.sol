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
    uint256 public constant ST_PENDLE_EXIT_POOL_ROLE = _ROLE_3;

    IstPENDLEExitNFT public stPENDLEExitNFT;
    IstPENDLE public stPENDLE;

    uint256 public shareBalance;
    uint256 public pendleBalance;

    error InsufficientPendleBalance();
    error InsufficientSharesBalance();


    constructor(address _stPENDLE, address _stPENDLEExitNFT, address _admin, address _timelockController) {
        _initializeOwner(address(msg.sender));
        stPENDLEExitNFT = IstPENDLEExitNFT(_stPENDLEExitNFT);
        stPENDLE = IstPENDLE(_stPENDLE);
        _grantRoles(_admin, ADMIN_ROLE);
        _grantRoles(_timelockController, TIMELOCK_CONTROLLER_ROLE);
        _grantRoles(stPENDLE, ST_PENDLE_VAULT_ROLE);
    }

    function addShares(address _user, uint256 _shares) external nonReentrant onlyRoles(ST_PENDLE_EXIT_POOL_ROLE) {
        shareBalance += _shares;
        SafeTransferLib.safeTransferFrom(address(stPENDLE), _user, address(this), _shares);
    }

    function addPendle(uint256 _amount) external nonReentrant onlyRoles(ST_PENDLE_VAULT_ROLE) {
        shareBalance += _amount;
        SafeTransferLib.safeTransferFrom(address(stPENDLE), msg.sender, address(this), _amount);
    }

    function claimShares(uint256 tokenId) external nonReentrant onlyRoles(ST_PENDLE_EXIT_POOL_ROLE) {
        IstPENDLEExitNFT.ExitNFT memory exitNFT = stPENDLEExitNFT.exitNFTs[tokenId];
        _requireAvailableShares(exitNFT.requestedAmount);
        uint256 amount = stPendle.previewRedeem(exitNFT.requestedAmount);
        _requireAvailablePendle(amount);
        shareBalance -= exitNFT.requestedAmount;
        pendleBalance -= amount;
        uint256 amountRedeemed = stPendle.burn(exitNFT.requestedAmount, exitNFT.owner);
        SafeTransferLib.safeTransfer(address(stPENDLE), exitNFT.owner, amount);
    }

    function _requireAvailablePendle(uint256 _amount) internal view {
        if (pendleBalance < _amount) revert InsufficientPendleBalance();
    }

    function _requireAvailableShares(uint256 _amount) internal view {
        if (shareBalance < _amount) revert InsufficientSharesBalance();
    }
}