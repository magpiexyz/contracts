// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../interfaces/pancake/IPancakeRouter02.sol";
import "../interfaces/pancake/IPancakePair.sol";
import "../interfaces/IWBNB.sol";

contract BNBZapper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ========== CONSTANT VARIABLES ========== */

    uint256 public constant DENOMINATOR = 10000;

    /* ============ State Variables ============ */

    mapping(address => address) public routePairAddresses;
    address public WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    IPancakeRouter02 public ROUTER = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    /* ========== Constructor ========== */

    constructor() {}

    /* ============ External Getters ============ */
    
    function previewAmount(address _from, uint256 amount) public view returns (uint256) {
        address[] memory path = _findRouteToBnb(_from);
        uint256[] memory amounts = ROUTER.getAmountsOut(amount, path);
        return amounts[amounts.length - 1];
    }

    function previewTotalAmount(IERC20[][] calldata inTokens, uint256[][] calldata amounts)
        external
        view
        returns (uint256 bnbAmount)
    {
        uint256 length = inTokens.length;
        for (uint256 i; i < length; i++) {
            for (uint256 j; j < inTokens[i].length; j++) {
                if (address(inTokens[i][j]) != address(0)) {
                    bnbAmount += previewAmount(address(inTokens[i][j]), amounts[i][j]);
                }
            }
        }
    }

    /* ============ External Functions ============ */

    function zapInToken(
        address fromToken,
        uint256 amount,
        uint256 minRec,
        address receiver
    ) external nonReentrant returns (uint256 bnbAmount) {
        if (amount > 0) {
            IERC20(fromToken).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(fromToken).safeApprove(address(ROUTER), amount);
            bnbAmount = _swapTokenForBNB(fromToken, amount, minRec, receiver);
        }
    }

    /* ============ Internal Functions ============ */
    function _findRouteToBnb(address token) private view returns (address[] memory) {
        address[] memory path;
        if (routePairAddresses[token] != address(0)) {
            path = new address[](3);
            path[0] = token;
            path[1] = routePairAddresses[token];
            path[2] = WBNB;
        } else {
            path = new address[](2);
            path[0] = token;
            path[1] = WBNB;
        }
        return path;
    }

    function _swapTokenForBNB (
        address token,
        uint256 amount,
        uint256 minRec,
        address receiver
    ) private returns (uint256) {
        address[] memory path = _findRouteToBnb(token);
        uint256[] memory amounts = ROUTER.swapExactTokensForETH(
            amount,
            minRec,
            path,
            receiver,
            block.timestamp
        );
        return amounts[amounts.length - 1];
    }

    /* ============ Admin Functions ============ */

    function setRoutePairAddress(address asset, address route) external onlyOwner {
        routePairAddresses[asset] = route;
    }

    function setRouter(address router) external onlyOwner {
        ROUTER = IPancakeRouter02(router);
    }

    function setWBNB(address _WBNB) external onlyOwner {
        WBNB = _WBNB;
    }

    function withdraw(address token) external onlyOwner {
        IERC20(token).safeTransfer(owner(), IERC20(token).balanceOf(address(this)));
    }
}