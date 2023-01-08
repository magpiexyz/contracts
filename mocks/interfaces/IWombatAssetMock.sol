pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWombatAssetMock is IERC20 {

    function mint(address _to, uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;

    function cash() external view returns (uint120);

    function liability() external view returns (uint120);

    function addCash(uint256 amount) external;

    function removeCash(uint256 amount) external;

    function addLiability(uint256 amount) external;

    function removeLiability(uint256 amount) external;
}