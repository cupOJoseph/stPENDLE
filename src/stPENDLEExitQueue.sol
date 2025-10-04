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
// import "forge-std/console.sol";
/**
 * @title stPENDLE - ERC-4626 Vault for PENDLE Staking
 * @notice Accepts PENDLE deposits and stakes them in vePENDLE for rewards
 * @dev Fully compliant with ERC-4626 tokenized vault standard using Solady
 */

contract stPENDLEExitQueue is ERC721, OwnableRoles, ReentrancyGuard {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant TIMELOCK_CONTROLLER_ROLE = _ROLE_1;

    uint256 public constant FEE_BASIS_POINTS = 1e18; // 1e18 = 100%

    struct ExitNFT {
        uint256 tokenId;
        uint256 stakedPendle;
        uint256 epoch;
        uint256 amount;
        uint256 claimed;
        uint256 claimedAt;
        uint256 claimedBy;
    }
}