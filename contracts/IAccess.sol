// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./Enum.sol";
import "./IERC20Extended.sol";

interface IAccess {
    // Function to set the numerator
    function setNumerator(uint256 value) external;

    // Function to set the denominator
    function setDenominator(uint256 value) external;

    // Function to set the swap ratio
    function setSwapRatio(uint256 _ratio) external;

    // Function to update the swap fee percent
    function updateSwapFeePercent(uint256 newSwapFeePercent) external;

    // Function to update the eligibility period
    function updateEligibilityPeriod(uint256 blocks) external;

    // Function to update the minimum liquidity percentage
    function updateMinimumLiquidityPercentage(uint8 newPercentage) external;

    // Function to update the network fee wallet
    function updateNetworkFeeWallet(address _networkFeeWallet) external;

    // Function to enable or disable the whitelist
    function enableWhitelist(bool enabled) external;

    // Function to update sub-admin status
    function updateSubAdmin(address _subAdmin, bool _value) external;

    // Function to update sign manager status
    function updateSignManager(address _signManagerAddress, bool _value)
        external;

    // Function to add investor to whitelist
    function addInvestorToWhitelist(address investor) external;

    // Function to remove investor from whitelist
    function removeInvestorFromWhitelist(address investor) external;

    // Function to check if an address is a signer
    function isSigner(address _address) external view returns (bool);

    // Function to calculate fees
    function feesCalculate(uint256 _amount) external view returns (uint256);

    // Function to getSigner
    function getSigner(bytes32 _message, bytes memory signature)
        external
        pure
        returns (address);

    // Public variables (not directly accessible but included for completeness)
    function signManagers(address) external view returns (bool);

    function subAdmin(address) external view returns (bool);

    function whitelist(address) external view returns (bool);

    function numerator() external view returns (uint256);

    function denominator() external view returns (uint256);

    function swapRatio() external view returns (uint256);

    function eligibilityPeriod() external view returns (uint256);

    function swapFeePercent() external view returns (uint256);

    function networkFeeWallet() external view returns (address);

    function minimumLiquidityPercentage() external view returns (uint8);

    function whitelistEnabled() external view returns (bool);

    function admin() external view returns (address);

    function eligibility(address) external view returns (bool);

    function convertFeesToUsdt(
        uint256 _feeAmount,
        ConversionType _conversionType,
        IERC20Extended _ntzcContract,
        IERC20Extended _usdtContract
    ) external view returns (uint256 usdtFeeAmount);

    function getInvestmentAmount(address investor)
        external
        view
        returns (uint256);


    function calculateFeeProfit(
        uint256 eligibleInvestmentAmount,
        uint256 liquidityCounter,
        uint256 totalFeesCollectedUSDT
    ) external pure returns (uint256 result);

    function ntzcAmount(
        uint256 _remainingTokenAmount,
        IERC20Extended _ntzcContract,
        IERC20Extended _usdtContract
    ) external view returns (uint256);

    function usdtAmount(
        uint256 _remainingTokenAmount,
        IERC20Extended _ntzcContract,
        IERC20Extended _usdtContract
    ) external view returns (uint256);

    function validateAllowanceAndBalance(
        ConversionType _conversionType,
        address _walletAddress,
        uint256 _amount,
        IERC20Extended _ntzcContract,
        IERC20Extended _usdtContract
    ) external view;
}
