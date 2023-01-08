// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

import "../interfaces/IVLMGP.sol";
import "../interfaces/IMasterMagpie.sol";
import "../interfaces/IvlmgpPBaseRewarder.sol";

/// @title A contract for managing rewards for a pool
/// @author Magpie Team
/// @notice You can use this contract for getting informations about rewards for a specific pools
contract vlMGPBaseRewarder is IvlmgpPBaseRewarder, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;

    IVLMGP public vlMGP; 

    /* ============ State Variables ============ */

    address public  stakingToken;
    address public  masterMagpie;    // master magpie
    address public rewardManager;    // wombat staking

    address[] public rewardTokens;

    struct Reward {
        address rewardToken;
        uint256 rewardPerTokenStored;
        uint256 queuedRewards;
        uint256 historicalRewards;
    }

    mapping(address => Reward) public rewards;
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;                 
    mapping(address => mapping(address => uint256)) public userRewards;
    mapping(address => bool) public isRewardToken;
    mapping(address => bool) public managers;

    /* ============ Events ============ */

    event RewardAdded(uint256 _reward, address indexed _token);
    event MGPHarvested(address indexed _user, uint256 _userReceiveAmount, uint256 _forfeitAmount);
    event Staked(address indexed _user, uint256 _amount);
    event Withdrawn(address indexed _user, uint256 _amount);
    event RewardPaid(address indexed _user, address indexed _receiver, uint256 _reward, address indexed _token);
    event ManagerUpdated(address indexed _manager, bool _allowed);

    /* ============ Errors ============ */

    error OnlyManager();
    error OnlyMasterMagpie();
    error NotAllowZeroAddress();

    /* ============ Constructor ============ */

    function __vlMGPBaseRewarder_init(
        address _vlMGP,
        address _rewardToken,
        address _masterMagpie,
        address _rewardManager
    ) public initializer {
        __Ownable_init();
        if(
            _vlMGP == address(0) ||
            _masterMagpie  == address(0) ||
            _rewardManager  == address(0)
        ) revert NotAllowZeroAddress();

        stakingToken = _vlMGP;
        masterMagpie = _masterMagpie;
        address mgp = address(IVLMGP(_vlMGP).MGP());
        // mgp as default reward
        rewards[_rewardToken] = Reward({
            rewardToken: mgp,
            rewardPerTokenStored: 0,
            queuedRewards: 0,
            historicalRewards: 0            
        });
        rewardTokens.push(mgp);
        isRewardToken[mgp] = true;

        if (_rewardToken != address(0)) {
            rewards[_rewardToken] = Reward({
                rewardToken: _rewardToken,
                rewardPerTokenStored: 0,
                queuedRewards: 0,
                historicalRewards: 0
            });
            rewardTokens.push(_rewardToken);
        }

        isRewardToken[_rewardToken] = true;
        managers[_rewardManager] = true;

        vlMGP = IVLMGP(_vlMGP);
    }

    /* ============ Modifiers ============ */

    modifier updateReward(address _account) {
        uint256 rewardTokensLength = rewardTokens.length;
        for (uint256 index = 0; index < rewardTokensLength; ++index) {
            address rewardToken = rewardTokens[index];
            userRewards[rewardToken][_account] = earned(_account, rewardToken);
            userRewardPerTokenPaid[rewardToken][_account] = rewardPerToken(
                rewardToken
            );
        }
        _;
    }
    
    modifier onlyManager() {
        if (!managers[msg.sender])
            revert OnlyManager();
        _;
    }

    modifier onlyMasterMagpie() {
        if (msg.sender != masterMagpie)
            revert OnlyMasterMagpie();
        _;
    }

    /* ============ External Getters ============ */

    /// @notice Returns decimals of reward token
    /// @param _rewardToken Address of reward token
    /// @return Returns decimals of reward token
    function rewardDecimals(address _rewardToken)
        override
        public
        view
        returns (uint256)
    {
        return IERC20Metadata(_rewardToken).decimals();
    }

    /// @notice Returns address of staking token
    /// @return address of staking token
    function getStakingToken() external override view returns (address) {
        return stakingToken;
    }

    /// @notice Returns decimals of staking token
    /// @return Returns decimals of staking token
    function stakingDecimals() public override view returns (uint256) {
        return IERC20Metadata(stakingToken).decimals();
    }

    /// @notice Returns total current lock weighting, lock weighting is calculated by 
    /// amount of MGP still in lock + amount of MGP in cool down / 2
    /// @return Returns current amount of staked tokens
    function totalStaked() external override view returns (uint256) {
        return IERC20(address(vlMGP)).totalSupply();
    }

    /// @notice Returns lock weighting of an user. Lock weighting is calculated by 
    /// amount of MGP still in lock + amount of MGP in cool down / 2
    /// @param _account Address account
    /// @return Returns amount of staked tokens by account
    function balanceOf(address _account) external override view returns (uint256) {
        (uint256 staked, ) =  IMasterMagpie(masterMagpie).stakingInfo(stakingToken, _account);
        return staked;
    }

    /// @notice Returns amount of reward token per staking tokens in pool
    /// @param _rewardToken Address reward token
    /// @return Returns amount of reward token per staking tokens in pool
    function rewardPerToken(address _rewardToken)
        public
        override
        view
        returns (uint256)
    {
        return rewards[_rewardToken].rewardPerTokenStored;
    }

    function rewardTokenInfos()
        override
        external
        view
        returns
        (
            address[] memory bonusTokenAddresses,
            string[] memory bonusTokenSymbols
        )
    {
        uint256 rewardTokensLength = rewardTokens.length;
        bonusTokenAddresses = new address[](rewardTokensLength);
        bonusTokenSymbols = new string[](rewardTokensLength);
        for (uint256 i; i < rewardTokensLength; i++) {
            bonusTokenAddresses[i] = rewardTokens[i];
            bonusTokenSymbols[i] = IERC20Metadata(address(bonusTokenAddresses[i])).symbol();
        }
    }

    function calExpireForfeit(address _account, address _rewardToken) public view returns(uint256) {
        uint256 fullyUnockAmount = vlMGP.getFullyUnlock(_account);
        uint256 reward = this.earned(_account, _rewardToken);
        if (fullyUnockAmount == 0)
            return 0;

        return (((reward * fullyUnockAmount * 1e12) / this.balanceOf(_account) ) / 1e12);
    }    

    /* ============ External Functions ============ */

    /// @notice Updates the reward information for one account
    /// @param _account Address account
    function updateFor(address _account) external override {
        uint256 length = rewardTokens.length;
        for (uint256 index = 0; index < length; ++index) {
            address rewardToken = rewardTokens[index];
            userRewards[rewardToken][_account] = earned(_account, rewardToken);
            userRewardPerTokenPaid[rewardToken][_account] = rewardPerToken(
                rewardToken
            );
        }
    }

    /// @notice Returns amount of reward token earned by a user
    /// @param _account Address account
    /// @param _rewardToken Address reward token
    /// @return Returns amount of reward token earned by a user
    function earned(address _account, address _rewardToken)
        public
        override
        view
        returns (uint256)
    {
        return (
            (((this.balanceOf(_account) *
                (rewardPerToken(_rewardToken) -
                    userRewardPerTokenPaid[_rewardToken][_account])) /
                (10**stakingDecimals())) + userRewards[_rewardToken][_account])
        );
    }

    /// @notice Returns amount of all reward tokens
    /// @param _account Address account
    /// @return pendingBonusRewards as amounts of all rewards.
    function allEarned(address _account)
        external
        override
        view
        returns (
            uint256[] memory pendingBonusRewards
        )
    {
        uint256 length = rewardTokens.length;
        pendingBonusRewards = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            pendingBonusRewards[i] = earned(_account, rewardTokens[i]);
        }

        return pendingBonusRewards;
    }

    /// @notice Calculates and sends reward to user. Only callable by masterMagpie
    /// @param _account Address account
    /// @return Returns True
    function getReward(address _account, address _receiver)
        override
        public
        onlyMasterMagpie
        updateReward(_account)
        nonReentrant
        returns (bool)
    {
        uint256 length = rewardTokens.length;
        for (uint256 index = 0; index < length; ++index) {
            address rewardToken = rewardTokens[index];
            
            uint256 forfeit = this.calExpireForfeit(_account, rewardToken);
            uint256 toSend = userRewards[rewardToken][_account] - forfeit;
            
            if (toSend > 0) {
                userRewards[rewardToken][_account] = 0;
                IERC20(rewardToken).safeTransfer(_receiver, toSend);
                emit RewardPaid(_account, _receiver, toSend, rewardToken);
            }

            if(forfeit > 0)
                _queueNewRewardsWithoutTransfer(forfeit, rewardToken);
        }
        return true;
    }

    function getRewardLength() external view returns(uint256) {
        return rewardTokens.length;
    }

    /* ============ Admin Functions ============ */

    function updateManager(address _rewardManager, bool _allowed) external onlyOwner {
        managers[_rewardManager] = _allowed;

        emit ManagerUpdated(_rewardManager, managers[_rewardManager]);
    }

    function queueMGP(uint256 _amount, address _account) override external onlyManager nonReentrant returns (bool) {
        IERC20(vlMGP.MGP()).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 fullyUnockAmount = vlMGP.getFullyUnlock(_account);
        uint256 forfeitAmount = 0;

        if (fullyUnockAmount != 0)
            forfeitAmount = (((_amount * fullyUnockAmount * 1e12) / this.balanceOf(_account) ) / 1e12);

        _queueNewRewardsWithoutTransfer(forfeitAmount, address(vlMGP.MGP()));
        IERC20(vlMGP.MGP()).safeTransfer(_account, _amount - forfeitAmount);

        emit MGPHarvested(_account, _amount, forfeitAmount);

        return true;
    }

    /// @notice Sends new rewards to be distributed to the users staking. Only callable by manager
    /// @param _amountReward Amount of reward token to be distributed
    /// @param _rewardToken Address reward token
    /// @return Returns True
    function queueNewRewards(uint256 _amountReward, address _rewardToken)
        override
        external
        onlyManager
        returns (bool)
    {
        if (!isRewardToken[_rewardToken]) {
            rewardTokens.push(_rewardToken);
            isRewardToken[_rewardToken] = true;
        }
        IERC20Metadata(_rewardToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amountReward
        );
        Reward storage rewardInfo = rewards[_rewardToken];
        rewardInfo.historicalRewards =
            rewardInfo.historicalRewards +
            _amountReward;
        if (this.totalStaked() == 0) {
            rewardInfo.queuedRewards += _amountReward;
        } else {
            if (rewardInfo.queuedRewards > 0) {
                _amountReward += rewardInfo.queuedRewards;
                rewardInfo.queuedRewards = 0;
            }
            rewardInfo.rewardPerTokenStored =
                rewardInfo.rewardPerTokenStored +
                (_amountReward * 10**stakingDecimals()) /
                this.totalStaked();
        }
        emit RewardAdded(_amountReward, _rewardToken);
        return true;
    }

    /* ============ Internal Functions ============ */

    function _queueNewRewardsWithoutTransfer(uint256 _amountReward, address _rewardToken)
        internal
        returns (bool)
    {
        Reward storage rewardInfo = rewards[_rewardToken];
        rewardInfo.historicalRewards = rewardInfo.historicalRewards + _amountReward;
        if (this.totalStaked() == 0) {
            rewardInfo.queuedRewards += _amountReward;
        } else {
            if (rewardInfo.queuedRewards > 0) {
                _amountReward += rewardInfo.queuedRewards;
                rewardInfo.queuedRewards = 0;
            }
            rewardInfo.rewardPerTokenStored =
                rewardInfo.rewardPerTokenStored +
                (_amountReward * 10**stakingDecimals()) /
                this.totalStaked();
        }
        emit RewardAdded(_amountReward, _rewardToken);
        return true;
    }
}