# xPENDLE

Token and vault contract for institutional grade vePENDLE liquid staking.

## Features:
1. Deposit PENDLE in the vault to recieve xPENDLE
2. PENDLE received by the vault auto locks for 30 days and pays 90% of rewards to xPENDLE holders. 10% of rewards are directed to xPENDLE-PENDLE LPs
3. Council governance on PENDLE votes that can be turned over to other guages or other systems in the future. Council Governance can also update the split of rewards.

<hr>

## Withdrawals and Redemption Queue (stPENDLE.sol)

- **Epoch-based queue**: Withdrawals are requested in shares and queued per epoch. Requests for the current epoch are not allowed; use the next epoch or a specific future epoch.
- **How to request**: `requestRedemptionForEpoch(uint256 shares, uint256 epoch)` where `epoch = 0` means `currentEpoch + 1`. The vault records pending shares per user per epoch.
- **Redemption window**: During each epoch, there is a window defined by `preLockRedemptionPeriod` when redemptions can be processed/claimed. Outside the window, claims return 0.
- **Processing**: Anyone can batch process the current epoch with `processRedemptions()` (withdraws unlocked PENDLE from vePENDLE and fulfills requests FIFO). Users can self-claim with `claimAvailableRedemptionShares(uint256 shares)` during the window.
- **Liquidity and epochs**: On `startNewEpoch()`, the vault advances the epoch, withdraws matured vePENDLE, reserves assets for pending redemptions of the new epoch, and re-locks remaining assets for `epochDuration`.
- **Observability**: `getUserAvailableRedemption(address)`, `getTotalRequestedRedemptionAmountPerEpoch(uint256)`, `getRedemptionUsersForEpoch(uint256)`, `getAvailableRedemptionAmount()`, and `previewVeWithdraw()` expose queue and liquidity state.
- **ERC-4626 overrides**: Direct `redeem` and `mint` are disabled (revert). Use the queue flow above.

## Dev Instructions 

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
