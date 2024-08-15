# Disclaimer

This code is part of a small personal project and is not intended for use in production environments. It has not been thoroughly tested, nor has it undergone any form of security audit. Use this code at your own risk, and be aware that it may contain bugs, vulnerabilities, or other issues that could lead to unexpected behavior.

# Incremental Distributor

## Overview
Incremental Distributor provides a set of smart contracts for managing the creation and distribution of ERC20 tokens. The contract acts as a deployer and distributor of ERC20 tokens with a linear price increase. The token creator can set various parameters which will influence both deployment and distribution.

## Components
This project consists of four main Solidity contracts:

### CustomERC20 Contract
This contract extends the OpenZeppelin ERC20 standard to include burnability and permit features, as well as a mechanism to enforce a maximum supply and handle initial premint conditions. It's designed for flexibility in deployment scenarios and robust handling of token logistics.

### DeployDistributor Contract
A script built with Forge's capabilities that simplifies the process of deploying the Distributor contract. This deployer allows ERC20 creators to create their own tokens, deciding the initial price and the linear price increase for their tokens.

### Distributor Contract
Serves as the core of the token distribution process, managing the economics of token sales through an incrementally increasing pricing model. It includes reentrancy protection for transaction security and features for financial management, such as fee withdrawals and adjustments. Buyers will be sent tokens after paying for them, and tokens creators can withdraw the sales proceeds minus a fee for the deployer owner.

### DistributorTest Contract
A suite of tests developed using Foundry’s framework to test the functionality and security of the Distributor contract. It checks that all components of the token distribution process, including token creation, fee management, and security measures, operate as intended under different scenarios.

## Getting Started

### Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0 (816e00b 2023-03-16T00:05:26.396218Z)`

### Installation

Clone the repository and compile contracts
```bash 
git clone https://github.com/monnidev/IncrementalDistributor
code IncrementalDistributor
```

### Build

```
forge build
```

### Test

```
forge test
```

## Licensing
- The CustomERC20, DeployDistributor and DistributorTest contracts are under the MIT license.
- The Distributor contract is released under the GPL 3 license.
