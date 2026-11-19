// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @notice SentinelVault — destination-chain callback contract (Unichain Sepolia).
/// Holds user mock-WETH deposits and their stop-loss / take-profit orders.
/// `SentinelReactive` (Lasna) watches the Chainlink ETH/USD feed and, on a
/// trigger, requests a callback here; this contract settles the exit in mock
/// USDC from its own reserve at the trigger price and pays the user.
///
/// DEMO NOTE: settlement is against the vault's mock-USDC reserve because
/// there is no meaningful DEX liquidity on testnet. A production version
/// would swap on a real DEX instead of settling from a reserve.
contract SentinelVault is AbstractCallback {
    IERC20 public immutable weth;
    IERC20 public immutable usdc;
    uint256 public nextOrderId = 1;

    struct Order {
        address user;
        uint256 amount; // original deposit (WETH wei, 18dp)
        uint256 remaining; // WETH not yet exited
        int256 stopLoss; // 0 = none
        int256 tp1; // 0 = none
        int256 tp2; // 0 = none
        bool open;
    }

    mapping(uint256 => Order) public orders;

    /// @dev Trailing stop lives in the reactive contract's book, but the
    /// value is carried in this event so the reactive contract learns it.
    event OrderOpened(
        uint256 indexed orderId,
        address indexed user,
        uint256 amount,
        int256 stopLoss,
        int256 tp1,
        int256 tp2,
        uint256 trailingBps
    );
    event OrderCancelled(uint256 indexed orderId, address indexed user);
    event ExitExecuted(
        uint256 indexed orderId,
        address indexed user,
        uint256 exitAmount,
        uint256 usdcOut,
        uint256 price,
        uint8 exitKind
    );
    event ReserveFunded(address indexed from, uint256 amount);

    constructor(IPayable callbackProxy_, address callbackSender_, address weth_, address usdc_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {
        weth = IERC20(weth_);
        usdc = IERC20(usdc_);
    }

    /// @notice Deposit mock WETH and open a stop-loss / take-profit order.
    /// At least one trigger must be set. trailingBps is in basis points
    /// (e.g. 200 = 2% trailing stop); 0 disables it.
    function openOrder(uint256 amount, int256 stopLoss, int256 tp1, int256 tp2, uint256 trailingBps)
        external
        returns (uint256 orderId)
    {
        require(amount > 0, "amount 0");
        require(stopLoss > 0 || tp1 > 0 || tp2 > 0 || trailingBps > 0, "no trigger");
        require(tp1 == 0 || tp2 == 0 || tp2 > tp1, "tp2>tp1");
        require(trailingBps <= 5000, "trailing too wide");
        require(weth.transferFrom(msg.sender, address(this), amount), "deposit failed");
        orderId = nextOrderId++;
        orders[orderId] = Order({
            user: msg.sender,
            amount: amount,
            remaining: amount,
            stopLoss: stopLoss,
            tp1: tp1,
            tp2: tp2,
            open: true
        });
        emit OrderOpened(orderId, msg.sender, amount, stopLoss, tp1, tp2, trailingBps);
    }

    /// @notice Cancel an open order and refund the unfilled WETH.
    function cancelOrder(uint256 orderId) external {
        Order storage o = orders[orderId];
        require(o.open, "not open");
        require(o.user == msg.sender, "not owner");
        o.open = false;
        uint256 remaining = o.remaining;
        o.remaining = 0;
        require(weth.transfer(msg.sender, remaining), "refund failed");
        emit OrderCancelled(orderId, msg.sender);
    }

    /// @notice Exit callback from SentinelReactive via the callback proxy.
    /// exitKind: 1 = stop-loss (full), 2 = TP1 (50%), 3 = TP2 (rest),
    /// 4 = trailing stop (full). Defensive: clamps to the remaining amount
    /// and no-ops when the order is already closed, so a duplicate or late
    /// callback can never over-fill.
    function executeExit(address reactive_, uint256 orderId, uint256 exitAmount, uint256 price, uint8 exitKind)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        Order storage o = orders[orderId];
        if (!o.open || o.remaining == 0) return;
        if (exitAmount > o.remaining) exitAmount = o.remaining;
        if (exitAmount == 0) return;
        o.remaining -= exitAmount;
        if (o.remaining == 0) o.open = false;
        // USDC out: exitAmount (WETH wei, 18dp) * price (8dp) / 1e8; mock USDC is 18dp.
        uint256 usdcOut = exitAmount * price / 1e8;
        require(usdc.transfer(o.user, usdcOut), "settle failed");
        emit ExitExecuted(orderId, o.user, exitAmount, usdcOut, price, exitKind);
    }

    /// @notice Top up the mock-USDC settlement reserve (deployer only in practice;
    /// anyone may fund it). Caller must approve this vault first.
    function fundReserve(uint256 amount) external {
        require(usdc.transferFrom(msg.sender, address(this), amount), "fund failed");
        emit ReserveFunded(msg.sender, amount);
    }

    function coverDebt() external {
        _coverDebt();
    }
}
