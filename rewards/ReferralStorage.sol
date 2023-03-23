// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../interfaces/IReferralStorage.sol";
import "../interfaces/IVLMGP.sol";
import '../libraries/DSMath.sol';

contract ReferralStorage is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, IReferralStorage {
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    struct Tier {
        uint256 rewardPercentage; // in DENOMINATOR decimals
        // need to reserve some attribute spaces?
    }

    struct UserInfo {
        uint256 tier;
        uint256 rewardAmount; //  reward to be claimed
        uint256 factor;
        bytes32 myCode;
        bytes32 codeIUsed;
    }

    uint256 public constant DENOMINATOR = 10000;
    uint256 public BoostPoint;         // percenage in DENOMINATOR decimals
    uint256 public totalBoostFactor;
    uint256 public sharePercent; // percentage in DENOMINATOR decimals to share with referree

    address public vlMGP;
    IERC20 public MGP;
    address public masterMagpie;

    mapping (uint256 => Tier) public tiers;
    mapping (bytes32 => address) public override codeOwners;
    mapping (address => UserInfo) public userInfos; // link between user <> tier

    mapping (address => address) public myReferer;
    mapping (address => address[]) public myReferees;

    /* ============ Events ============ */

    event SetTraderReferralCode(address indexed account, bytes32 code);
    event SetTier(uint256 tierId, uint256 totalRebate);
    event SetReferrerTier(address referrer, uint256 tierId);
    event SetSharePercent(uint256 sharePercent);
    event RegisterCode(address indexed account, bytes32 code);
    event SetCodeOwner(address indexed account, address newAccount, bytes32 code);
    event ForceSetCodeOwner(bytes32 code, address newAccount);
    event RewardClaimed(address indexed account, uint256 amount);

    /* ============ Errors ============ */

    error OnlyMasterMagpie();
    error OnlyVlMGP();
    error InvalidCode();
    error CodeOccupied();
    error HasReferral();
    error InvalidPercentage();
    error Circled();

    /* ============ Constructor ============ */

    function __ReferralStorage_init(
        address _vlMGP,
        address _masterMagpie,
        uint256 _boostPoint,
        uint256 _sharePercent
    ) public initializer {
        __Ownable_init();
        vlMGP = _vlMGP;
        MGP = IVLMGP(_vlMGP).MGP();
        masterMagpie = _masterMagpie;
        BoostPoint = _boostPoint;
        sharePercent = _sharePercent;
    }

    /* ============ Modifiers ============ */

    modifier _onlyMasterMagpie() {
        if (msg.sender != masterMagpie)
            revert OnlyMasterMagpie();
        _;
    }

    modifier _onlyVlMGP() {
        if (msg.sender != vlMGP)
            revert OnlyVlMGP();
        _;
    }

    /* ============ External Getters ============ */

    function getMyRefererInfo(address _account) external override view returns (bytes32, address) {
        bytes32 code = userInfos[_account].codeIUsed;
        address referrer;
        if (code != bytes32(0)) {
            referrer = codeOwners[code];
        }
        return (code, referrer);
    }

    /* ============ External Functions ============ */

    function setReferer(address _referer) external {
        if (_referer == msg.sender) revert Circled();
        if (myReferer[msg.sender] != address(0)) revert HasReferral();

        myReferer[msg.sender] = _referer;
        myReferees[_referer].push(msg.sender);
    }

    function useCode(bytes32 _code) external {
        if (_code == bytes32(0)) revert InvalidCode();
        if (codeOwners[_code] != address(0)) revert CodeOccupied();
        if (codeOwners[_code] == msg.sender) revert Circled();
        if (myReferer[msg.sender] != address(0)) revert HasReferral();
        
        userInfos[msg.sender].codeIUsed = _code;
        myReferer[msg.sender] = codeOwners[_code];
        myReferees[codeOwners[_code]].push(msg.sender);
    }

    function registerCode(bytes32 _code) external {
        if (_code == bytes32(0)) revert InvalidCode();
        if (codeOwners[_code] != address(0)) revert CodeOccupied();

        codeOwners[_code] = msg.sender;
        userInfos[msg.sender].myCode = _code;
        emit RegisterCode(msg.sender, _code);
    }

    function claimReward() external {
        UserInfo storage userInfo = userInfos[msg.sender];

        MGP.safeTransfer(msg.sender, userInfo.rewardAmount);

        emit RewardClaimed(msg.sender, userInfo.rewardAmount);
        userInfo.rewardAmount = 0;
    }

    function boosted(address _user) external view returns(uint256) {
        return _calBoosted(_user);
    }

    function getMyReferees(address _account) external  view returns (address[] memory) {
       return myReferees[_account];
    }

    /* ============ Admin Functions ============ */

    // should be called from masterMagpie upon referee claiming reward
    function trigger(address _referee, uint256 _amount) external _onlyMasterMagpie {
        UserInfo storage refereeInfo = userInfos[_referee];
        address _referer = myReferer[_referee];

        if (_referer == address(0))
            return;

        UserInfo storage refererInfo = userInfos[_referer];
        uint256 tierId = userInfos[_referer].tier;
        uint256 basic = tiers[tierId].rewardPercentage;
        uint256 boostesd = _calBoosted(_referer);

        uint256 refererPercentage = (basic + boostesd) * (DENOMINATOR - sharePercent)  / DENOMINATOR;
        uint256 refereePercentage = (basic + boostesd) *  sharePercent / DENOMINATOR;

        refererInfo.rewardAmount += _amount * refererPercentage / DENOMINATOR;
        refereeInfo.rewardAmount += _amount * refereePercentage / DENOMINATOR;
    }

    function updateTotalFactor(address _account) external override _onlyVlMGP {
        UserInfo storage userInfo = userInfos[_account];
        if (userInfo.myCode == bytes32(0)) return; // user did not activate referral feature
        
        totalBoostFactor -= userInfo.factor;
        uint256 vlMGPLockedAmoubnt = IVLMGP(vlMGP).getUserTotalLocked(_account);
        userInfo.factor = DSMath.sqrt(vlMGPLockedAmoubnt);

        totalBoostFactor += userInfo.factor;
    }

    function forceSetCodeOwner(bytes32 _code, address _newAccount) external override onlyOwner {
        if (_code == bytes32(0)) revert InvalidCode();

        codeOwners[_code] = _newAccount;
        emit ForceSetCodeOwner(_code, _newAccount);
    }

    function setReferrerTier(address _account, uint256 _tierId) external override onlyOwner {
        UserInfo storage userInfo = userInfos[_account];
        userInfo.tier = _tierId;
        // userInfo.bonusFactor
    }

    function setTier(uint256 _tierId, uint256 _rewardPercentage) external override onlyOwner {
        if (_rewardPercentage > DENOMINATOR) revert InvalidPercentage();

        Tier memory tier = tiers[_tierId];
        tier.rewardPercentage = _rewardPercentage;
        tiers[_tierId] = tier;
        emit SetTier(_tierId, _rewardPercentage);
    }

    function setSharePercent(uint256 _sharePercent) external override onlyOwner {
        if (_sharePercent > DENOMINATOR) revert InvalidPercentage();

        sharePercent = _sharePercent;
        emit SetSharePercent(_sharePercent);
    }

    /* ============ Internal Functions ============ */

    // The boosted part is share among all vlMGP holders who created referral link.
    function _calBoosted(address _account) private view returns(uint256) {
        if (totalBoostFactor == 0) return 0;
        return BoostPoint * userInfos[_account].factor / totalBoostFactor;
    }

}
