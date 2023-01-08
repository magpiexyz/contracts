pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import "../../libraries/SignedSafeMath.sol";
import "../../interfaces/wombat/IMasterWombat.sol";
import "../interfaces/IWombatAssetMock.sol";

contract WombatPoolMock {
    using SafeERC20 for IERC20;
    using SignedSafeMath for int256;
 
    mapping(address => address) public depositTokenToLp;
    mapping(address => address) public lpToDepositToken;

    mapping(address => uint256) public depositBalance;

    uint256 public constant ampFactor = 2000000000000000;

    IMasterWombat public masterWombat;

    constructor(address _masterWombat) {
        masterWombat = IMasterWombat(_masterWombat);
    }

    /**
     * @notice Deposits amount of tokens into pool ensuring deadline
     * @dev Asset needs to be created and added to pool before any operation. This function assumes tax free token.
     * @param token The token address to be deposited
     * @param amount The amount to be deposited
     * @param to The user accountable for deposit, receiving the Wombat assets (lp)
     * @param deadline The deadline to be respected
     * @return liquidity Total asset liquidity minted
     */
    function deposit(
        address token,
        uint256 amount,
        uint256 minimumLiquidity,
        address to,
        uint256 deadline,
        bool shouldStake
    ) external returns (uint256 liquidity) {
        IERC20(token).safeTransferFrom(address(msg.sender), address(this), amount);

        IWombatAssetMock lpToken = IWombatAssetMock(depositTokenToLp[token]);

        depositBalance[msg.sender] += amount;

        uint256 liabilityToMint = exactDepositLiquidityInEquilImpl(
            int256(amount),
            int256(uint256(lpToken.cash())),
            int256(uint256(lpToken.liability())),
            int256(ampFactor)
        ).toUint256();

        if (liabilityToMint < amount) {
            liabilityToMint = amount;
        }

        uint256 lpTokenToMint = (
            lpToken.liability() == 0
                ? liabilityToMint
                : (liabilityToMint * lpToken.totalSupply()) / lpToken.liability()
        );
        
        if (!shouldStake) {
            lpToken.mint(to, lpTokenToMint);
        } else {
            lpToken.mint(address(this), lpTokenToMint);

            lpToken.approve(address(masterWombat), lpTokenToMint);

            uint256 pid = masterWombat.getAssetPid(address(lpToken)); 
            masterWombat.depositFor(pid, lpTokenToMint, to);
        }

        lpToken.addCash(amount);
        lpToken.addLiability(liabilityToMint);

        return amount;
    }

    /**
     * @notice Withdraws liquidity amount of asset to `to` address ensuring minimum amount required
     * @param token The token to be withdrawn
     * @param liquidity The liquidity to be withdrawn
     * @param minimumAmount The minimum amount that will be accepted by user
     * @param to The user receiving the withdrawal
     * @param deadline The deadline to be respected
     * @return amount The total amount withdrawn
     */
    function withdraw(
        address token,
        uint256 liquidity,
        uint256 minimumAmount,
        address to,
        uint256 deadline
    ) external returns (uint256 amount) {
        address lpToken = depositTokenToLp[token];

        IERC20(lpToken).safeTransferFrom(address(msg.sender), address(lpToken), liquidity);
        IERC20(token).safeTransfer(to, liquidity);

        IWombatAssetMock lpAsset = IWombatAssetMock(depositTokenToLp[token]);

        uint256 liabilityToBurn;
        // (amount, liabilityToBurn, ) = _withdrawFrom(asset, liquidity);
        liabilityToBurn = (lpAsset.liability() * liquidity) / lpAsset.totalSupply();

        amount = withdrawalAmountInEquilImpl(
            -int256(liabilityToBurn),
            int256(uint256(lpAsset.cash())),
            int256(uint256(lpAsset.liability())),
            int256(ampFactor)
        ).toUint256();

        if (liabilityToBurn >= amount) {
            // fee = liabilityToBurn - amount;
        } else {
            // rounding error
            amount = liabilityToBurn;
        }

        lpAsset.burn(address(lpAsset), liquidity);
        lpAsset.removeCash(amount);
        lpAsset.removeLiability(liabilityToBurn);

    }

    function addPool(address depositToken, address lp) external {
        depositTokenToLp[depositToken] = lp;
        lpToDepositToken[lp] = depositToken;
    }

    function quotePotentialWithdraw(address token, uint256 amount) external pure returns (uint256 amounts, uint256 fee) {
        return (amount, 0);
    }

    function quotePotentialDeposit(
        address token, 
        uint256 amount
    ) external pure returns (uint256 liquidity, uint256 reward) {
        return (amount, 0);
    }    

    function exactDepositLiquidityInEquilImpl(
        int256 D_i,
        int256 A_i,
        int256 L_i,
        int256 A
    ) internal pure returns (int256 liquidity) {
        if (L_i == 0) {
            return D_i;
        }

        int256 WAD_I = 10**18;
        int256 r_i = A_i.wdiv(L_i);
        int256 k = D_i + A_i;
        int256 b = k.wmul(WAD_I - A) + 2 * A.wmul(L_i);
        int256 c = k.wmul(A_i - (A * L_i) / r_i) - k.wmul(k) + A.wmul(L_i).wmul(L_i);
        int256 l = b * b - 4 * A * c;
        return (-b + l.sqrt(b)).wdiv(A) / 2;
    }

    function withdrawalAmountInEquilImpl(
        int256 delta_i,
        int256 A_i,
        int256 L_i,
        int256 A
    ) internal pure returns (int256 amount) {
        int256 WAD_I = 10**18;
        int256 L_i_ = L_i + delta_i;
        int256 r_i = A_i.wdiv(L_i);
        int256 rho = L_i.wmul(r_i - A.wdiv(r_i));
        int256 beta = (rho + delta_i.wmul(WAD_I - A)) / 2;
        int256 A_i_ = beta + (beta * beta + A.wmul(L_i_ * L_i_)).sqrt(beta);
        amount = A_i - A_i_;
    }
}