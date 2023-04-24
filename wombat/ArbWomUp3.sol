// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/ILocker.sol";
import "../interfaces/IConverter.sol";
import "../interfaces/wombat/IMWom.sol";
import "../interfaces/traderjoeV2/ILBQuoter.sol";
import "../interfaces/traderjoeV2/ILBRouter.sol";

/// @title ArbWomUp
/// @author Magpie Team, an wom up program to with amount of lock mWom
/// @notice WOM will be transfered to admin address and later bridged over ther, for the arbitrum Airdrop

contract ArbWomUp3 is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public wom; // 18 decimals
    address public mWom;
    address public arb; // 18 decimals
    address public mgp;
    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    ILocker public vlMGP;
    ILocker public mWomSV;

    address public smartWomConvert;
    
    uint256 public constant DENOMINATOR = 10000;
    uint256 public tierLength;
    uint256[] public rewardMultiplier;
    uint256[] public rewardTier;

    mapping(address => uint) public bracketRewarded;   // not in use

    uint256 public bullBonusRatio;  // should be divided by DENOMINATOR
    address public immutable traderjoev2Quoter = 0x3660268Ed43583a2cdd09e3fC7079ff07DBD4Caa;
    address public immutable traderjoev2Router = 0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30;
        // 0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30
    /* ============ Events ============ */

    event ARBRewarded(address indexed _beneficiary, uint256 _amount);
    event VLMGPRewarded(address indexed _beneficiary, uint256 _buybackAmount, uint256 _vlMGPAmount);
    event WomDeposited(address indexed _account, uint256 _amount, uint256 _mode);

    /* ============ Errors ============ */

    error InvalidAmount();
    error LengthMissmatch();
    error AddressZero();
    error ZeroBalance();

    /* ============ Constructor ============ */

    function __arbWomUp_init(address _wom, address _mWom, address _mWomSV, address _arb, address _mgp, address _vlMGP, address _smartConvert) public initializer {
        wom = _wom;
        mWom = _mWom;
        vlMGP = ILocker(_vlMGP);
        arb = _arb;
        mWomSV = ILocker(_mWomSV);
        mgp = _mgp;
        smartWomConvert = _smartConvert;
        __Ownable_init();
    }

    /* ============ Modifier ============ */

    modifier _checkAmount(uint256 _amt) {
        if (_amt == 0) revert InvalidAmount();
        _;
    }

    /* ============ External Functions ============ */

    function incentiveDeposit(
        uint256 _amount, uint256 _convertRatio, bool _bullMode, uint256 _mode // 1 stake, 2 lock
    ) external _checkAmount(_amount) whenNotPaused nonReentrant {
        if (_amount == 0) return;
        
        uint256 rewardToSend = this.getRewardAmount(_amount, msg.sender, _mode == 2);

        // giving out 50% more bonus
        if (_mode == 2)
            rewardToSend = rewardToSend * 2;

        _deposit(msg.sender, _convertRatio, _amount, _mode);

        IERC20(mgp).safeApprove(address(vlMGP), rewardToSend);
        vlMGP.lockFor(rewardToSend, msg.sender);
        // _bullMGP(rewardToSend, _minMGPRec, msg.sender);
        emit VLMGPRewarded(msg.sender, 0, rewardToSend);
    }

    function getRewardAmount(uint256 _amountToConvert, address _account, bool _lock) external view returns (uint256) {
        uint256 mgpReward = 0;

        if (!_lock) {
            mgpReward = _amountToConvert * rewardMultiplier[getUserTier(_account)] / DENOMINATOR;
        } else {
            uint256 accumulated = _amountToConvert + mWomSV.getUserTotalLocked(_account);
            uint256 rewardAmount = 0;
            uint256 i = 1;

            while (i < rewardTier.length && accumulated > rewardTier[i]) {
                rewardAmount +=
                    (rewardTier[i] - rewardTier[i - 1]) *
                    rewardMultiplier[i - 1];
                i++;
            }
            rewardAmount += (accumulated - rewardTier[i - 1]) * rewardMultiplier[i - 1];
            mgpReward = (rewardAmount / DENOMINATOR) - calDoubledCounted(_account);
        }

        uint256 mgpleft = IERC20(mgp).balanceOf(address(this));
        return mgpReward > mgpleft ? mgpleft : mgpReward;
    }

    function calDoubledCounted(address _account) public view returns (uint256) {
        uint256 accuIn1 = mWomSV.getUserTotalLocked(_account);
        uint256 rewardAmount = 0;
        uint256 i = 1;
        while (i < rewardTier.length && accuIn1 > rewardTier[i]) {
            rewardAmount +=
                (rewardTier[i] - rewardTier[i - 1]) *
                rewardMultiplier[i - 1];
            i++;
        }

        rewardAmount += (accuIn1 - rewardTier[i - 1]) * rewardMultiplier[i - 1];
        return rewardAmount / DENOMINATOR;
    }    

    function getUserTier(address _account) public view returns (uint256) {
        uint256 userMWOMSVBal = mWomSV.getUserTotalLocked(_account);
        for (uint256 i = tierLength - 1; i >= 1; i--) {
            if (userMWOMSVBal >= rewardTier[i]) {
                return i;
            }
        }

        return 0;
    }

    function amountToNextTier(address _account) external view returns (uint256) {
        uint256 userTier = this.getUserTier(_account);
        if (userTier == tierLength - 1) return 0;

        return rewardTier[userTier + 1] - mWomSV.getUserTotalLocked(_account);
    }

    function quoteMGP(uint128 _arbAmount)  external view returns (uint256) {
        address[] memory path = new address[](3);
        path[0] = arb;
        path[1] = weth;
        path[2] = mgp;
        return (ILBQuoter(traderjoev2Quoter).findBestPathFromAmountIn(path, _arbAmount)).amounts[2];
    }

    function quoteBullMGP(uint128 _convertAmount, address _account, bool _lock) external view returns (uint256 noBull, uint256 withBull) {
        uint256 rewardAmount = this.getRewardAmount(_convertAmount, _account, _lock);
        uint256 mgpBuyBack = this.quoteMGP(uint128(rewardAmount));
        return (mgpBuyBack, mgpBuyBack * (DENOMINATOR + bullBonusRatio) / DENOMINATOR);
    }

    /* ============ Internal Functions ============ */

    function _deposit(address _account, uint256 _convertRatio, uint256 _amount, uint256 _mode) internal {
        IERC20(wom).safeTransferFrom(_account, address(this), _amount);

        if (_mode == 1) {
            IERC20(wom).safeApprove(mWom, _amount);
            IMWom(mWom).deposit(_amount);            
            IERC20(mWom).safeApprove(smartWomConvert, _amount);
            IConverter(smartWomConvert).depositFor(_amount, _account);

        } else if (_mode == 2) {
            uint256 toDeposit = _amount / 2;
            uint256 toSwap = _amount - toDeposit;

            // 50% goes to deposit
            IERC20(wom).safeApprove(mWom, toDeposit);
            IMWom(mWom).deposit(toDeposit); 

            // 50% smart smart convert
            IERC20(wom).safeApprove(smartWomConvert, toSwap);
            IConverter(smartWomConvert).convert(toSwap, _convertRatio, 0, 0);

            uint256 mWomBal = IERC20(mWom).balanceOf(address(this));
            IERC20(mWom).safeApprove(address(mWomSV), mWomBal);
            ILocker(mWomSV).lockFor(mWomBal, _account);

        } else {
            IERC20(wom).safeApprove(mWom, _amount);
            IMWom(mWom).deposit(_amount);               
            IERC20(mWom).safeTransfer(_account, _amount);
        }
        
        emit WomDeposited(_account, _amount, _mode);
    }

    function _bullMGP(uint256 _arbAmount, uint256 _minRec, address _account) internal {
        IERC20(arb).safeApprove(address(traderjoev2Router), _arbAmount);
        
        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = IERC20(arb);
        tokens[1] = IERC20(weth);
        tokens[2] = IERC20(mgp);

        uint256[] memory pairBinSteps = new uint256[](2);
        pairBinSteps[0] = 20; pairBinSteps[1] = 50;

        ILBRouter.Version[] memory versions = new ILBRouter.Version[](2);
        versions[0] = ILBRouter.Version.V2; versions[1] = ILBRouter.Version.V2;

        ILBRouter.Path memory path;
        path.pairBinSteps = pairBinSteps;
        path.tokenPath = tokens;
        path.versions = versions;

        uint256 receivedMGP = ILBRouter(traderjoev2Router).swapExactTokensForTokens(
            _arbAmount,
            _minRec,
            path,
            address(this),
            block.timestamp
        );

        uint256 mgpAmountToLcok = receivedMGP * (DENOMINATOR + bullBonusRatio) / DENOMINATOR; // get bull mode bonus
        IERC20(mgp).approve(address(vlMGP), mgpAmountToLcok);
        vlMGP.lockFor(mgpAmountToLcok, _account);

        emit VLMGPRewarded(_account, _arbAmount, mgpAmountToLcok);
    }

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setup(address _smartWomConvert) external onlyOwner {
        smartWomConvert = _smartWomConvert;
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

    function resetMultiplier() external onlyOwner {
        uint256 len = rewardMultiplier.length;
        for (uint8 i = 0; i < len; ++i) {
            rewardMultiplier.pop();
            rewardTier.pop();
        }

        tierLength = 0;
    }

    function adminWithdrawReward() external onlyOwner {
        uint256 arbBalance = IERC20(arb).balanceOf(address(this));
        uint256 mgpBalance = IERC20(mgp).balanceOf(address(this));
        IERC20(arb).transfer(owner(), arbBalance);
        IERC20(mgp).transfer(owner(), mgpBalance);
    }
}
