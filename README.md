# xPENDLE

Token and vault contract for institutional grade vePENDLE liquid staking.

## Features:
1. Deposit PENDLE in the vault to recieve xPENDLE
2. PENDLE received by the vault auto locks for 30 days and pays 90% of rewards to xPENDLE holders. 10% of rewards are directed to xPENDLE-PENDLE LPs
3. Council governance on PENDLE votes that can be turned over to other guages or other systems in the future. Council Governance can also update the split of rewards.

<hr>

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
