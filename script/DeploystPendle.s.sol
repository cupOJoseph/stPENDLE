// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "lib/forge-std/src/Script.sol";
import {DeploymentParams} from "script/DeploymentParams.sol";
import {stPENDLE} from "src/stPENDLE.sol";
import {stPENDLECrossChainGateway} from "src/crosschain/stPENDLECrossChainGateway.sol";
import {IstPENDLE} from "src/interfaces/IstPENDLE.sol";
import {Create3Deployer} from "src/dependencies/Create3Deployer.sol";

contract stPendleDeploy is Script, DeploymentParams {
    // function run() public {


    //     // Required env var for CCIP router (vault needs it)
    //     address ccipRouter = vm.envAddress("CCIP_ROUTER");
    //     // Optional env var for fee token (0 means native)
    //     address feeToken = vm.envOr("FEE_TOKEN", address(0));

    //     // Optional: external CREATE3 deployer to ensure same addresses across chains
    //     address create3DeployerAddr = vm.envOr("CREATE3_DEPLOYER", address(0));

    //     vm.startBroadcast();

    //     if (create3DeployerAddr == address(0)) {
    //         // Deploy a local Create3Deployer if none provided
    //         create3DeployerAddr = address(new Create3Deployer());
    //     }
    //     Create3Deployer c3 = Create3Deployer(create3DeployerAddr);

    //     setup();
    //     IstPENDLE.VaultConfig storage config = stPendleParams[block.chainid];

    //     // Deterministic CREATE3 deploy with fixed salt
    //     bytes32 salt = keccak256(abi.encodePacked("stpendle.vault.v1"));
    //     bytes memory creationCode = abi.encodePacked(type(stPENDLE).creationCode, abi.encode(config));
    //     address predicted = c3.predict(salt);
    //     // Idempotent: only deploy if code not present
    //     if (predicted.code.length == 0) {
    //         c3.deploy(salt, creationCode);
    //     }
    //     stPENDLE vault = stPENDLE(predicted);

    //     vm.stopBroadcast();

    //     // Write vault deployment JSON: deployments/<chainId>-vault.json
    //     vm.createDir("deployments", true);
    //     string memory path = string.concat("deployments/", vm.toString(block.chainid), "-vault.json");
    //     string memory json = "deploy";
    //     json = vm.serializeUint(json, "chainId", block.chainid);
    //     json = vm.serializeAddress(json, "address", address(vault));
    //     json = vm.serializeBytes32(json, "salt", salt);
    //     json = vm.serializeAddress(json, "create3Deployer", create3DeployerAddr);
    //     json = vm.serializeAddress(json, "pendleTokenAddress", config.pendleTokenAddress);
    //     json = vm.serializeAddress(json, "merkleDistributorAddress", config.merkleDistributorAddress);
    //     json = vm.serializeAddress(json, "votingEscrowMainchain", config.votingEscrowMainchain);
    //     json = vm.serializeAddress(json, "votingControllerAddress", config.votingControllerAddress);
    //     json = vm.serializeAddress(json, "timelockController", config.timelockController);
    //     json = vm.serializeAddress(json, "admin", config.admin);
    //     json = vm.serializeAddress(json, "lpFeeReceiver", config.lpFeeReceiver);
    //     json = vm.serializeAddress(json, "feeReceiver", config.feeReceiver);
    //     json = vm.serializeAddress(json, "stPENDLEExitPoolAddress", config.stPENDLEExitPoolAddress);
    //     json = vm.serializeAddress(json, "stPENDLEExitNFTAddress", config.stPENDLEExitNFTAddress);
    //     json = vm.serializeUint(json, "epochDuration", config.epochDuration);
    //     json = vm.serializeAddress(json, "ccipRouter", config.ccipRouter);
    //     json = vm.serializeAddress(json, "feeToken", config.feeToken);
    //     vm.writeJson(json, path);
    // }
}

contract stPendleGatewayDeploy is Script, DeploymentParams {
    // function run() public {
    //     // Optional allowlist arrays via JSON env strings:
    //     // export AUTH_CHAINS='[16000,17000]'
    //     // export AUTH_GATEWAYS='["0x...","0x..."]'
    //     uint64[] memory chainIds = new uint64[](0);
    //     address[] memory gateways = new address[](0);
    //     string memory chainsStr = vm.envOr("AUTH_CHAINS", string(""));
    //     string memory gwsStr = vm.envOr("AUTH_GATEWAYS", string(""));
    //     if (bytes(chainsStr).length != 0) {
    //         bytes memory raw = vm.parseJson(chainsStr);
    //         chainIds = abi.decode(raw, (uint64[]));
    //     }
    //     if (bytes(gwsStr).length != 0) {
    //         bytes memory raw2 = vm.parseJson(gwsStr);
    //         gateways = abi.decode(raw2, (address[]));
    //     }

    //     require(chainIds.length == gateways.length, "auth arrays mismatch");
    //     setup();
    //     L2Params storage config = l2Params[block.chainid];
    //     vm.startBroadcast();

    //     if (config.create3Deployer == address(0)) {
    //         // Deploy a local Create3Deployer if none provided
    //         config.create3Deployer = address(new Create3Deployer());
    //     }
        
    //     Create3Deployer c3 = Create3Deployer(config.create3Deployer);

    //     // Deterministic CREATE3 deploy with fixed salt
    //     bytes32 salt = keccak256(abi.encodePacked("stpendle.gateway.v1"));
    //     bytes memory creationCode = abi.encodePacked(
    //         type(stPENDLECrossChainGateway).creationCode,
    //         abi.encode(chainIds,  gateways,  config.ccipRouter, config.admin, config.feeToken)
    //     );
    //     address predicted = c3.predict(salt);
    //     if (predicted.code.length == 0) {
    //         c3.deploy(salt, creationCode);
    //     }
    //     stPENDLECrossChainGateway gateway = stPENDLECrossChainGateway(predicted);
    //     vm.stopBroadcast();

    //     // Write gateway deployment JSON: deployments/<chainId>-gateway.json
    //     vm.createDir("deployments", true);
    //     string memory path = string.concat("deployments/", vm.toString(block.chainid), "-gateway.json");
    //     string memory json = "deploy";
    //     json = vm.serializeUint(json, "chainId", block.chainid);
    //     json = vm.serializeAddress(json, "address", address(gateway));
    //     json = vm.serializeAddress(json, "router", config.ccipRouter);
    //     json = vm.serializeBytes32(json, "salt", salt);
    //     json = vm.serializeAddress(json, "create3Deployer", config.create3Deployer);
    //     json = vm.serializeAddress(json, "admin", config.admin);
    //     json = vm.serializeAddress(json, "feeToken", config.feeToken);
    //     json = vm.serializeUint(json, "authorizedLen", chainIds.length);
    //     vm.writeJson(json, path);
    // }
}
