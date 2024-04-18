// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import statements for ERC20, ERC20Burnable, and ERC20Permit from OpenZeppelin Contracts library
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title A Custom ERC20 Token with Burn and Permit Capabilities
/// @notice This contract extends ERC20 standard with burnable and permit features, including an initial premint and max supply enforcement
/// @dev Inherits ERC20, ERC20Burnable, and ERC20Permit from OpenZeppelin Contracts to create a fully featured token
contract CustomERC20 is ERC20, ERC20Burnable, ERC20Permit {
    /// @dev Error to indicate that the max supply was exceeded at token generation
    error ERC20__MaxSupplyExceededAtGeneration(uint256, uint256);
    /// @dev Error to indicate that the max supply must be in whole token units
    error ERC20__MaxSupplyOnlyTokenUnits();
    /// @dev Error to indicate mismatch in premint addresses and amounts
    error ERC20__PremintLengthNotMatch(uint256, uint256);
    /// @dev Error to indicate that premints must be in whole token units
    error ERC20__PremintOnlyTokenUnitsAllowedAtGeneration();

    uint256 private immutable i_maxSupply; // Immutable variable for maximum supply of the token
    address private immutable i_distributor; // Immutable variable for the distributor address

    /// @notice Constructs the CustomERC20 token
    /// @param _name Name of the token
    /// @param _symbol Symbol of the token
    /// @param _maxSupply Maximum supply of the token (in smallest unit)
    /// @param _distributor Address that will handle token distribution
    /// @param _premintAddresses Array of addresses to receive the preminted tokens
    /// @param _premintAmounts Array of amounts to premint to the respective addresses
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _maxSupply,
        address _distributor,
        address[] memory _premintAddresses,
        uint256[] memory _premintAmounts
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        if (_premintAddresses.length != _premintAmounts.length) {
            revert ERC20__PremintLengthNotMatch(_premintAddresses.length, _premintAmounts.length);
        }
        if (_maxSupply % 1 ether != 0) {
            revert ERC20__MaxSupplyOnlyTokenUnits();
        }

        i_maxSupply = _maxSupply;
        i_distributor = _distributor;

        for (uint256 i = 0; i < _premintAddresses.length; ++i) {
            if (_premintAmounts[i] % 1 ether != 0) {
                revert ERC20__PremintOnlyTokenUnitsAllowedAtGeneration();
            }
            _mint(_premintAddresses[i], _premintAmounts[i]);
        }

        if (totalSupply() > _maxSupply) {
            revert ERC20__MaxSupplyExceededAtGeneration(totalSupply(), _maxSupply);
        }

        // Calculate and mints the remaining supply to the distributor
        uint256 _supplyToDistribute = _maxSupply - totalSupply();
        _mint(i_distributor, _supplyToDistribute);
    }

    /// @notice Returns the maximum supply of the token
    /// @return The maximum supply as a uint256
    function maxSupply() public view returns (uint256) {
        return i_maxSupply;
    }

    /// @notice Returns the address of the distributor
    /// @return The distributor's address as an address type
    function distributor() public view returns (address) {
        return i_distributor;
    }
}
