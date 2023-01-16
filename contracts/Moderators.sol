// SPDX-License-Identifier : MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Moderators is Ownable {

    /// @notice Map with all registered moderators
    /// @return bool (true moderator is registered, false is unknown)
    mapping(address => bool) public moderators;

    /// @notice count of total moderators
    /// @return uint256 total active moderators
    uint256 public totalModerators;


    /******************************** Modifiers ********************************/
    modifier onlyModerator() {
        require(moderators[msg.sender], "this function can be called by moderator only");
        _;
    }


    /******************************** Events ********************************/
    event ModeratorAdded(address indexed moderator);
    event ModeratorRemoved(address indexed moderator);


    /// @notice register new moderator (address)
    /// @dev can be called only by owner
    /// @param _moderator address of new moderator
    function addModerator(address _moderator) external onlyOwner {
        require(_moderator != address(0), "Can't be zero address");
        require(!moderators[_moderator], "moderator already exists");
        moderators[_moderator] = true;
        ++totalModerators;
        emit ModeratorAdded(_moderator);
    }

    /// @notice delete known moderator
    /// @dev can be called only by owner
    /// @param _moderator address of deleted moderator
    function removeModerator(address _moderator) external onlyOwner {
        require(_moderator != address(0), "Can't be zero address");
        require(moderators[_moderator], "moderator not found");
        moderators[_moderator] = false;
        --totalModerators;
        emit ModeratorRemoved(_moderator);
    }
}