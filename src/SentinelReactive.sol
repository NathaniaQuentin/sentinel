// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @notice SentinelReactive — Lasna reactive contract (Omni API).
/// Subscribes to Chainlink ETH/USD `AnswerUpdated` events on Unichain
/// Sepolia from BOTH the MockOracle (demo harness) and the real feed, plus
/// `OrderOpened` / `OrderCancelled` events from SentinelVault. On every
/// price update it checks its own order book:
///   - stop-loss hit  -> exit 100% (kind 1)
///   - trailing stop hit -> exit 100% (kind 4)
///   - TP2 hit        -> exit the rest (kind 3)
///   - TP1 hit        -> exit 50% (kind 2)
/// Each exit is one callback to the vault (one order per callback, so the
/// vault's `executeExit` stays lean). Fills are applied optimistically in
/// this contract's book when the callback is requested, so a duplicate
/// trigger can never double-fill; the vault additionally clamps to the
/// remaining amount, so a late callback is a harmless no-op.
contract SentinelReactive is AbstractReactive {
    uint256 public constant DEST_CHAIN_ID = 1301; // Unichain Sepolia
    uint64 private constant CALLBACK_GAS_LIMIT = 1_000_000;
    uint256 private constant MAX_SCAN = 50; // orders scanned per price event

    uint256 private immutable _answerUpdatedTopic0;
    uint256 private immutable _orderOpenedTopic0;
    uint256 private immutable _orderCancelledTopic0;

    address public immutable mockOracle;
    address public immutable realFeed;
    address public vault;
    address public callback; // == vault; the callback recipient
    address public owner;
    int256 public lastPrice;

    struct TrackedOrder {
        address user;
        uint256 amount;
        uint256 remaining;
        int256 stopLoss;
        int256 tp1;
        int256 tp2;
        uint256 trailingBps;
        int256 highWater;
        bool tp1Done;
        bool open;
    }

    mapping(uint256 => TrackedOrder) public tracked;
    uint256[] public openIds;

    event PriceSeen(int256 price, uint256 updatedAt, address feed);
    event OrderTracked(uint256 indexed orderId, address indexed user);
    event OrderClosed(uint256 indexed orderId);
    event ExitRequested(uint256 indexed orderId, uint8 exitKind, uint256 exitAmount, uint256 price);

    constructor(address mockOracle_, address realFeed_) payable {
        owner = msg.sender;
        mockOracle = mockOracle_;
        realFeed = realFeed_;
        _answerUpdatedTopic0 = uint256(keccak256("AnswerUpdated(int256,uint256,uint256)"));
        _orderOpenedTopic0 =
            uint256(keccak256("OrderOpened(uint256,address,uint256,int256,int256,int256,uint256)"));
        _orderCancelledTopic0 = uint256(keccak256("OrderCancelled(uint256,address)"));
        SYSTEM.subscribe(
            DEST_CHAIN_ID, mockOracle_, _answerUpdatedTopic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
        SYSTEM.subscribe(
            DEST_CHAIN_ID, realFeed_, _answerUpdatedTopic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }

    /// @notice Point this contract at the deployed vault: sets the callback
    /// recipient and subscribes to the vault's order events. One-time.
    function setVault(address vault_) external {
        require(msg.sender == owner, "not owner");
        require(vault == address(0), "vault set");
        vault = vault_;
        callback = vault_;
        SYSTEM.subscribe(
            DEST_CHAIN_ID, vault_, _orderOpenedTopic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
        SYSTEM.subscribe(
            DEST_CHAIN_ID, vault_, _orderCancelledTopic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        if (log_.topic0 == _answerUpdatedTopic0) {
            // Chainlink AnswerUpdated: current price is indexed -> topic1,
            // roundId indexed -> topic2, updatedAt in data.
            int256 price = int256(log_.topic1);
            uint256 updatedAt = abi.decode(log_.data, (uint256));
            emit PriceSeen(price, updatedAt, log_.contractAddress);
            if (price > 0) _onPrice(price);
            return;
        }
        if (log_.contractAddress == vault && log_.topic0 == _orderOpenedTopic0) {
            uint256 orderId = log_.topic1;
            address user = address(uint160(log_.topic2));
            (uint256 amount, int256 stopLoss, int256 tp1, int256 tp2, uint256 trailingBps) =
                abi.decode(log_.data, (uint256, int256, int256, int256, uint256));
            tracked[orderId] = TrackedOrder({
                user: user,
                amount: amount,
                remaining: amount,
                stopLoss: stopLoss,
                tp1: tp1,
                tp2: tp2,
                trailingBps: trailingBps,
                highWater: lastPrice,
                tp1Done: false,
                open: true
            });
            openIds.push(orderId);
            emit OrderTracked(orderId, user);
            return;
        }
        if (log_.contractAddress == vault && log_.topic0 == _orderCancelledTopic0) {
            uint256 orderId = log_.topic1;
            if (tracked[orderId].open) {
                tracked[orderId].open = false;
                tracked[orderId].remaining = 0;
                _removeOpen(orderId);
                emit OrderClosed(orderId);
            }
            return;
        }
    }

    function _onPrice(int256 price) internal {
        lastPrice = price;
        uint256 scanned = 0;
        uint256 i = 0;
        while (i < openIds.length && scanned < MAX_SCAN) {
            uint256 orderId = openIds[i];
            TrackedOrder storage o = tracked[orderId];
            scanned++;
            if (!o.open) {
                _removeOpenAt(i);
                continue;
            }
            if (price > o.highWater) o.highWater = price;
            (bool trigger, uint8 kind, uint256 exitAmount) = _checkTrigger(o, price);
            if (trigger && exitAmount > 0) {
                o.remaining -= exitAmount;
                if (kind == 2) o.tp1Done = true;
                if (o.remaining == 0) o.open = false;
                _requestExit(orderId, kind, exitAmount, uint256(price));
                if (!o.open) {
                    _removeOpenAt(i);
                    continue;
                }
            }
            i++;
        }
    }

    /// @dev Priority: stop-loss, then trailing stop, then TP2 (rest), then TP1 (50%).
    function _checkTrigger(TrackedOrder storage o, int256 price)
        internal
        view
        returns (bool trigger, uint8 kind, uint256 exitAmount)
    {
        if (o.stopLoss > 0 && price <= o.stopLoss) {
            return (true, 1, o.remaining);
        }
        if (
            o.trailingBps > 0 && o.highWater > 0
                && uint256(price) * 10000 <= uint256(o.highWater) * (10000 - o.trailingBps)
        ) {
            return (true, 4, o.remaining);
        }
        if (o.tp2 > 0 && price >= o.tp2) {
            return (true, 3, o.remaining);
        }
        if (!o.tp1Done && o.tp1 > 0 && price >= o.tp1) {
            return (true, 2, o.remaining / 2);
        }
        return (false, 0, 0);
    }

    function _requestExit(uint256 orderId, uint8 kind, uint256 exitAmount, uint256 price) internal {
        bytes memory payload = abi.encodeWithSignature(
            "executeExit(address,uint256,uint256,uint256,uint8)", address(0), orderId, exitAmount, price, kind
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: DEST_CHAIN_ID,
                recipient: callback,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
        emit ExitRequested(orderId, kind, exitAmount, price);
    }

    function _removeOpen(uint256 orderId) internal {
        for (uint256 i = 0; i < openIds.length; i++) {
            if (openIds[i] == orderId) {
                _removeOpenAt(i);
                return;
            }
        }
    }

    function _removeOpenAt(uint256 index) internal {
        openIds[index] = openIds[openIds.length - 1];
        openIds.pop();
    }

    function openOrderCount() external view returns (uint256) {
        return openIds.length;
    }

    function coverDebt() external {
        _coverDebt();
    }
}
