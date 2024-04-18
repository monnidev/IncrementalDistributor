// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "../lib/forge-std/src/Script.sol";
import {Distributor} from "../src/Distributor.sol";

/// @title Deployment script for the Distributor contract
/// @notice This script is used to deploy the Distributor contract via Forge's scripting capabilities
contract DeployDistributor is Script {
    /// @notice Deploys the Distributor contract with an initial owner and fee configuration
    /// @dev Uses the vm from Forge standard library to handle EVM state manipulation for deployment
    /// @param _initialOwner The address that will be set as the owner of the Distributor contract
    /// @param _initialFee The initial fee percentage in basis points that the Distributor contract will use
    /// @return _distributor The address of the newly deployed Distributor contract
    function run(address _initialOwner, uint256 _initialFee) external returns (Distributor) {
        vm.startBroadcast(); // Start transaction
        Distributor _distributor = new Distributor(_initialOwner, _initialFee); // Deploy new Distributor contract
        vm.stopBroadcast(); // End transaction
        return (_distributor); // Return deployed contract
    }
}
