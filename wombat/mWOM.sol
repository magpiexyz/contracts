// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

import "../interfaces/wombat/IWombatStaking.sol";
import "../interfaces/ISimpleHelper.sol";

/// @title mWOM
/// @author Magpie Team
/// @notice mWOM is a token minted when 1 wom is locked in Magpie
contract mWOM is Initializable, ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public wombatStaking;
    address public wom;
    address public helper;
    uint256 public totalConverted;
    uint256 public totalAccumulated;

    bool    public isWomUp;

    /* ============ Events ============ */

    event mWomMinted(address indexed user, uint256 amount);
    event HelperSet(address indexed _helper);
    event WombatStakingSet(address indexed _wombatStaking);
    event WomConverted(uint256 _womAmount, uint256 _veWomAmount);
    event WomUpSet(bool _isWomUp);

    /* ============ Errors ============ */

    error HelperNotSet();
    error WombatStakingNotSet();
    error OnlyWomUp();

    /* ============ Constructor ============ */

    function __mWom_init(address _wombatStaking, address _wom) public initializer {
        __ERC20_init("mWOM", "mWOM");
        __Ownable_init();
        wombatStaking = _wombatStaking;
        wom = _wom;
        totalConverted = 0;
        totalAccumulated = 0;

        isWomUp = true; // when deployed, it should be during Wom Up campaign.
    }

    /* ============ External Functions ============ */
    
    /// @notice deposit WOM in magpie finance and get mWOM at a 1:1 rate
    /// @param _amount the amount of WOM
    function convert(uint256 _amount) whenNotPaused external {
        _convert(_amount, false, true);
    }

    function convertAndStake(uint256 _amount) whenNotPaused external {
        _convert(_amount, true, true);
    }

    function deposit(uint256 _amount) whenNotPaused external {
        if(!isWomUp)
            revert OnlyWomUp();

        _convert(_amount, false, false);
    }

    /* ============ Internal Functions ============ */

    function _convert(uint256 _amount, bool _forStake, bool _doConvert) whenNotPaused nonReentrant internal {
        if (_doConvert) {
            if (wombatStaking == address(0))
                revert WombatStakingNotSet();
            IERC20(wom).safeTransferFrom(msg.sender, wombatStaking, _amount);
            _lockWom(_amount, false);

        } else {
            IERC20(wom).safeTransferFrom(msg.sender, address(this), _amount);
        }

        if(_forStake) {
            if (helper == address(0))
                revert HelperNotSet();
            _mint(address(this), _amount);
            IERC20(address(this)).safeApprove(helper, _amount);
            ISimpleHelper(helper).depositFor(_amount, address(msg.sender));
            IERC20(address(this)).safeApprove(helper, 0);
        } else {
            _mint(msg.sender, _amount);
        }

        totalConverted = totalConverted + _amount;
        emit mWomMinted(msg.sender, _amount);
    }

    function _lockWom(uint256 _amount, bool _needSend) internal {
        if (_needSend)
            IERC20(wom).safeTransfer(wombatStaking, _amount);

        uint256 mintedVeWomAmount = IWombatStaking(wombatStaking).convertWOM(_amount);
        totalAccumulated = totalAccumulated + mintedVeWomAmount;

        emit WomConverted(_amount, mintedVeWomAmount);
    }

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setHelper(address _helper) external onlyOwner {
        helper = _helper;

        emit HelperSet(_helper);
    }

    function setWombatStaking(address _wombatStaking) external onlyOwner {
        wombatStaking =_wombatStaking;

        emit WombatStakingSet(wombatStaking);
    }

    function setWomUp(bool _isWomUp) external onlyOwner {
        isWomUp = _isWomUp;

        emit WomUpSet(isWomUp);
    }

    function lockAllWom() external onlyOwner {
        uint256 allWom = IERC20(wom).balanceOf(address(this));
        _lockWom(allWom, true);
    }
}