// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
contract Access is Ownable {

    mapping(address => bool) public signManagers;
    mapping(address => bool) public subAdmin;
    mapping(address => bool) public whitelist;

    uint public numerator = 5 ;
    uint public denominator = 10;
    uint public swapRatio;
    uint256 public eligibilityPeriod;
    address public networkFeeWallet;
    uint8 public minimumLiquidityPercentage;
    bool public whitelistEnabled;
    address public admin;

    event NumeratorFeesUpdate(uint value);
    event DenominatorFeesUpdate(uint value);
    event UpdateRatio(uint value);
    event UpdateNetworkFeeWallet(address indexed networkFeeWallet);
    event SwapFeePercentUpdated(uint256 newSwapFeePercent);
    event WhitelistEnabled(bool enabled);
    event MinimumLiquidityPercentageUpdated(uint8 newPercentage);
    event UpdateSigner(address indexed signer, bool value);
    event UpdateSubAdmin(address indexed subAdmin, bool value);
    event ManagerAdded(address indexed manager);
    event ManagerRemoved(address indexed manager);
    event InvestorWhitelisted(address indexed investor);
    event InvestorRemovedFromWhitelist(address indexed investor);

    modifier onlySubAdminOrOwner() {
        require(subAdmin[msg.sender] || msg.sender == owner(), "Only owner and sub admin can call this function");
        _;
    }

    modifier onlyAdminOrOwner() {
        require(msg.sender == admin || msg.sender == owner(), "Not authorized");
        _;
    }


    constructor(
        uint _ratio,
        address _networkFeeWallet,
        uint8 _minimumLiquidityPercentage,
        uint256 _eligibilityPeriod,
        address _admin
    ) Ownable(msg.sender) {
        swapRatio = _ratio;
        networkFeeWallet = _networkFeeWallet;
        minimumLiquidityPercentage = _minimumLiquidityPercentage;
        eligibilityPeriod = _eligibilityPeriod;
        whitelistEnabled = false;
        admin = _admin;
    }


    function setNumerator(uint256 value) external onlySubAdminOrOwner {
        numerator = value;
        emit NumeratorFeesUpdate(value);
    }

    function setDenominator(uint256 value) external onlySubAdminOrOwner {
        denominator = value;
        emit DenominatorFeesUpdate(value);
    }

    function setSwapRatio(uint _ratio) external onlySubAdminOrOwner {
        swapRatio = _ratio;
        emit UpdateRatio(_ratio);
    }

    function updateEligibilityPeriod(uint256 blocks) external onlyAdminOrOwner {
        eligibilityPeriod = blocks;
    }

    function updateMinimumLiquidityPercentage(uint8 newPercentage) external onlyAdminOrOwner {
        minimumLiquidityPercentage = newPercentage;
        emit MinimumLiquidityPercentageUpdated(newPercentage);
    }

    function updateNetworkFeeWallet(address _networkFeeWallet) external onlySubAdminOrOwner {
        require(networkFeeWallet != _networkFeeWallet, "Same wallet address");
        networkFeeWallet = _networkFeeWallet;
        emit UpdateNetworkFeeWallet(_networkFeeWallet);
    }

    function enableWhitelist(bool enabled) external onlyOwner {
        whitelistEnabled = enabled;
        emit WhitelistEnabled(enabled);
    }

    function updateSubAdmin(address _subAdmin, bool _value) external onlyOwner {
        subAdmin[_subAdmin] = _value;
        emit UpdateSubAdmin(_subAdmin, _value);
    }

    function updateSignManager(address _signManagerAddress, bool _value) external onlySubAdminOrOwner {
        signManagers[_signManagerAddress] = _value;
        emit UpdateSigner(_signManagerAddress, _value);
    }

    function addInvestorToWhitelist(address investor) external onlyAdminOrOwner {
        whitelist[investor] = true;
        emit InvestorWhitelisted(investor);
    }

    function removeInvestorFromWhitelist(address investor) external onlyAdminOrOwner {
        whitelist[investor] = false;
        emit InvestorRemovedFromWhitelist(investor);
    }

    function isSigner(address _address) external view returns (bool) {
        return signManagers[_address];
    }

    function feesCalculate(uint _amount) external view returns (uint) {
        return (_amount * numerator / denominator) / 100;
    }

    function getSigner(
        bytes32 _message,
        bytes memory signature
    ) external  pure returns (address) {
        _message = MessageHashUtils.toEthSignedMessageHash(_message);
        return ECDSA.recover(_message, signature);
    }
}
