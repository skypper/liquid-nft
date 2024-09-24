// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CollectionToken} from "./CollectionToken.sol";

abstract contract TokenEscrow {
    error InsufficientBalance();

    mapping(address user => mapping(address collection => uint256 amount)) public balances;

    function _deposit(address token, uint256 amount, address receiver) internal {
        balances[receiver][token] += amount;
    }
    
    function withdraw(address token, uint256 amount, address recipient) public {
        require(balances[msg.sender][token] >= amount, InsufficientBalance());
        balances[msg.sender][token] -= amount;
        CollectionToken(token).transfer(recipient, amount);
    }
}
