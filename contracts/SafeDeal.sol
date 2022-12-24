pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Moderators.sol";


// final version works with BUSD token
contract SafeDeal is Moderators {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    struct Deal {
        address seller;
        address buyer;
        address referer;
        uint256 amount;
        uint256 serviceFee;
        uint256 referrerFee;
        uint256 totalAmount;
        bool isActive;
    }

    // @notice Signer address that used for checking EDSCA
    // @dev Can be changed by owner
    // @return address of signer
    address public signer;

    // @notice Returns address of token that used in deals (USDT,BUSD)
    // @dev Initialize only during deployment, can't be changed
    // @return address of used token
    IERC20 private immutable _token;

    // @notice Map with all deals and their status
    // @return struct Deal with all info inside
    mapping(uint256 => Deal) private _deals;

    // @notice Map with all deals id's
    // @dev Used to check during creating position on unique id
    // @return bool that indicates if id used or not
    mapping(uint256 => bool) private _dealIds;

    // @notice Total amount of tokens locked in active trades on contract
    uint256 private _totalBalance;

    /******************************** Modifiers ********************************/
    modifier notRegisteredId(uint256 id){
        require(!_dealIds[id], "Deal id is used");
        _;
        _dealIds[id] = true;
    }


    /******************************** Events ********************************/
    event Started(uint256 indexed id, Deal deal);
    event Completed(uint256 indexed id, Deal deal);
    event Cancelled(uint256 indexed id, Deal deal);
    event Withdraw(uint256 balanceBefore, uint256 balanceAfter);

    constructor() {
        _token = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    }

    // @notice Creates new offer, checks on unique, check sign, transfer money from user to contract and lock it.
    // @dev Id generates off-chain, all info signs by signer, id should be unique
    // @dev referrer and referrerFee can't be zero in case of trade without referrer
    // @param id unique id of trade
    // @param seller address that sells
    // @param buyer address that buys
    // @param referrer address of referrer (can be zero address)
    // @param amount of IERC20 tokens without fee
    // @param serviceFee fee of service
    // @param referrerFee fee of referrer (used only if referrer not zero)
    function start(
        uint256 id,
        address seller,
        address referrer,
        uint256 amount,
        uint256 serviceFee,
        uint256 referrerFee,
        bytes memory signature
    ) public notRegisteredId(id) {
        bytes32 hash = ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(id, seller, referrer, amount, serviceFee, referrerFee)));
        require(hash.recover(signature) == signer, "invalid sign");
        require(msg.sender != seller, "Seller can't be buyer");
        require(seller != address(0), "Seller can't be zero");
        require(amount != 0, "Amount can't be zero");

        // @notice this is crucial to avoid errors during closing trades
        if (referrerFee != 0) {
            require(referrer != address(0), "referrer can't be zero");
        }


        uint256 totalAmount = amount + serviceFee + referrerFee;
        Deal memory deal = Deal({
        seller : seller,
        buyer : msg.sender,
        referer : referrer,
        amount : amount,
        serviceFee : serviceFee,
        referrerFee : referrerFee,
        totalAmount : totalAmount,
        isActive : true
        });

        _deals[id] = deal;

        _token.safeTransferFrom(msg.sender, address(this), totalAmount);
        _totalBalance += totalAmount;
        emit Started(id, deal);
    }

    // @notice Produce active trade, transfer tokens to seller and referrer (in case if it exist)
    // @dev this function can be called only by buyer
    // @param id unique id of deal
    function completeByBuyer(uint256 id) public {
        Deal memory deal = _deals[id];
        require(deal.buyer == msg.sender, "this function can be called by buyer only");
        closeDeal(id, true);
        emit Completed(id, deal);
    }

    // @notice Produce active trade, transfer tokens to seller and referrer (in case if it exist)
    // @dev this function can be called only by moderator
    // @param id unique id of deal
    function completeByModerator(uint256 id) public onlyModerator {
        Deal memory deal = _deals[id];
        closeDeal(id, true);
        emit Completed(id, deal);
    }

    // @notice Produce active trade, transfer tokens to buyer
    // @dev this function can be called only by moderator
    // @param id unique id of deal
    function cancelByModerator(uint256 id) public onlyModerator {
        Deal memory deal = _deals[id];
        closeDeal(id, false);
        emit Cancelled(id, deal);
    }

    // @notice close deal,transfer money according to boolean and change state
    // @param id unique id of deal
    // @param isSuccess bool that shows status of deal (true-success, false-revert)
    function closeDeal(uint256 id, bool isSuccess) internal {
        Deal storage deal = _deals[id];
        require(deal.isActive, "closed trade");

        if (isSuccess) {
            // payment to seller
            _token.transfer(deal.seller, deal.amount);

            // payment to referer
            if (deal.referrerFee > 0) {
                _token.transfer(deal.referer, deal.referrerFee);
            }
        } else {
            // payment back to buyer
            _token.transfer(deal.buyer, deal.totalAmount);
        }

        deal.isActive = false;
        _totalBalance -= deal.totalAmount;
    }

    /******************************** Owner Functions ********************************/

    // @notice change signer that using in ECDSA
    // @param _signer address of new signer
    function setSigner(address _signer) public onlyOwner {
        signer = _signer;
    }

    // @notice get amount of tokens that locked in active trades
    // @dev this function require signature, as this information should be visible only for owner
    // @param _text string that used for checking sign
    // @param _signature bytes to check signer
    function getBalance(string memory _text, bytes memory _signature) public view returns (uint256) {
        bytes32 hash32 = ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(_text)));
        if (hash32.recover(_signature) == owner()) {
            return _token.balanceOf(address(this)) - _totalBalance;
        } else {
            return 0;
        }
    }

    // @notice withdraw service fee from contract
    // @dev can be called only by owner
    // @param wallet address of user to withdraw
    // @param value amount of fee to withdraw
    function withdraw(address wallet, uint256 value) onlyOwner public {
        require(wallet != address(0), "Can't be zero address");
        uint balance = _token.balanceOf(address(this)) - _totalBalance;
        require(balance >= value, "insufficient tokens");

        _token.transfer(wallet, value);
        emit Withdraw(balance, balance - value);
    }
}
