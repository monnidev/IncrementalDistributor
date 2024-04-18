# Incremental Distributor

## Overview
Incremental Distributor provides a set of smart contracts for managing the creation and distribution of ERC20 tokens. It incorporates dynamic pricing, reentrancy safeguards, and ownership management to facilitate token distribution in a decentralized setting.

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

## Licensing
- The CustomERC20 and DeployDistributor contracts are under the MIT license.
- The Distributor and DistributorTest contracts are released under the GPL license.

This project is a personal effort and is intended for developers looking for a basic framework to manage ERC20 token distribution. It is recommended to perform comprehensive testing and consider additional security audits before using it in a production environment.