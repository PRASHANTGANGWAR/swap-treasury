// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./Enum.sol";
import "./IERC20Extended.sol";
import "./InvestorStructs.sol";
import "./Events.sol";
import "./ErrorMessages.sol";


contract Access is Ownable, InvestorStructures {
    using ErrorMessages for *;
    mapping(address => bool) public signManagers;
    mapping(address => bool) public subAdmin;
    mapping(address => bool) public whitelist;
    mapping(address => bool) public eligibility;

    uint256 public numerator = 5;
    uint256 public denominator = 10;
    uint256 public swapRatio;
    uint256 public eligibilityPeriod;
    address public networkFeeWallet;
    uint8 public minimumLiquidityPercentage;
    bool public whitelistEnabled;
    address public admin;

    modifier onlySubAdminOrOwner() {
        require(
            subAdmin[msg.sender] ||
                msg.sender == admin ||
                msg.sender == owner(),
            ErrorMessages.E18

        );
        _;
    }

    modifier onlyAdminOrOwner() {
        require(msg.sender == admin || msg.sender == owner(), ErrorMessages.E3);
        _;
    }

    constructor(
        uint256 _ratio,
        address _networkFeeWallet,
        uint8 _minimumLiquidityPercentage,
        uint256 _eligibilityPeriod,
        address _admin
    ) Ownable(msg.sender) {
        require(_admin != address(0), ErrorMessages.E19);
        swapRatio = _ratio;
        networkFeeWallet = _networkFeeWallet;
        minimumLiquidityPercentage = _minimumLiquidityPercentage;
        eligibilityPeriod = _eligibilityPeriod;
        whitelistEnabled = false;
        admin = _admin;
    }

    function setNumerator(uint256 value) external onlySubAdminOrOwner {
        numerator = value;
        emit Events.NumeratorFeesUpdate(value);
    }

    function setDenominator(uint256 value) external onlySubAdminOrOwner {
        require(denominator > 0, ErrorMessages.E20);
        denominator = value;
        emit Events.DenominatorFeesUpdate(value);
    }

    function setSwapRatio(uint256 _ratio) external onlySubAdminOrOwner {
        swapRatio = _ratio;
        emit Events.UpdateRatio(_ratio);
    }

    function updateEligibilityPeriod(uint256 blocks) external onlyAdminOrOwner {
        eligibilityPeriod = blocks;
        emit Events.UpdateEligibilityPeriod(blocks);
    }

    function updateMinimumLiquidityPercentage(uint8 newPercentage)
        external
        onlyAdminOrOwner
    {
        minimumLiquidityPercentage = newPercentage;
        emit Events.MinimumLiquidityPercentageUpdated(newPercentage);
    }

    function updateNetworkFeeWallet(address _networkFeeWallet)
        external
        onlySubAdminOrOwner
    {
        require(networkFeeWallet != _networkFeeWallet, ErrorMessages.E21);
        networkFeeWallet = _networkFeeWallet;
        emit Events.UpdateNetworkFeeWallet(_networkFeeWallet);
    }

    function enableWhitelist(bool enabled) external onlyOwner {
        whitelistEnabled = enabled;
        emit Events.WhitelistEnabled(enabled);
    }

    function updateSubAdmin(address _subAdmin, bool _value)
        external
        onlyAdminOrOwner
    {
        require(_subAdmin != address(0), ErrorMessages.E22);
        subAdmin[_subAdmin] = _value;
        emit Events.UpdateSubAdmin(_subAdmin, _value);
    }

    function updateSignManager(address _signManagerAddress, bool _value)
        external
        onlySubAdminOrOwner
    {
        require(
            _signManagerAddress != address(0),
            ErrorMessages.E23
        );
        signManagers[_signManagerAddress] = _value;
        emit Events.UpdateSigner(_signManagerAddress, _value);
    }

    function addInvestorToWhitelist(address investor)
        external
        onlyAdminOrOwner
    {
        require(investor != address(0), ErrorMessages.E24);
        whitelist[investor] = true;
        emit Events.InvestorWhitelisted(investor);
    }

    function removeInvestorFromWhitelist(address investor)
        external
        onlyAdminOrOwner
    {
        require(investor != address(0), ErrorMessages.E24);
        whitelist[investor] = false;
        emit Events.InvestorRemovedFromWhitelist(investor);
    }

    function isSigner(address _address) external view returns (bool) {
        return signManagers[_address];
    }

    function feesCalculate(uint256 _amount) external view returns (uint256) {
        return ((_amount * numerator) / denominator) / 100;
    }

    function getSigner(bytes32 _message, bytes memory signature)
        external
        pure
        returns (address)
    {
        _message = MessageHashUtils.toEthSignedMessageHash(_message);
        return ECDSA.recover(_message, signature);
    }

    function updateAdmin(address newAdmin) external onlyOwner {
        admin = newAdmin;
        emit Events.AdminUpdated(newAdmin);
    }

    function convertFeesToUsdt(
        uint256 _feeAmount,
        ConversionType _conversionType,
        IERC20Extended _ntzcContract,
        IERC20Extended _usdtContract
    ) public view returns (uint256 usdtFeeAmount) {
        if (_conversionType == ConversionType.usdt) {
            uint256 usdtAmount = (((_feeAmount * swapRatio) / 100) *
                (10**_usdtContract.decimals())) /
                (10**_ntzcContract.decimals());
            return usdtAmount;
        } else if (_conversionType == ConversionType.ntzc) {
            return _feeAmount;
        }
    }

    function calculateFeeProfit(
        uint256 eligibleInvestmentAmount,
        uint256 liquidityCounter,
        uint256 totalFeesCollectedUSDT
    ) external pure returns (uint256 result) {
        result =
            (eligibleInvestmentAmount * totalFeesCollectedUSDT) /
            liquidityCounter;
    }

    function ntzcAmount(
        uint256 _remainingTokenAmount,
        IERC20Extended _ntzcContract,
        IERC20Extended _usdtContract
    ) public view returns (uint256) {
        return
            (((_remainingTokenAmount * 100) / swapRatio) *
                (10**_ntzcContract.decimals())) /
            (10**_usdtContract.decimals());
    }

    function usdtAmount(
        uint256 _remainingTokenAmount,
        IERC20Extended _ntzcContract,
        IERC20Extended _usdtContract
    ) public view returns (uint256) {
        return
            (((_remainingTokenAmount * swapRatio) / 100) *
                (10**_usdtContract.decimals())) /
            (10**_ntzcContract.decimals());
    }

    function validateAllowanceAndBalance(
        ConversionType _conversionType,
        address _walletAddress,
        uint256 _amount,
        IERC20Extended _ntzcContract,
        IERC20Extended _usdtContract
    ) public  view {
        IERC20Extended tokenContract = _conversionType == ConversionType.ntzc
            ? _usdtContract
            : _ntzcContract;

        require(
            tokenContract.allowance(_walletAddress, address(this)) >= _amount &&
                tokenContract.balanceOf(_walletAddress) >= _amount,
            ErrorMessages.E17
        );
    }

}
