// SPDX-License-Identifier : MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Moderators.sol";


// final version works with BUSD token
contract SafeDeal is Moderators, EIP712("SafeDeal", "1.0") {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    struct Deal {
        address seller;
        address buyer;
        address referrer;
        uint256 amount;
        uint256 serviceFee;
        uint256 referrerFee;
        uint256 totalAmount;
        bool isActive;
    }

    /// @notice Signer address that used for checking EDSCA
    /// @dev Can be changed by owner
    /// @return address of signer
    address public signer;

    /// @notice Returns address of token that used in deals (USDT,BUSD)
    /// @dev Initialize only during deployment, can't be changed
    IERC20 private immutable _token;

    /// @notice Map with all deals and their status
    mapping(uint256 => Deal) private _deals;

    /// @notice Map with all deals id's
    /// @dev Used to check during creating position on unique id
    mapping(uint256 => bool) private _dealIds;

    /// @notice Total amount of tokens locked in active trades on contract
    uint256 private _totalBalance;

    /******************************** Modifiers ********************************/
    modifier notRegisteredId(uint256 id){
        require(!_dealIds[id], "Deal id is used");
        _;
    }


    /******************************** Events ********************************/
    event Started(uint256 indexed id, Deal deal);
    event Completed(uint256 indexed id, Deal deal);
    event Cancelled(uint256 indexed id, Deal deal);
    event Withdraw(uint256 balanceBefore, uint256 balanceAfter);
    event NewSigner(address indexed signer);

    /// @param token address of token
    constructor(address token) {
        require(token != address(0),"Can't be zero");
        _token = IERC20(token);
    }

    /// @notice Creates new offer, checks on unique, check sign, transfer money from user to contract and lock it.
    /// @dev Id generates off-chain, all info signs by signer, id should be unique
    /// @dev referrer and referrerFee can't be zero in case of trade without referrer
    /// @param id unique id of trade
    /// @param seller address that sells
    /// @param referrer address of referrer (can be zero address)
    /// @param amount of IERC20 tokens without fee
    /// @param serviceFee fee of service
    /// @param referrerFee fee of referrer (used only if referrer not zero)
    function start(
        uint256 id,
        address seller,
        address referrer,
        uint256 amount,
        uint256 serviceFee,
        uint256 referrerFee,
        bytes memory signature
    ) external notRegisteredId(id) {
        bytes32 hash = keccak256(abi.encode(
                keccak256("SafeDeal(uint256 id,address seller,address referrer,uint256 amount,uint256 serviceFee,uint256 referrerFee)"),
                id,
                seller,
                referrer,
                amount,
                serviceFee,
                referrerFee
            ));

        require(_hashTypedDataV4(hash).recover(signature) == signer, "invalid sign");

        require(msg.sender != seller, "Seller can't be buyer");
        require(seller != address(0), "Seller can't be zero");
        require(amount != 0, "Amount can't be zero");

        /// @notice this is crucial to avoid errors during closing trades
        if (referrerFee != 0) {
            require(referrer != address(0), "referrer can't be zero");
        }


        uint256 totalAmount = amount + serviceFee + referrerFee;
        Deal memory deal = Deal({
        seller : seller,
        buyer : msg.sender,
        referrer : referrer,
        amount : amount,
        serviceFee : serviceFee,
        referrerFee : referrerFee,
        totalAmount : totalAmount,
        isActive : true
        });

        _deals[id] = deal;
        _dealIds[id] = true;

        _totalBalance += totalAmount;
        emit Started(id, deal);

        _token.safeTransferFrom(msg.sender, address(this), totalAmount);
    }

    /// @notice Produce active trade, transfer tokens to seller and referrer (in case if it exist)
    /// @dev this function can be called only by buyer
    /// @param id unique id of deal
    function completeByBuyer(uint256 id) external {
        Deal memory deal = _deals[id];
        require(deal.buyer == msg.sender, "this function can be called by buyer only");
        emit Completed(id, deal);
        closeDeal(id, true);
    }

    /// @notice Produce active trade, transfer tokens to seller and referrer (in case if it exist)
    /// @dev this function can be called only by moderator
    /// @param id unique id of deal
    function completeByModerator(uint256 id) external onlyModerator {
        Deal memory deal = _deals[id];
        emit Completed(id, deal);
        closeDeal(id, true);
    }

    /// @notice Produce active trade, transfer tokens to buyer
    /// @dev this function can be called only by moderator
    /// @param id unique id of deal
    function cancelByModerator(uint256 id) external onlyModerator {
        Deal memory deal = _deals[id];
        emit Cancelled(id, deal);
        closeDeal(id, false);
    }

    /// @notice close deal,transfer money according to boolean and change state
    /// @param id unique id of deal
    /// @param isSuccess bool that shows status of deal (true-success, false-revert)
    function closeDeal(uint256 id, bool isSuccess) internal {
        Deal storage deal = _deals[id];
        require(deal.isActive, "closed trade");

        deal.isActive = false;
        _totalBalance -= deal.totalAmount;


        if (isSuccess) {
            // payment to seller
            _token.safeTransfer(deal.seller, deal.amount);

            // payment to referrer
            if (deal.referrerFee > 0) {
                _token.safeTransfer(deal.referrer, deal.referrerFee);
            }
        } else {
            // payment back to buyer
            _token.safeTransfer(deal.buyer, deal.totalAmount);
        }

    }

    /******************************** Owner Functions ********************************/

    /// @notice change signer that using in ECDSA
    /// @param _signer address of new signer
    function setSigner(address _signer) external onlyOwner {
        require(_signer != address(0), "Can't be zero");
        signer = _signer;
        emit NewSigner(_signer);
    }

    /// @notice get amount of tokens (service fee)
    /// @return uint256 amount of tokens
    function getBalance() external view returns (uint256) {
        return _token.balanceOf(address(this)) - _totalBalance;
    }

    /// @notice withdraw service fee from contract
    /// @dev can be called only by owner
    /// @param wallet address of user to withdraw
    /// @param value amount of fee to withdraw
    function withdraw(address wallet, uint256 value) external onlyOwner {
        require(wallet != address(0), "Can't be zero address");
        uint256 balance = _token.balanceOf(address(this)) - _totalBalance;
        require(balance >= value, "insufficient tokens");

        emit Withdraw(balance, balance - value);

        _token.safeTransfer(wallet, value);
    }
}
