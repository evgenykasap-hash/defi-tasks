## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

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

## Aave V3 Lending Provider

The `AaveV3LendingProvider` contract (under `src/AaveV3LendingProvider/`) aggregates all user deposits and borrows into Aave V3 on Ethereum mainnet. Key features:

- Preconfigured with the canonical pool (`0x87870BCa3F3fd6335C3F4ce8392D69350Fb90F9C`), wrapped token gateway (`0xd01607c3C5eCABa394D8be377a08590149325722`), and core assets (WETH via gateway, USDC, and DAI).
- Uses share-based accounting so user balances automatically reflect the interest earned on aTokens or accrued on variable debt tokens.
- Supports depositing/withdrawing WETH liquidity via the WrappedTokenGateway so users interact with ETH natively.
- Provides `deposit`, `withdraw`, `borrow`, and `repay` entry points together with view helpers (`supplyBalanceOf`, `debtBalanceOf`, etc.).

### Deployment

Use the bundled script to deploy with the default configuration:

```shell
forge script src/AaveV3LendingProvider/AaveV3LendingProvider.s.sol:DeployAaveV3LendingProvider \
  --rpc-url <RPC> \
  --private-key <PK> \
  --broadcast
```

### Testing

The dedicated test suite relies on lightweight mocks that emulate the Aave V3 pool, tokens, and ETH gateway behaviour:

```shell
forge test --match-path src/AaveV3LendingProvider/test/AaveV3LendingProvider.t.sol
```

This keeps the tests deterministic while the on-chain contract continues to use the real Aave mainnet endpoints.

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
