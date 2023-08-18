// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    constructor() ERC20("DecentralisedStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        require(_amount != 0, "Amount must be higher than 0");
        uint256 balance = balanceOf(msg.sender);
        require(balance >= _amount, "Insufficient amount");
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        require(_to != address(0), "Address 0");
        require(_amount != 0, "Amount must be higher than 0");

        _mint(_to, _amount);
        return true;
    }
}
