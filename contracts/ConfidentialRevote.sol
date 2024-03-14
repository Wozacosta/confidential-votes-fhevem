// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity ^0.8.20;

import "fhevm/abstracts/Reencrypt.sol";
import "fhevm/lib/TFHE.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract ConfidentialRevote is Reencrypt, Ownable2Step {
    // State variables
    Poll[] public polls;
    // mapping(uint => mapping(address => Vote)) public votes;
    // mapping(uint => mapping(euint32 => uint)) public voteCounts; // poll -> options -> #nbOfVotes
    uint256 public pollCreationFee = 0.005 ether;
    uint256 public extraPollFee = 0.005 ether;
    uint256 public changeVoteFee = 0.005 ether;
    bool public paused = false;
    address public feeCollector;

    mapping(address => uint[]) public userPolls;
    // mapping(address => uint[]) public userVotes;

    mapping(uint => mapping(uint8 => euint32)) internal resultForPolls;
    mapping(uint => euint8[]) internal encOptionsForPolls;
    mapping(address => mapping(uint => euint8)) internal votesForPolls;

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
        address creator;
    }

    /// @dev A vote is associated with a poll and an option ID
    struct Vote {
        uint pollId;
        euint32 optionId;
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
    }

    /// @notice Updates the extra poll fee
    /// @param _newFee The new extra poll fee
    function updateExtraPollFee(uint256 _newFee) public onlyOwner {
        extraPollFee = _newFee;
    }

    /// @notice Updates the change vote fee
    /// @param _newFee The new change vote fee
    function updateChangeVoteFee(uint256 _newFee) public onlyOwner {
        changeVoteFee = _newFee;
    }

    /// @notice Create a new poll
    /// @param _question The poll question
    /// @param _options The poll options
    /// @dev  _options must have at least two choices and at most ten.
    function createPoll(string memory _question, string[] memory _options) public payable whenNotPaused {
        require(msg.value >= pollCreationFee, "Insufficient fee");
        require(_options.length >= 2 && _options.length <= 100, "There must be at least two and at most 100 options"); // Option validity check

        Poll memory newPoll = Poll(_question, _options, true, msg.sender);
        polls.push(newPoll);

        uint pollId = polls.length - 1;
        userPolls[msg.sender].push(pollId);

        for (uint8 i = 0; i < _options.length; i++) {
            resultForPolls[pollId][i] = TFHE.asEuint32(0);
            encOptionsForPolls[pollId].push(TFHE.asEuint8(i));
        }
    }

    /// @notice Retrieve vote by poll and voter
    /// @param _pollId The poll ID
    /// @param publicKey The voter's public key
    /// @return encrypted option
    function getVoteByPollAndVoter(uint _pollId, bytes32 publicKey) public view returns (bytes memory) {
        // TODO: could return -1 to indicate that no votes were made?
        require(TFHE.isInitialized(votesForPolls[msg.sender][_pollId]), "Didn't vote");
        return (TFHE.reencrypt(votesForPolls[msg.sender][_pollId], publicKey));
    }

    // NOTE: too much of a pain
    // function getPollIdsVotedOn(bytes32 publicKey) external view returns (bytes[] memory) {
    //     bytes[] memory pollsVotedOn = new bytes[](polls.length);
    //     for (uint8 i = 0; i < polls.length; i++) {
    //         bool hasVoted = TFHE.isInitialized(votesForPolls[msg.sender][i]);
    //         euint32 vote = TFHE.cmux(hasVoted, TFHE.votesForPolls[msg.sender][i], 50); //TFHE.asEuint32(50));
    //         pollsVotedOn[i] = TFHE.reencrypt(vote, publicKey);
    //     }
    //     // TFHE.reencrypt(TFHE.asEbool(true));
    //     return pollsVotedOn;
    //     // return TFHE.reencrypt(pollsVotedOn, publicKey);
    // }

    /// @notice Vote in a poll
    /// @param _pollId The poll ID
    /// @param _encryptedOptionId The chosen option ID (encrypted)
    function vote(
        uint _pollId,
        bytes calldata _encryptedOptionId
    ) public payable whenNotPaused pollExists(_pollId) pollIsActive(_pollId) {
        require(!TFHE.isInitialized(votesForPolls[msg.sender][_pollId]), "Double voting is not allowed");

        euint8 option = TFHE.asEuint8(_encryptedOptionId);
        votesForPolls[msg.sender][_pollId] = option;
        addToVoteResults(_pollId, option, TFHE.asEuint32(1));

        // Vote memory newVote = Vote(_pollId, _optionId, true);
        // votes[_pollId][msg.sender] = newVote;
        // voteCounts[_pollId][_optionId]++;
        // userVotes[msg.sender].push(_pollId);
    }

    /// @notice addToVoteResults
    /// @param _pollId The poll ID to end
    /// @param option option
    /// @param amount the amount
    function addToVoteResults(uint _pollId, euint8 option, euint32 amount) internal {
        for (uint8 i = 0; i < encOptionsForPolls[_pollId].length; i++) {
            // euint32 isOption = TFHE.asEuint32(TFHE.eq(option, encOptionsForPolls[_pollId][i]));
            ebool isOption = TFHE.eq(option, encOptionsForPolls[_pollId][i]);
            // TFHE.cmux(control, a, b);
            euint32 toAdd = TFHE.cmux(isOption, amount, TFHE.asEuint32(0));
            resultForPolls[_pollId][i] = TFHE.add(resultForPolls[_pollId][i], toAdd);
        }
    }

    function getResults(uint _pollId, bytes32 publicKey) public view returns (bytes[] memory) {
        bytes[] memory resultByOption = new bytes[](encOptionsForPolls[_pollId].length);
        for (uint8 i = 0; i < encOptionsForPolls[_pollId].length; i++) {
            resultByOption[i] = (TFHE.reencrypt(resultForPolls[_pollId][i], publicKey));
        }

        return resultByOption;
    }

    /// @notice End a poll
    /// @param _pollId The poll ID to end
    function endPoll(uint _pollId) public onlyPollOwnerOrContractOwner(_pollId) pollExists(_pollId) {
        polls[_pollId].active = false;
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

    // NOTE: use getResults(poll_id) instead
    // function getVoteCountByPollAndOption(uint _pollId, bytes calldata _encryptedOptionId) public view returns (uint) {
    //     euint32 _optionId = TFHE.asEuint32(_encryptedOptionId);
    //     return voteCounts[_pollId][_optionId];
    // }

    // TODO: use message.sender
    function getPollsByCreator(address user) external view returns (uint[] memory) {
        return userPolls[user];
    }
}
