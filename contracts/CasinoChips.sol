// File: contracts/CasinoChips.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CasinoChips is ERC20, Ownable {
    constructor() 
        ERC20("CasinoChips", "CHIPS")
        Ownable(msg.sender)  // <-- Pass the deployer as the owner
    {
        // Mint initial supply to deployer (the same "msg.sender" above)
        _mint(msg.sender, 1_000_000 * 10**18);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }
}
