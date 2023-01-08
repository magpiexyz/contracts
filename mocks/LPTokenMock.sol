pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// mock class using BasicToken
contract LPTokenMock is ERC20 {
    uint8 myDecimals;
    string myName;
    string mySymbol;
    address myToken0;
    address myToken1;

    constructor(
        address _initialAccount,
        uint256 _initialBalance,
        string memory _name,
        string memory _symbol,
        address _token0,
        address _token1,
        uint8 _decimals
    ) public ERC20("mock token", "mock token") {
        _mint(_initialAccount, _initialBalance);
        myDecimals = _decimals;
        myName = _name;
        mySymbol = _symbol;
        myToken0 = _token0;
        myToken1 = _token1;
    }

    function name() public view virtual override returns (string memory) {
        return myName;
    }

    function symbol() public view virtual override returns (string memory) {
        return mySymbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return myDecimals;
    }

    function mint(address _to, uint256 _amount) external returns (uint256) {
        _mint(_to, _amount);
        return _amount;
    }

    function burn(address _from, uint256 _amount) external returns (uint256) {
        _burn(_from, _amount);
        return _amount;
    }

    function token0() external view returns (address) {
        return myToken0;
    }
    
    function token1() external view returns (address) {
        return myToken1;
    }

 


}
