// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @title ArbWomUp
/// @author Magpie Team
/// @notice WOM will be transfered to admin address and later bridged over ther, for the arbitrum Airdrop

contract ArbWomUp is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public wom; // 18 decimals
    address public usdt; // 18 decimals
    uint256 public totalAccumulated;

    uint256 public constant DENOMINATOR = 10000;
    uint256 public tierLength;
    uint256[] public rewardMultiplier;
    uint256[] public rewardTier;

    mapping(address => uint) public userWOMDeposited;
    mapping(address => uint) public claimedReward;

    /* ============ Events ============ */

    event USDTRewarded(address indexed _beneficiary, uint256 _amount);
    event WomDeposited(address indexed _user, uint _amount);
    event WomTransferredToAdmin(uint256 amount, address destination);

    /* ============ Errors ============ */

    error InvalidAmount();
    error LengthMissmatch();
    error AddressZero();
    error ZeroBalance();

    /* ============ Constructor ============ */

    function __arbWomUp_init(address _wom, address _usdt) public initializer {
        wom = _wom;
        usdt = _usdt;
        __Ownable_init();
    }

    /* ============ Modifier ============ */

    modifier _checkAmount(uint256 _amt) {
        if (_amt == 0) revert InvalidAmount();
        _;
    }

    /* ============ External Functions ============ */

    // if reward ratio is turned on, reward wom converter with USDT
    function incentiveDeposit(
        uint256 _amount
    ) external _checkAmount(_amount) whenNotPaused nonReentrant {
        uint256 rewardToSend = this.getRewardAmount(_amount, msg.sender);
        _deposit(_amount);
        claimedReward[msg.sender] += rewardToSend;
        
        IERC20(usdt).transfer(msg.sender, rewardToSend);
        emit USDTRewarded(msg.sender, rewardToSend);
    }

    function getRewardAmount(uint256 _amount, address _account) external view returns (uint256) {
        if (_amount == 0 || rewardMultiplier.length == 0) return 0;
        uint256 accumulated = _amount + userWOMDeposited[_account];

        uint256 rewardAmount = 0;
        uint256 i = 1;
        while (i < rewardTier.length && accumulated > rewardTier[i]) {
            rewardAmount +=
                (rewardTier[i] - rewardTier[i - 1]) *
                rewardMultiplier[i - 1];
            i++;
        }
        rewardAmount += (accumulated - rewardTier[i - 1]) * rewardMultiplier[i - 1];

        uint256 usdtReward = (rewardAmount / DENOMINATOR) - claimedReward[_account];
        uint256 usdtleft = IERC20(usdt).balanceOf(address(this));

        return usdtReward > usdtleft ? usdtleft : usdtReward;
    }

    function getUserTier(address _account) external view returns (uint256) {
        for (uint256 i = tierLength - 1; i >= 1; i--) {
            if (userWOMDeposited[_account] >= rewardTier[i]) {
                return i;
            }
        }

        return 0;
    }

    function amountToNextTier(address _account) external view returns (uint256) {
        uint256 userTier = this.getUserTier(_account);
        if (userTier == tierLength - 1) return 0;

        return rewardTier[userTier + 1] - userWOMDeposited[_account];
    }

    /* ============ Internal Functions ============ */

    function _deposit(uint256 _amount) internal whenNotPaused {
        IERC20(wom).safeTransferFrom(msg.sender, address(this), _amount);
        userWOMDeposited[msg.sender] += _amount;
        totalAccumulated += _amount;

        emit WomDeposited(msg.sender, _amount);
    }

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function transferToAdmin() external onlyOwner {
        uint256 balance = IERC20(wom).balanceOf(address(this));
        if (balance == 0) revert ZeroBalance();
        IERC20(wom).transfer(owner(), balance);

        emit WomTransferredToAdmin(balance, owner());
    }

    function setMultiplier(
        uint256[] calldata _multiplier,
        uint256[] calldata _tier
    ) external onlyOwner {
        if (
            _multiplier.length == 0 ||
            _tier.length == 0 ||
            (_multiplier.length != _tier.length)
        ) revert LengthMissmatch();

        for (uint8 i = 0; i < _multiplier.length; ++i) {
            if (_multiplier[i] == 0) revert InvalidAmount();
            rewardMultiplier.push(_multiplier[i]);
            rewardTier.push(_tier[i]);
            tierLength += 1;
        }
    }
}
