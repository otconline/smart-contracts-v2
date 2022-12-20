pragma solidity 0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Moderators is Ownable {

    mapping(address => bool) public moderators;
    uint256 public totalModerators;

    event ModeratorAdded(address indexed moderator);
    event ModeratorRemoved(address indexed moderator);

    modifier onlyModerator() {
        require(moderators[msg.sender], "this function can be called by moderator only");
        _;
    }


    function addModerator(address _moderator) public onlyOwner {
        require(_moderator != address(0), "Can't be zero address");
        require(!moderators[_moderator], "moderator already exists");
        moderators[_moderator] = true;
        ++totalModerators;
        emit ModeratorAdded(_moderator);
    }

    function removeModerator(address _moderator) public onlyOwner {
        require(_moderator != address(0), "Can't be zero address");
        require(moderators[_moderator], "moderator not found");
        moderators[_moderator] = false;
        --totalModerators;
        emit ModeratorRemoved(_moderator);
    }
}