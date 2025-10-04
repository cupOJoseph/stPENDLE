// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CREATE3} from "lib/solady/src/utils/CREATE3.sol";

contract Create3Deployer {
    using CREATE3 for bytes;

    event Deployed(address addr, bytes32 salt);

    function deploy(bytes32 salt, bytes memory creationCode) external payable returns (address addr) {
        addr = CREATE3.deployDeterministic(msg.value, creationCode, salt);
        emit Deployed(addr, salt);
    }

    function predict(bytes32 salt) external view returns (address) {
        return CREATE3.predictDeterministicAddress(salt);
    }
}


