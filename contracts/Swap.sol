// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./utils/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Swap is Ownable {
    uint numerator = 5;
    uint denominator = 10;
    uint swapRatio;
    address public networkFeeWallet;
    bool public swapWithSignatureEnabled = false;
    bool public delegateSwapWithSignatureEnabled = false;
    ContractStruct public contractData;
    enum ConversionType {
        token1,
        token2
    }

    struct SwapStruct {
        address _address;
        string _from;
        string _to;
        uint _amount;
        uint _conversionFactor;
        uint _paidAmount;
    }

    struct WithdrawStruct {
        address _to;
        uint _amount;
        string _tokenType;
        uint _blockTimestamp;
    }

    struct ContractStruct {
        IERC20 _token1Contract;
        uint _token1Decimals;
        IERC20 _token2Contract;
        uint _token2Decimals;
    }

    SwapStruct[] public swapStructArray;
    WithdrawStruct[] public withdrawStructArray;

    // mappings
    mapping(address => SwapStruct[]) public swapStructMapping;
    mapping(address => WithdrawStruct[]) public WithdrawStructMapping;
    mapping(address => bool) public signManagers;
    mapping(address => bool) public subAdmin;

    // events
    event WithdrawTransaction(
        address indexed  _to,
        ConversionType indexed _conversionType,
        uint amount
    );
    event SwapTransaction(
        address indexed  _from,
        ConversionType indexed  _conversionType,
        uint indexed _ratio,
        uint _sentAmount,
        uint receiveAmount
    );
    event NumeratorFeesUpdate(uint value);
    event DenominatorFeesUpdate(uint value);
    event UpdateSigner(address, bool);
    event UpdateSubAdmin(address, bool);
    event UpdateRatio(uint);
    event SwapEnabled(bool);
    event DelegateSwapEnabled(bool);

    constructor(
        address _token1Address,
        uint _token1Decimal,
        address _token2Address,
        uint _token2Decimal,
        uint _ratio,
        address _networkFeeWallet
    ) Ownable(msg.sender){
        contractData = ContractStruct(
            IERC20(_token1Address),
            _token1Decimal,
            IERC20(_token2Address),
            _token2Decimal
        );
        signManagers[msg.sender] = true;
        swapRatio = _ratio;
        networkFeeWallet = _networkFeeWallet;
    }


    modifier swapIsEnabled() {
        require(swapWithSignatureEnabled, "Swapping is currently disabled");
        _;
    }
    modifier onlySubAdminOrOwner() {
        require(
            subAdmin[msg.sender] || msg.sender == owner(),
            "Only owner and sub admin can call this function"
        );
        _;
    }

    modifier delegateSwapModifier() {
        require(
            delegateSwapWithSignatureEnabled,
            "Delegate swap with signature is currently disabled"
        );
        _;
    }

    modifier onlySigner(){
        require(
            isSigner(msg.sender) || msg.sender == owner(),
            "Only Signer and owner is allowed"
        );
        _;
    }

    /**
     * @dev Allows the owner to withdraw a specified amount of tokens to another address.
     * @param _to The address to withdraw the tokens to.
     * @param _type The type of withdrawal.
     * @param _amount The amount of tokens to withdraw.
     */

    function withdrawToAnother(
        address _to,
        ConversionType _conversionType,
        uint _amount
    ) public onlyOwner {
        require(_to != address(0), "Invalid address");
        _withdraw(_to, _conversionType, _amount);
    }

    /**
     *
     * @dev Function to perform a swap with signature operation.
     * @param _signature The signature used to verify the swap.
     * @param _ratio The conversion ratio for the swap.
     * @param _amount The amount of tokens to be swapped.
     * @param _conversionType The type of conversion for the swap.
     */
    function swap(
        bytes memory _signature,
        uint256 _ratio,
        uint256 _amount,
        ConversionType _conversionType
    ) public swapIsEnabled {
        bytes32 message = swapProof(
            _ratio,
            _amount,
            _conversionType,
            msg.sender
        );
        address signerAddress = getSigner(message, _signature);
        require(signerAddress != address(0), "Invalid signer address");
        require(_amount > 0, "Invalid amount");
        require(isSigner(signerAddress), "Invalid signer address");
        uint fees = feesCalculate(_amount);
        uint remainingTokenAmount = SafeMath.sub(_amount, fees);
        _swap(msg.sender,_ratio, _conversionType, remainingTokenAmount, _amount, fees);
    }

    /**
     * @dev Function to perform a swap without signature operation.
     * @param _amount The amount of tokens to be swapped.
     * @param _conversionType The type of conversion for the swap.
     */
    function swapDirect(
        uint256 _amount,
        ConversionType _conversionType
    ) public {
        require(_amount > 0, "Invalid amount");
        uint fees = feesCalculate(_amount);
        uint remainingTokenAmount = SafeMath.sub(_amount, fees);
        _swap(msg.sender,swapRatio, _conversionType, remainingTokenAmount, _amount, fees);
    }

    /**
     * @dev Function to delegate a swap operation with a signature.
     * @param signature The signature used to verify the swap.
     * @param amount The amount of tokens to be swapped.
     * @param conversionType The type of conversion for the swap.
     * @param networkFee The network fee associated with the swap.
     */
    function delegateSwapWithSignature(
        bytes memory _signature,
        uint _amount,
        ConversionType _conversionType,
        uint _networkFee,
        address _walletAddress
    ) public delegateSwapModifier onlySigner{
        bytes32 message = delgateSwapProof(
            _amount,
            _conversionType,
            _walletAddress,
            _networkFee
        );
        address signerAddress = getSigner(message, _signature);
        require(
            signerAddress == _walletAddress,
            "Invalid user address"
        );
        uint remToken = SafeMath.sub(_amount, _networkFee);
        uint fees = feesCalculate(remToken);
        uint remainingTokenAmount = SafeMath.sub(remToken, fees);
        _swap(_walletAddress, swapRatio, _conversionType, remainingTokenAmount, _amount, fees);
        if (_conversionType == ConversionType.token1) {
            SafeERC20.safeTransfer(
                contractData._token2Contract,
                networkFeeWallet,
                _networkFee
            );
        }
        if (_conversionType == ConversionType.token2) {
            SafeERC20.safeTransfer(
                contractData._token1Contract,
                networkFeeWallet,
                _networkFee
            );
        }
    }

    /**
     * @dev Function to delegate a swap operation without a signature.
     * @param signature The signature used to verify the swap.
     * @param amount The amount of tokens to be swapped.
     * @param conversionType The type of conversion for the swap.
     * @param networkFee The network fee associated with the swap.
     */
    function delegateswap(
        bytes memory _signature,
        address _walletAddress, 
        uint256 _amount,
        ConversionType _conversionType,
        uint _networkFee
    ) public  onlySigner {
        require(_amount > 0, "Invalid amount");
        bytes32 message = delgateSwapProof(
            _amount,
            _conversionType,
            _walletAddress,
            _networkFee
        );
        address signerAddress = getSigner(message, _signature);
        require(
            signerAddress == _walletAddress,
            "Invalid user address"
        );
        uint remToken = SafeMath.sub(_amount, _networkFee);//4877
        uint fees = feesCalculate(remToken);
        uint remainingTokenAmount = SafeMath.sub(remToken, fees);

        _swap(_walletAddress, swapRatio, _conversionType, remainingTokenAmount, _amount, fees);
        if (_conversionType == ConversionType.token1) {
            SafeERC20.safeTransfer(
               contractData._token2Contract,
                networkFeeWallet,
                _networkFee
            );
        }
        if (_conversionType == ConversionType.token2) {
            SafeERC20.safeTransfer(
                contractData._token1Contract,
                networkFeeWallet,
                _networkFee
            );
        }
    }

    /**
     * @dev Internal function to perform the swap operation.
     * @param _swapRatio The conversion ratio for the swap.
     * @param _conversionType The type of conversion for the swap.
     * @param _remainingTokenAmount The remaining amount of tokens after deducting fees and network fees.
     * @param _amount The total amount of tokens to be swapped.
     * @param _fees The fees associated with the swap
     */
    function _swap(
        address _walletAddress,
        uint _swapRatio,
        ConversionType _conversionType,
        uint _remainingTokenAmount,
        uint _amount,
        uint _fees
    ) internal {
        if (_conversionType == ConversionType.token1) {
            require(
                contractData._token2Contract.allowance(
                    _walletAddress,
                    address(this)
                ) >= _amount,
                "Insufficient allowance for this transaction.Please approve a higher allowance."
            );
            require(
                contractData._token2Contract.balanceOf(_walletAddress) >= _amount,
                "Insufficient balance"
            );
            uint token2BaseUnits = SafeMath.mul(_remainingTokenAmount, (10 ** contractData._token2Decimals));
            uint token1Amount = SafeMath.div(SafeMath.div(SafeMath.mul(token2BaseUnits, 100), swapRatio), (10 ** contractData._token2Decimals));
            require(
                contractData._token1Contract.balanceOf(address(this)) >=
                    token1Amount,
                "Insufficient balance for swap"
            );

            SwapStruct memory swapValues = SwapStruct(
                _walletAddress,
                "token2",
                "token1",
                _amount,
                _swapRatio,
                token1Amount
            );
            swapStructMapping[_walletAddress].push(swapValues);

            SafeERC20.safeTransferFrom(
                contractData._token2Contract,
                _walletAddress,
                address(this),
                _amount
            );
            SafeERC20.safeTransfer(
                contractData._token1Contract,
                _walletAddress,
                token1Amount
            );
            SafeERC20.safeTransfer(
                contractData._token2Contract,
                address(this),
                _fees
            );
            emit SwapTransaction(
                _walletAddress,
                _conversionType,
                swapRatio,
                token1Amount,
                _amount
            );
        }
        if (_conversionType == ConversionType.token2) {
            require(
                contractData._token1Contract.allowance(
                   _walletAddress,
                    address(this)
                ) >= _amount,
                "Insufficient allowance for this transaction.Please approve a higher allowance."
            );
            require(
                contractData._token1Contract.balanceOf(_walletAddress) >= _amount,
                "Insufficient balance"
            );
            uint token1BaseUnits = SafeMath.mul(_remainingTokenAmount, (10 ** contractData._token1Decimals));
            uint token2Amount = SafeMath.div(SafeMath.div(SafeMath.mul(token1BaseUnits,swapRatio), 100),(10 ** contractData._token1Decimals));

            require(
                contractData._token2Contract.balanceOf(address(this)) >=
                    token2Amount,
                "Insufficient balance for swap"
            );

            SwapStruct memory swapValues = SwapStruct(
                _walletAddress,
                "token1",
                "token2",
                _amount,
                _swapRatio,
                token2Amount
            );
            swapStructMapping[_walletAddress].push(swapValues);

            SafeERC20.safeTransferFrom(
                contractData._token1Contract,
               _walletAddress,
                address(this),
                _amount
            );
            SafeERC20.safeTransfer(
                contractData._token2Contract,
                _walletAddress,
                token2Amount
            );
            SafeERC20.safeTransfer(
                contractData._token1Contract,
                address(this),
                _fees
            );
            emit SwapTransaction(
                _walletAddress,
                _conversionType,
                _swapRatio,
                token2Amount,
                _amount
            );
        }
    }

    /**
     * @dev Internal function to withdraw tokens to a specified address.
     * @param _to The address to which tokens will be withdrawn.
     * @param _conversionType The type of conversion for the withdrawal.
     * @param _amount The amount of tokens to be withdrawn.
     */
    function _withdraw(
        address _to,
        ConversionType _conversionType,
        uint _amount
    ) internal {
        if (_conversionType == ConversionType.token1) {
            require(
                contractData._token1Contract.balanceOf(address(this)) > _amount,
                "Insufficient token1 balance"
            );
            WithdrawStruct memory withdrawValues = WithdrawStruct(
                _to,
                _amount,
                "token1",
                block.timestamp
            );

            WithdrawStructMapping[msg.sender].push(withdrawValues);
            SafeERC20.safeTransfer(contractData._token1Contract, _to, _amount);
        }
        if (_conversionType == ConversionType.token2) {
            require(
                contractData._token2Contract.balanceOf(address(this)) > _amount,
                "Insufficient token2 balance"
            );
            WithdrawStruct memory withdrawValues = WithdrawStruct(
                _to,
                _amount,
                "token2",
                block.timestamp
            );
            WithdrawStructMapping[msg.sender].push(withdrawValues);
            SafeERC20.safeTransfer(contractData._token2Contract, _to, _amount);
        }
        emit WithdrawTransaction(_to, _conversionType, _amount);
    }

    /**
     * @dev External function to retrieve the current balance of token1 held by the contract.
     * @return The current balance of token1.
     */
    function token1Balance() external view returns (uint) {
        return contractData._token1Contract.balanceOf(address(this));
    }

    /**
     * @dev External function to retrieve the current balance of token2 held by the contract.
     * @return The current balance of token2.
     */
    function token2Balance() external view returns (uint) {
        return contractData._token2Contract.balanceOf(address(this));
    }

    /**
     * @dev External function to retrieve an array of swap transaction structs.
     * @return An array of swap transaction structs.
     */
    function getSwapStructArray() external view returns (SwapStruct[] memory) {
        return swapStructMapping[msg.sender];
    }

    /**
     * @dev External function to retrieve an array of withdrawal transaction structs.
     * @return An array of withdrawal transaction structs.
     */
    function getWithdrawStructArray()
        external
        view
        returns (WithdrawStruct[] memory)
    {
        return withdrawStructArray;
    }

    /**
     * @dev Function to generate a proof for a swap operation.
     * @param ratio The conversion ratio for the swap.
     * @param amount The amount of tokens to be swapped.
     * @param conversionType The type of conversion for the swap.
     * @param receiver The receiver address for the swap.
     * @return The generated message hash for the swap proof.
     */
    function swapProof(
        uint256 _ratio,
        uint _amount,
        ConversionType _conversionType,
        address _receiver
    ) public pure returns (bytes32 message) {
        message = keccak256(
            abi.encode(_ratio, _amount, _conversionType, _receiver)
        );
    }

    /**
     * @dev Generates a proof message for delegating a swap.
     * @param _amount The amount of tokens to be swapped.
     * @param _conversionType The type of conversion being performed.
     * @param _receiver The address of the recipient who will receive the swapped tokens.
     * @param _networkFee The amount of network fee associated with the swap.
     * @return message The generated proof message, a hash of the provided parameters.
     */
    function delgateSwapProof(
        uint _amount,
        ConversionType _conversionType,
        address _receiver,
        uint _networkFee
    ) public pure returns (bytes32 message) {
        message = keccak256(
            abi.encode(_amount, _conversionType, _receiver, _networkFee)
        );
    }

    /**
     * @dev Function to retrieve the signer address from a message hash and signature.
     * @param _message The message hash for the swap.
     * @param _signature The signature used to verify the swap.
     * @return The address of the signer.
     */
    function getSigner(
        bytes32 _message,
        bytes memory signature
    ) public pure returns (address) {
        _message = ECDSA.toEthSignedMessageHash(_message);
        return ECDSA.recover(_message, signature);
    }

    /**
     * @dev Function to check if an address is authorized as a signer.
     * @param _signer The address to check.
     * @return True if the address is authorized as a signer, false otherwise.
     */
    function isSigner(address _signer) public view returns (bool) {
        return signManagers[_signer];
    }

    /**
     * @dev Function to update the authorization status of a signer address.
     * @param _address The address of the signer to update.
     * @param _value The new authorization status.
     * Requirements:
     * - Only the owner or sub-admin can call this function.
     */
    function updateSigner(
        address _address,
        bool _value
    ) external onlySubAdminOrOwner {
        require(signManagers[_address] != _value, "Already exixst");
        signManagers[_address] = _value;
        emit UpdateSigner(_address, _value);
    }

    /**
     * @dev Function to update the numerator value for fee calculation.
     * @param _value The new numerator value.
     * Requirements:
     * - Only the owner or sub-admin can call this function.
     */
    function updateNumerator(uint _value) external onlySubAdminOrOwner {
        numerator = _value;
        emit NumeratorFeesUpdate(_value);
    }

    /** 
     * @dev Function to update the denominator value for fee calculation.
     * @param _value The new denominator value.
     * Requirements:
     * - Only the owner or sub-admin can call this function.
     */
    function updateDenominator(uint _value) external onlySubAdminOrOwner {
        denominator = _value;
        emit DenominatorFeesUpdate(_value);
    }

    /**
     * @dev External function to retrieve the current numerator value used for fee calculation.
     * @return The current numerator value.
     */
    function getNumerator() external view returns (uint) {
        return numerator;
    }

    /**
     * @dev External function to retrieve the denominator value used for fee calculation.
     * @return The current denominator value.
     */
    function getDenominator() external view returns (uint) {
        return denominator;
    }

    /**
     * @dev Function to calculate fees based on the provided amount.
     * @param _amount The amount for which fees are to be calculated.
     * @return The calculated fees.
     */
    function feesCalculate(uint _amount) public view returns (uint) {
        return SafeMath.div(SafeMath.div(SafeMath.mul(_amount,numerator), denominator), 100);
    }

    /**
     * @dev Function to update the sub-admin authorization status.
     * @param _address The address of the sub-admin to update.
     * @param _value The new authorization status.
     * Requirements:
     * - Only the contract owner can call this function.
     */

    function updateSubAdmin(address _address, bool _value) external onlyOwner {
        require(subAdmin[_address] != _value, "Already exists");
        subAdmin[_address] = _value;
        emit UpdateSubAdmin(_address, _value);
    }

    /**
     * @dev Function to update the swap ratio.
     * @param _value The new swap ratio value.
     * Requirements:
     * - Only the contract owner or sub-admin can call this function.
     */

    function updateRatio(uint _value) external onlySubAdminOrOwner {
        swapRatio = _value;
        emit UpdateRatio(_value);
    }

    /**
     * @dev External function to retrieve the current swap ratio.
     * @return The current swap ratio value.
     */

    function getRatio() external view returns (uint) {
        return swapRatio;
    }

    /**
     * @dev Function to update the swap toggle to enable or disable swapping.
     * @param _value The new value to set for swapEnabled.
     * Requirements:
     * - No specific requirements.
     */
    function updateSwapToggle(bool _value) external onlySubAdminOrOwner {
        require(swapWithSignatureEnabled != _value, "Already exists");
        swapWithSignatureEnabled = _value;
        emit SwapEnabled(_value);
    }

    /**
     * @dev Function to update the delegate swap toggle to enable or disable swapping.
     * @param _value The new value to set for swapEnabled.
     * Requirements:
     * - No specific requirements.
     */
    function updateDelegateSwapToggle(bool _value) external onlySubAdminOrOwner {
        require(delegateSwapWithSignatureEnabled != _value, "Already exist");
        delegateSwapWithSignatureEnabled = _value;
        emit DelegateSwapEnabled(_value);
    }

    /**
     * @dev Updates the contract data for the first  token instance.
     * @param _address The address of the  token contract to be assigned to `_token1Contract`.
     * @param _value The decimal value of the  token to be assigned to `_token1Decimals`.
     */
    function updateToken1Instance(address _address, uint _value) external onlySubAdminOrOwner {
        contractData._token1Contract = IERC20(_address);
        contractData._token1Decimals = _value;
    }

    /**
     * @dev Updates the contract data for the second  token instance.
     * @param _address The address of the  token contract to be assigned to `_token2Contract`.
     * @param _value The decimal value of the  token to be assigned to `_token2Decimals`.
     */
    function updateToken2Instance(address _address, uint _value) external onlySubAdminOrOwner {
        contractData._token2Contract = IERC20(_address);
        contractData._token2Decimals = _value;
    }

    /**
     * @dev Updates the network fee wallet.
     * @param _address The address of the  network fee wallet.`.
     */
    function updateNetworkFeeWallet(address _address) external onlySubAdminOrOwner {
        require(networkFeeWallet != _address, "Already exists");
        networkFeeWallet = _address
    }
}