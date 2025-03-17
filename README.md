# KyberSwap Rewards KSDistributor

The **KSDistributor**, is a smart contract allowing the distribution of multiple ERC20 tokens through multiple campaigns, each with its own distribution schedule and Merkle tree. The design is heavily inspired by the [Universal Rewards Distributor](https://github.com/morpho-org/universal-rewards-distributor) by Morpho Protocol. Compared to the URD, the KSD has the following differences:

- Supports multiple campaigns, each with its own Merkle tree and distribution schedule.
- Supports distributing rewards to NFTs' holders, not just to addresses.
- Supports claiming rewards on behalf of another address.
- Supports batch claiming of rewards.

## Usage

### Pre-requisites
- Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Install [Yarn](https://yarnpkg.com/getting-started/install)

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

### Deploy

```shell
$ forge create src/KSDistributor.sol:KSDistributor --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Generate Merkle Tree

```shell
$ yarn ts-node script/generate-merkle-tree.ts
```
