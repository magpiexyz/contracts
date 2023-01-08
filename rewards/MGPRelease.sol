// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title Contract for vesting a token linearly through a time range
/// @author Megpie Team
contract MGPRelease is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ============ Structs ============ */

    struct Vesting {
        uint256 totalAlloced;
        uint256 claimed;
        bool revoked;
    } 

    /* ============ State Variables ============ */    

    uint256 public immutable startTimestamp;
    uint256 public immutable endTimestamp;
    uint256 public immutable timeInSecBeforeWithdrawDust;

    uint256 public immutable initialUnlockPercentage;
    uint256 public constant denominator = 1000;

    mapping(address => Vesting) public beneficiaries;
    address public immutable tokenToRelease;

    /* ============ Errors ============ */

    error RewardNotMatch();
    error AccountRevoked();
    error InvalidStartTime();
    error InvalidEndTIme();
    error InvalidInitPerc();
    error NotAllowedToRegister();
    error WithdrawDustNotAllowedYet();
    error NotAllowZeroAddress();

    /* ============ Events ============ */

    event Claimed(address _account, uint256 _amount);
    event RevokedUpdated(address _account, bool _isRevoked);
    event DustWithdraw(address _to, uint256 _amount);

    /* ============ Constructor ============ */

    constructor(uint256 _startTimestamp, uint256 _endTimestamp, address _token, uint256 _initialUnlockPercentage, uint256 _timeInSecBeforeWithdrawDust) {
        if (block.timestamp > _startTimestamp)
            revert InvalidStartTime();
        if (_endTimestamp <= _startTimestamp)
            revert InvalidEndTIme();

        if (_initialUnlockPercentage > denominator)
            revert InvalidInitPerc();

        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;
        tokenToRelease = _token;
        initialUnlockPercentage = _initialUnlockPercentage;
        timeInSecBeforeWithdrawDust = _timeInSecBeforeWithdrawDust;
    }

    /* ============ External Getters ============ */

    function getVestingInfo(address _account) external view returns(uint256 total, uint256 claimed, bool isRevoked) {
        Vesting storage vesting = beneficiaries[_account];
        total = vesting.totalAlloced;
        claimed = vesting.claimed;
        isRevoked = vesting.revoked;
    }

    function getClaimable(address _account) public view returns (uint256 claimable) {
        Vesting storage vesting = beneficiaries[_account];
        uint256 initialUnlockedAmount = vesting.totalAlloced * initialUnlockPercentage / denominator;

        if (block.timestamp <= startTimestamp)
            return  initialUnlockedAmount - vesting.claimed;

        if (block.timestamp >= endTimestamp)
            return vesting.totalAlloced - vesting.claimed;

        uint256 needVesting = vesting.totalAlloced - initialUnlockedAmount;
        uint256 vested = (((block.timestamp - startTimestamp) * needVesting) / (endTimestamp - startTimestamp));

        claimable = (initialUnlockedAmount + vested - vesting.claimed);
    }    

    /* ============ External Functions ============ */

    function claim() nonReentrant external {
        Vesting storage vesting = beneficiaries[msg.sender];
        if (vesting.revoked)
            revert AccountRevoked();
        
        uint256 claimable = getClaimable(msg.sender);
        IERC20(tokenToRelease).safeTransfer(msg.sender, claimable);
        vesting.claimed += claimable;

        emit Claimed(msg.sender, claimable);
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
        if(block.timestamp >= endTimestamp) revert NotAllowedToRegister();

        if(_addresses.length != _amounts.length) revert RewardNotMatch();

        uint256 length = _addresses.length;
        for (uint256 i = 0; i < length; i++) {
            if(_addresses[i] == address(0)) revert NotAllowZeroAddress();
            beneficiaries[_addresses[i]] = Vesting({
                totalAlloced: _amounts[i],
                claimed: 0,
                revoked: false
            });
        }
    }

    function revoke(address _account, bool _isRevoked) external onlyOwner() {
        Vesting storage vesting = beneficiaries[_account];
        vesting.revoked = _isRevoked;

        emit RevokedUpdated(_account, _isRevoked);
    }

    function withdrawDust() external onlyOwner() {
        if (block.timestamp < endTimestamp + timeInSecBeforeWithdrawDust)
            revert WithdrawDustNotAllowedYet();

        uint256 dustAmount = IERC20(tokenToRelease).balanceOf(address(this));
        IERC20(tokenToRelease).safeTransfer(owner(), dustAmount);

        emit DustWithdraw(owner(), dustAmount);
    }
}