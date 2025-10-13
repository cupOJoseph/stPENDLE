//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "lib/solady/src/tokens/ERC721.sol";
import {OwnableRoles} from "lib/solady/src/auth/OwnableRoles.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "lib/solady/src/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "lib/solady/src/utils/FixedPointMathLib.sol";

import {IPMerkleDistributor} from "src/interfaces/pendle/IPMerkleDistributor.sol";
import {IPVotingEscrowMainchain} from "src/interfaces/pendle/IPVotingEscrowMainchain.sol";
import {IPVotingController} from "src/interfaces/pendle/IPVotingController.sol";
import {IstPENDLECrossChain} from "src/interfaces/IstPENDLECrossChain.sol";
import {IstPENDLE} from "src/interfaces/IstPENDLE.sol";
import {IstPENDLEExitPool} from "src/interfaces/IstPENDLEExitPool.sol";
// cross chain
import {CCIPReceiver} from "lib/chainlink-ccip/chains/evm/contracts/applications/CCIPReceiver.sol";
import {Client} from "lib/chainlink-ccip/chains/evm/contracts/libraries/Client.sol";
import {IRouterClient} from "lib/chainlink-ccip/chains/evm/contracts/interfaces/IRouterClient.sol";
import {IstPENDLEExitNFT} from "src/interfaces/IstPENDLEExitNFT.sol";
// import "forge-std/console.sol";
/**
 * @title stPENDLE - ERC-4626 Vault for PENDLE Staking
 * @notice Accepts PENDLE deposits and stakes them in vePENDLE for rewards
 * @dev Fully compliant with ERC-4626 tokenized vault standard using Solady
 */

contract stPENDLEExitNFT is ERC721, OwnableRoles, ReentrancyGuard, IstPENDLEExitNFT {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant TIMELOCK_CONTROLLER_ROLE = _ROLE_1;
    uint256 public constant ST_PENDLE_VAULT_ROLE = _ROLE_2;

    uint256 public constant FEE_BASIS_POINTS = 1e18; // 1e18 = 100%

    IstPENDLE public stPendleVault;
    IstPENDLEExitPool public stPENDLEExitPool;

    uint256 public tokenIdCounter;

    mapping(uint256 tokenId => ExitNFTData exitNFTData) public exitNFTData;

    constructor(address _stPendleVault, address _stPENDLEExitPool, address _admin, address _timelockController) {
        _initializeOwner(address(msg.sender));
        stPendleVault = IstPENDLE(_stPendleVault);
        stPENDLEExitPool = IstPENDLEExitPool(_stPENDLEExitPool);
        _grantRoles(_admin, ADMIN_ROLE);
        _grantRoles(_timelockController, TIMELOCK_CONTROLLER_ROLE);
        _grantRoles(_stPendleVault, ST_PENDLE_VAULT_ROLE);
    }

    function createExitPosition(address _to, uint256 _shares) external {
        uint256 tokenId = ++tokenIdCounter;
        uint256 epoch = stPendleVault.currentEpoch() + 1;

        // transfer requested shares to exit pool
        stPENDLEExitPool.addShares(msg.sender, _shares, epoch);
        
        ExitNFTData memory exitNFT = ExitNFTData({
            requestedShares: _shares,
            requestedEpoch: epoch,
            claimed: false
        });

        _setExitNFTData(tokenId, exitNFT);
        _mint(_to, tokenId);
    }


    function redeemExitPosition(address _to, uint256 _tokenId) external returns (uint256 pendleClaimed) {
        if(ownerOf(_tokenId) != msg.sender) revert InvalidOwner();
        if(exitNFTData[_tokenId].claimed) revert AlreadyClaimed();
        pendleClaimed = stPENDLEExitPool.claimShares(_to, _tokenId);
        // update exit nft
        exitNFTData[_tokenId].claimed = true;
        _burn(_tokenId);
    }

    function getExitNFTData(uint256 _tokenId) external view returns (ExitNFTData memory) {
        return exitNFTData[_tokenId];
    }
    
    function getRequestedRedemptionAmount(uint256 _tokenId) external view returns (uint256) {
        return exitNFTData[_tokenId].requestedShares;
    }

    function name() public pure override returns (string memory) {
        return "stPENDLEExitNFT";
    }

    function symbol() public pure override returns (string memory) {
        return "stPENDLEEx";
    }
    // TODO: implement tokenURI
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return "";
    }

    function _setExitNFTData(uint256 tokenId, ExitNFTData memory exitNFT) internal {
        exitNFTData[tokenId] = exitNFT;
    }
}