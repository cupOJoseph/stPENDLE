// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {stPENDLE} from "../src/stPENDLE.sol";
import {ERC20} from "lib/solady/src/tokens/ERC20.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {IPVotingEscrowMainchain} from "src/interfaces/pendle/IPVotingEscrowMainchain.sol";
import {IPVeToken} from "src/interfaces/pendle/IPVeToken.sol";
import {IPVotingController} from "src/interfaces/pendle/IPVotingController.sol";
import {VaultPosition, UserPosition, WithdrawalRequest} from "src/dependencies/VaultStructs.sol";

/// forge-lint: disable-start(all)
// Mock contracts for testing
contract MockVotingEscrowMainchain {
    mapping(address => uint128) public balances;
    mapping(address => uint128) public lockedBalances;
    mapping(address => uint128) public unlockTimes;
    uint128 public totalSupply;

    constructor() {}

    function increaseLockPosition(uint128 additionalAmountToLock, uint128 expiry) external returns (uint128) {
        balances[msg.sender] += additionalAmountToLock;
        lockedBalances[msg.sender] += additionalAmountToLock;
        unlockTimes[msg.sender] = expiry;
        return lockedBalances[msg.sender];
    }

    function withdraw() external returns (uint128) {
        uint128 balance = lockedBalances[msg.sender];
        lockedBalances[msg.sender] = 0;
        balances[msg.sender] = 0;
        return balance;
    }

    function balanceOf(address user) public view returns (uint128) {
        return balances[user];
    }

    function positionData(address user) external view returns (uint128 amount, uint128 expiry) {
        return (balanceOf(user), unlockTimes[user]);
    }

    function totalSupplyStored() external view returns (uint128) {
        return totalSupply;
    }

    function totalSupplyCurrent() external view returns (uint128) {
        return totalSupply;
    }

    function totalSupplyAndBalanceCurrent(address user) external view returns (uint128, uint128) {
        return (totalSupply, balances[user]);
    }

    function mint(address to, uint128 amount) external {
        balances[to] += amount;
        totalSupply += amount;
    }
}

contract MockMerkleDistributor {
    mapping(address => uint256) public claimableAmounts;

    function setClaimable(address account, uint256 amount) external {
        claimableAmounts[account] = amount;
    }

    function claimable(address account) external view returns (uint256) {
        return claimableAmounts[account];
    }

    function claim(uint256, /* index */ address account, uint256, /* amount */ bytes32[] calldata /* merkleProof */ )
        external
        returns (uint256)
    {
        uint256 claimableAmount = claimableAmounts[account];
        claimableAmounts[account] = 0;
        return claimableAmount;
    }
}

contract MockVotingController {
    function vote(uint256 poll, uint256 voteAmount) external {
        // Mock implementation
    }
}

