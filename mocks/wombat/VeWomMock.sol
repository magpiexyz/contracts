pragma solidity ^0.8.0;

import "../../interfaces/wombat/IVeWom.sol";
import "../StandardTokenMock.sol";
import "../../libraries/LogExpMath.sol";
import "../../libraries/DSMath.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


contract VeWomMock is IVeWom {
    using SafeERC20 for IERC20;
    using DSMath for uint256;

    IERC20 public WOM;

    uint256 constant WAD = 1e18;
    uint32 public maxLockDays;
    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => UserInfo) internal users;

    constructor(address _wom) {
        WOM = IERC20(_wom);
        maxLockDays = 1461;    
    }

    function burn(uint256 slot) external override {
        uint256 length = users[msg.sender].breedings.length;
        require(slot < length, 'wut?');

        Breeding memory breeding = users[msg.sender].breedings[slot];
        require(uint256(breeding.unlockTime) <= block.timestamp, 'not yet meh');

        // remove slot
        if (slot != length - 1) {
            users[msg.sender].breedings[slot] = users[msg.sender].breedings[length - 1];
        }
        users[msg.sender].breedings.pop();

        WOM.transfer(msg.sender, breeding.womAmount);

        // event Burn(address indexed user, uint256 indexed amount) is emitted
        balanceOf[msg.sender] -= breeding.veWomAmount;
        totalSupply -= breeding.veWomAmount;
    }

    function mint(uint256 amount, uint256 lockDays) external override returns (uint256) {
        uint256 unlockTime = block.timestamp + 86400 * lockDays; // seconds in a day = 86400
        
        uint256 veWomAmount = this.expectedVeWomAmount(amount, lockDays);

        users[msg.sender].breedings.push(Breeding(uint48(unlockTime), uint104(amount), uint104(veWomAmount)));

        WOM.safeTransferFrom(msg.sender, address(this), amount);
        
        balanceOf[msg.sender] += veWomAmount;
        totalSupply += veWomAmount;

        return veWomAmount;
    }

    function isUser(address _addr) external override view returns (bool) {
         return balanceOf[_addr] > 0;
    }

    // function getUserInfo(address addr) external view returns (UserInfo memory) {
    //     return users[addr];
    // }

    function expectedVeWomAmount(uint256 amount, uint256 lockDays) external pure returns (uint256) {
        // veWOM = 0.026 * lockDays^0.5
        return amount.wmul(26162237992630200).wmul(LogExpMath.pow(lockDays * WAD, 50e16));
    }   

    function getStakedWom(address addr) external view returns(uint256) {
        uint256 totalStaked = 0;
        UserInfo memory userInfo = users[addr];
        for (uint256 i = 0; i < userInfo.breedings.length; i++) {
            totalStaked += userInfo.breedings[i].womAmount;
        }

        return totalStaked;
    }

    function getUserInfo(address addr) external override view returns(Breeding[] memory) {
        return users[addr].breedings;
    }

}
