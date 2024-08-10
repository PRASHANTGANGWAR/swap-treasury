// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IAccess.sol";
interface IERC20Extended is IERC20 {
    function decimals() external view returns (uint8);
}

contract SwapTreasury is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20Extended;

    uint256[50] private __gap;
    uint256 public totalLiquidityUSDT;
    uint256 public totalFeesCollectedUSDT;

    IAccess public  accessContract;
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

    mapping(address => Investor) public investors;
    mapping(address => uint256) public investorBalancesUSDT;
    mapping(address => uint256) public nonces; // unique count for address


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


    modifier onlySigner() {
        require(accessContract.isSigner(msg.sender) || msg.sender == owner(), "Only signer and owner is allowed");
        _;
    }

    modifier onlyAdminOrOwner()  {
        require(msg.sender == accessContract.admin() || msg.sender == owner(), "Not authorized");
        _;
    }


    modifier onlyWhitelisted() {
        require(!accessContract.whitelistEnabled() || accessContract.whitelist(msg.sender), "Not whitelisted");
        _;
    }

    function initialize(
        address _usdt,
        address _ntzc,
        address _initialOwner,
       address _accessContract
    ) public initializer  {
        require(_initialOwner != address(0), "Initial owner cannot be zero address");
        __Ownable_init(_initialOwner);
        contractData = ContractStruct(
            IERC20Extended(_ntzc),
            IERC20Extended(_usdt)
        );
        accessContract = IAccess(_accessContract);
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

    function withdrawLiquidity(address token, uint256 amount) external  onlyWhitelisted{
        require(amount > 0, "Amount must be greater than zero");
        require(token == address(contractData.usdtContract), "Only USDT withdrawals are allowed");
        require(amount > 0 && amount <= investorBalancesUSDT[msg.sender], "Cannot withdraw more than the balance or amount is zero");

        if (msg.sender != accessContract.admin()) {
            uint256 minRequiredBalance = (totalLiquidityUSDT - investorBalancesUSDT[accessContract.admin()] - investorBalancesUSDT[owner()]) * accessContract.minimumLiquidityPercentage() / 100;
            require(contractData.usdtContract.balanceOf(address(this)) >= minRequiredBalance, "Contract is out of balance, try later");
        }

        updateAllInvestorProfits();
        uint256 eligibleAmount = updateInvestorInvestments(_msgSender(), amount);
        totalLiquidityUSDT -= eligibleAmount;
        uint256 profit = getCurrentInvestorProfits(_msgSender());
        uint256 totalAmountToWithdraw = eligibleAmount + profit;
        require(totalAmountToWithdraw > 0, "No liquiidity to withdraw");
        contractData.usdtContract.safeTransfer(msg.sender, totalAmountToWithdraw);
        withdrawFees();
        emit LiquidityWithdrawn(msg.sender, totalAmountToWithdraw, token, amount, eligibleAmount, profit);
    }

    function getCurrentInvestorProfits(address investor) public view returns (uint256) {
        uint256 totalProfit = 0;

        for (uint256 i = 0; i < investors[investor].feeProfits.length; i++) {
            totalProfit += investors[investor].feeProfits[i].amount;
        }
        return totalProfit;
    }

    function updateAllInvestorProfits() private {
        uint256 liquidityCounter = totalLiquidityUSDT;
        for (uint256 i = 0; i < investorsList.length(); i++) {
            (, address investor) = investorsList.at(i);
            updateInvestorProfits(investor, liquidityCounter);
            emit InvestorProfitsUpdated(investor, liquidityCounter, investorBalancesUSDT[investor]);
            liquidityCounter -= investorBalancesUSDT[investor];
        }
    }

    function updateAllInvestorProfitsAdmin() public onlyAdminOrOwner {
        updateAllInvestorProfits();
    }

    function updateInvestorProfits(address investor, uint256 liquidityCounter) private {
        uint256 eligibleInvestmentAmount = getInvestmentAmount(investor);
        if(totalFeesCollectedUSDT > 0 && eligibleInvestmentAmount > 0 && liquidityCounter > 0){
            uint256 feeShare = calculateFeeProfit(eligibleInvestmentAmount, liquidityCounter);
            totalFeesCollectedUSDT -= feeShare;
            investors[investor].feeProfits.push(FeeProfit(feeShare, block.number));
            emit InvestorProfitUpdated(investor, feeShare, block.number);
        }
    }

    function getInvestmentAmount(address investor) public view returns (uint256) {
        uint256 amount = 0;
        for (uint256 i = 0; i < investors[investor].investments.length; i++) {
            amount += investors[investor].investments[i].amount;
        }
        return amount;
    }


    function updateInvestorInvestments(address investor, uint256 amount) private  returns(uint256){
        uint256 remainingAmount = amount;
        uint256 eligibleBalance = 0;
        for (uint256 i = 0; i < investors[investor].investments.length; i++) {
            if (remainingAmount == 0) break;
            if (block.number - investors[investor].investments[i].blockNumber >= accessContract.eligibilityPeriod()) {
                if (investors[investor].investments[i].amount <= remainingAmount) {
                    remainingAmount -= investors[investor].investments[i].amount;
                    eligibleBalance += investors[investor].investments[i].amount;
                    investors[investor].investments[i].amount = 0;
                } else {
                    investors[investor].investments[i].amount -= remainingAmount;
                    eligibleBalance += remainingAmount;
                    remainingAmount = 0;
                }
            }
        }
        investorBalancesUSDT[msg.sender] -= eligibleBalance;
        return eligibleBalance;
    }

    function withdrawFees() internal {
        while(investors[_msgSender()].feeProfits.length > 0) {
            investors[_msgSender()].feeProfits.pop();
        }
    }

    function rebalancePool(uint256 amount) external onlyAdminOrOwner {
        require(amount > 0, "Amount must be greater than zero");

        uint256 contractBalance = contractData.usdtContract.balanceOf(address(this));
        require(contractBalance <= totalLiquidityUSDT, "Contract balance exceeds total liquidity");
        contractData.usdtContract.safeTransferFrom(msg.sender, address(this), amount);

        uint256 excessLiquidity = amount > totalLiquidityUSDT - contractBalance ? amount - (totalLiquidityUSDT - contractBalance) : 0;

        if (excessLiquidity > 0) {
            investors[msg.sender].investments.push(Investment(excessLiquidity, block.number));
            investorBalancesUSDT[msg.sender] += excessLiquidity;
            totalLiquidityUSDT += excessLiquidity;
        }

        emit PoolRebalanced(amount, address(contractData.usdtContract));
    }

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
        uint fees = accessContract.feesCalculate(_amount);

        uint256 feesInUSDT = convertFeesToUsdt(fees, _conversionType);
        totalFeesCollectedUSDT += feesInUSDT;

        uint remainingTokenAmount = _amount - fees;

        _swap(
            msg.sender,
            accessContract.swapRatio(),
            _conversionType,
            remainingTokenAmount,
            _amount,
            _tokenReceiveAddress        
        );
    }

    function convertFeesToUsdt(uint256 _feeAmount, ConversionType _conversionType) public view returns (uint256 usdtFeeAmount)  {
        if(_conversionType == ConversionType.usdt) {
            uint usdtAmount = (((_feeAmount * accessContract.swapRatio()) / 100) *
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
        address _tokenReceiveAddress,
        uint _nonce
    ) public onlySigner {
        require(_nonce == nonces[_walletAddress], "Invalid nonce");

        validateAllowanceAndBalance(_conversionType, _walletAddress, _amount);
    
        bytes32 message = keccak256(
            abi.encode(_amount, _conversionType, _walletAddress, _networkFee, _tokenReceiveAddress, _nonce)
        );
        address signerAddress = accessContract.getSigner(message, _signature);
        require(signerAddress == _walletAddress, "Invalid user address");
        uint remainingToken = _amount - _networkFee;
        uint fees = accessContract.feesCalculate(remainingToken);
        uint256 feesInUSDT = convertFeesToUsdt(fees, _conversionType);
        totalFeesCollectedUSDT += feesInUSDT;

        uint remainingTokenAmount = remainingToken - fees;

        _swap(
            _walletAddress,
            accessContract.swapRatio(),
            _conversionType,
            remainingTokenAmount,
            _amount,
            _tokenReceiveAddress
        );
        if (_conversionType == ConversionType.ntzc) {
            SafeERC20.safeTransfer(
                contractData.usdtContract,
                accessContract.networkFeeWallet(),
                _networkFee
            );
        } else if (_conversionType == ConversionType.usdt) {
            SafeERC20.safeTransfer(
                contractData.ntzcContract,
                accessContract.networkFeeWallet(),
                _networkFee
            );
        }
        nonces[_walletAddress]++;
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
                accessContract.swapRatio() *
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
            uint usdtAmount = (((_remainingTokenAmount * accessContract.swapRatio()) / 100) *
                (10 ** contractData.usdtContract.decimals())) /
                (10 ** contractData.ntzcContract.decimals());
            require(
                contractData.usdtContract.balanceOf(address(this)) >=
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

    function numerator() public  view  returns(uint256){
        return  accessContract.numerator();
    }

    function denominator() public  view  returns(uint256){
        return  accessContract.denominator();
    }

    function calculateFeeProfit(uint256 eligibleInvestmentAmount, uint256 liquidityCounter) public view  returns (uint256 result) {
        result = (eligibleInvestmentAmount * totalFeesCollectedUSDT) / liquidityCounter;
    }
    function getInvestorDetails(address _investor) 
            public 
            view 
            returns (Investment[] memory, FeeProfit[] memory) 
        {
            Investor storage investor = investors[_investor];
            return (investor.investments, investor.feeProfits);
        }

    function blockNumber() public  view returns(uint256){
        return  block.number;
    }

    function getEligibleBalance(address investor) public view returns (uint256) {
        uint256 eligibleBalance = 0;
        for (uint256 i = 0; i < investors[investor].investments.length; i++) {
            if (block.number - investors[investor].investments[i].blockNumber >= accessContract.eligibilityPeriod()) {
                eligibleBalance += investors[investor].investments[i].amount;
            }
        }
        return eligibleBalance;
    }
}