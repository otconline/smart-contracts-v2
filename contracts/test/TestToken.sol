import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract TestToken is ERC20("TEST", "TEST") {
    constructor(){
        _mint(msg.sender, 1000000000000000000000);
    }
}