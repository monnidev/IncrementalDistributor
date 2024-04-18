// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DeployDistributor} from "../script/DeployDistributor.s.sol";
import {Distributor} from "../src/Distributor.sol";
import {CustomERC20} from "../src/CustomERC20.sol";
import {Test, console} from "../lib/forge-std/src/Test.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";
import {StdCheats} from "../lib/forge-std/src/StdCheats.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title Tests for the Distributor Contract
/// @notice Implements tests for various functionalities in the Distributor smart contract
contract DistributorTest is StdCheats, Test {
    DeployDistributor public s_deployer;
    Distributor public s_distributor;

    address public s_distributorOwner = makeAddr("s_distributorOwner");
    address public s_firstCreator = makeAddr("s_firstCreator");
    address public s_firstUser = makeAddr("s_firstUser");
    address public s_secondUser = makeAddr("s_secondUser");
    address public s_richUser = makeAddr("s_richUser");
    address public s_thief = makeAddr("s_thief");
    uint256 public constant STARTING_USER_BALANCE = 100 ether;
    uint256 public constant MAX_STARTING_USER_BALANCE = type(uint256).max;

    /// @notice Set up the environment for each test, deploying contracts and funding test accounts
    function setUp() external {
        s_deployer = new DeployDistributor();
        (s_distributor) = s_deployer.run(s_distributorOwner, 1);
        vm.deal(s_firstCreator, STARTING_USER_BALANCE);
        vm.deal(s_firstUser, STARTING_USER_BALANCE);
        vm.deal(s_secondUser, STARTING_USER_BALANCE);
        vm.deal(s_richUser, MAX_STARTING_USER_BALANCE);
        vm.deal(s_thief, STARTING_USER_BALANCE);
    }

    /// @notice Test that generating a token with premint amounts exceeding the maximum supply reverts as expected
    function testGenerationPremintAboveMax() public {
        address[] memory _premintAddresses = new address[](3);
        _premintAddresses[0] = s_firstUser;
        _premintAddresses[1] = s_secondUser;
        _premintAddresses[2] = s_richUser;

        uint256[] memory _premintAmounts = new uint256[](3);
        _premintAmounts[0] = 100 ether;
        _premintAmounts[1] = 1589 ether;
        _premintAmounts[2] = 999999 ether;

        vm.expectRevert();
        vm.prank(s_firstCreator);
        s_distributor.generateNewToken(
            s_firstCreator, "TEST", "TST", 1000000 ether, _premintAddresses, _premintAmounts, 1e15 wei, 1e12 wei
        );
    }

    /// @notice Test that generating a token with correct settings emits the expected logs
    function testTokenGenerationWithEvents() public {
        address[] memory _premintAddresses = new address[](3);
        _premintAddresses[0] = s_firstUser;
        _premintAddresses[1] = s_secondUser;
        _premintAddresses[2] = s_richUser;

        uint256[] memory _premintAmounts = new uint256[](3);
        _premintAmounts[0] = 100 ether;
        _premintAmounts[1] = 1589 ether;
        _premintAmounts[2] = 999999 ether;

        vm.prank(s_firstCreator);
        vm.recordLogs();
        s_distributor.generateNewToken(
            s_firstCreator, "TEST", "TST", 10000000 ether, _premintAddresses, _premintAmounts, 1e15 wei, 1e12 wei
        );
        Vm.Log[] memory _entries = vm.getRecordedLogs();

        assertEq(IERC20(address(uint160(uint256(_entries[4].topics[1])))).balanceOf(s_firstUser), _premintAmounts[0]);
        assertEq(s_firstCreator, address(uint160(uint256(_entries[4].topics[2]))));
        assertEq(10000000 ether, uint256(_entries[4].topics[3]));
    }

    /// @notice Test that trying to generate a token with prices out of acceptable range fails
    function testGenerationOutOfRange() public {
        address[] memory _premintAddresses = new address[](0);
        uint256[] memory _premintAmounts = new uint256[](0);

        vm.prank(s_firstCreator);
        vm.expectRevert(Distributor.Distributor__TokenPricesOutOfRange.selector);
        s_distributor.generateNewToken(
            s_firstCreator, "TEST", "TST", 10000000 ether, _premintAddresses, _premintAmounts, 100 ether, 10 wei
        );
    }

    /// @notice Test distribution logic for distributing tokens based on incoming ether
    function testTokenDistribution() public {
        uint256 _initialPrice = 1e15 wei;
        uint256 _priceIncrease = 1e12 wei;
        address[] memory _premintAddresses = new address[](0);
        uint256[] memory _premintAmounts = new uint256[](0);

        vm.prank(s_firstCreator);
        vm.recordLogs();
        address _tokenAddress = s_distributor.generateNewToken(
            s_firstCreator,
            "TEST",
            "TST",
            10000000 ether,
            _premintAddresses,
            _premintAmounts,
            _initialPrice,
            _priceIncrease
        );

        uint256 _amountToBuy = 1 ether;
        uint256 _remainingAmount = _amountToBuy;
        uint256 _expectedTokens = 0;
        uint256 _currentPrice = _initialPrice;

        vm.prank(s_richUser);
        s_distributor.distributeTokens{value: _amountToBuy}(_tokenAddress);

        while (_remainingAmount >= _currentPrice) {
            _expectedTokens += 1 ether; // Increment expected tokens by 1 (considering 1 _token = 1 ether for simplicity)
            _remainingAmount -= _currentPrice; // Deduct the current _token price from the amount
            _currentPrice += _priceIncrease; // Increase the price for the next _token
        }
        _expectedTokens += (_remainingAmount * 1 ether) / _currentPrice;
        assertApproxEqRel(IERC20(_tokenAddress).balanceOf(s_richUser), _expectedTokens, 1e14); // 0.01% accuracy
    }

    /// @notice Test to ensure proper handling when not enough tokens remain to fulfill a distribution request
    function testTokenDistributionNotEnoughTokensRemaining() public {
        uint256 _initialPrice = 1 ether;
        uint256 _priceIncrease = 5000 wei;
        uint256 _maxSupply = 100 ether;

        address[] memory _premintAddresses = new address[](0);
        uint256[] memory _premintAmounts = new uint256[](0);

        vm.prank(s_firstCreator);
        vm.recordLogs();
        address _tokenAddress = s_distributor.generateNewToken(
            s_firstCreator, "TEST", "TST", _maxSupply, _premintAddresses, _premintAmounts, _initialPrice, _priceIncrease
        );

        uint256 _amountToBuy = 9999 ether;
        uint256 _remainingAmount = _amountToBuy;
        uint256 _expectedTokens = 0;
        uint256 _currentPrice = _initialPrice;

        vm.prank(s_richUser);
        s_distributor.distributeTokens{value: _amountToBuy}(_tokenAddress);

        while (_expectedTokens < _maxSupply && _remainingAmount >= _currentPrice) {
            _expectedTokens += 1 ether; // Increment expected tokens by 1 (considering 1 _token = 1 ether for simplicity)
            _remainingAmount -= _currentPrice; // Deduct the current _token price from the amount
            _currentPrice += _priceIncrease; // Increase the price for the next _token
        }
        Vm.Log[] memory _entries = vm.getRecordedLogs();
        assertApproxEqRel(_remainingAmount, uint256(_entries[2].topics[2]), 1e14); // 0.01% accuracy
    }

    /// @notice Test for uneven minimum values to check token distribution precision
    function testTokenDistributionMinValuesUneven() public {
        uint256 _initialPrice = 5001 wei;
        uint256 _priceIncrease = 5001 wei;
        address[] memory _premintAddresses = new address[](0);
        uint256[] memory _premintAmounts = new uint256[](0);

        vm.prank(s_firstCreator);
        vm.recordLogs();
        address _tokenAddress = s_distributor.generateNewToken(
            s_firstCreator, "TEST", "TST", 3 ether, _premintAddresses, _premintAmounts, _initialPrice, _priceIncrease
        );

        uint256 _amountToBuy = 15003 wei + 15003 wei;
        uint256 _remainingAmount = _amountToBuy;
        uint256 _expectedTokens = 0;
        uint256 _currentPrice = _initialPrice;

        vm.prank(s_richUser);
        s_distributor.distributeTokens{value: _amountToBuy}(_tokenAddress);

        while (_remainingAmount >= _currentPrice) {
            _expectedTokens += 1 ether; // Increment expected tokens by 1 (considering 1 _token = 1 ether for simplicity)
            _remainingAmount -= _currentPrice; // Deduct the current _token price from the amount
            _currentPrice += _priceIncrease; // Increase the price for the next _token
        }
        _expectedTokens += (_remainingAmount * 1 ether) / _currentPrice;
        assertApproxEqRel(IERC20(_tokenAddress).balanceOf(s_richUser), _expectedTokens, 1e14); // 0.01% accuracy
    }

    /// @notice Test max values to explore the boundaries of token distribution
    function testTokenDistributionMaxValues() public {
        uint256 _initialPrice = 1 ether;
        uint256 _priceIncrease = 1 ether;
        address[] memory _premintAddresses = new address[](0);
        uint256[] memory _premintAmounts = new uint256[](0);

        vm.prank(s_firstCreator);
        vm.recordLogs();
        address _tokenAddress = s_distributor.generateNewToken(
            s_firstCreator,
            "TEST",
            "TST",
            (type(uint256).max / 1 ether) * 1 ether, // Decimals removed
            _premintAddresses,
            _premintAmounts,
            _initialPrice,
            _priceIncrease
        );

        uint256 _amountToBuy = 10 ** 30;
        uint256 _remainingAmount = _amountToBuy;
        uint256 _expectedTokens = 0;
        uint256 _currentPrice = _initialPrice;

        vm.prank(s_richUser);
        s_distributor.distributeTokens{value: _amountToBuy}(_tokenAddress);

        while (_remainingAmount >= _currentPrice) {
            _expectedTokens += 1 ether; // Increment expected tokens by 1 (considering 1 _token = 1 ether for simplicity)
            _remainingAmount -= _currentPrice; // Deduct the current _token price from the amount
            _currentPrice += _priceIncrease; // Increase the price for the next _token
        }
        _expectedTokens += (_remainingAmount * 1 ether) / _currentPrice;
        assertApproxEqRel(IERC20(_tokenAddress).balanceOf(s_richUser), _expectedTokens, 1e14); // 0.01% accuracy
    }

    /// @notice Test external token fails to be distributed by the contract
    function testExternalTokenFails() public {
        vm.prank(s_thief);
        vm.expectRevert(Distributor.Distributor__TokenNotAuthorized.selector);
        s_distributor.distributeTokens{value: 1 ether}(makeAddr("random"));
    }

    /// @notice Test creators' ability to withdraw accumulated funds
    function testCreatorsWithdrawal() public {
        uint256 _currentFee = s_distributor.s_currentFee();
        testTokenDistribution();
        uint256 _initialBalance = s_firstCreator.balance;
        vm.prank(s_firstCreator);
        s_distributor.creatorsWithdrawal();
        uint256 _finalBalance = s_firstCreator.balance;
        assertEq(
            _finalBalance,
            _initialBalance + 1 ether /*Amount distributed*/ - (1 ether * _currentFee) / 10000 /*Distributor fee calculation*/
        );
    }

    /// @notice Test owner's ability to withdraw accumulated fees
    function testOwnerWithdrawal() public {
        uint256 _currentFee = s_distributor.s_currentFee();
        testTokenDistribution();
        uint256 _initialBalance = s_distributorOwner.balance;
        vm.prank(s_distributorOwner);
        s_distributor.ownerWithdrawal(s_distributorOwner);
        uint256 _finalBalance = s_distributorOwner.balance;
        assertEq(_finalBalance, _initialBalance + (1 ether * _currentFee) / 10000 /*Distributor fee calculation*/ );
        vm.prank(s_thief);
        vm.expectRevert();
        s_distributor.ownerWithdrawal(makeAddr("random"));
    }

    /// @notice Test the functionality of changing the fee percentage by the owner
    function testOwnerChangeFee() public {
        vm.prank(s_distributorOwner);
        vm.expectRevert(Distributor.Distributor__WrongFee.selector); // Expect to revert if the fee is too high
        s_distributor.ownerChangeFee(99999);
        vm.prank(s_distributorOwner);
        s_distributor.ownerChangeFee(1000); // Set a valid fee
        testOwnerWithdrawal(); // Re-run the owner withdrawal to check with new fee
        vm.prank(s_thief);
        vm.expectRevert(); // Expect revert due to unauthorized access
        s_distributor.ownerChangeFee(500);
    }
}
