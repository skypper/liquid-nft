// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CollectionToken} from "./CollectionToken.sol";

/**
 * Holds tokens in escrow for users to later withdraw
 */
abstract contract TokenEscrow {
    // Emitted when a new deposit is made
    event Deposited(address indexed token, uint256 amount, address receiver);

    // Emitted when a withdrawal is made
    event Withdrawn(address indexed caller, address indexed token, uint256 amount, address indexed recipient);

    error InsufficientBalance();

    // Stores the deposited balances of the collection tokens for each user
    mapping(address user => mapping(address collection => uint256 amount)) public balances;

    /**
     * Internal function used to manage the accounting for collection tokens (mostly fee accrual)
     */
    function _deposit(address token, uint256 amount, address receiver) internal {
        balances[receiver][token] += amount;

        emit Deposited(token, amount, receiver);
    }

    /**
     * Enables a user to withdraw their allocated collection tokens
     */
    function withdraw(address token, uint256 amount, address recipient) public {
        require(balances[msg.sender][token] >= amount, InsufficientBalance());
        balances[msg.sender][token] -= amount;
        CollectionToken(token).transfer(recipient, amount);

        emit Withdrawn(msg.sender, token, amount, recipient);
    }
}
