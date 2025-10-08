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
import {ISTPENDLECrossChain} from "src/interfaces/ISTPENDLECrossChain.sol";
import {ISTPENDLE} from "src/interfaces/ISTPENDLE.sol";

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

contract stPendleExitNFT is ERC721, OwnableRoles, ReentrancyGuard, IstPendleExitNFT {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant TIMELOCK_CONTROLLER_ROLE = _ROLE_1;
    uint256 public constant ST_PENDLE_VAULT_ROLE = _ROLE_2;

    uint256 public constant FEE_BASIS_POINTS = 1e18; // 1e18 = 100%

    ISTPENDLE public stPendleVault;

    uint256 public tokenIdCounter;

    mapping(uint256 tokenId => ExitNFT exitNFT) public exitNFTs;
    mapping(uint256 epoch => uint256 totalWithdrawals) public totalWithdrawalsByEpoch;

    constructor(address _stPendleVault, address _admin, address _timelockController) ERC721("stPENDLEExitQueue", "stPENDLEExitQueue") {
        _initializeOwner(address(msg.sender));
        stPendleVault = ISTPENDLE(_stPendleVault);
        _grantRoles(_admin, ADMIN_ROLE);
        _grantRoles(_timelockController, TIMELOCK_CONTROLLER_ROLE);
        _grantRoles(stPendleVault, ST_PENDLE_VAULT_ROLE);
    }

    function createExitPosition(address _to, uint256 _requestedAmount) external onlyRoles(ST_PENDLE_VAULT_ROLE) {
        tokenIdCounter++;
        uint256 tokenId = tokenIdCounter;
        uint256 epoch = stPendleVault.currentEpoch();

        ExitNFT memory exitNFT = ExitNFT({
            tokenId: tokenId,
            owner: _to,
            requestedAmount: _requestedAmount,
            epoch: epoch,
            claimed: false,
            claimableAt: 0
        });


        _setExitNFT(tokenId, exitNFT);
        totalWithdrawalsByEpoch[epoch] += amount;
        _mint(_to, tokenId);
    }

    function _setExitNFT(uint256 tokenId, ExitNFT memory exitNFT) internal {
        exitNFTs[tokenId] = exitNFT;
    }
}