// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IERC20Extended is IERC20 {
    function decimals() external view returns (uint8);
}

contract SwapTreasury is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20Extended;

    uint public numerator;
    uint public denominator;
    uint public swapRatio;
    uint256 public eligibilityPeriod;
    uint256 public swapFeePercent;
    address public networkFeeWallet;
    address public admin;
    bool public whitelistEnabled;
    uint256 public totalLiquidityUSDT;
    uint256 public totalFeesCollectedUSDT;
    uint8 public minimumLiquidityPercentage;

    struct ContractStruct {
        IERC20Extended ntzcContract;
        IERC20Extended usdtContract;
    }

    ContractStruct public contractData;

    enum ConversionType {
        ntzc,
        usdt
    }

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

    using EnumerableMap for EnumerableMap.UintToAddressMap;
    EnumerableMap.UintToAddressMap private investorsList;

    mapping(address => Investor) investors;
    mapping(address => uint256) public investorBalancesUSDT;
    mapping(address => bool) public signManagers;
    mapping(address => bool) public subAdmin;
    mapping(address => bool) public whitelist;

    address[] public managers;

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

    event NumeratorFeesUpdate(uint value);
    event DenominatorFeesUpdate(uint value);
    event UpdateSigner(address indexed signer, bool value);
    event UpdateSubAdmin(address indexed subAdmin, bool value);
    event UpdateRatio(uint value);
    event UpdateNetworkFeeWallet(address indexed networkFeeWallet);
    event LiquidityAdded(address indexed investor, uint256 amount, address token);
    event LiquidityWithdrawn(address indexed investor, uint256 fullAmount, address token, uint256 baseInvestment, uint256 fee);
    event PoolRebalanced(uint256 amount, address token);
    event SwapExecuted(address indexed client, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, address indexed receiver, uint256 fee);
    event InvestorWhitelisted(address indexed investor);
    event InvestorRemovedFromWhitelist(address indexed investor);
    event WhitelistEnabled(bool enabled);
    event ManagerAdded(address indexed manager);
    event ManagerRemoved(address indexed manager);
    event SwapFeePercentUpdated(uint256 newSwapFeePercent);
    event AdminUpdated(address indexed newAdmin);

    modifier onlySubAdminOrOwner() {
        require(subAdmin[msg.sender] || msg.sender == owner(), "Only owner and sub admin can call this function");
        _;
    }

    modifier onlySigner() {
        require(isSigner(msg.sender) || msg.sender == owner(), "Only signer and owner is allowed");
        _;
    }

    modifier onlyAdminOrOwner() {
        require(msg.sender == admin || msg.sender == owner(), "Not authorized");
        _;
    }

    modifier onlyManagers() {
        bool isManager = false;
        for (uint i = 0; i < managers.length; i++) {
            if (managers[i] == msg.sender) {
                isManager = true;
                break;
            }
        }
        require(isManager, "Not a manager");
        _;
    }

    modifier onlyWhitelisted() {
        require(!whitelistEnabled || whitelist[msg.sender], "Not whitelisted");
        _;
    }

    function initialize(
        address _usdt,
        address _ntzc,
        address _admin,
        uint256 _swapFeePercent,
        uint _ratio,
        address _networkFeeWallet,
        address _initialOwner,
        uint8 _minimumLiquidityPercentage,
        uint256 _eligibilityPeriod
    ) public initializer {
        require(_initialOwner != address(0), "Initial owner cannot be zero address");
        numerator = 5;
        denominator = 10;
        admin = _admin;
        swapFeePercent = _swapFeePercent;
        swapRatio = _ratio;
        networkFeeWallet = _networkFeeWallet;
        __Ownable_init(_initialOwner);
        whitelistEnabled = false; 
        contractData = ContractStruct(
            IERC20Extended(_ntzc),
            IERC20Extended(_usdt)
        );
        signManagers[_initialOwner] = true;
        minimumLiquidityPercentage = _minimumLiquidityPercentage;
        eligibilityPeriod = _eligibilityPeriod;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function addLiquidity(address token, uint256 amount) external onlyWhitelisted {
        require(token == address(contractData.usdtContract), "Only USDT is accepted for liquidity");
        updateAllInvestorProfits();
        contractData.usdtContract.safeTransferFrom(_msgSender(), address(this), amount);

        if(investors[_msgSender()].isInvestor == false){
            investorsList.set(investorsList.length(), _msgSender());
        }

        investors[_msgSender()].investments.push(Investment(amount, block.number));
        investors[_msgSender()].isInvestor = true;
        investorBalancesUSDT[msg.sender] += amount;
        totalLiquidityUSDT += amount;

        emit LiquidityAdded(msg.sender, amount, token);
    }

    function withdrawLiquidity(address token, uint256 amount) external {
        require(token == address(contractData.usdtContract), "Only USDT withdrawals are allowed");
        require(amount <= investorBalancesUSDT[msg.sender], "Cannot withdraw more than in balance");

        if (msg.sender != admin) {
            uint256 minRequiredBalance = (totalLiquidityUSDT - investorBalancesUSDT[admin]) * minimumLiquidityPercentage / 100;
            require(contractData.usdtContract.balanceOf(address(this)) >= minRequiredBalance, "Contract is out of balance, try later");
        }

        updateAllInvestorProfits();
        updateInvestorInvestments(_msgSender(), amount);
        totalLiquidityUSDT -= amount;
        uint256 profit = getCurrentInvestorProfits(_msgSender());
        uint256 totalAmountToWithdraw = amount + profit;
        contractData.usdtContract.safeTransfer(msg.sender, totalAmountToWithdraw);
        withdrawFees();
        emit LiquidityWithdrawn(msg.sender, totalAmountToWithdraw, token, amount, profit);
    }

    function getCurrentInvestorProfits(address investor) public view returns (uint256) {
        uint256 totalProfit = 0;

        for (uint256 i = 0; i < investors[investor].feeProfits.length; i++) {
            totalProfit += investors[investor].feeProfits[i].amount;
        }
        return totalProfit;
    }

    function updateAllInvestorProfits() public onlyAdminOrOwner {
        uint256 liquidityCounter = totalLiquidityUSDT;
        for (uint256 i = 0; i < investorsList.length(); i++) {
            (uint256 mapKey, address investor) = investorsList.at(i);
            updateInvestorProfits(investor, liquidityCounter);
            liquidityCounter -= investorBalancesUSDT[investor];
        }
    }

    function updateInvestorProfits(address investor, uint256 liquidityCounter) internal {
        uint256 eligibleInvestmentAmount = getInvestmentAmount(_msgSender());
        uint256 feeShare = (eligibleInvestmentAmount * totalFeesCollectedUSDT) / liquidityCounter;
        totalFeesCollectedUSDT -= feeShare;

        investors[investor].feeProfits.push(FeeProfit(feeShare, block.number));
    }

    function getInvestmentAmount(address investor) public view returns (uint256) {
        uint256 amount = 0;
        for (uint256 i = 0; i < investors[investor].investments.length; i++) {
            amount += investors[investor].investments[i].amount;
        }
        return amount;
    }

    function updateEligibilityPeriod(uint256 blocks) external onlyAdminOrOwner {
        eligibilityPeriod = blocks;
    }

    function updateInvestorInvestments(address investor, uint256 amount) internal {
        uint256 remainingAmount = amount;
        for (uint256 i = 0; i < investors[investor].investments.length; i++) {
            if (remainingAmount == 0) break;
            if (block.number - investors[investor].investments[i].blockNumber >= eligibilityPeriod) {
                if (investors[investor].investments[i].amount <= remainingAmount) {
                    remainingAmount -= investors[investor].investments[i].amount;
                    investors[investor].investments[i].amount = 0;
                } else {
                    investors[investor].investments[i].amount -= remainingAmount;
                    remainingAmount = 0;
                }
            }
        }
        investorBalancesUSDT[msg.sender] -= amount;
    }

    function withdrawFees() internal {
        while(investors[_msgSender()].feeProfits.length > 0) {
            investors[_msgSender()].feeProfits.pop();
        }
    }

    function rebalancePool(uint256 amount) external onlyAdminOrOwner {
        require(amount > 0, "Amount must be greater than zero");
        contractData.usdtContract.safeTransferFrom(msg.sender, address(this), amount);

        uint256 contractBalance = contractData.usdtContract.balanceOf(address(this));
        uint256 excessLiquidity = amount > totalLiquidityUSDT - contractBalance ? amount - (totalLiquidityUSDT - contractBalance) : 0;

        if (excessLiquidity > 0) {
            investors[msg.sender].investments.push(Investment(excessLiquidity, block.number));
            investorBalancesUSDT[msg.sender] += excessLiquidity;
            totalLiquidityUSDT += excessLiquidity;
        }

        emit PoolRebalanced(amount, address(contractData.usdtContract));
    }

    function addManager(address manager) external onlyOwner {
        managers.push(manager);
        emit ManagerAdded(manager);
    }

    function removeManager(address manager) external onlyOwner {
        for (uint i = 0; i < managers.length; i++) {
            if (managers[i] == manager) {
                managers[i] = managers[managers.length - 1];
                managers.pop();
                break;
            }
        }
        emit ManagerRemoved(manager);
    }

    function updateMinimumLiquidityPercentage(uint8 newPercentage) external onlyAdminOrOwner {
        minimumLiquidityPercentage = newPercentage;
    }

    function updateSwapFeePercent(uint256 newSwapFeePercent) external onlyManagers {
        swapFeePercent = newSwapFeePercent;
        emit SwapFeePercentUpdated(newSwapFeePercent);
    }

    function updateAdmin(address newAdmin) external onlyOwner {
        admin = newAdmin;
        emit AdminUpdated(newAdmin);
    }

    function addInvestorToWhitelist(address investor) external onlyAdminOrOwner {
        whitelist[investor] = true;
        emit InvestorWhitelisted(investor);
    }

    function removeInvestorFromWhitelist(address investor) external onlyAdminOrOwner {
        whitelist[investor] = false;
        emit InvestorRemovedFromWhitelist(investor);
    }

    function enableWhitelist(bool enabled) external onlyAdminOrOwner {
        whitelistEnabled = enabled;
        emit WhitelistEnabled(enabled);
    }

    // Swap-related methods from the first contract

    function withdrawToAnother(
        address _to,
        ConversionType _conversionType,
        uint _amount
    ) public onlyOwner {
        require(_to != address(0), "Invalid address");
        _withdraw(_to, _conversionType, _amount);
    }

    function swapDirect(
        uint256 _amount,
        ConversionType _conversionType,
        address _tokenReceiveAddress
    ) public {
        validateAllowanceAndBalance(_conversionType, msg.sender, _amount);
        uint fees = feesCalculate(_amount);

        uint256 feesInUSDT = convertFeesToUsdt(fees, _conversionType);
        totalFeesCollectedUSDT += feesInUSDT;

        uint remainingTokenAmount = _amount - fees;

        _swap(
            msg.sender,
            swapRatio,
            _conversionType,
            remainingTokenAmount,
            _amount,
            _tokenReceiveAddress        
        );
    }

    function convertFeesToUsdt(uint256 _feeAmount, ConversionType _conversionType) public view returns (uint256 usdtFeeAmount)  {
        if(_conversionType == ConversionType.usdt) {
            uint usdtAmount = (((_feeAmount * swapRatio) / 100) *
                (10 ** contractData.usdtContract.decimals())) /
                (10 ** contractData.ntzcContract.decimals());
            return usdtAmount;
        }
        else if(_conversionType == ConversionType.ntzc) {
            return _feeAmount;
        }
    }

    function delegateSwap(
        bytes memory _signature,
        address _walletAddress,
        uint256 _amount,
        ConversionType _conversionType,
        uint _networkFee,
        address _tokenReceiveAddress
    ) public onlySigner {
        validateAllowanceAndBalance(_conversionType, _walletAddress, _amount);
    
        bytes32 message = keccak256(
            abi.encode(_amount, _conversionType, _walletAddress, _networkFee, _tokenReceiveAddress)
        );
        address signerAddress = getSigner(message, _signature);
        require(signerAddress == _walletAddress, "Invalid user address");
        uint remainingToken = _amount - _networkFee;
        uint fees = feesCalculate(remainingToken);
        uint256 feesInUSDT = convertFeesToUsdt(fees, _conversionType);
        totalFeesCollectedUSDT += feesInUSDT;

        uint remainingTokenAmount = remainingToken - fees;

        _swap(
            _walletAddress,
            swapRatio,
            _conversionType,
            remainingTokenAmount,
            _amount,
            _tokenReceiveAddress
        );
        if (_conversionType == ConversionType.ntzc) {
            SafeERC20.safeTransfer(
                contractData.usdtContract,
                networkFeeWallet,
                _networkFee
            );
        } else if (_conversionType == ConversionType.usdt) {
            SafeERC20.safeTransfer(
                contractData.ntzcContract,
                networkFeeWallet,
                _networkFee
            );
        }
    }

    function _swap(
        address _walletAddress,
        uint _swapRatio,
        ConversionType _conversionType,
        uint _remainingTokenAmount,
        uint _amount,
        address _tokenReceiveAddress
    ) internal {
        if (_conversionType == ConversionType.ntzc) {
            uint ntzcAmount = ((_remainingTokenAmount * 100) /
                swapRatio *
                (10 ** contractData.ntzcContract.decimals())) /
                (10 ** contractData.usdtContract.decimals());
            require(
                contractData.ntzcContract.balanceOf(address(this)) >=
                    ntzcAmount,
                "Insufficient balance for swap"
            );

            SafeERC20.safeTransferFrom(
                contractData.usdtContract,
                _walletAddress,
                address(this),
                _amount
            );
            SafeERC20.safeTransfer(
                contractData.ntzcContract,
                _tokenReceiveAddress,
                ntzcAmount
            );
            emit SwapTransaction(
                _walletAddress,
                ConversionType.usdt,
                _conversionType,
                _swapRatio,
                ntzcAmount,
                _amount
            );
        } else if (_conversionType == ConversionType.usdt) {
            uint usdtAmount = (((_remainingTokenAmount * swapRatio) / 100) *
                (10 ** contractData.usdtContract.decimals())) /
                (10 ** contractData.ntzcContract.decimals());
            require(
                contractData.ntzcContract.balanceOf(address(this)) >=
                    usdtAmount,
                "Insufficient balance for swap"
            );

            SafeERC20.safeTransferFrom(
                contractData.ntzcContract,
                _walletAddress,
                address(this),
                _amount
            );
            SafeERC20.safeTransfer(
                contractData.usdtContract,
                _tokenReceiveAddress,
                usdtAmount
            );
            emit SwapTransaction(
                _walletAddress,
                ConversionType.ntzc,
                _conversionType,
                _swapRatio,
                usdtAmount,
                _amount
            );
        }
    }

    function feesCalculate(uint _amount) public view returns (uint) {
        uint fees = (((_amount * numerator) / denominator) / 100);
        return fees;
    }

    function updateSignManager(
        address _signManagerAddress,
        bool _value
    ) public onlySubAdminOrOwner {
        require(
            signManagers[_signManagerAddress] != _value,
            "Signer already exist"
        );
        signManagers[_signManagerAddress] = _value;
        emit UpdateSigner(_signManagerAddress, _value);
    }

    function updateSubAdmin(address _subAdmin, bool _value) public onlyOwner {
        require(subAdmin[_subAdmin] != _value, "Sub admin already exist");
        subAdmin[_subAdmin] = _value;
        emit UpdateSubAdmin(_subAdmin, _value);
    }

    function setNumerator(uint256 value) public onlySubAdminOrOwner {
        numerator = value;
        emit NumeratorFeesUpdate(value);
    }

    function setDenominator(uint256 value) public onlySubAdminOrOwner {
        denominator = value;
        emit DenominatorFeesUpdate(value);
    }

    function setRatio(uint _ratio) public onlySubAdminOrOwner {
        swapRatio = _ratio;
        emit UpdateRatio(_ratio);
    }

    function isSigner(address _address) public view returns (bool) {
        return signManagers[_address];
    }

    function getSigner(
        bytes32 _message,
        bytes memory signature
    ) public pure returns (address) {
        _message = MessageHashUtils.toEthSignedMessageHash(_message);
        return ECDSA.recover(_message, signature);
    }

    function _withdraw(
        address _to,
        ConversionType _conversionType,
        uint _amount
    ) internal {
        if (_conversionType == ConversionType.ntzc) {
            require(
                contractData.ntzcContract.balanceOf(address(this)) >= _amount,
                "Insufficient funds"
            );
            SafeERC20.safeTransfer(contractData.ntzcContract, _to, _amount);
        } else if (_conversionType == ConversionType.usdt) {
            require(
                contractData.usdtContract.balanceOf(address(this)) >= _amount,
                "Insufficient funds"
            );
            SafeERC20.safeTransfer(contractData.usdtContract, _to, _amount);
        }

        emit WithdrawTransaction(
            _to,
            _conversionType,
            _amount,
            block.timestamp
        );
    }

    function withdrawAdmin(
        address _to,
        ConversionType _conversionType,
        uint _amount
    ) public onlyAdminOrOwner {
        require(_conversionType == ConversionType.ntzc,"Only NTZC withdrawals are allowed.");
        _withdraw(_to, _conversionType, _amount);
    }
    
    function validateAllowanceAndBalance(
        ConversionType _conversionType,
        address _walletAddress,
        uint _amount
    ) internal view {
        IERC20Extended tokenContract = _conversionType == ConversionType.ntzc
            ? contractData.usdtContract
            : contractData.ntzcContract;

        require(
            tokenContract.allowance(_walletAddress, address(this)) >= _amount &&
                tokenContract.balanceOf(_walletAddress) >= _amount,
            "Insufficient allowance or balance"
        );
    }

    function updateNetworkFeeWallet(address _networkFeeWallet) public onlySubAdminOrOwner {
        require(networkFeeWallet != _networkFeeWallet, "Network fee wallet already exist");
        networkFeeWallet = _networkFeeWallet;
        emit UpdateNetworkFeeWallet(_networkFeeWallet);
    }
}
