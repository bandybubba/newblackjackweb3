// File: contracts/BlackjackShoeVRF.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * Minimal "BlackjackShoeVRF" contract:
 *  - Single shoe
 *  - One game at a time
 *  - Chainlink VRF v2 for random seed
 *  - Off-chain shuffle + commit
 *  - Using CasinoChips ERC20 for bets
 *
 *  NOTE: We added a "mockFulfillRandomWords" for local testing only,
 *  since the "fulfillRandomWords" is internal and can't be called directly.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Updated Chainlink VRF imports (v0.8) with new file paths
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

contract BlackjackShoeVRF is VRFConsumerBaseV2, Ownable {
    // --------------------------------------------------
    // State Variables
    // --------------------------------------------------

    IERC20 public chipsToken; // Reference to CasinoChips token

    // Chainlink VRF
    VRFCoordinatorV2Interface public COORDINATOR;
    uint64 public subscriptionId;
    bytes32 public keyHash;
    uint32 public callbackGasLimit = 200000;
    uint16 public requestConfirmations = 3;
    uint256 public randomSeed;  
    uint256 public vrfRequestId;

    // Shoe data
    bytes32 public shoeCommit;  
    uint256 public shoeSize;    
    uint256 public shoePointer; 
    bool public shoeActive;     

    // Single game
    bool public gameInProgress;
    address public currentPlayer;
    uint256 public currentBet;

    // --------------------------------------------------
    // Events
    // --------------------------------------------------
    event RequestedRandomSeed(uint256 requestId);
    event ReceivedRandomSeed(uint256 randomSeed);
    event ShoeCommitted(bytes32 deckCommit, uint256 size);
    event GameStarted(address player, uint256 bet);
    event GameFinished(address player, uint256 bet, bool playerWon);

    // --------------------------------------------------
    // Constructor
    // --------------------------------------------------
    constructor(
        address chipsTokenAddress,
        address vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId
    )
        VRFConsumerBaseV2(vrfCoordinator)
        Ownable(msg.sender)
    {
        chipsToken = IERC20(chipsTokenAddress);

        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
    }

    // --------------------------------------------------
    // Chainlink VRF Functions
    // --------------------------------------------------
    /**
     * @dev Request a new random seed for shuffling a new shoe off-chain.
     */
    function requestNewRandomSeed() external onlyOwner {
        uint32 numWords = 1;
        vrfRequestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        emit RequestedRandomSeed(vrfRequestId);
    }

    /**
     * @dev The real VRF callback. Called by coordinator in production.
     * This is internal only, so we can't directly call it in tests.
     */
    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        randomSeed = randomWords[0];
        emit ReceivedRandomSeed(randomSeed);
    }

    /**
     * @dev Test-only function to simulate VRF's fulfillRandomWords,
     *      since we can't call an internal function externally.
     *      Remove or restrict in production.
     */
    function mockFulfillRandomWords(uint256 _requestId, uint256[] calldata randomWords) external onlyOwner {
        // Just call the internal function
        fulfillRandomWords(_requestId, randomWords);
    }

    // --------------------------------------------------
    // Shoe Management
    // --------------------------------------------------
    function commitShoe(bytes32 _shoeCommit, uint256 _shoeSize) external onlyOwner {
        require(randomSeed != 0, "No random seed yet");
        require(!gameInProgress, "Finish current game first");
        require(_shoeSize > 0, "Shoe size must be > 0");

        shoeCommit = _shoeCommit;
        shoeSize = _shoeSize;
        shoePointer = 0;
        shoeActive = true;
        gameInProgress = false;

        emit ShoeCommitted(_shoeCommit, _shoeSize);
    }

    // --------------------------------------------------
    // Game Flow: One Game at a Time
    // --------------------------------------------------
    function startGame(uint256 betAmount) external {
        require(shoeActive, "No active shoe");
        require(!gameInProgress, "Game in progress");
        require(betAmount > 0, "Bet must be > 0");

        bool success = chipsToken.transferFrom(msg.sender, address(this), betAmount);
        require(success, "Transfer failed");

        currentPlayer = msg.sender;
        currentBet = betAmount;
        gameInProgress = true;

        emit GameStarted(msg.sender, betAmount);
    }

    function finishGame(
        uint256 cardsUsed,
        bytes32 subDeckHash,
        bool playerWon
    ) external {
        require(gameInProgress, "No game in progress");
        require(msg.sender == currentPlayer, "Not your game");
        require(cardsUsed > 0, "No cards used?");
        require(shoePointer + cardsUsed <= shoeSize, "Not enough cards in shoe");
        require(subDeckHash != 0, "Invalid sub-deck hash");

        shoePointer += cardsUsed;

        if (playerWon) {
            uint256 payout = currentBet * 2;
            chipsToken.transfer(currentPlayer, payout);
        }

        emit GameFinished(currentPlayer, currentBet, playerWon);

        currentPlayer = address(0);
        currentBet = 0;
        gameInProgress = false;
    }

    // --------------------------------------------------
    // Admin Helpers
    // --------------------------------------------------
    function withdrawChips(address to, uint256 amount) external onlyOwner {
        chipsToken.transfer(to, amount);
    }

    function setVRFConfig(
        bytes32 _keyHash,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    ) external onlyOwner {
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
    }
}
