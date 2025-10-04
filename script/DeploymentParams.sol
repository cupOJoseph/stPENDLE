// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// forge-lint: disable-start(all)
abstract contract DeploymentParams {
    struct StPendleParams {
        address merkleDistributor;
        address votingEscrowMainchain;
        address pendleTokenAddress;
        address votingController;
        address timelockController;
        address admin;
        address lpFeeReceiver;
        address feeReceiver;
        address create3Deployer;
        address ccipRouter;
        address feeToken;
    }

    struct L2Params {
        address ccipRouter;
        address feeToken;
        address create3Deployer;
        address admin;
        address stPENDLEMainnet;
    }

    mapping(uint chainId => StPendleParams params) public stPendleParams;
    mapping(uint chainId => L2Params params) public l2Params;

    function setup() public {
        // mainnet
        stPendleParams[1] = StPendleParams({
            merkleDistributor: 0x0000000000000000000000000000000000000000,
            votingEscrowMainchain: 0x4f30A9D41B80ecC5B94306AB4364951AE3170210,
            pendleTokenAddress: 0x808507121b80c02388fad14726482e061b8da827,
            votingController: 0x44087E105137a5095c008AaB6a6530182821F2F0,
        });

        // testnet
        //sepolia
        stPendleParams[11155111] = StPendleParams({
            merkleDistributor: 0x0000000000000000000000000000000000000000,
            votingEscrowMainchain: 0x4f30A9D41B80ecC5B94306AB4364951AE3170210,
            pendleTokenAddress: 0x0000000000000000000000000000000000000000,
            votingController: 0x0000000000000000000000000000000000000000,
        });

        //l2 testnet
        //arbitrum nova
        l2Params[42170] = L2Params({
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            create3Deployer: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
        });

        // layer 2
        //arbitrum one
        l2Params[42161] = L2Params({
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            create3Deployer: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
        });
        // optimism
        l2Params[10] = L2Params({
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            create3Deployer: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
        });
        // bnb chain
        l2Params[56] = L2Params({
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            create3Deployer: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
        });
        // avalanche
        l2Params[43114] = L2Params({
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            create3Deployer: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
        });
        // polygon
        l2Params[137] = L2Params({
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            create3Deployer: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
        });
        // base
        l2Params[8453] = L2Params({
            ccipRouter: 0x0000000000000000000000000000000000000000,
            feeToken: 0x0000000000000000000000000000000000000000,
            create3Deployer: 0x0000000000000000000000000000000000000000,
            admin: 0x0000000000000000000000000000000000000000,
        });
    }


    function getMainnetParams(uint chainId) public pure returns (StPendleParams memory) {
        return stPendleParams[chainId];
    }
    function getTestnetParams(uint chainId) public pure returns (StPendleParams memory) {
        return stPendleParams[chainId];
    }
    function getL2Params(uint chainId) public pure returns (L2Params memory) {
        return l2Params[chainId];
    }
    address public constant merkleDistributor = 0x0000000000000000000000000000000000000000;
    address public constant votingEscrowMainchain = 0x4f30A9D41B80ecC5B94306AB4364951AE3170210;
    address public constant pendleTokenAddress = 0x0000000000000000000000000000000000000000;
    address public constant votingController = 0x0000000000000000000000000000000000000000;
    address public constant stPENDLEMainnet = 0x0000000000000000000000000000000000000000;
    address public constant timelockController = 0x0000000000000000000000000000000000000000;
    address public constant admin = 0x0000000000000000000000000000000000000000;
    address public constant lpFeeReceiver = 0x0000000000000000000000000000000000000000;
    address public constant feeReceiver = 0x0000000000000000000000000000000000000000;
    address public constant create3Deployer = 0x0000000000000000000000000000000000000000;
    address public constant ccipRouter = 0x0000000000000000000000000000000000000000;
    address public constant feeToken = 0x0000000000000000000000000000000000000000;
}
// forge-lint: disable-end(all)
