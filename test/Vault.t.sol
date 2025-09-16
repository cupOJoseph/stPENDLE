// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {stPENDLE} from "../src/stPENDLE.sol";
import {ERC20} from "lib/solady/src/tokens/ERC20.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {IPVotingEscrowMainchain} from "src/interfaces/pendle/IPVotingEscrowMainchain.sol";
import {IPVeToken} from "src/interfaces/pendle/IPVeToken.sol";
import {IPVotingController} from "src/interfaces/pendle/IPVotingController.sol";
import {ISTPENDLE} from "src/interfaces/ISTPENDLE.sol";
import {VaultPosition, UserPosition, WithdrawalRequest} from "src/dependencies/VaultStructs.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";

/// forge-lint: disable-start(all)
// Mock contracts for testing
contract MockVotingEscrowMainchain {
    mapping(address => uint128) public balances;
    mapping(address => uint128) public lockedBalances;
    mapping(address => uint128) public unlockTimes;
    uint128 public totalSupply;
    MockPENDLE public pendle;
    MockMerkleDistributor public merkleDistributor;
    constructor(MockPENDLE _pendle, MockMerkleDistributor _merkleDistributor) {
        pendle = _pendle;
        merkleDistributor = _merkleDistributor;
    }

    function increaseLockPosition(uint128 additionalAmountToLock, uint128 expiry) external returns (uint128) {
        require(additionalAmountToLock > 0, "Additional amount to lock must be greater than 0");
       pendle.transferFrom(msg.sender, address(this), additionalAmountToLock);
       merkleDistributor.setClaimable(msg.sender, additionalAmountToLock / 10);
        balances[msg.sender] += additionalAmountToLock;
        lockedBalances[msg.sender] += additionalAmountToLock;
        unlockTimes[msg.sender] = expiry;
        return lockedBalances[msg.sender];
    }

    function withdraw() external returns (uint128) {
        uint128 balance = lockedBalances[msg.sender];
        pendle.transfer(msg.sender, balance);
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
    MockPENDLE public pendle;

    constructor(MockPENDLE _mockErc20) {
        pendle = _mockErc20;
        pendle.mint(address(this), 1000e18);
    }

    function setClaimable(address account, uint256 amount) external {
        claimableAmounts[account] = amount;
    }

    function claimable(address account) external view returns (uint256) {
        return claimableAmounts[account];
    }

    function claim(address account, uint256, /* amount */ bytes32[] calldata /* merkleProof */ )
        external
        returns (uint256)
    {
        uint256 claimableAmount = claimableAmounts[account];
        claimableAmounts[account] = 0;
        pendle.mint(account, claimableAmount);
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
    address public charlie = address(0x3);
    address public david = address(0x4);
    address public eve = address(0x5);
    address public feeReceiver = address(0x6);

    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant DEPOSIT_AMOUNT = 100e18;

    event FeeSwitchSet(bool enabled);
    event UseUSDTForFeesSet(bool useUSDT);
    event WithdrawalRequested(address indexed user, uint256 amount, uint256 requestTime);
    event WithdrawalProcessed(address indexed user, uint256 amount);

    function setUp() public {
        // warp state ahead so first epoch == 1
        vm.warp(block.timestamp + 31 days);
        usdt = new MockUSDT();
        pendle = new MockPENDLE();

        // Deploy mock contracts
        merkleDistributor = new MockMerkleDistributor(pendle);
        votingController = new MockVotingController();
        votingEscrowMainchain = new MockVotingEscrowMainchain(pendle, merkleDistributor);
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(this);
        executors[0] = address(this);
        timelockController = new TimelockController(1 hours, proposers, executors, address(this));

        // Deploy vault
        vault = new stPENDLE(
            address(pendle),
            address(merkleDistributor),
            address(votingEscrowMainchain),
            address(votingController),
            address(timelockController),
            address(this),
            20 days,
            30 days
        );

        // Setup initial balances
        pendle.mint(alice, INITIAL_BALANCE);
        pendle.mint(bob, INITIAL_BALANCE);
        pendle.mint(charlie, INITIAL_BALANCE);
        pendle.mint(david, INITIAL_BALANCE);
        pendle.mint(eve, INITIAL_BALANCE);

        // Setup fee receiver
        vault.setFeeReceiver(feeReceiver);

        // Label addresses for better test output
        vm.label(address(vault), "Vault");
        vm.label(address(merkleDistributor), "MerkleDistributor");
        vm.label(address(usdt), "USDT");
        vm.label(address(pendle), "PENDLE");
        vm.label(address(votingEscrowMainchain), "VotingEscrowMainchain");
        vm.label(address(votingController), "VotingController");
        vm.label(address(timelockController), "TimelockController");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(david, "David");
        vm.label(eve, "Eve");
        vm.label(feeReceiver, "FeeReceiver");
    }

    function startFirstEpoch() public {
        vm.startPrank(alice);
        pendle.approve(address(vault), DEPOSIT_AMOUNT);
        vault.depositBeforeFirstEpoch(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        vm.startPrank(address(this));
        vault.startFirstEpoch();
        vm.stopPrank();
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
        vault.claimFees(100e18, new bytes32[](0));

        // Check that fee was distributed in PENDLE
        // assertEq(pendle.balanceOf(feeReceiver), 5e18, "Fee receiver should get 5% in PENDLE");
        uint256 totalPendleUnderManagement = vault.totalSupply();
        uint256 totalPendleLocked = vault.totalLockedPendle();
        assertEq(totalPendleLocked, 100e18, "Vault should have 100% locked");
        assertEq(totalPendleUnderManagement, 100e18, "Vault should have 100% locked");
        assertEq(votingEscrowMainchain.balanceOf(address(vault)), 100e18, "Vault should have 95% locked");
    }

    function test_WithdrawalQueue() public {
        startFirstEpoch();
        // Alice and Bob deposit
        vm.startPrank(alice);
        pendle.approve(address(vault), DEPOSIT_AMOUNT);
        uint256 aliceShares = vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        pendle.approve(address(vault), DEPOSIT_AMOUNT);
        uint256 bobShares = vault.deposit(DEPOSIT_AMOUNT, bob);
        vm.stopPrank();

        // Initially, all deposited PENDLE is locked; available for redemption should be 0
        assertEq(vault.getAvailableRedemptionAmount(), 0, "No unlocked assets initially");

        // Queue redemptions for the next epoch (epoch=0 aliases to currentEpoch+1)
        uint256 aliceRequestShares = aliceShares / 2; // partial
        uint256 bobRequestShares = bobShares; // full

        // Determine the epoch where requests were queued: currentEpoch + 1 (post _updateEpoch inside calls)
        uint256 requestEpoch = vault.currentEpoch() + 1;

        vm.prank(alice);
        vault.requestRedemptionForEpoch(aliceRequestShares, requestEpoch);

        vm.prank(bob);
        vault.requestRedemptionForEpoch(bobRequestShares, requestEpoch);

        // Per-epoch totals should reflect both users' queued shares
        uint256 totalQueued = vault.totalRequestedRedemptionAmountPerEpoch(requestEpoch);
        assertEq(totalQueued, aliceRequestShares + bobRequestShares, "Queued shares per epoch mismatch");

        // User list for that epoch should include Alice then Bob
        address[] memory users = vault.redemptionUsersForEpoch(requestEpoch);
        assertEq(users.length, 2, "Unexpected number of redemption users");
        assertEq(users[0], alice, "First redemption user should be Alice");
        assertEq(users[1], bob, "Second redemption user should be Bob");

        // Before the epoch advances, current-epoch availability for users should be 0
        assertEq(vault.getUserAvailableRedemption(alice), 0, "Alice shouldn't have current-epoch availability yet");
        assertEq(vault.getUserAvailableRedemption(bob), 0, "Bob shouldn't have current-epoch availability yet");

        // Claiming during the wrong epoch should return 0
        vm.prank(alice);
        vault.claimAvailableRedemptionShares(aliceRequestShares);
        assertEq(vault.getUserAvailableRedemption(alice), 0, "Alice shouldn't have current-epoch availability yet");

        // warp to pending epoch
        vm.warp(block.timestamp + 30 days);

        assertEq(vault.currentEpoch(), 2, "Should have advanced to next epoch");
        // start new epoch
        vm.prank(address(this));
        vault.startNewEpoch();
        // assert available redemption
        assertEq(vault.getUserAvailableRedemption(alice), DEPOSIT_AMOUNT / 2, "Alice should have current-epoch availability");
        assertEq(vault.getUserAvailableRedemption(bob), DEPOSIT_AMOUNT, "Bob should have current-epoch availability");

        vm.prank(alice);
        uint256 aliceClaimed = vault.claimAvailableRedemptionShares(aliceRequestShares);
        assertEq(aliceClaimed, aliceRequestShares, "Alice should have claimed their shares");
    }

    function test_ProcessWithdrawals() public {}

    function test_startFirstEpoch() public {
        vm.startPrank(alice);
        pendle.approve(address(vault), DEPOSIT_AMOUNT);
        vault.depositBeforeFirstEpoch(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        vault.startFirstEpoch();
        assertEq(vault.currentEpoch(), 1, "Should have started first epoch");
        assertEq(vault.totalSupply(), DEPOSIT_AMOUNT, "total supply should be equal to initial balance");
        assertEq(vault.totalLockedPendle(), DEPOSIT_AMOUNT, "total locked pendle should be equal to initial balance");
        assertEq(votingEscrowMainchain.balanceOf(address(vault)), DEPOSIT_AMOUNT, "Should have all PENDLE locked");
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
        vm.expectRevert(ISTPENDLE.InvalidFeeBasisPoints.selector);
        vault.setFeeBasisPoints(1001); // 10.01%
    }

    function test_RevertInvalidEpochDuration() public {
        vm.expectRevert(ISTPENDLE.EpochDurationInvalid.selector);
        vm.prank(address(timelockController));
        vault.setEpochDuration(30 minutes); // Less than 1 hour

        vm.expectRevert(ISTPENDLE.EpochDurationInvalid.selector);
        vm.prank(address(timelockController));
        vault.setEpochDuration(900 days); // More than 7 days
    }

    function test_RevertInvalidFeeReceiver() public {
        vm.expectRevert(ISTPENDLE.InvalidFeeReceiver.selector);
        vault.setFeeReceiver(address(0));
    }
}
/// forge-lint: disable-end
