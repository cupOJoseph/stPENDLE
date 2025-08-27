//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC4626} from "solady/tokens/ERC4626.sol";
import {Ownable} from "solady/auth/Ownable.sol";


//basic interface for vePENDLE. Some things are missing here but these are all we need.
//
interface IVEPENDLE {
    function claimFees() external;
    function lock(uint256 amount, uint256 lockDuration) external;
    function unlock(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

interface IMerkleDistributor {
    function claimable(address account) external view returns (uint256);
    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external;
}

interface IVotingController {
    function vote(uint poll, uint voteAmount) external;
}


/**
 * @title xPENDLE - ERC-4626 Vault for PENDLE Staking
 * @notice Accepts PENDLE deposits and stakes them in vePENDLE for rewards
 * @dev Fully compliant with ERC-4626 tokenized vault standard using Solady
 */
contract xPENDLE is ERC4626, Ownable { 
    
    bool public feeSwitchIsEnabled = false;
    uint public feeBasisPoints = 0;
    address public feeReceiver;
    
    IVEPENDLE vePendle;
    IMerkleDistributor merkleDistributor;
    IVotingController votingController;

    uint public lockDurationDefault = 0;

    event FeeSwitchSet(bool enabled);
    event FeeBasisPointsSet(uint basisPoints);
    event LockDurationDefaultSet(uint duration);
    event FeeReceiverSet(address feeReceiver);

    constructor(address merkleDistributorAddress, address vePENDLETokenAddress, address votingControllerAddress) ERC4626("xPENDLE", "xPENDLE", _vault) {
        vePendle = IVEPENDLE(vePENDLETokenAddress);
        merkleDistributor = IMerkleDistributor(merkleDistributorAddress);
        votingController = IVotingController(votingControllerAddress);
    }

    function deposit(uint256 amount, address receiver) public override returns (uint256) {
        uint depositAmount = super.deposit(amount, receiver);

        vePendle.lock(depositAmount, 0);

        return depositAmount;
    }


    // @dev This function is called by the anyone to claim fees to the vault.
    // This should be done daily or more often to compound rewards.
    function claimFees() public {
        uint claimedAmount = merkleDistributor.claim(0, msg.sender, 0, new bytes32[](0));
        
        if (feeSwitchIsEnabled) {
            uint fee = (claimedAmount * feeBasisPoints) / 10000;
            //do to: transfer % of claimed pendle to feeReceiver
            claimedAmount -= fee;
        }   

        //lock everything claimed to the vault
        vePendle.lock(claimedAmount, lockDurationDefault);
    }


    /// =========== Governance Council Functions ================ ///


    function setFeeSwitch(bool enabled) public onlyOwner {
        feeSwitchIsEnabled = enabled;
        emit FeeSwitchSet(enabled);
    }

    function setFeeBasisPoints(uint basisPoints) public onlyOwner {
        feeBasisPoints = basisPoints;
        emit FeeBasisPointsSet(basisPoints);
    }

    function setLockDurationDefault(uint duration) public onlyOwner {
        lockDurationDefault = duration;
        emit LockDurationDefaultSet(duration);
    }
    
    function setFeeReceiver(address feeReceiver) public onlyOwner {
        feeReceiver = feeReceiver;
        emit FeeReceiverSet(feeReceiver);
    }

}