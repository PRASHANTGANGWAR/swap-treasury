// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Enum.sol";

contract Events {
    event WithdrawTransaction(
        address indexed to,
        ConversionType indexed conversionType,
        uint amount,
        uint indexed blockTimestamp
    );

    event SwapTransaction(
        address indexed userWalletAddress,
        ConversionType indexed fromToken,
        ConversionType indexed toToken,
        uint ratio,
        uint sentAmount,
        uint receivedAmount
    );

    event LiquidityAdded(address indexed investor, uint256 amount, address token);
    event LiquidityWithdrawn(address indexed investor, uint256 fullAmount, address token, uint256 requestedAmount, uint256 baseInvestment, uint256 fee);
    event PoolRebalanced(uint256 amount, address token);
    event SwapExecuted(address indexed client, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, address indexed receiver, uint256 fee);
    event InvestorProfitsUpdated(address indexed investor, uint256 liquidityCounter, uint256 investorBalance);
    event InvestorProfitUpdated(address indexed investor, uint256 feeShare, uint256 blockNumber);

    event NumeratorFeesUpdate(uint value);
    event DenominatorFeesUpdate(uint value);
    event UpdateRatio(uint value);
    event UpdateNetworkFeeWallet(address indexed networkFeeWallet);
    event SwapFeePercentUpdated(uint256 newSwapFeePercent);
    event WhitelistEnabled(bool enabled);
    event MinimumLiquidityPercentageUpdated(uint8 newPercentage);
    event UpdateSigner(address indexed signer, bool value);
    event UpdateSubAdmin(address indexed subAdmin, bool value);
    event InvestorWhitelisted(address indexed investor);
    event InvestorRemovedFromWhitelist(address indexed investor);
    event AdminUpdated(address indexed admin);
    event UpdateEligibilityPeriod(uint256 indexed blocks);
}
