// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../interfaces/wombat/IWombatBribeManager.sol";
import "./BribeRewardPool.sol";

/// @title A contract for managing rewards for a pool
/// @author Magpie Team
/// @notice You can use this contract for getting informations about rewards for a specific pools
contract DelegateVoteRewardPool is BribeRewardPool {
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public feeCollector;
    uint256 public protocolFee;
    uint256 public totalWeight;
    address[] public votePools;

    mapping(address => bool) public isVotePool;
    mapping(address => uint256) public votingWeights;
    mapping(address => uint256) private _balances;

    uint256 public constant DENOMINATOR = 10000;

    /* ========== Errors ========== */

    error InvalidPoolTokenAddress();
    error PoolNotActive();

    /* ============ Constructor ============ */

    constructor(
        address _stakingToken,
        address _rewardToken,
        address _operator,
        address _rewardManager
    ) BribeRewardPool(_stakingToken, _rewardToken, _operator, _rewardManager) {}

    /* ============ External Getters ============ */

    function balanceOf(
        address _account
    ) public view override returns (uint256) {
        return _balances[_account];
    }

    /* ============ External Functions ============ */

    /// @notice Updates information for a user in case of staking. Can only be called by the BribeManager operator
    /// @param _for Address account
    /// @param _amount Amount of newly staked tokens by the user on BribeManager
    function stakeFor(
        address _for,
        uint256 _amount
    ) external override onlyOperator updateRewards(_for, rewardTokens) {
        totalSupply = totalSupply + _amount;
        _balances[_for] = _balances[_for] + _amount;
        _updateVote();

        emit Staked(_for, _amount);
    }

    function withdrawFor(
        address _for,
        uint256 _amount,
        bool _claim
    ) external override onlyOperator updateRewards(_for, rewardTokens) {
        totalSupply = totalSupply - _amount;
        _balances[_for] = _balances[_for] - _amount;
        _updateVote();

        emit Withdrawn(_for, _amount);

        if (_claim) {
            _getReward(_for);
        }
    }

    function getReward(
        address _for
    )
        public
        updateRewards(_for, rewardTokens)
        returns (
            address[] memory rewardTokensList,
            uint256[] memory earnedRewards
        )
    {
        (rewardTokensList, earnedRewards) = _getDelegateReward(_for);
    }

    function harvestAll() external {
        (
            address[] memory rewardTokensList,
            uint256[] memory earnedRewards
        ) = IWombatBribeManager(operator).claimAllBribes(address(this));
        _manageRewards(rewardTokensList, earnedRewards);
    }

    /* ============ Internal Functions ============ */

    function _getDelegateReward(
        address _account
    )
        internal
        returns (
            address[] memory rewardTokensList,
            uint256[] memory earnedRewards
        )
    {
        uint256 length = rewardTokens.length;
        rewardTokensList = new address[](length);
        earnedRewards = new uint256[](length);
        for (uint256 index = 0; index < length; ++index) {
            address rewardToken = rewardTokens[index];
            rewardTokensList[index] = rewardToken;
            uint256 reward = earned(_account, rewardToken);
            earnedRewards[index] = reward;
            if (reward > 0) {
                userRewards[rewardToken][_account] = 0;
                IERC20(rewardToken).safeTransfer(_account, reward);
                emit RewardPaid(_account, _account, reward, rewardToken);
            }
        }
    }

    function _updateVote() internal {
        uint256 length = votePools.length;
        int256[] memory deltas = new int256[](length);
        for (uint256 index = 0; index < length; ++index) {
            address pool = votePools[index];
            uint256 targetVote = (votingWeights[pool] * totalSupply) /
                totalWeight;
            uint256 currentVote = _getVoteForLp(pool);
            deltas[index] = int256(targetVote) - int256(currentVote);
        }
        IWombatBribeManager(operator).vote(votePools, deltas);
    }

    function _getVoteForLp(address lp) internal view returns (uint256 vote) {
        vote = IWombatBribeManager(operator).userVotedForPoolInVlmgp(
            address(this),
            lp
        );
    }

    function _manageRewards(
        address[] memory rewardTokensList,
        uint256[] memory earnedRewards
    ) internal {
        uint256 length = rewardTokensList.length;
        for (uint256 index = 0; index < length; ++index) {
            uint256 fees = (protocolFee * earnedRewards[index]) / DENOMINATOR;
            if (fees > 0 && feeCollector != address(0)) {
                earnedRewards[index] = earnedRewards[index] - fees;
                IERC20(rewardTokensList[index]).safeTransfer(
                    feeCollector,
                    fees
                );
            }
            if (earnedRewards[index] > 0) {
                _queueNewRewardsWithoutTransfer(
                    earnedRewards[index],
                    rewardTokensList[index]
                );
            }
        }
    }

    /// @notice Sends new rewards to be distributed to the users staking.
    /// @param _amountReward Amount of reward token to be distributed
    /// @param _rewardToken Address reward token
    function _queueNewRewardsWithoutTransfer(
        uint256 _amountReward,
        address _rewardToken
    ) internal {
        if (!isRewardToken[_rewardToken]) {
            rewardTokens.push(_rewardToken);
            isRewardToken[_rewardToken] = true;
        }
        Reward storage rewardInfo = rewards[_rewardToken];
        rewardInfo.historicalRewards =
            rewardInfo.historicalRewards +
            _amountReward;
        if (totalSupply == 0) {
            rewardInfo.queuedRewards += _amountReward;
        } else {
            if (rewardInfo.queuedRewards > 0) {
                _amountReward += rewardInfo.queuedRewards;
                rewardInfo.queuedRewards = 0;
            }
            rewardInfo.rewardPerTokenStored =
                rewardInfo.rewardPerTokenStored +
                (_amountReward * 10 ** this.stakingDecimals()) /
                totalSupply;
        }
        emit RewardAdded(_amountReward, _rewardToken);
    }

    /* ============ Admin Functions ============ */

    function updateWeight(address lp, uint256 weight) external onlyOwner {
        if (lp == address(this)) revert InvalidPoolTokenAddress();
        if (!isVotePool[lp]) {
            if (!IWombatBribeManager(operator).isPoolActive(lp))
                revert PoolNotActive();
            isVotePool[lp] = true;
            votePools.push(lp);
        }
        totalWeight = totalWeight - votingWeights[lp] + weight;
        votingWeights[lp] = weight;
    }
}
