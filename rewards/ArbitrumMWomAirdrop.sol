// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { ReentrancyGuard } from '@openzeppelin/contracts/security/ReentrancyGuard.sol';


import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "../interfaces/ISimpleHelper.sol";
import "../interfaces/ILocker.sol";

contract ArbitrumMWomAirdrop is Ownable, Pausable, ReentrancyGuard {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    bytes32 public totalRewardMerkleRoot;
    uint256 public startVestingTime;
    uint256 public vestingPeriodCount;
    uint256 public intervals;

    mapping(address => uint256) private claimedAmount;

    IERC20 public reward;
    ISimpleHelper public helper;
    ILocker public locker;

    /* ============ Events ============ */

    event ClaimEvent(address account, uint256 amount, bool isStake, bool isLock);
    event HelperUpdated(address _newHelper, address _oldHelper);
    event LockerUpdated(address _newLocker, address _oldLocker);

    /* ============ Constructor ============ */

    constructor(IERC20 _reward, address _helper, address _locker,  uint256 _startVestingTime, bytes32 _totalRewardMerkleRoot) {
        reward = _reward;
        totalRewardMerkleRoot = _totalRewardMerkleRoot;
        startVestingTime = _startVestingTime;
        helper = ISimpleHelper(_helper);
        locker = ILocker(_locker);
    }

    /* ============ External Getters ============ */

    function getClaimed(address account) public view returns (uint256) {
        return claimedAmount[account];
    }

    function getClaimable(address account, uint256 totalAmount, bytes32[] calldata merkleProof) public view returns (uint256) {
        if (block.timestamp < startVestingTime) {
            return 0;
        }
        
        if (!verifyProof(account, totalAmount, merkleProof)) {
            return 0;
        }

        uint256 claimable =  _getClaimable(account, totalAmount);
        return claimable;
    }

    /* ============ External Functions ============ */

    function verifyProof(address account, uint256 amount,  bytes32[] calldata merkleProof) public view returns (bool) {
         bytes32 node = keccak256(abi.encodePacked(account, amount));
         return MerkleProof.verify(
                merkleProof,
                totalRewardMerkleRoot,
                node
        );
    }

    function claim(
        uint256 totalAmount,
        bytes32[] calldata merkleProof,
        bool isStake,
        bool isLock
    ) external whenNotPaused nonReentrant {
        require(block.timestamp >= startVestingTime, "ArbitrumMWomAirdrop: Drop dose not start.");
        // isStake & isLock cannot be true at the same time
        require(!(isStake && isLock), "ArbitrumMWomAirdrop: Operation error.");
        //Verify the merkle proof.
        require(verifyProof(msg.sender, totalAmount, merkleProof), "ArbitrumMWomAirdrop: Invalid proof.");

        uint256 claimable = _getClaimable(msg.sender, totalAmount);
        require(claimable > 0, "ArbitrumMWomAirdrop: Insufficient claimable.");

        // Mark it claimed and send the token.
        if (isStake) {
            reward.safeApprove(address(helper), claimable);
            helper.depositFor(claimable, address(msg.sender));
        } else if (isLock) {
            reward.safeApprove(address(locker), claimable);
            locker.lockFor(claimable, address(msg.sender));
        } else {
            reward.safeTransfer(msg.sender, claimable);
        }

        uint256 userClaimedAmount = claimedAmount[msg.sender];
        claimedAmount[msg.sender] = userClaimedAmount + claimable;
        emit ClaimEvent(msg.sender, claimable, isStake, isLock);
    }

    /* ============ Internal Functions ============ */

    function _getClaimable(address account, uint256 totalAmount) internal view returns (uint256) {
        uint256 claimed = getClaimed(account);
        if (claimed >= totalAmount) {
            return 0;
        }

        uint256 vested = totalAmount;
        if (vested > totalAmount) {
            return totalAmount - claimed;
        }

        return vested - claimed;
    }

    /* ============ Admin functions ============ */

    function setHelper(address _newHelper) external onlyOwner
    {
        address oldHelper = address(helper);
        helper = ISimpleHelper(_newHelper);
        emit HelperUpdated(address(helper), oldHelper);
    }

    function setLocker(address _newLocker) external onlyOwner
    {
        address oldLocker = address(locker);
        locker = ILocker(_newLocker);
        emit LockerUpdated(address(locker), oldLocker);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw() external onlyOwner whenPaused {
        reward.safeTransfer(owner(), reward.balanceOf((address(this))));
    }
}
