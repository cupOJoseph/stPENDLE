//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IRouterClient} from "lib/foundry-chainlink-toolkit/lib/chainlink-router-client/src/interfaces/IRouterClient.sol";
import {Client} from "lib/foundry-chainlink-toolkit/lib/chainlink-router-client/src/Client.sol";
import {CCIPReceiver} from "lib/foundry-chainlink-toolkit/lib/chainlink-router-client/src/CCIPReceiver.sol";

import {Ownable} from "lib/solady/src/auth/Ownable.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
import {ERC20} from "lib/solady/src/tokens/ERC20.sol";

/**
 * @title stPendleCrosschainReceiver
 * @notice Receiver for cross-chain transfers of stPENDLE.
 * this contract will mint stPENDLE on the destination chain and burn tokens being sent to another chain
 */
contract stPendleCrosschainReceiver is ERC20, Ownable {
    using SafeTransferLib for address;

    IRouterClient public immutable routerClient;

    mapping(uint64 => address) public chainIdToReceiver;

    error InvalidChainIdsAndReceivers();

    error InvalidChainId();

    constructor(uint64[] memory chainIds, address[] memory receivers, address admin) {
        if (chainIds.length != receivers.length) {
            revert InvalidChainIdsAndReceivers();
        }
        for (uint256 i = 0; i < chainIds.length; i++) {
            chainIdToReceiver[chainIds[i]] = receivers[i];
        }

        _initializeOwner(admin);
    }

    function setChainIdToReceiver(uint64 chainId, address receiver) public onlyOwner {
        chainIdToReceiver[chainId] = receiver;
    }

    function getReceiver(uint64 chainId) public view returns (address) {
        return chainIdToReceiver[chainId];
    }

    function crossChainMint(uint64 chainId, address sender, uint256 amount, bytes calldata data) external {
        // TODO: Implement
        address receiver = chainIdToReceiver[chainId];
        _requireAllowedChain(chainId);
        SafeTransferLib.safeTransfer(address(this), receiver, amount);
        emit CrossChainMint(chainId, sender, receiver, amount);
    }

    function _requireAllowedChain(uint64 chainId) internal view {
        if (chainIdToReceiver[chainId] == address(0)) revert InvalidChainId(chainId);
    }
}