contract MockUSDT is ERC20 {
    constructor() {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function name() public pure override returns (string memory) {
        return "USDTether";
    }

    function symbol() public pure override returns (string memory) {
        return "USDT";
    }
}

contract MockPENDLE is ERC20 {
    constructor() {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function name() public pure override returns (string memory) {
        return "PENDLE";
    }

    function symbol() public pure override returns (string memory) {
        return "PEN";
    }
}

contract stPENDLETest is Test {
    stPENDLE public vault;
    MockVotingEscrowMainchain public votingEscrowMainchain;
    MockMerkleDistributor public merkleDistributor;
    MockVotingController public votingController;
    MockUSDT public usdt;
    MockPENDLE public pendle;
    TimelockController public timelockController;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public feeReceiver = address(0x3);

    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant DEPOSIT_AMOUNT = 100e18;

    event FeeSwitchSet(bool enabled);
    event UseUSDTForFeesSet(bool useUSDT);
    event WithdrawalRequested(address indexed user, uint256 amount, uint256 requestTime);
    event WithdrawalProcessed(address indexed user, uint256 amount);

    function setUp() public {
        // Deploy mock contracts
        merkleDistributor = new MockMerkleDistributor();
        votingController = new MockVotingController();
        votingEscrowMainchain = new MockVotingEscrowMainchain();
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(this);
        executors[0] = address(this);
        timelockController = new TimelockController(1 hours, proposers, executors, address(this));
        usdt = new MockUSDT();
        pendle = new MockPENDLE();

        // Deploy vault
        vault = new stPENDLE(
            address(pendle),
            address(merkleDistributor),
            address(votingEscrowMainchain),
            address(votingController),
            address(timelockController),
            address(this),
            block.timestamp + 1 hours
        );

        // Setup initial balances
        pendle.mint(alice, INITIAL_BALANCE);
        pendle.mint(bob, INITIAL_BALANCE);
        usdt.mint(address(vault), INITIAL_BALANCE);

        // Setup fee receiver
        vault.setFeeReceiver(feeReceiver);

        // Label addresses for better test output
        vm.label(address(vault), "Vault");
        vm.label(address(merkleDistributor), "MerkleDistributor");
        vm.label(address(usdt), "USDT");
        vm.label(address(pendle), "PENDLE");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(feeReceiver, "FeeReceiver");
    }

    function test_Constructor() public view {
        assertEq(address(vault.votingEscrowMainchain()), address(votingEscrowMainchain));
        assertEq(address(vault.merkleDistributor()), address(merkleDistributor));
        assertEq(address(vault.votingController()), address(votingController));
    }

    function test_Deposit() public {
        vm.startPrank(alice);

        pendle.approve(address(vault), DEPOSIT_AMOUNT);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, alice);

        assertGt(shares, 0, "Should receive shares");
        assertEq(vault.balanceOf(alice), shares, "User should have correct share balance");
        assertEq(votingEscrowMainchain.balanceOf(address(vault)), DEPOSIT_AMOUNT, "Vault should have locked PENDLE");

        vm.stopPrank();
    }

    function test_ClaimFeesInPENDLE() public {
        // Setup claimable fees
        merkleDistributor.setClaimable(address(vault), 100e18);

        // Enable fees
        vault.setFeeSwitch(true);
        vault.setFeeBasisPoints(500); // 5%

        // Claim fees
        vault.claimFees();

        // Check that fee was distributed in PENDLE
        assertEq(pendle.balanceOf(feeReceiver), 5e18, "Fee receiver should get 5% in PENDLE");
        assertEq(vePendle.balanceOf(address(vault)), 95e18, "Vault should have 95% locked");
    }

    function test_ClaimFeesInUSDT() public {
        // // Setup claimable fees
        // merkleDistributor.setClaimable(address(vault), 100e18);

        // // Enable fees and set USDT
        // vault.setFeeSwitch(true);
        // vault.setFeeBasisPoints(500); // 5%
        // vault.setUseUSDTForFees(true);

        // // Claim fees
        // vault.claimFees();

        // // Check that fee was distributed in USDT
        // // Note: The current implementation has a placeholder conversion
        // // In production, this would use actual DEX integration
        // assertEq(usdt.balanceOf(feeReceiver), 5e18, "Fee receiver should get 5% in USDT");
        // assertEq(vePendle.balanceOf(address(vault)), 95e18, "Vault should have 95% locked");
    }

    function test_WithdrawalQueue() public {
        // // Setup: Alice deposits and requests withdrawal
        // vm.startPrank(alice);

        // pendle.approve(address(vault), DEPOSIT_AMOUNT);
        // vault.deposit(DEPOSIT_AMOUNT, alice);

        // // Request withdrawal
        // vault.requestWithdrawal(50e18);

        // assertEq(vault.getUserPendingWithdrawal(alice), 50e18, "Should track pending withdrawal");
        // assertEq(vault.totalPendingWithdrawals(), 50e18, "Total pending should be updated");

        // vm.stopPrank();

        // // Check withdrawal request details
        // WithdrawalRequest[] memory requests = vault.getUserWithdrawalRequests(alice);
        // assertEq(requests.length, 1, "Should have one withdrawal request");
        // assertEq(requests[0].amount, 50e18, "Request amount should match");
        // assertEq(requests[0].isProcessed, false, "Request should not be processed yet");
    }

    function test_ProcessWithdrawals() public {
        // // Setup: Alice deposits and requests withdrawal
        // vm.startPrank(alice);

        // pendle.approve(address(vault), DEPOSIT_AMOUNT);
        // vault.deposit(DEPOSIT_AMOUNT, alice);
        // vault.requestWithdrawal(50e18);

        // vm.stopPrank();

        // // Fast forward to next epoch
        // vm.warp(block.timestamp + 1 days);

        // // Process withdrawals
        // vault.processWithdrawals();

        // // Check that withdrawal was processed
        // assertEq(vault.getUserPendingWithdrawal(alice), 0, "Pending withdrawal should be cleared");
        // assertEq(vault.totalPendingWithdrawals(), 0, "Total pending should be cleared");

        // // Check withdrawal request status
        // WithdrawalRequest[] memory requests = vault.getUserWithdrawalRequests(alice);
        // assertEq(requests[0].isProcessed, true, "Request should be marked as processed");
    }

    function test_RelockPendle() public {
        // // Setup: Alice deposits
        // vm.startPrank(alice);

        // pendle.approve(address(vault), DEPOSIT_AMOUNT);
        // vault.deposit(DEPOSIT_AMOUNT, alice);

        // // Request and process withdrawal
        // vault.requestWithdrawal(50e18);

        // vm.stopPrank();

        // // Fast forward and process withdrawal
        // vm.warp(block.timestamp + 1 days);
        // vault.processWithdrawals();

        // // Alice now has PENDLE, let's re-lock it
        // vm.startPrank(alice);

        // pendle.approve(address(vault), 50e18);
        // uint256 newShares = vault.relockPendle(50e18, 30 days);

        // assertGt(newShares, 0, "Should receive new shares");
        // assertEq(vePendle.balanceOf(address(vault)), 100e18, "Vault should have all PENDLE locked");

        // vm.stopPrank();
    }

    function test_GetNextEpochWithdrawalAmount() public {
        // // Setup: Alice deposits and requests withdrawal
        // vm.startPrank(alice);

        // pendle.approve(address(vault), DEPOSIT_AMOUNT);
        // vault.deposit(DEPOSIT_AMOUNT, alice);
        // vault.requestWithdrawal(50e18);

        // vm.stopPrank();

        // // Check available withdrawal amount
        // uint256 available = vault.getNextEpochWithdrawalAmount();
        // assertEq(available, 10e18, "Should allow 10% of locked amount per epoch");
    }

    function test_CanProcessWithdrawal() public {
        // // Setup: Alice deposits and requests withdrawal
        // vm.startPrank(alice);

        // pendle.approve(address(vault), DEPOSIT_AMOUNT);
        // vault.deposit(DEPOSIT_AMOUNT, alice);
        // vault.requestWithdrawal(50e18);

        // vm.stopPrank();

        // // Check if withdrawal can be processed
        // bool canProcess = vault.canProcessWithdrawal(alice, 0);
        // assertFalse(canProcess, "Should not be able to process before epoch change");

        // // Fast forward to next epoch
        // vm.warp(block.timestamp + 1 days);

        // canProcess = vault.canProcessWithdrawal(alice, 0);
        // assertTrue(canProcess, "Should be able to process after epoch change");
    }

    function test_GovernanceFunctions() public {
        // // Test fee switch
        // vault.setFeeSwitch(true);
        // assertTrue(vault.feeSwitchIsEnabled());

        // // Test fee basis points
        // vault.setFeeBasisPoints(1000); // 10%
        // assertEq(vault.feeBasisPoints(), 1000);

        // // Test lock duration
        // vault.setEpochDuration(30 days);
        // assertEq(vault.epochDuration(), 30 days);

        // // Test USDT fee setting
        // vault.setUseUSDT(true);
        // assertTrue(vault.useUSDTForFees());

        // // Test epoch duration
        // vault.setEpochDuration(12 hours);
        // assertEq(vault.epochDuration(), 12 hours);
    }

    function test_RevertInvalidFeeBasisPoints() public {
        vm.expectRevert("Fee cannot exceed 10%");
        vault.setFeeBasisPoints(1001); // 10.01%
    }

    function test_RevertInvalidLockDuration() public {
        vm.expectRevert("Duration too short");
        vault.setEpochDuration(12 hours); // Less than 1 day

        vm.expectRevert("Duration too long");
        vault.setEpochDuration(366 days); // More than 365 days
    }

    function test_RevertInvalidEpochDuration() public {
        vm.expectRevert("Epoch duration too short");
        vault.setEpochDuration(30 minutes); // Less than 1 hour

        vm.expectRevert("Epoch duration too long");
        vault.setEpochDuration(8 days); // More than 7 days
    }

    function test_RevertInvalidFeeReceiver() public {
        vm.expectRevert("Invalid fee receiver");
        vault.setFeeReceiver(address(0));
    }

    function test_RevertInvalidUSDTAddress() public {
        vm.expectRevert("Invalid USDT address");
    }
}
/// forge-lint: disable-end
