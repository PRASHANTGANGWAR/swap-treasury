// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./utils/ECDSA.sol";

contract NetzUsdtSwap {
    address public owner;
    address feesWallet;
    uint numerator = 1;
    uint denominator = 10;
    IERC20 public tokenContractNTZ; 
    IERC20 public usdtContract;
    
    struct SwapStruct {
        address _address;
        string from;
        string to;
        uint amount;
        uint conversion_factor;
        uint paid_amount;
    }

    struct WithdrawStruct {
        address to;
        uint amount;
        string token_type;
        uint block_timestamp;
    }

    SwapStruct[] public swapStructArray;
    WithdrawStruct[] public withdrawStructArray;

    // mappings
    mapping(address => SwapStruct) public swapStructMapping;
    mapping(address => WithdrawStruct) public WithdrawStructMapping;
    mapping(address => bool) public signManagers; 
    mapping(address => bool) public subAdmin; 

  

    // events
    event WithdrawTransaction(address _to, string _type, uint amount);
    event SwapTransaction(address _from, string _type, uint ratio, uint _sentAmount, uint receiveAmount);
    event NumeratorFessUpdate(uint value);
    event DenominatorFessUpdate(uint value);
    event FeesWalletUpdate(address);
    event SignerAdded(address);
    event SignerRemove(address);


    constructor(address _netzAddress, address _usdtAddress, address _feesWallet) {
        owner = msg.sender;
        tokenContractNTZ = IERC20(_netzAddress); 
        usdtContract = IERC20(_usdtAddress); 
        signManagers[msg.sender] = true;
        feesWallet = _feesWallet;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    modifier onlySubAdminOrOwner() {
        require(subAdmin[msg.sender] || msg.sender == owner , "Only the sub admin can call this function");
        _;
    }
    
    // Transfer tokens to another account
    function withdrawToAnother(address _to, string memory _type, uint _amount) public onlyOwner {
        require(_to != address(0), "Invalid address");
        withdraw(_to, _type, _amount);
    }

    // Transfer tokens to owner
    function withdrawToAdmin(string memory _type, uint _amount) public onlyOwner {
        withdraw(owner, _type, _amount);
    }

    // token swap
    function swap(bytes memory signature, uint256 ratio, uint256 amount, string memory conversionType) public {
        bytes32 message = swapProof(ratio, amount, conversionType, msg.sender);
        address signerAddress = getSigner(message, signature);
        require(signerAddress != address(0) , "Invalid signer address");
        require(isSigner(signerAddress), "Invalid signer address");
        require(amount > 0, "Invalid amount");
        uint fees = feesCalculate(amount);
        uint remainingTokenAmount = amount - fees;

        if (keccak256(abi.encodePacked(conversionType)) == keccak256(abi.encodePacked("token"))) {
            require(usdtContract.balanceOf(msg.sender) >= amount, "Insufficient balance");
           
            uint tokenAmount = remainingTokenAmount / ratio;
            require(tokenContractNTZ.balanceOf(address(this)) >= tokenAmount, "Insufficient balance for swap");

            SwapStruct memory swapValues = SwapStruct(msg.sender, "usdt", "token", amount, ratio, tokenAmount);
            swapStructArray.push(swapValues);
            swapStructMapping[msg.sender] = swapValues;

            SafeERC20.safeTransferFrom(usdtContract, msg.sender, address(this), amount);
            SafeERC20.safeTransfer(tokenContractNTZ, msg.sender, tokenAmount);
            SafeERC20.safeTransfer(usdtContract,feesWallet, fees);
            emit SwapTransaction(msg.sender, conversionType, ratio,tokenAmount, amount);
        } 
        else if (keccak256(abi.encodePacked(conversionType)) == keccak256(abi.encodePacked("usdt"))) {
            require(tokenContractNTZ.balanceOf(msg.sender) >= amount, "Insufficient balance");
            uint256 usdtAmount = remainingTokenAmount * ratio;
            require(usdtContract.balanceOf(address(this)) >= usdtAmount , "Insufficient balance for swap");

            SwapStruct memory swapValues = SwapStruct(msg.sender, "token", "usdt", amount, ratio, usdtAmount);
            swapStructArray.push(swapValues);
            swapStructMapping[msg.sender] = swapValues;

            SafeERC20.safeTransferFrom(tokenContractNTZ, msg.sender, address(this), amount);
            SafeERC20.safeTransfer(usdtContract, msg.sender, usdtAmount);
            SafeERC20.safeTransfer(tokenContractNTZ, feesWallet, fees);
            emit SwapTransaction(msg.sender, conversionType, ratio, usdtAmount, amount);

        }

    }

    function withdraw(address _to, string memory _type, uint _amount) internal {
        if (keccak256(abi.encodePacked(_type)) == keccak256(abi.encodePacked("token"))) {
            require(tokenContractNTZ.balanceOf(address(this))> _amount, "Insufficient token balance");
            WithdrawStruct memory withdrawValues = WithdrawStruct(_to, _amount, "token", block.timestamp);
            withdrawStructArray.push(withdrawValues);
            WithdrawStructMapping[msg.sender] = withdrawValues;
            SafeERC20.safeTransfer(tokenContractNTZ, _to, _amount);
        }
        if (keccak256(abi.encodePacked(_type)) == keccak256(abi.encodePacked("usdt"))) {
            require(usdtContract.balanceOf(address(this))> _amount, "Insufficient USDT balance");
            WithdrawStruct memory withdrawValues = WithdrawStruct(_to, _amount, "usdt", block.timestamp);
            withdrawStructArray.push(withdrawValues);
            WithdrawStructMapping[msg.sender] = withdrawValues;
            SafeERC20.safeTransfer(usdtContract, _to, _amount);
        }
        emit WithdrawTransaction (_to, _type, _amount);
    }

    function currentContractTokenBalance() public view returns (uint) {
       return tokenContractNTZ.balanceOf(address(this));
    }

    function currentContractUSDTBalance() public view returns (uint) {
       return usdtContract.balanceOf(address(this));
    }
   
    function getSwapStructArray() public view returns (SwapStruct[] memory) {
        return swapStructArray;
    }

    function getWithdrawStructArray() public view returns (WithdrawStruct[] memory) {
        return withdrawStructArray;
    }

    /**
     * @dev Get the message hash for signing for mint NTZC
     */
    function swapProof(uint256 ratio, uint amount, string memory conversionType, address receiver) public pure returns (bytes32 message) {
        message = keccak256(abi.encode(ratio, amount, conversionType, receiver));
    }

    function getSigner(bytes32 message, bytes memory signature) public pure returns (address) {
        message = ECDSA.toEthSignedMessageHash(message);
        return ECDSA.recover(message, signature);
    }

    function isSigner(address _signer) public view returns (bool) {
        return signManagers[_signer];
    }

    function addSigner(address _address) public onlySubAdminOrOwner {
        signManagers[_address] = true;
        emit  SignerAdded(_address);
    }

    function removeSigner(address _address) public onlySubAdminOrOwner {
        signManagers[_address] = false;
        emit SignerRemove(_address);
    }

    function updateNumerator(uint _value) public  onlySubAdminOrOwner {
        numerator = _value;
        emit NumeratorFessUpdate(_value);
    }

    function updateDenominator(uint _value) public  onlySubAdminOrOwner {
        denominator = _value;
        emit DenominatorFessUpdate(_value);
    }

    function getNumerator() public view  returns(uint) {
        return  numerator;
    }

    function getDenominator() public view  returns(uint) {
       return  denominator;
    }

    function feesCalculate(uint _amount) public view  returns (uint)   {
        return ((_amount * numerator/denominator)*1/100);
    }

    function updateFessWallet(address _address) public onlySubAdminOrOwner {
        feesWallet = _address;
        emit FeesWalletUpdate(_address);
    }

    function getFessWallet() public  view returns(address)  {
        return  feesWallet;
    }

    function addSubAdmin(address _address) public onlyOwner {
        subAdmin[_address] =  true;
    }
    function removeSubAdmin(address _address) public onlyOwner {
        subAdmin[_address] =  false;
    }

}
