// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IERC20Extended is IERC20 {
    function decimals() external view returns (uint8);
}

contract Treasury is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    IERC20Extended public usdt;
    IERC20Extended public ntzc;

    uint8 public usdtDecimals;
    uint8 public ntzcDecimals;

    mapping(address => uint256) public investorBalancesUSDT;
    mapping(address => uint256) public investorBalancesNTZC;
    uint256 public totalLiquidityUSDT;
    uint256 public totalFeesCollectedUSDT;
    uint256 public swapFeePercent; // e.g., 1 means 1%

    address public admin;
    address[] public managers;

    event LiquidityAdded(address indexed investor, uint256 amount, address token);
    event LiquidityWithdrawn(address indexed investor, uint256 amount, address token);
    event SwapExecuted(address indexed client, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event PoolRebalanced(uint256 amount, address token);

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

    function initialize(
        address _usdt,
        address _ntzc,
        address _admin,
        uint256 _swapFeePercent,
        address _initialOwner
    ) public initializer {
        usdt = IERC20Extended(_usdt);
        ntzc = IERC20Extended(_ntzc);
        admin = _admin;
        swapFeePercent = _swapFeePercent;
        usdtDecimals = IERC20Extended(_usdt).decimals();
        ntzcDecimals = IERC20Extended(_ntzc).decimals();
        __Ownable_init(_initialOwner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function addLiquidity(address token, uint256 amount) external {
        require(token == address(usdt), "Only USDT is accepted for liquidity");
        usdt.transferFrom(msg.sender, address(this), amount);

        investorBalancesUSDT[msg.sender] += amount;
        totalLiquidityUSDT += amount;

        emit LiquidityAdded(msg.sender, amount, token);
    }

    function withdrawLiquidity(address token, uint256 amount) external {
        require(token == address(usdt), "Only USDT withdrawals are allowed");

        uint256 feeShare = (investorBalancesUSDT[msg.sender] * totalFeesCollectedUSDT) / totalLiquidityUSDT;
        require(investorBalancesUSDT[msg.sender] >= amount, "Insufficient balance");

        investorBalancesUSDT[msg.sender] -= amount;
        totalLiquidityUSDT -= amount;
        totalFeesCollectedUSDT -= feeShare;

        uint256 totalAmountToWithdraw = amount + feeShare;
        usdt.transfer(msg.sender, totalAmountToWithdraw);
        emit LiquidityWithdrawn(msg.sender, totalAmountToWithdraw, token);
    }

    function swap(address tokenIn, uint256 amountIn) external {
        require(tokenIn == address(usdt) || tokenIn == address(ntzc), "Invalid token");
        address tokenOut = (tokenIn == address(usdt)) ? address(ntzc) : address(usdt);
        IERC20Extended inToken = IERC20Extended(tokenIn);
        IERC20Extended outToken = IERC20Extended(tokenOut);

        uint8 inTokenDecimals = (tokenIn == address(usdt)) ? usdtDecimals : ntzcDecimals;
        uint8 outTokenDecimals = (tokenOut == address(usdt)) ? usdtDecimals : ntzcDecimals;

        uint256 fee = (amountIn * swapFeePercent) / 100;
        uint256 amountOut = (amountIn - fee) * (10 ** outTokenDecimals) / (10 ** inTokenDecimals);

        require(inToken.transferFrom(msg.sender, address(this), amountIn), "Transfer failed");
        require(outToken.transfer(msg.sender, amountOut), "Transfer failed");

        if (tokenIn == address(ntzc)) {
            // Convert NTZC fee to USDT
            uint256 feeInUSDT = fee * (10 ** usdtDecimals) / (10 ** ntzcDecimals);
            require(ntzc.transferFrom(msg.sender, address(this), fee), "Transfer failed");
            totalFeesCollectedUSDT += feeInUSDT;
        } else {
            totalFeesCollectedUSDT += fee;
        }

        emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }


    function rebalancePool(uint256 amount) external onlyAdminOrOwner {
        usdt.transferFrom(msg.sender, address(this), amount);

        uint256 contractBalance = usdt.balanceOf(address(this));
        uint256 excessLiquidity = amount > totalLiquidityUSDT - contractBalance ? amount - (totalLiquidityUSDT - contractBalance) : 0;

        if (excessLiquidity > 0) {
            investorBalancesUSDT[msg.sender] += excessLiquidity;
            totalLiquidityUSDT += excessLiquidity;
        }

        emit PoolRebalanced(amount, address(usdt));
    }

    function addManager(address manager) external onlyOwner {
        managers.push(manager);
    }

    function removeManager(address manager) external onlyOwner {
        for (uint i = 0; i < managers.length; i++) {
            if (managers[i] == manager) {
                managers[i] = managers[managers.length - 1];
                managers.pop();
                break;
            }
        }
    }

    function updateSwapFeePercent(uint256 newSwapFeePercent) external onlyManagers {
        swapFeePercent = newSwapFeePercent;
    }

    function updateAdmin(address newAdmin) external onlyOwner {
        admin = newAdmin;
    }

    function updateTokenAddresses(address newUSDT, address newNTZC) external onlyOwner {
        usdt = IERC20Extended(newUSDT);
        ntzc = IERC20Extended(newNTZC);
        usdtDecimals = IERC20Extended(newUSDT).decimals();
        ntzcDecimals = IERC20Extended(newNTZC).decimals();
    }
}
