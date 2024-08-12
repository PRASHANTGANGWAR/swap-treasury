// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ErrorMessages {
    string internal constant E1 = "Initial owner cannot be zero address";
    string internal constant E2 = "Only signer and owner is allowed";
    string internal constant E3 = "Not authorized";
    string internal constant E4 = "Not whitelisted";
    string internal constant E5 = "Only USDT is accepted for liquidity";
    string internal constant E6 = "Only USDT withdrawals are allowed";
    string internal constant E7 =
        "Cannot withdraw more than the balance or amount is zero";
    string internal constant E8 =  "Contract is out of balance, try later";
    string internal constant E9 =  "Withdrawal on hold, please wait.";
    string internal constant E10 = "Amount must be greater than zero";
    string internal constant E11 = "Contract balance exceeds total liquidity";
    string internal constant E12 = "Invalid address";
    string internal constant E13 = "Invalid nonce";
    string internal constant E14 = "Invalid user address";
    string internal constant E15 = "Insufficient balance for swap";
    string internal constant E16 = "Insufficient funds";
    string internal constant E17 = "Insufficient allowance or balance";
    string internal constant E18 = "Only owner, admin and sub admin can call this function";
    string internal constant E19 = "Admin cannot be zero address";
    string internal constant E20 = "Denominator cannot be zero";
    string internal constant E21 = "Same wallet address";
    string internal constant E22 = "sub admin cannot be zero address";
    string internal constant E23 = "sign manager address cannot be zero address";
    string internal constant E24 = "Investor cannot be zero address";
}
