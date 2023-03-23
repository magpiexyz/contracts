// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import { IMWom } from "../interfaces/wombat/IMWom.sol";

import "../interfaces/IVLMGP.sol";
import "../interfaces/ISimpleHelper.sol";

contract WomUp is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    IVLMGP public vlMGP;
    IMWom public mWom;
    address public wom;
    address public mgp;

    uint256 public startTime;
    uint256 public duration;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 internal _totalSupply;

    uint256 public constant DENOMINATOR = 10000;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) private _balances;
    mapping(address => bool) public validHelpers;

    /* ============ Events ============ */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event PenaltyForwarded(uint256 amount);
    event Rescued();
    event SetLocker(address locker);
    event Migrate(address indexed user, uint256 amount, address targetHelper);

    /* ============ Errors ============ */

    error MustNotZero();
    error MustZero();
    error AlreadyStarted();
    error NotValidTarget();

    function __womup_init(
        address _vlMGP,
        address _mWom,
        address _wom,
        uint256 _startTime
    ) public initializer {
        __Ownable_init();
        vlMGP = IVLMGP(_vlMGP);
        mWom = IMWom(_mWom);
        wom = _wom;
        mgp = address(vlMGP.MGP());
        startTime = _startTime;
        duration = 7 days;
    }

    /* ============ Modifiers ============ */

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /* ============ External Getters ============ */    

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return (block.timestamp < periodFinish ? block.timestamp : periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (
                (lastTimeRewardApplicable() - (lastUpdateTime)) * rewardRate * (1e18) / (totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account) * (rewardPerToken() - (userRewardPerTokenPaid[account])) / (1e18) + (
                rewards[account]
            );
    }

    /* ============ External Functions ============ */

    function stake(uint256 _amount) public updateReward(msg.sender) returns (bool) {
        if (_amount == 0) revert MustNotZero();

        _totalSupply = _totalSupply + (_amount);
        _balances[msg.sender] = _balances[msg.sender] + (_amount);

        IERC20(wom).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(wom).safeApprove(address(mWom), _amount);
        mWom.deposit(_amount);

        emit Staked(msg.sender, _amount);

        return true;
    }

    function withdraw(uint256 amount, bool claim) public updateReward(msg.sender) returns (bool) {
        if (amount == 0) revert MustNotZero();

        _totalSupply = _totalSupply - (amount);
        _balances[msg.sender] = _balances[msg.sender] - (amount);

        IERC20(mWom).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);

        if (claim) {
            getReward();
        }

        return true;
    }

    function migrate(uint256 _amount, bool _claim, address _targetHelper) external updateReward(msg.sender) {
        if (_amount == 0) revert MustNotZero();
        if (!validHelpers[_targetHelper]) revert NotValidTarget();

        _totalSupply = _totalSupply - (_amount);
        _balances[msg.sender] = _balances[msg.sender] - (_amount);

        IERC20(mWom).safeApprove(_targetHelper, _amount);
        ISimpleHelper(_targetHelper).depositFor(_amount, msg.sender);
        emit Migrate(msg.sender, _amount, _targetHelper);

        if (_claim) {
            getReward();
        }
    }

    function getReward() public updateReward(msg.sender) returns (bool) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            IERC20(mgp).safeApprove(address(vlMGP), reward);
            vlMGP.lockFor(reward, msg.sender);
            emit RewardPaid(msg.sender, reward);
        }
        return true;
    }

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function rescueReward() public onlyOwner {
        if(block.timestamp >= startTime || rewardRate > 0) revert AlreadyStarted();

        uint256 balance = IERC20(mgp).balanceOf(address(this));
        IERC20(mgp).safeTransfer(owner(), balance);

        emit Rescued();
    }

    function setTargetHelper(address _helper, bool valid) external onlyOwner {
        validHelpers[_helper] = valid;
    }

    function initializeRewards() external onlyOwner returns (bool) {
        if(rewardRate > 0) revert MustZero();

        uint256 rewardsAvailable = IERC20(mgp).balanceOf(address(this));
        if(rewardsAvailable == 0) revert MustNotZero();

        rewardRate = rewardsAvailable / (duration);

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + (duration);

        emit RewardAdded(rewardsAvailable);

        return true;
    }
}