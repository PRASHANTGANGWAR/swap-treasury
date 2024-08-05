// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAccess {
    // Function to initialize the contract
    function initialize(
        uint _numerator,
        uint _denominator,
        uint _ratio,
        uint256 _swapFeePercent,
        address _networkFeeWallet,
        uint8 _minimumLiquidityPercentage,
        uint256 _eligibilityPeriod
    ) external;

    // Function to add a manager
    function addManager(address manager) external;

    // Function to remove a manager
    function removeManager(address manager) external;

    // Function to set the numerator
    function setNumerator(uint256 value) external;

    // Function to set the denominator
    function setDenominator(uint256 value) external;

    // Function to set the swap ratio
    function setSwapRatio(uint _ratio) external;

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
    function updateSignManager(address _signManagerAddress, bool _value) external;

    // Function to add investor to whitelist
    function addInvestorToWhitelist(address investor) external;

    // Function to remove investor from whitelist
    function removeInvestorFromWhitelist(address investor) external;

    // Function to check if an address is a signer
    function isSigner(address _address) external view returns (bool);

    // Function to calculate fees
    function feesCalculate(uint _amount) external view returns (uint);

    // Function to getSigner 
    function getSigner(bytes32 _message,  bytes memory signature ) external pure returns (address);
    // Public variables (not directly accessible but included for completeness)
    function signManagers(address) external view returns (bool);
    function subAdmin(address) external view returns (bool);
    function whitelist(address) external view returns (bool);
    function numerator() external view returns (uint);
    function denominator() external view returns (uint);
    function swapRatio() external view returns (uint);
    function eligibilityPeriod() external view returns (uint256);
    function swapFeePercent() external view returns (uint256);
    function networkFeeWallet() external view returns (address);
    function minimumLiquidityPercentage() external view returns (uint8);
    function whitelistEnabled() external view returns (bool);
    function admin() external view returns (address);
    function managers(uint) external view returns (address);
}
