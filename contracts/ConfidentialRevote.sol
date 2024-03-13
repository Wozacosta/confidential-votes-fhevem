// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity ^0.8.20;
import "hardhat/console.sol";

import "fhevm/abstracts/Reencrypt.sol";
import "fhevm/lib/TFHE.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract ConfidentialRevote is Reencrypt, Ownable2Step {
    // Events
    event PollCreated(uint indexed pollId, string question, string[] options);
    event Voted(uint indexed pollId, address indexed voter, uint optionId);
    event PollEnded(uint indexed pollId);
    event PollDeleted(uint indexed pollId); // Added PollDeleted Event
    event FeesUpdated(uint256 pollCreationFee, uint256 extraPollFee, uint256 changeVoteFee);

    // State variables
    Poll[] public polls;
    mapping(uint => mapping(address => Vote)) public votes;
    mapping(uint => mapping(uint => uint)) public voteCounts;
    uint256 public pollCreationFee = 0.005 ether;
    uint256 public extraPollFee = 0.005 ether;
    uint256 public changeVoteFee = 0.005 ether;
    bool public paused = false;
    address public feeCollector;

    mapping(address => euint32[]) public userPolls;
    mapping(address => euint32[]) public userVotes;

    /// @dev Modifiers to simplify requirements
    modifier pollExists(uint _pollId) {
        require(_pollId < polls.length, "Invalid poll ID");
        _;
    }

    modifier pollIsActive(uint _pollId) {
        require(polls[_pollId].active, "Poll is not active");
        _;
    }

    modifier onlyPollOwnerOrContractOwner(uint _pollId) {
        require(msg.sender == polls[_pollId].creator || msg.sender == owner(), "Not authorized");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    /// @dev A poll has a question, a list of options, an end time, and an active status
    struct Poll {
        string question;
        string[] options;
        bool active;
        uint256 endTime;
        address creator;
    }

    /// @dev A vote is associated with a poll and an option ID
    struct Vote {
        uint pollId;
        uint optionId;
        bool hasVoted;
    }

    /// @notice Constructor sets owner and fee collector
    constructor() Ownable(msg.sender) {
        feeCollector = msg.sender;
    }

    /// @notice Updates the fee collector address
    /// @param _feeCollector The new fee collector address
    function setFeeCollector(address _feeCollector) public onlyOwner {
        feeCollector = _feeCollector;
    }

    /// @notice Pause the contract in case of emergencies
    function pause() public onlyOwner {
        paused = true;
    }

    /// @notice Unpause the contract
    function unpause() public onlyOwner {
        paused = false;
    }

    /// @notice Kill the contract and send remaining funds to owner
    function kill() public onlyOwner {
        address payable ownerAddress = payable(owner());
        selfdestruct(ownerAddress);
    }

    /// @notice Withdraw the fees collected
    function withdrawFees() public onlyOwner {
        payable(feeCollector).transfer(address(this).balance);
    }

    /// @notice Updates the poll creation fee
    /// @param _newFee The new poll creation fee
    function updatePollCreationFee(uint256 _newFee) public onlyOwner {
        pollCreationFee = _newFee;
        emit FeesUpdated(pollCreationFee, extraPollFee, changeVoteFee);
    }

    /// @notice Updates the extra poll fee
    /// @param _newFee The new extra poll fee
    function updateExtraPollFee(uint256 _newFee) public onlyOwner {
        extraPollFee = _newFee;
        emit FeesUpdated(pollCreationFee, extraPollFee, changeVoteFee);
    }

    /// @notice Updates the change vote fee
    /// @param _newFee The new change vote fee
    function updateChangeVoteFee(uint256 _newFee) public onlyOwner {
        changeVoteFee = _newFee;
        emit FeesUpdated(pollCreationFee, extraPollFee, changeVoteFee);
    }

    /// @notice Create a new poll
    /// @param _question The poll question
    /// @param _options The poll options
    /// @param _duration The poll duration in seconds
    /// @dev _duration must be between 1 second and 1 week. _options must have at least two choices and at most ten.

    function createPoll(
        string memory _question,
        string[] memory _options,
        uint256 _duration
    ) public payable whenNotPaused {
        require(msg.value >= pollCreationFee, "Insufficient fee");
        require(_duration > 0 && _duration <= 604800, "Duration must be between 1 second and 1 week"); // Duration validity check
        require(_options.length >= 2 && _options.length <= 10, "There must be at least two and at most ten options"); // Option validity check

        uint256 endTime = block.timestamp + _duration;
        Poll memory newPoll = Poll(_question, _options, true, endTime, msg.sender);
        polls.push(newPoll);

        uint32 pollId = polls.length - 1;
        userPolls[msg.sender].push(pollId);

        emit PollCreated(pollId, _question, _options);
    }

    /// @notice Delete a poll
    /// @param _pollId The poll ID to delete
    /// @dev Only the poll creator or contract owner can delete a poll. The poll must be inactive to be deleted.
    function deletePoll(uint _pollId) public onlyPollOwnerOrContractOwner(_pollId) {
        require(!polls[_pollId].active, "Can't delete an active poll");

        delete polls[_pollId];
        emit PollDeleted(_pollId);
    }

    /// @notice Vote in a poll
    /// @param _pollId The poll ID
    /// @param _optionId The chosen option ID
    function vote(uint _pollId, uint _optionId) public payable whenNotPaused pollExists(_pollId) pollIsActive(_pollId) {
        require(!votes[_pollId][msg.sender].hasVoted, "Double voting is not allowed");

        Vote memory newVote = Vote(_pollId, _optionId, true);
        votes[_pollId][msg.sender] = newVote;
        voteCounts[_pollId][_optionId]++;
        userVotes[msg.sender].push(_pollId);
        console.log("voted %s with %s", _pollId, _optionId);

        emit Voted(_pollId, msg.sender, _optionId);
    }

    /// @notice Change vote in a poll
    /// @param _pollId The poll ID
    /// @param _newOptionId The new chosen option ID
    /// @dev User must pay the changeVoteFee to change their vote. Poll must be active.
    function changeVote(
        uint _pollId,
        uint _newOptionId
    ) public payable whenNotPaused pollExists(_pollId) pollIsActive(_pollId) {
        require(msg.value >= changeVoteFee, "Insufficient fee for changing vote");
        require(votes[_pollId][msg.sender].hasVoted, "You must have voted before to change your vote");

        uint oldOptionId = votes[_pollId][msg.sender].optionId;
        votes[_pollId][msg.sender].optionId = _newOptionId;
        voteCounts[_pollId][oldOptionId]--;
        voteCounts[_pollId][_newOptionId]++;

        emit Voted(_pollId, msg.sender, _newOptionId);
    }

    /// @notice End a poll
    /// @param _pollId The poll ID to end
    function endPoll(uint _pollId) public onlyPollOwnerOrContractOwner(_pollId) pollExists(_pollId) {
        require(block.timestamp >= polls[_pollId].endTime, "Poll has not ended yet");

        polls[_pollId].active = false;
        emit PollEnded(_pollId);
    }

    /// @notice Retrive all polls
    /// @return Poll array
    function getPolls() public view returns (Poll[] memory) {
        return polls;
    }

    /// @notice Retrieve poll by its ID
    /// @param _pollId The poll ID
    /// @return Poll object
    function getPollById(uint _pollId) public view returns (Poll memory) {
        return polls[_pollId];
    }

    function getVoteCountByPollAndOption(uint _pollId, uint _optionId) public view returns (uint) {
        return voteCounts[_pollId][_optionId];
    }

    /// @notice Retrieve vote by poll and voter
    /// @param _pollId The poll ID
    /// @param _voter The voter's address
    /// @return Vote object
    function getVoteByPollAndVoter(uint _pollId, address _voter) public view returns (Vote memory) {
        return votes[_pollId][_voter];
    }

    function getPollsByCreator(address user) external view returns (uint[] memory) {
        return userPolls[user];
    }

    function getPollIdsVotedOn(address user) external view returns (uint[] memory) {
        return userVotes[user];
    }
}
