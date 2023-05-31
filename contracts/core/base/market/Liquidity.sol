// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IUSUMLiquidityCallback} from "@usum/core/interfaces/callback/IUSUMLiquidityCallback.sol";
import {LpContext} from "@usum/core/libraries/LpContext.sol";
import {LpReceipt, LpAction} from "@usum/core/libraries/LpReceipt.sol";
import {MarketValue} from "@usum/core/base/market/MarketValue.sol";

abstract contract Liquidity is MarketValue, IERC1155Receiver {
    using Math for uint256;

    uint256 constant MINIMUM_LIQUIDITY = 10 ** 3;

    uint256 internal _lpReceiptId;

    modifier onlyVault() {
        if (msg.sender != address(vault)) revert OnlyAccessableByVault();
        _;
    }

    function addLiquidity(
        address recipient,
        int16 tradingFeeRate,
        bytes calldata data
    ) external override nonReentrant returns (LpReceipt memory) {
        uint256 balanceBefore = settlementToken.balanceOf(address(vault));
        IUSUMLiquidityCallback(msg.sender).addLiquidityCallback(
            address(settlementToken),
            address(vault),
            data
        );

        uint256 amount = settlementToken.balanceOf(address(vault)) - balanceBefore;
        if (amount <= MINIMUM_LIQUIDITY) revert TooSmallAmount();

        LpContext memory ctx = newLpContext();
        ctx.syncOracleVersion();

        vault.onAddLiquidity(amount);
        lpSlotSet.acceptAddLiquidity(ctx, tradingFeeRate, amount);

        LpReceipt memory receipt = newLpReceipt(
            ctx,
            LpAction.ADD_LIQUIDITY,
            amount,
            recipient,
            tradingFeeRate
        );
        lpReceipts[receipt.id] = receipt;

        emit AddLiquidity(recipient, receipt);
        return receipt;
    }

    function claimLiquidity(uint256 receiptId, bytes calldata data) external override nonReentrant {
        LpReceipt memory receipt = lpReceipts[receiptId];
        if (receipt.id == 0) revert NotExistLpReceipt();
        if (receipt.action != LpAction.ADD_LIQUIDITY) revert InvalidLpReceiptAction();

        LpContext memory ctx = newLpContext();
        ctx.syncOracleVersion();

        uint256 lpTokenAmount = lpSlotSet.acceptClaimLiquidity(
            ctx,
            receipt.tradingFeeRate,
            receipt.amount,
            receipt.oracleVersion
        );
        lpToken.safeTransferFrom(
            address(this),
            receipt.recipient,
            receipt.lpTokenId(),
            lpTokenAmount,
            bytes("")
        );

        IUSUMLiquidityCallback(msg.sender).claimLiquidityCallback(receipt.id, data);
        delete lpReceipts[receiptId];

        emit ClaimLiquidity(receipt.recipient, lpTokenAmount, receipt);
    }

    function removeLiquidity(
        address recipient,
        int16 tradingFeeRate,
        bytes calldata data
    ) external override nonReentrant returns (LpReceipt memory) {
        LpContext memory ctx = newLpContext();
        ctx.syncOracleVersion();

        LpReceipt memory receipt = newLpReceipt(
            ctx,
            LpAction.REMOVE_LIQUIDITY,
            0,
            recipient,
            tradingFeeRate
        );

        uint256 lpTokenId = receipt.lpTokenId();
        uint256 balanceBefore = lpToken.balanceOf(address(this), lpTokenId);
        IUSUMLiquidityCallback(msg.sender).removeLiquidityCallback(
            address(lpToken),
            lpTokenId,
            data
        );

        uint256 lpTokenAmount = lpToken.balanceOf(address(this), lpTokenId) - balanceBefore;
        if (lpTokenAmount == 0) revert TooSmallAmount();

        lpSlotSet.acceptRemoveLiquidity(ctx, tradingFeeRate, lpTokenAmount);
        receipt.amount = lpTokenAmount;

        lpReceipts[receipt.id] = receipt;

        emit RemoveLiquidity(recipient, receipt);
        return receipt;
    }

    function withdrawLiquidity(
        uint256 receiptId,
        bytes calldata data
    ) external override nonReentrant {
        LpReceipt memory receipt = lpReceipts[receiptId];
        if (receipt.id == 0) revert NotExistLpReceipt();
        if (receipt.action != LpAction.REMOVE_LIQUIDITY) revert InvalidLpReceiptAction();

        LpContext memory ctx = newLpContext();
        ctx.syncOracleVersion();

        address recipient = receipt.recipient;
        uint256 lpTokenAmount = receipt.amount;

        (uint256 amount, uint256 burnedLpTokenAmount) = lpSlotSet.acceptWithdrawLiquidity(
            ctx,
            receipt.tradingFeeRate,
            lpTokenAmount,
            receipt.oracleVersion
        );

        lpToken.safeTransferFrom(
            address(this),
            recipient,
            receipt.lpTokenId(),
            lpTokenAmount - burnedLpTokenAmount,
            bytes("")
        );
        vault.onWithdrawLiquidity(recipient, amount);

        IUSUMLiquidityCallback(msg.sender).withdrawLiquidityCallback(receipt.id, data);
        delete lpReceipts[receiptId];

        emit WithdrawLiquidity(recipient, amount, burnedLpTokenAmount, receipt);
    }

    function getSlotLiquidities(
        int16[] calldata tradingFeeRates
    ) external view override returns (uint256[] memory amounts) {
        amounts = new uint256[](tradingFeeRates.length);
        for (uint i = 0; i < tradingFeeRates.length; i++) {
            amounts[i] = lpSlotSet.getSlotLiquidity(tradingFeeRates[i]);
        }
    }

    function getSlotFreeLiquidities(
        int16[] calldata tradingFeeRates
    ) external view override returns (uint256[] memory amounts) {
        amounts = new uint256[](tradingFeeRates.length);
        for (uint i = 0; i < tradingFeeRates.length; i++) {
            amounts[i] = lpSlotSet.getSlotFreeLiquidity(tradingFeeRates[i]);
        }
    }

    function distributeEarningToSlots(uint256 earning, uint256 marketBalance) external onlyVault {
        lpSlotSet.distributeEarning(earning, marketBalance);
    }

    function calculateLpTokenMinting(
        int16 tradingFeeRate,
        uint256 amount
    ) external view returns (uint256) {
        return lpSlotSet.calculateLpTokenMinting(newLpContext(), tradingFeeRate, amount);
    }

    function calculateLpTokenValue(
        int16 tradingFeeRate,
        uint256 lpTokenAmount
    ) external view returns (uint256) {
        return lpSlotSet.calculateLpTokenValue(newLpContext(), tradingFeeRate, lpTokenAmount);
    }

    function newLpReceipt(
        LpContext memory ctx,
        LpAction action,
        uint256 amount,
        address recipient,
        int16 tradingFeeRate
    ) private returns (LpReceipt memory) {
        return
            LpReceipt({
                id: ++_lpReceiptId,
                oracleVersion: ctx.currentOracleVersion().version,
                action: action,
                amount: amount,
                recipient: recipient,
                tradingFeeRate: tradingFeeRate
            });
    }

    // implement IERC1155Receiver

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceID) external view returns (bool) {
        return
            interfaceID == this.supportsInterface.selector || // ERC165
            interfaceID == this.onERC1155Received.selector ^ this.onERC1155BatchReceived.selector; // IERC1155Receiver
    }
}
