//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
 import {OwnableRoles} from "lib/solady/src/auth/OwnableRoles.sol";
 import {ReentrancyGuard} from "lib/solady/src/utils/ReentrancyGuard.sol";
 import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
 import {IstPENDLE} from "src/interfaces/IstPENDLE.sol";
 import {IstPENDLEExitNFT} from "src/interfaces/IstPENDLEExitNFT.sol";

contract stPENDLEExitPool is OwnableRoles, ReentrancyGuard, IstPENDLE {

    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant TIMELOCK_CONTROLLER_ROLE = _ROLE_1;
    uint256 public constant ST_PENDLE_VAULT_ROLE = _ROLE_2;
    uint256 public constant ST_PENDLE_EXIT_POOL_ROLE = _ROLE_3;

    IstPENDLEExitNFT public stPENDLEExitNFT;
    IstPENDLE public stPENDLE;

    uint256 public lockedShares;


    constructor(address _stPENDLE, address _stPENDLEExitNFT, address _admin, address _timelockController) {
        _initializeOwner(address(msg.sender));
        stPENDLEExitNFT = IstPENDLEExitNFT(_stPENDLEExitNFT);
        stPENDLE = IstPENDLE(stPENDLE);
        _grantRoles(_admin, ADMIN_ROLE);
        _grantRoles(_timelockController, TIMELOCK_CONTROLLER_ROLE);
        _grantRoles(stPENDLE, ST_PENDLE_VAULT_ROLE);
    }

    function addShares(address _user, uint256 _shares) external nonReentrant onlyRoles(ST_PENDLE_EXIT_POOL_ROLE) {
        lockedShares += _shares;
        SafeTransferLib.safeTransferFrom(address(stPENDLE), _user, address(this), _shares);
    }


    function claimShares(uint256 tokenId) external nonReentrant onlyRoles(ST_PENDLE_EXIT_POOL_ROLE) {
        lockedShares -= stPENDLEExitNFT.exitNFTs[tokenId].requestedAmount;
        stPENDLEExitNFT.claimShares(tokenId);
    }
}