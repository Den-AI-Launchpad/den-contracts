// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract DenToken is ERC20 {
    constructor() ERC20("Den", "DEN") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
