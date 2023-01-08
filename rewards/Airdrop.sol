// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Contract for MGP rewards for veWOM holders
/// @author Megpie Team
contract Airdrop is Ownable {
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    mapping(address => uint256) public allocations;
    uint256 private constant threeMonthsTime = 3 * 30 * 24 * 3600;
    mapping(uint256 => uint256) public periodsEndTime;
    mapping(uint256 => uint256) public percentPerPeriod;
    uint256 public constant denominator = 10000;
    uint256 public startTime;
    uint256 public totalBonus;
    uint256 public totalEndRemainingAllocation;
    uint256 public totalRemainingAllocation;
    IERC20 public immutable aidropToken;

    /* ============ Errors ============ */

    error AlreadyStarted();
    error AirdropNotEnded();
    error RewardNotMatch();
    error NothingToClaim();
    error InsufficientBalance();
    error NotAllowZeroAddress();
    error StartInThePast();

    /* ============ Constructor ============ */

    constructor(uint256 _startTime, address _token) {
        if(_token == address(0)) revert NotAllowZeroAddress();
        if(_startTime < block.timestamp) revert StartInThePast();

        startTime = _startTime;
        aidropToken = IERC20(_token);
        periodsEndTime[0] = startTime;
        periodsEndTime[1] = startTime + threeMonthsTime;
        periodsEndTime[2] = startTime + 2 * threeMonthsTime;
        periodsEndTime[3] = startTime + 3 * threeMonthsTime;
        periodsEndTime[4] = startTime + 4 * threeMonthsTime;
        percentPerPeriod[0] = 1000;
        percentPerPeriod[1] = 1000;
        percentPerPeriod[2] = 2000;
        percentPerPeriod[3] = 3000;
        percentPerPeriod[4] = 3000;
    }

    /* ============ Admin functions ============ */

    /// @notice Register users allocations
    /// @param _addresses addresses of elligible wallets
    /// @param _amounts amount of MGP for each eligible wallet
    /// @dev both list must be the same length
    function register(
        address[] calldata _addresses,
        uint256[] calldata _amounts
    ) external onlyOwner {
        if(_addresses.length != _amounts.length) revert RewardNotMatch();
        if(block.timestamp >= startTime) revert AlreadyStarted();

        uint256 length = _addresses.length;
        for (uint256 i = 0; i < length; i++) {
            if(_addresses[i] == address(0)) revert NotAllowZeroAddress();
            if(allocations[_addresses[i]] > 0)
                totalRemainingAllocation -= allocations[_addresses[i]];
            allocations[_addresses[i]] = _amounts[i];
            totalRemainingAllocation += _amounts[i];
        }
    }

    /// @notice This will update the start date. Only available before Airdop has already started.
    function adjustStartDate(uint256 _newStartDate) external onlyOwner {
        if(_newStartDate < block.timestamp) revert StartInThePast();
        if(block.timestamp >= startTime) revert AlreadyStarted();

        startTime = _newStartDate;
        periodsEndTime[0] = startTime;
        periodsEndTime[1] = startTime + threeMonthsTime;
        periodsEndTime[2] = startTime + 2 * threeMonthsTime;
        periodsEndTime[3] = startTime + 3 * threeMonthsTime;
        periodsEndTime[4] = startTime + 4 * threeMonthsTime;
    }

    /// @notice 21 months after start date, 9 months after end date, owner will be able to collect the remaining allocations considering the users will not.
    function withdrawDust() external onlyOwner {
        if(block.timestamp < startTime + 7 * threeMonthsTime) revert AirdropNotEnded();

        aidropToken.safeTransfer(owner(), aidropToken.balanceOf(address(this)));
    }

    /* ============ External Functions ============ */

    /// @notice Get the claimable MGP amount of _user
    /// @param _user The user to get the claimable amount for
    /// @dev includes the bonus amount
    /// @return claimableAmount The claimable amount
    function getClaimableAmount(address _user)
        public
        view
        returns (uint256 claimableAmount)
    {
        uint256 userAllocation = allocations[_user];
        claimableAmount = 0;
        if (userAllocation > 0) {
            for (uint256 i = 0; i < 5; i++) {
                if (block.timestamp >= periodsEndTime[i]) {
                    claimableAmount += userAllocation * percentPerPeriod[i];
                }
            }
            claimableAmount /= denominator;
            claimableAmount += getBonusAmount(_user);
        }
    }

    /// @notice Get the bonus amount for user
    /// @param _user The user to get the bonus amount for
    /// @return bonusAmount The vonus amount
    function getBonusAmount(address _user)
        public
        view
        returns (uint256 bonusAmount)
    {
        bonusAmount = 0;
        uint256 userAllocation = allocations[_user];
        if (
            block.timestamp >= periodsEndTime[4] &&
            totalEndRemainingAllocation != 0
        ) {
            bonusAmount =
                ((userAllocation * 10**9) * totalBonus) /
                totalEndRemainingAllocation /
                10**9;
        }
    }

    /// @notice This will store the ending remaining amount for the bonus.
    function updateEndRemainingAllocation() public {
        if (block.timestamp >= periodsEndTime[4]) {
            totalEndRemainingAllocation = totalRemainingAllocation;
        }
    }

    /// @notice Claim MGP and forfeit remaining allocation
    function claim() external {
        if (totalEndRemainingAllocation == 0) {
            updateEndRemainingAllocation();
        }
        uint256 claimableAmount = getClaimableAmount(msg.sender);
        
        if(claimableAmount == 0) revert NothingToClaim();
        if(claimableAmount > aidropToken.balanceOf(address(this))) revert InsufficientBalance();

        uint256 userAllocation = allocations[msg.sender];
        allocations[msg.sender] = 0;
        totalRemainingAllocation -= userAllocation;
        if (claimableAmount <= userAllocation) {
            uint256 forfeited = userAllocation - claimableAmount;
            totalBonus += forfeited;
        }
        aidropToken.safeTransfer(msg.sender, claimableAmount);
    }

}