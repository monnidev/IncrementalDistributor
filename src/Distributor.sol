// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

// Importing interfaces and contracts for ERC20 token interaction, security against re-entrancy, and ownership management
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {CustomERC20} from "./CustomERC20.sol"; // Custom ERC20 token contract

/// @title Incremental distributor for ERC20 tokens
/// @notice This contract manages the distribution of ERC20 tokens with variable pricing and provides security features like reentrancy protection.
/// @dev Extends Ownable and ReentrancyGuard to manage ownership and prevent re-entrant calls.
contract Distributor is ReentrancyGuard, Ownable {
    /// Custom errors for handling specific fail states
    error Distributor__WrongFee();
    error Distributor__CreatorWithdrawalFailed();
    error Distributor__OwnerWithdrawalFailed();
    error Distributor__TokenPricesOutOfRange();
    error Distributor__NotEnoughTokens();
    error Distributor__TokenNotAuthorized();
    error Distributor__AmountTooLow();
    error Distributor__FinalRefundFailed();

    struct tokenData {
        address tokenPriceReceiver; // Receives the price for token sales
        uint256 currentTokenPrice; // Current price of the token
        uint256 increaseTokenPrice; // Amount to increase the token price per sale
    }

    uint256 private s_distributorOwnerbalance; // Balance of the contract owner from fees
    uint256 public s_currentFee; // Current fee percentage for transactions in basis points (100 = 1%)

    // Mappings for token data and balances
    mapping(IERC20 => tokenData) public s_tokensGenerated;
    mapping(address => uint256) public s_tokenCreatorBalance;

    // Events for logging actions within the contract
    event NewTokenGenerated(
        address indexed tokenAddress, address indexed tokenPriceReceiver, uint256 indexed maxSupply
    );
    event TokensDistributed(address indexed receiver, address indexed tokenAddress, uint256 indexed amount);
    event FinalRefundIssued(address indexed receiver, uint256 indexed amount);
    event CreatorWithdrew(address indexed creator, uint256 indexed amount);
    event OwnerWithdrew(address indexed owner, uint256 indexed amount);
    event FeeChanged(uint256 indexed newFee);

    /// @notice Initializes the contract with a specified owner and fee
    /// @dev Sets the initial owner and fee for the distributor contract, reverts if fee is above 10000 basis points
    /// @param _initialOwner The initial owner of the contract
    /// @param _initialFee The initial fee, in basis points, for distributing tokens
    constructor(address _initialOwner, uint256 _initialFee) Ownable(_initialOwner) {
        if (_initialFee <= 10000) {
            s_currentFee = _initialFee;
        } else {
            revert Distributor__WrongFee();
        }
    }

    /// @notice Creates a new ERC20 token with specific attributes
    /// @dev Deploys a new instance of CustomERC20 with given parameters, registers it in s_tokensGenerated
    /// @param _tokenPriceReceiver Address that will receive payments for token sales
    /// @param _name The name of the new token
    /// @param _symbol The symbol of the new token
    /// @param _maxSupply The maximum supply of the new token
    /// @param _premintAddresses Addresses to which the initial supply will be allocated
    /// @param _premintAmounts Amounts of the initial supply for each premint address
    /// @param _currentTokenPrice Initial selling price of the token
    /// @param _increaseTokenPrice Price increment per token sale
    /// @return _tokenAddress The address of the newly created token
    function generateNewToken(
        address _tokenPriceReceiver,
        string memory _name,
        string memory _symbol,
        uint256 _maxSupply,
        address[] memory _premintAddresses,
        uint256[] memory _premintAmounts,
        uint256 _currentTokenPrice,
        uint256 _increaseTokenPrice
    ) public returns (address) {
        // The initial token price and the price increase must be between 1 Eth and 5000 wei to avoid overflows and rounding errors
        if (
            _currentTokenPrice > 1 ether || _increaseTokenPrice > 1 ether || _currentTokenPrice < 5000 wei
                || _increaseTokenPrice < 5000 wei
        ) {
            revert Distributor__TokenPricesOutOfRange();
        }
        // Deploy the token with the specified parameters
        CustomERC20 _currentToken =
            new CustomERC20(_name, _symbol, _maxSupply, address(this), _premintAddresses, _premintAmounts);
        // Add token details to the distributor mapping
        s_tokensGenerated[IERC20(_currentToken)] = tokenData({
            tokenPriceReceiver: _tokenPriceReceiver,
            currentTokenPrice: _currentTokenPrice,
            increaseTokenPrice: _increaseTokenPrice
        });
        address _tokenAddress = address(_currentToken);
        emit NewTokenGenerated(_tokenAddress, _tokenPriceReceiver, _maxSupply);
        return _tokenAddress;
    }

    /// @notice Distributes tokens based on the current price and available supply
    /// @dev Handles the sale of tokens, including price adjustment and refunds if necessary, guarded against reentrancy
    /// @param _token The address of the token to distribute
    function distributeTokens(address _token) public payable nonReentrant {
        // Retrieve the token interface and current token pricing information
        IERC20 _currentToken = IERC20(_token);
        uint256 _currentTokenPrice = s_tokensGenerated[_currentToken].currentTokenPrice;
        uint256 _increaseTokenPrice = s_tokensGenerated[_currentToken].increaseTokenPrice;

        // Ensure the token is authorized for sale
        if (_currentTokenPrice == 0 || _increaseTokenPrice == 0) {
            revert Distributor__TokenNotAuthorized();
        }
        // Check that enough ETH was sent to cover at least the current token price
        if (msg.value < _currentTokenPrice) {
            revert Distributor__AmountTooLow();
        }
        // Get the balance of tokens available for distribution
        uint256 _tokenBalance = _currentToken.balanceOf(address(this));
        if (_tokenBalance == 0) {
            revert Distributor__NotEnoughTokens();
        }

        // Calculate how many tokens can be bought with the provided ETH amount
        uint256 _amountEth = msg.value; // Tested up to 10^50, risk of overflow above 10^58 but it shouldn't be an issue
        uint256 _tokensToTransfer = calculateTokens(_amountEth, _currentTokenPrice, _increaseTokenPrice);

        // Check if there are fewer tokens available than the amount calculated to transfer
        if (_tokenBalance < _tokensToTransfer) {
            // Adjust tokens to transfer to available balance
            _tokensToTransfer = _tokenBalance;
            // Calculate the total ETH spent on the tokens to be transfered
            uint256 _finalExpense = calculateExpense(_tokensToTransfer, _currentTokenPrice, _increaseTokenPrice);
            // Calculate the amount of ETH to refund to the buyer
            uint256 _toRefund = _amountEth - _finalExpense;
            // Update the token price based on the number of tokens actually available
            s_tokensGenerated[_currentToken].currentTokenPrice += _increaseTokenPrice * _tokensToTransfer / 10 ** 18;
            // Update the ETH amount to reflect the amount actually spent
            _amountEth = _finalExpense;
            // Refund excess ETH back to the buyer
            (bool success,) = payable(address(msg.sender)).call{value: _toRefund}("");
            if (!success) {
                revert Distributor__FinalRefundFailed();
            }
            emit FinalRefundIssued(msg.sender, _toRefund);
        } else {
            // Update the token price if all requested tokens are available
            s_tokensGenerated[_currentToken].currentTokenPrice += _increaseTokenPrice * _tokensToTransfer / 10 ** 18;
        }
        // Transfer the tokens to the buyer
        _currentToken.transfer(msg.sender, _tokensToTransfer);
        // Calculate and allocate the fee
        uint256 _distributorFee = (_amountEth * s_currentFee) / 10000;
        s_tokenCreatorBalance[s_tokensGenerated[_currentToken].tokenPriceReceiver] += _amountEth - _distributorFee;
        s_distributorOwnerbalance += _distributorFee;
        // Emit an event indicating the distribution of tokens
        emit TokensDistributed(msg.sender, address(_currentToken), _tokensToTransfer);
    }

    /// @notice Allows token creators to withdraw their accumulated balance
    /// @dev Transfers the accumulated balance to the caller's address, secured against re-entrancy
    function creatorsWithdrawal() public {
        uint256 _toSend = s_tokenCreatorBalance[msg.sender];
        s_tokenCreatorBalance[msg.sender] = 0;
        (bool success,) = payable(msg.sender).call{value: _toSend}("");
        if (!success) {
            revert Distributor__CreatorWithdrawalFailed();
        }
        emit CreatorWithdrew(msg.sender, _toSend);
    }

    /// @notice Allows the owner to withdraw the accumulated fees
    /// @dev Transfers the accumulated fees to the specified receiver, only callable by the owner
    /// @param withdrawalReceiver The address to receive the withdrawn fees
    function ownerWithdrawal(address withdrawalReceiver) public onlyOwner {
        uint256 _toSend = s_distributorOwnerbalance;
        s_distributorOwnerbalance = 0;
        (bool success,) = payable(address(withdrawalReceiver)).call{value: _toSend}("");
        if (!success) {
            revert Distributor__OwnerWithdrawalFailed();
        }
        emit OwnerWithdrew(msg.sender, _toSend);
    }

    /// @notice Allows the owner to change the fee percentage
    /// @dev Sets a new fee percentage, reverts if new fee is above 10000 basis points
    /// @param _newFee The new fee percentage in basis points
    function ownerChangeFee(uint256 _newFee) public onlyOwner {
        if (_newFee <= 10000) {
            s_currentFee = _newFee;
        } else {
            revert Distributor__WrongFee();
        }
        emit FeeChanged(_newFee);
    }

    /// Credits to the user hiddenintheworld of ethereum-magicians.org for this implementation
    /// @dev Calculates the square root of a number, optimized using bit shifting
    /// @param x The number to calculate the square root of
    /// @return result The approximate square root as a uint128
    function sqrt(uint256 x) internal pure returns (uint128 result) {
        if (x == 0) {
            return 0;
        } else {
            uint256 xx = x;
            uint256 r = 1;
            if (xx >= 0x100000000000000000000000000000000) {
                xx >>= 128;
                r <<= 64;
            }
            if (xx >= 0x10000000000000000) {
                xx >>= 64;
                r <<= 32;
            }
            if (xx >= 0x100000000) {
                xx >>= 32;
                r <<= 16;
            }
            if (xx >= 0x10000) {
                xx >>= 16;
                r <<= 8;
            }
            if (xx >= 0x100) {
                xx >>= 8;
                r <<= 4;
            }
            if (xx >= 0x10) {
                xx >>= 4;
                r <<= 2;
            }
            if (xx >= 0x8) r <<= 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            uint256 r1 = x / r;
            return uint128(r < r1 ? r : r1);
        }
    }

    /// @dev Calculates the number of tokens to transfer based on ETH sent and price escalation
    /// @param _amountEth The amount of ETH sent by the buyer
    /// @param _currentTokenPrice The current price of one token
    /// @param _increaseTokenPrice The price increase per token for each token sold
    /// @return _tokensToTransfer The number of tokens that can be transfered with the provided ETH
    function calculateTokens(uint256 _amountEth, uint256 _currentTokenPrice, uint256 _increaseTokenPrice)
        internal
        pure
        returns (uint256)
    {
        // Formula to determine tokens to transfer based on payment and incremental pricing
        uint256 _tokensToTransfer = 10 ** 18
            * (
                (_increaseTokenPrice / 2)
                    + (sqrt((_currentTokenPrice - (_increaseTokenPrice / 2)) ** 2 + (2 * _increaseTokenPrice * _amountEth)))
                    - _currentTokenPrice
            ) / _increaseTokenPrice;
        return _tokensToTransfer;
    }

    /// @dev Calculates the amount of ETH to refund when supply is less than demand, issues can arise if the remaining amount is very low
    /// @param _tokensToTransfer The number of tokens initially intended to be transfered
    /// @param _currentTokenPrice The current price per token before sale
    /// @param _increaseTokenPrice The increase in token price per token sold
    /// @return _finalExpense The final expense in ETH for the number of tokens transfered
    function calculateExpense(uint256 _tokensToTransfer, uint256 _currentTokenPrice, uint256 _increaseTokenPrice)
        internal
        pure
        returns (uint256)
    {
        // Calculating the total cost using formula derived from the price increase mechanism
        uint256 _valueA = _tokensToTransfer * _increaseTokenPrice / 1 ether;
        uint256 _valueB = 2 * _currentTokenPrice - _increaseTokenPrice;
        uint256 _divisor = 2 * _increaseTokenPrice;
        uint256 _finalExpense = (_valueA * (_valueA + _valueB)) / _divisor;
        return _finalExpense;
    }
}
