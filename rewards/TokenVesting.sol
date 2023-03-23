pragma solidity ^0.8.0;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title PartnersVesting
 * @dev A token holder contract that can release its token balance gradually at different vesting points
 */
contract TokenVesting is Ownable {
    // The vesting schedule is time-based (i.e. using block timestamps as opposed to e.g. block numbers), and is
    // therefore sensitive to timestamp manipulation (which is something miners can do, to a certain degree). Therefore,
    // it is recommended to avoid using short time durations (less than a minute). Typical vesting schemes, with a
    // cliff period of a year and a duration of four years, are safe to use.
    // solhint-disable not-rely-on-time

    using SafeERC20 for IERC20;

    event TokensReleased(address token, address receiver, uint256 amount);

    // The token being vested
    IERC20 public _token;
    uint256 public DENOMINATOR = 10000;

    struct Beneficiary {
        address beneficiary;
        uint256 released;
        uint256 amount;
    }

    // beneficiary of tokens after they are released
    mapping(address => Beneficiary) private _beneficiaries;
    address[] private _beneficiaryList;

    uint256[] private _schedule;
    uint256[] private _percent;

    /**
     * @dev Creates a vesting contract that vests its balance of any ERC20 token to the
     * beneficiary, gradually in a linear fashion until start + duration. By then all
     * of the balance will have vested.
     * @param token ERC20 token which is being vested
     * @param receiver address of the beneficiary to whom vested tokens are transferred
     * @param amount Amount of tokens being vested
     * @param schedule array of the timestamps (as Unix time) at which point vesting starts
     * @param percent array of the percents which can be released at which vesting points
     */
    constructor (IERC20 token, address[] memory receiver, uint256[] memory amount, uint256[] memory schedule,
        uint256[] memory percent) {
        // require(receiver != address(0), "TokenVesting: beneficiary is the zero address");
        require(receiver.length == amount.length, "TokenVesting: Incorrect receiver mapping");

        require(schedule.length == percent.length, "TokenVesting: Incorrect release schedule");
        require(schedule.length <= 255, "TokenVesting: Incorrect schedule length");

        _token = token;
        _schedule = schedule;
        _percent = percent;

        for(uint i = 0; i < receiver.length; i++) {
            require(receiver[i] != address(0), "TokenVesting: beneficiary is the zero address");
            Beneficiary memory benef = Beneficiary(receiver[i], 0, amount[i]);
            _beneficiaries[receiver[i]] = benef;
            _beneficiaryList.push(receiver[i]);
        }
    }

    /**
     * @return the beneficiary of the tokens.
     */
    function beneficiary() public view returns (address[] memory) {
        return _beneficiaryList;
    }
    /**
     * @dev Throws if called by any account other than the beneficiary.
     */
    modifier onlyBeneficiary() {
        require(isBeneficiary(), "caller is not the beneficiary");
        _;
    }
    /**
     * @dev Returns true if the caller is the current beneficiary.
     */
    function isBeneficiary() private view returns (bool) {
        return _beneficiaries[_msgSender()].beneficiary != address(0);
    }

    /**
     * @return the vesting token address.
     */
    function tokenAddress() public view returns (IERC20) {
        return _token;
    }
    /**
     * @return the schedule and percent arrays.
     */
    function getScheduleAndPercent() public view returns (uint256[] memory, uint256[] memory) {
	return (_schedule, _percent);
    }

    /**
     * @return the start time of the token vesting.
     */
    function totalAmount(address receiver) public view returns (uint256) {
        return _beneficiaries[receiver].amount;
    }

    /**
     * @return the amount of the token released.
     */
    function released(address receiver) public view returns (uint256) {
        return _beneficiaries[receiver].released;
    }

    /**
     * @return the vested amount of the token for a particular timestamp.
     */
    function vestedAmount(uint256 ts, address receiver) public view returns (uint256) {
        int256 unreleasedIdx = _releasableIdx(ts);
        if(unreleasedIdx < 0) return 0;
        
        uint256 percentSum = 0;
        for (uint256 i = 0; i <= uint256(unreleasedIdx); i++) {
            percentSum += _percent[i];
        }

        return _beneficiaries[receiver].amount * percentSum / DENOMINATOR;
    }

    function getClaimable(address receiver) public view returns (uint256) {
        uint256 vestedAmountNow = vestedAmount(block.timestamp, receiver);
        return vestedAmountNow - _beneficiaries[receiver].released;
    }

    /**
     * @notice Transfers vested tokens to beneficiary.
     */
    function release() public onlyBeneficiary {
        uint256 claimable = getClaimable(_msgSender());
        if (claimable > 0) {
            Beneficiary storage _beneficiary = _beneficiaries[_msgSender()];
            _beneficiary.released += claimable;
            _token.safeTransfer(_msgSender(), claimable);
        }

        emit TokensReleased(address(_token), msg.sender, claimable);
    }

    /**
     * @dev Calculates the index that has already vested but hasn't been released yet.
     */
    function _releasableIdx(uint256 ts) private view returns (int256) {
        for (int256 i = int256(_schedule.length) - 1; i >= 0; i--) {
            if (ts >= _schedule[uint256(i)]) {
                return i;
            }
        }

        return -1;
    }

}