// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./InvestorStructs.sol";
import "./IAccess.sol";
import "./ErrorMessages.sol";
import "./Events.sol";
import "./Enum.sol";

contract SwapTreasury is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    InvestorStructures
{
    using SafeERC20 for IERC20Extended;
    using ErrorMessages for *;

    uint256[50] private __gap;
    uint256 public totalLiquidityUSDT;
    uint256 public totalFeesCollectedUSDT;

    IAccess public accessContract;
    struct ContractStruct {
        IERC20Extended ntzcContract;
        IERC20Extended usdtContract;
    }

    ContractStruct public contractData;

    using EnumerableMap for EnumerableMap.UintToAddressMap;
    EnumerableMap.UintToAddressMap private investorsList;

    mapping(address => uint256) public nonces;

    modifier onlySigner() {
        require(
            accessContract.isSigner(msg.sender) || msg.sender == owner(),
            ErrorMessages.E2
        );
        _;
    }

    modifier onlyAdminOrOwner() {
        require(
            msg.sender == accessContract.admin() || msg.sender == owner(),
            ErrorMessages.E3
        );
        _;
    }

    modifier onlyWhitelisted() {
        require(
            !accessContract.whitelistEnabled() ||
                accessContract.whitelist(msg.sender),
            ErrorMessages.E4
        );
        _;
    }

    function initialize(
        address _usdt,
        address _ntzc,
        address _initialOwner,
        address _accessContract
    ) public initializer {
        require(_initialOwner != address(0), ErrorMessages.E1);
        __Ownable_init(_initialOwner);
        contractData = ContractStruct(
            IERC20Extended(_ntzc),
            IERC20Extended(_usdt)
        );
        accessContract = IAccess(_accessContract);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    function addLiquidity(address token, uint256 amount)
        external
        onlyWhitelisted
    {
        require(token == address(contractData.usdtContract), ErrorMessages.E5);
        updateAllInvestorProfits();
        contractData.usdtContract.safeTransferFrom(
            _msgSender(),
            address(this),
            amount
        );

        if (investors[_msgSender()].isInvestor == false) {
            investorsList.set(investorsList.length(), _msgSender());
        }

        investors[_msgSender()].investments.push(
            Investment(amount, block.number)
        );
        investors[_msgSender()].isInvestor = true;
        investorBalancesUSDT[msg.sender] += amount;
        totalLiquidityUSDT += amount;

        emit Events.LiquidityAdded(msg.sender, amount, token);
    }

    function withdrawLiquidity(address token, uint256 amount)
        external
        onlyWhitelisted
    {
        require(token == address(contractData.usdtContract), ErrorMessages.E6);
        require(
            amount > 0 && amount <= investorBalancesUSDT[msg.sender],
            ErrorMessages.E7
        );

        if (msg.sender != accessContract.admin()) {
            uint256 minRequiredBalance = ((totalLiquidityUSDT -
                investorBalancesUSDT[accessContract.admin()] -
                investorBalancesUSDT[owner()]) *
                accessContract.minimumLiquidityPercentage()) / 100;
            require(
                contractData.usdtContract.balanceOf(address(this)) >=
                    minRequiredBalance,
                ErrorMessages.E8
            );
        }

        updateAllInvestorProfits();
        uint256 eligibleAmount = updateInvestorInvestments(
            _msgSender(),
            amount
        );
        totalLiquidityUSDT -= eligibleAmount;
        uint256 profit = getCurrentInvestorProfits(_msgSender());
        uint256 totalAmountToWithdraw = eligibleAmount + profit;
        require(totalAmountToWithdraw > 0, ErrorMessages.E9);
        contractData.usdtContract.safeTransfer(
            msg.sender,
            totalAmountToWithdraw
        );
        withdrawFees();
        emit Events.LiquidityWithdrawn(
            msg.sender,
            totalAmountToWithdraw,
            token,
            amount,
            eligibleAmount,
            profit
        );
    }

    function getCurrentInvestorProfits(address investor)
        public
        view
        returns (uint256)
    {
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
            emit Events.InvestorProfitsUpdated(
                investor,
                liquidityCounter,
                investorBalancesUSDT[investor]
            );
            liquidityCounter -= investorBalancesUSDT[investor];
        }
    }

    function updateAllInvestorProfitsAdmin() public onlyAdminOrOwner {
        updateAllInvestorProfits();
    }

    function updateInvestorProfits(address investor, uint256 liquidityCounter)
        private
    {
        uint256 eligibleInvestmentAmount = getInvestmentAmount(investor);
        if (
            liquidityCounter > 0
        ) {
            uint256 feeShare = accessContract.calculateFeeProfit(
                eligibleInvestmentAmount,
                liquidityCounter,
                totalFeesCollectedUSDT
            );
            totalFeesCollectedUSDT -= feeShare;
            investors[investor].feeProfits.push(
                FeeProfit(feeShare, block.number)
            );
            emit Events.InvestorProfitUpdated(investor, feeShare, block.number);
        }
    }

    function getInvestmentAmount(address investor)
            public
            view
            returns (uint256)
        {
            uint256 amount = 0;
            for (uint256 i = 0; i < investors[investor].investments.length; i++) {
                amount += investors[investor].investments[i].amount;
            }
            return amount;
        }

    function updateInvestorInvestments(address investor, uint256 amount)
        private
        returns (uint256)
    {
        uint256 remainingAmount = amount;
        uint256 eligibleBalance = 0;
        for (uint256 i = 0; i < investors[investor].investments.length; i++) {
            if (remainingAmount == 0) break;
            if (
                block.number - investors[investor].investments[i].blockNumber >=
                accessContract.eligibilityPeriod()
            ) {
                if (
                    investors[investor].investments[i].amount <= remainingAmount
                ) {
                    remainingAmount -= investors[investor]
                        .investments[i]
                        .amount;
                    eligibleBalance += investors[investor]
                        .investments[i]
                        .amount;
                    investors[investor].investments[i].amount = 0;
                } else {
                    investors[investor]
                        .investments[i]
                        .amount -= remainingAmount;
                    eligibleBalance += remainingAmount;
                    remainingAmount = 0;
                }
            }
        }
        investorBalancesUSDT[msg.sender] -= eligibleBalance;
        return eligibleBalance;
    }

    function withdrawFees() internal {
        while (investors[_msgSender()].feeProfits.length > 0) {
            investors[_msgSender()].feeProfits.pop();
        }
    }

    function rebalancePool(uint256 amount) external onlyAdminOrOwner {
        require(amount > 0, ErrorMessages.E10);

        uint256 contractBalance = contractData.usdtContract.balanceOf(
            address(this)
        );
        require(contractBalance <= totalLiquidityUSDT, ErrorMessages.E11);
        contractData.usdtContract.safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        uint256 excessLiquidity = amount > totalLiquidityUSDT - contractBalance
            ? amount - (totalLiquidityUSDT - contractBalance)
            : 0;

        if (excessLiquidity > 0) {
            investors[msg.sender].investments.push(
                Investment(excessLiquidity, block.number)
            );
            investorBalancesUSDT[msg.sender] += excessLiquidity;
            totalLiquidityUSDT += excessLiquidity;
        }

        emit Events.PoolRebalanced(amount, address(contractData.usdtContract));
    }

    function swapDirect(
        uint256 _amount,
        ConversionType _conversionType,
        address _tokenReceiveAddress
    ) public {
        accessContract.validateAllowanceAndBalance(_conversionType, msg.sender, _amount,  contractData.ntzcContract, contractData.usdtContract);
        uint256 fees = accessContract.feesCalculate(_amount);

        uint256 feesInUSDT = accessContract.convertFeesToUsdt(
            fees,
            _conversionType,
            contractData.ntzcContract,
            contractData.usdtContract
        );
        totalFeesCollectedUSDT += feesInUSDT;

        uint256 remainingTokenAmount = _amount - fees;

        _swap(
            msg.sender,
            accessContract.swapRatio(),
            _conversionType,
            remainingTokenAmount,
            _amount,
            _tokenReceiveAddress
        );
    }

    function delegateSwap(
        bytes memory _signature,
        address _walletAddress,
        uint256 _amount,
        ConversionType _conversionType,
        uint256 _networkFee,
        address _tokenReceiveAddress,
        uint256 _nonce
    ) public onlySigner {
        require(_nonce == nonces[_walletAddress], ErrorMessages.E13);

        accessContract.validateAllowanceAndBalance(_conversionType, _walletAddress, _amount,   contractData.ntzcContract, contractData.usdtContract);

        bytes32 message = keccak256(
            abi.encode(
                _amount,
                _conversionType,
                _walletAddress,
                _networkFee,
                _tokenReceiveAddress,
                _nonce
            )
        );
        address signerAddress = accessContract.getSigner(message, _signature);
        require(signerAddress == _walletAddress, ErrorMessages.E14);
        uint256 remainingToken = _amount - _networkFee;
        uint256 fees = accessContract.feesCalculate(remainingToken);
        uint256 feesInUSDT = accessContract.convertFeesToUsdt(
            fees,
            _conversionType,
            contractData.ntzcContract,
            contractData.usdtContract
        );
        totalFeesCollectedUSDT += feesInUSDT;

        uint256 remainingTokenAmount = remainingToken - fees;

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
        uint256 _swapRatio,
        ConversionType _conversionType,
        uint256 _remainingTokenAmount,
        uint256 _amount,
        address _tokenReceiveAddress
    ) internal {
        if (_conversionType == ConversionType.ntzc) {
            uint256 ntzcAmount = accessContract.ntzcAmount(
                _remainingTokenAmount,
                contractData.ntzcContract,
                contractData.usdtContract
            );
            require(
                contractData.ntzcContract.balanceOf(address(this)) >=
                    ntzcAmount,
                ErrorMessages.E15
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
            emit Events.SwapTransaction(
                _walletAddress,
                ConversionType.usdt,
                _conversionType,
                _swapRatio,
                ntzcAmount,
                _amount
            );
        } else if (_conversionType == ConversionType.usdt) {
            uint256 usdtAmount = accessContract.usdtAmount(
                _remainingTokenAmount,
                contractData.ntzcContract,
                contractData.usdtContract
            );
            require(
                contractData.usdtContract.balanceOf(address(this)) >=
                    usdtAmount,
                ErrorMessages.E15
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
            emit Events.SwapTransaction(
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
        uint256 _amount
    ) internal {
        if (_conversionType == ConversionType.ntzc) {
            require(
                contractData.ntzcContract.balanceOf(address(this)) >= _amount,
                ErrorMessages.E16
            );
            SafeERC20.safeTransfer(contractData.ntzcContract, _to, _amount);
        } else if (_conversionType == ConversionType.usdt) {
            require(
                contractData.usdtContract.balanceOf(address(this)) >= _amount,
                ErrorMessages.E16
            );
            SafeERC20.safeTransfer(contractData.usdtContract, _to, _amount);
        }

        emit Events.WithdrawTransaction(
            _to,
            _conversionType,
            _amount,
            block.timestamp
        );
    }

    function withdrawAdmin(
        address _to,
        ConversionType _conversionType,
        uint256 _amount
    ) public onlyAdminOrOwner {
        _withdraw(_to, _conversionType, _amount);
    }

  
    function numerator() public view returns (uint256) {
        return accessContract.numerator();
    }

    function denominator() public view returns (uint256) {
        return accessContract.denominator();
    }

    function getEligibleBalance(address investor)
        public
        view
        returns (uint256)
    {
        uint256 eligibleBalance = 0;
        for (uint256 i = 0; i < investors[investor].investments.length; i++) {
            if (
                block.number - investors[investor].investments[i].blockNumber >=
                accessContract.eligibilityPeriod()
            ) {
                eligibleBalance += investors[investor].investments[i].amount;
            }
        }
        return eligibleBalance;
    }
}
