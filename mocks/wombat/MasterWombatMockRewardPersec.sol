pragma solidity ^0.8.0;

import "../interfaces/IStandardTokenMock.sol";
import "../../interfaces/wombat/IMasterWombat.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IMultiRewarder.sol";

contract MasterWombatMockRewardPersec is IMasterWombat {

    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 available; // in case of locking
    }

    // Info of each pool.
    struct PoolInfo {
        address lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. MGPs to distribute per second.
        uint256 lastRewardTimestamp; // Last timestamp that MGPs distribution occurs.
        uint256 accRewardPerShare; // Accumulated MGPs per share, times 1e12. See below.

        // storage slot 2
        IMultiRewarder rewarder;
    }

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    mapping(uint256 => PoolInfo) public pidToPoolInfo;
    // amount everytime deposit or withdraw will get

    mapping (address => uint256) public lpToPid;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    address public rewardToken;
    // MGP tokens created per second.
    uint256 public rewardPerSec;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // reward upon each deposit and withdraw call;
    

    // The timestamp when MGP mining starts.
    uint256 public startTimestamp;    

    constructor(address _rewardToken,
                uint256 _rewardPerSec
    ) {
        rewardToken = _rewardToken;
        rewardPerSec = _rewardPerSec;
        startTimestamp = block.timestamp;
        totalAllocPoint = 0;
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
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_account];
        
        IERC20 poolLpToken = IERC20(pool.lpToken);        
        
        poolLpToken.transferFrom(address(msg.sender), address(this), _amount);

        if (user.amount > 0) {
            _harvest(_pid, _account);            
        }

        user.amount += _amount;
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;
    }
 
    function withdraw(uint256 _pid, uint256 _amount) override external returns (uint256, uint256) {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount && user.amount > 0,  'withdraw: not good');
        
        _harvest(_pid, msg.sender);
        user.amount = user.amount - _amount;
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;

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

        for (uint256 i = 0; i < _pids.length; i++) {            
            PoolInfo storage pool = poolInfo[_pids[i]];
            UserInfo storage user = userInfo[_pids[i]][msg.sender];
            updatePool(_pids[i]);
            if (user.amount > 0)
                _harvest(_pids[i], msg.sender);
            user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;
        }
        
        return (0, amounts, additionalRewards); // return value is wrong
    }


    function safeWOMTransfer(address payable to, uint256 _amount) internal {
        IStandardTokenMock(rewardToken).mint(to, _amount);
    }

    function addPool(address lp, uint256 _allocpoint, address _rewarder) external returns (uint256) {
        PoolInfo memory newPool = PoolInfo(lp, _allocpoint, block.timestamp, 0, IMultiRewarder(_rewarder));
        poolInfo.push(newPool);
        uint256 poolId = poolInfo.length - 1;
        pidToPoolInfo[poolId] = newPool;        
        lpToPid[lp] = poolId;
        totalAllocPoint = totalAllocPoint + _allocpoint;
        return poolId;
    }

    function setPool(address lp, uint256 _allocpoint, IMultiRewarder _rewarder) external {
        require(lpToPid[lp] != 0);

        PoolInfo storage pool = pidToPoolInfo[lpToPid[lp]];
        pool.allocPoint = _allocpoint;
        pool.rewarder = _rewarder;
    }

    function pendingTokens(uint256 _pid, address _user) public override view
        returns (
            uint256 pendingRewards,
            IERC20[] memory bonusTokenAddresses,
            string[] memory bonusTokenSymbols,
            uint256[] memory pendingBonusRewards
        ) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = IERC20(pool.lpToken).balanceOf(address(this));
        
        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;
            uint256 rewards = (multiplier * accRewardPerShare * pool.allocPoint) /
            totalAllocPoint;
            accRewardPerShare = accRewardPerShare + (rewards * 1e12) / lpSupply;
        }

        pendingRewards = (user.amount * accRewardPerShare) / 1e12 - user.rewardDebt;

        // If it's a double reward farm, we return info about the bonus token
        if (address(pool.rewarder) != address(0)) {
            (bonusTokenAddresses, bonusTokenSymbols) = rewarderBonusTokenInfo(_pid);
            pendingBonusRewards = pool.rewarder.pendingTokens(_user);
        }
    }

    /// @notice Get bonus token info from the rewarder contract for a given pool, if it is a double reward farm
    /// @param _pid the pool id
    function rewarderBonusTokenInfo(uint256 _pid)
        public
        view
        returns (IERC20[] memory bonusTokenAddresses, string[] memory bonusTokenSymbols)
    {
        PoolInfo storage pool = poolInfo[_pid];
        if (address(pool.rewarder) == address(0)) {
            return (bonusTokenAddresses, bonusTokenSymbols);
        }

        bonusTokenAddresses = pool.rewarder.rewardTokens();
        uint256 len = bonusTokenAddresses.length;
        bonusTokenSymbols = new string[](len);
        for (uint256 i; i < len; ++i) {
            if (address(bonusTokenAddresses[i]) == address(0)) {
                bonusTokenSymbols[i] = 'BNB';
            } else {
                bonusTokenSymbols[i] = IERC20Metadata(address(bonusTokenAddresses[i])).symbol();
            }
        }
    }

    /// @notice Harvest MGP for an account
    function _harvest(uint256 _pid, address _account) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_account]; 
        // Harvest MGP
        uint256 pending = (user.amount * pool.accRewardPerShare) /
            1e12 -
            user.rewardDebt;
        IStandardTokenMock(rewardToken).mint(_account, pending);
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = IERC20(pool.lpToken).balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;
        uint256 mgpReward = (multiplier * rewardPerSec * pool.allocPoint) /
            totalAllocPoint;
        
        pool.accRewardPerShare = pool.accRewardPerShare + ((mgpReward * 1e12) / lpSupply);
        pool.lastRewardTimestamp = block.timestamp;
    }
}