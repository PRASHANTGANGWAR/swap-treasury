// InvestorStructures.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

contract InvestorStructures {
    struct Investment {
        uint256 amount;
        uint256 blockNumber;
    }

    struct FeeProfit {
        uint256 amount;
        uint256 blockNumber;
    }

    struct Investor {
        Investment[] investments;
        FeeProfit[] feeProfits;
        bool isInvestor;
    }
   
   
    mapping(address => Investor) public investors;
    mapping(address => uint256) public investorBalancesUSDT;
}
