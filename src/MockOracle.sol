// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @notice Chainlink-compatible price feed stand-in for the demo.
/// Emits the EXACT Chainlink `AnswerUpdated` event (indexed current and
/// roundId, updatedAt in data) so the reactive contract reads it identically
/// to the real ETH/USD feed. The real feed will not move 0.5% on cue during
/// a 5-minute demo, so the demo drives this mock; SentinelReactive subscribes
/// to BOTH this mock and the real feed on Unichain Sepolia.
contract MockOracle {
    int256 public answer;
    uint80 public roundId;
    uint256 public updatedAt;
    address public owner;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    constructor(int256 initialPrice) {
        owner = msg.sender;
        answer = initialPrice;
        roundId = 1;
        updatedAt = block.timestamp;
    }

    function setPrice(int256 price) external {
        require(msg.sender == owner, "not owner");
        answer = price;
        roundId += 1;
        updatedAt = block.timestamp;
        emit AnswerUpdated(price, roundId, updatedAt);
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (roundId, answer, block.timestamp, updatedAt, roundId);
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function description() external pure returns (string memory) {
        return "Mock ETH / USD";
    }
}
