// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// forge-lint: disable-start(all)
import {IstPENDLE} from "src/interfaces/IstPENDLE.sol";



abstract contract DeploymentParams {

    struct L2Params {
    address ccipRouter;
    address feeToken;
    address create3Deployer;
    address admin;
    address stPENDLEMainnet;
}

    address public create3Deployer = 0x0000000000000000000000000000000000000000;

    mapping(uint chainId => IstPENDLE.VaultConfig params) internal stPendleParams;
    mapping(uint chainId => L2Params params) internal l2Params;

    function setup() public {

    // struct VaultConfig {
    //     address pendleTokenAddress;
    //     address stPENDLEExitPoolAddress;
    //     address stPENDLEExitNFTAddress;
    //     address merkleDistributorAddress;
    //     address votingEscrowMainchain;
    //     address votingControllerAddress;
    //     address timelockController;
    //     address admin;
    //     address lpFeeReceiver;
    //     address feeReceiver;
    //     uint256 epochDuration;
    //     address ccipRouter;
    //     address feeToken;
    // }

        //mainnet
        stPendleParams[1] = IstPENDLE.VaultConfig({
            merkleDistributorAddress: 0x0000000000000000000000000000000000000000,
            votingEscrowMainchain: 0x4f30A9D41B80ecC5B94306AB4364951AE3170210,
            pendleTokenAddress: 0x808507121B80c02388fAd14726482e061B8da827,
            votingControllerAddress: 0x44087E105137a5095c008AaB6a6530182821F2F0,
            timelockController: 0x0000000000000000000000000000000000000000,
            stPENDLEExitPoolAddress: 0x0000000000000000000000000000000000000000,
            stPENDLEExitNFTAddress: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
            lpFeeReceiver: 0x0000000000000000000000000000000000000000,
            feeReceiver: 0x0000000000000000000000000000000000000000,
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            epochDuration: 730 days
        });

        // testnet
        //sepolia
        stPendleParams[11155111] = IstPENDLE.VaultConfig({
            merkleDistributorAddress: 0x0000000000000000000000000000000000000000,
            votingEscrowMainchain: 0x4f30A9D41B80ecC5B94306AB4364951AE3170210,
            pendleTokenAddress: 0x0000000000000000000000000000000000000000,
            votingControllerAddress: 0x0000000000000000000000000000000000000000,
            timelockController: 0x0000000000000000000000000000000000000000,
            stPENDLEExitPoolAddress: 0x0000000000000000000000000000000000000000,
            stPENDLEExitNFTAddress: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
            lpFeeReceiver: 0x0000000000000000000000000000000000000000,
            feeReceiver: 0x0000000000000000000000000000000000000000,
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            epochDuration: 730 days
        });

        //l2 testnet
        //arbitrum nova
        l2Params[42170] = L2Params({
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            create3Deployer: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
            stPENDLEMainnet: 0x0000000000000000000000000000000000000000
        });

        // layer 2
        //arbitrum one
        l2Params[42161] = L2Params({
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            create3Deployer: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
            stPENDLEMainnet: 0x0000000000000000000000000000000000000000
        });
        // optimism
        l2Params[10] = L2Params({
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            create3Deployer: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
            stPENDLEMainnet: 0x0000000000000000000000000000000000000000

        });
        // bnb chain
        l2Params[56] = L2Params({
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            create3Deployer: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
            stPENDLEMainnet: 0x0000000000000000000000000000000000000000
        });
        // avalanche
        l2Params[43114] = L2Params({
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            create3Deployer: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
            stPENDLEMainnet: 0x0000000000000000000000000000000000000000
        });
        // polygon
        l2Params[137] = L2Params({
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            create3Deployer: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
            stPENDLEMainnet: 0x0000000000000000000000000000000000000000

        });
        // base
        l2Params[8453] = L2Params({
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            create3Deployer: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
            stPENDLEMainnet: 0x0000000000000000000000000000000000000000
        });
    }


    function getMainnetParams(uint chainId) public view returns (IstPENDLE.VaultConfig memory) {
        return stPendleParams[chainId];
    }
    function getTestnetParams(uint chainId) public view returns (IstPENDLE.VaultConfig memory) {
        return stPendleParams[chainId];
    }
    function getL2Params(uint chainId) public view returns (L2Params memory) {
        return l2Params[chainId];
    }
}
// forge-lint: disable-end(all)
