pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// mock class using BasicToken
contract WombatAssetMock is ERC20 {
    uint8 myDecimals;
    string myName;
    string mySymbol;

    uint120 public cash;
    uint120 public liability;

    constructor(
        address _initialAccount,
        uint256 _initialBalance,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) public ERC20("mock token", "mock token") {
        _mint(_initialAccount, _initialBalance);
        myDecimals = _decimals;
        myName = _name;
        mySymbol = _symbol;
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

    function addCash(uint256 amount) external {
        cash += uint120(amount);
    }

    function removeCash(uint256 amount) external {
        require(cash >= amount, 'Wombat: INSUFFICIENT_CASH');
        cash -= uint120(amount);
    }

    function addLiability(uint256 amount) external {
        liability += uint120(amount);
    }

    function removeLiability(uint256 amount) external {
        require(liability >= amount, 'Wombat: INSUFFICIENT_LIABILITY');
        liability -= uint120(amount);
    }
}
