pragma solidity ^0.8.0;

import "../interfaces/IStandardTokenMock.sol";
import "../../interfaces/wombat/IMasterWombat.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MasterWombatMock is IMasterWombat {

    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 available; // in case of locking
    }

    // Info of each pool.
    struct PoolInfo {
        address lpToken; // Address of LP token contract.
        uint256 rewardAmount;
        address additionalReward;
        uint256 additionalRewardAmount;
    }

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    mapping(uint256 => PoolInfo) public pidToPoolInfo;
    // amount everytime deposit or withdraw will get

    mapping (address => uint256) public lpToPid;

    address public rewardToken;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // reward upon each deposit and withdraw call;

    constructor(address _rewardToken) {
        rewardToken = _rewardToken;
    }

    function getAssetPid(address lp) override external view returns(uint256) {
        return lpToPid[lp];
    }

    /// @notice Deposit LP tokens to Master Magpie for MGP allocation.
    /// @dev it is possible to call this function with _amount == 0 to claim current rewards
    function depositFor(uint256 _pid, uint256 _amount, address _account) override external {
        _deposit(_pid, _amount, _account);
    }

    function deposit(uint256 _pid, uint256 _amount) override external returns (uint256, uint256) {
        _deposit(_pid, _amount, msg.sender);
    }

    function _deposit(uint256 _pid, uint256 _amount, address _account) internal {
        PoolInfo storage pool = poolInfo[_pid];
        
        IERC20 poolLpToken = IERC20(pool.lpToken);        
        
        poolLpToken.transferFrom(address(msg.sender), address(this), _amount);
        UserInfo storage user = userInfo[_pid][_account];

        if (user.amount > 0) {
            safeWOMTransfer(payable(_account), pool.rewardAmount);
            if(pool.additionalReward != address(0)) {
                IStandardTokenMock(pool.additionalReward).mint(msg.sender, pool.additionalRewardAmount);
            }
        }

        user.amount += _amount;
    }
 
    function withdraw(uint256 _pid, uint256 _amount) override external returns (uint256, uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount && user.amount > 0,  'withdraw: not good');
        
        safeWOMTransfer(payable(msg.sender), pool.rewardAmount);
        if(pool.additionalReward != address(0)) {
            IStandardTokenMock(pool.additionalReward).mint(msg.sender, pool.additionalRewardAmount);
        }

        user.amount = user.amount - _amount;

        IERC20 poolLpToken = IERC20(pool.lpToken);
        poolLpToken.transfer(address(msg.sender), _amount);
    }

    function multiClaim(uint256[] memory _pids) override external returns (
        uint256,
        uint256[] memory,
        uint256[] memory
    ) {
        uint256[] memory amounts = new uint256[](_pids.length);
        uint256[] memory additionalRewards= new uint256[](_pids.length);
        uint256 transfered;

        for (uint256 i = 0; i < _pids.length; i++) {
            PoolInfo storage pool = poolInfo[_pids[i]];
            UserInfo storage user = userInfo[_pids[i]][msg.sender];
            if (user.amount > 0) {
                transfered += pool.rewardAmount;
                amounts[i] = (pool.rewardAmount);
                if (pool.additionalReward != address(0)) {
                    additionalRewards[i] = pool.additionalRewardAmount;
                    IStandardTokenMock(pool.additionalReward).mint(msg.sender, pool.additionalRewardAmount);
                }                   
            }
        }

        safeWOMTransfer(payable(msg.sender), transfered);
        return (transfered, amounts, additionalRewards);
    }


    function safeWOMTransfer(address payable to, uint256 _amount) internal {
        IStandardTokenMock(rewardToken).mint(to, _amount);
    }

    function addPool(address lp, uint256 _rewardAmount, address _additionalReward, uint256 _additionalRewardAmount) external returns (uint256) {
        PoolInfo memory newPool = PoolInfo(lp, _rewardAmount, _additionalReward, _additionalRewardAmount);
        poolInfo.push(newPool);
        uint256 poolId = poolInfo.length - 1;
        pidToPoolInfo[poolId] = newPool;        
        lpToPid[lp] = poolId;
        return poolId;
    }

    function setPool(address lp, uint256 _rewardAmount, address _additionalReward, uint256 _additionalRewardAmount) external {
        uint256 pid = lpToPid[lp];
        PoolInfo storage pool = poolInfo[pid];
        pool.rewardAmount = _rewardAmount;
        pool.additionalReward = _additionalReward;
        pool.additionalRewardAmount = _additionalRewardAmount;
    }

    function pendingTokens(uint256 _pid, address _user) override external view
        returns (
            uint256 pendingRewards,
            IERC20[] memory bonusTokenAddresses,
            string[] memory bonusTokenSymbols,
            uint256[] memory pendingBonusRewards
        ) {
        UserInfo storage user = userInfo[_pid][_user];
        PoolInfo storage pool = poolInfo[_pid];

        if (user.amount > 0) {
            pendingRewards = pool.rewardAmount;
        } else {
            pendingRewards = 0;
        }
    }

    function rewardAmounts(uint256 _pid) external view returns(uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        return pool.rewardAmount;
    }

}