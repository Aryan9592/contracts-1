// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IERC1155Receiver} from '@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol';
import {IUSUMLiquidityCallback} from '@usum/core/interfaces/callback/IUSUMLiquidityCallback.sol';
import {LpContext} from '@usum/core/libraries/LpContext.sol';
import {LpTokenLib} from '@usum/core/libraries/LpTokenLib.sol';
import {LpReceipt} from '@usum/core/libraries/LpReceipt.sol';
import {MarketValue} from '@usum/core/base/market/MarketValue.sol';

abstract contract Liquidity is MarketValue, IERC1155Receiver {
    using Math for uint256;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

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
        IUSUMLiquidityCallback(msg.sender).addLiquidityCallback(address(settlementToken), address(vault), data);

        uint256 amount = settlementToken.balanceOf(address(vault)) - balanceBefore;
        if (amount <= MINIMUM_LIQUIDITY) revert TooSmallAmount();

        LpContext memory ctx = newLpContext();
        ctx.syncOracleVersion();

        vault.onAddLiquidity(amount);
        lpSlotSet.addLiquidity(ctx, tradingFeeRate, amount);

        emit AddLiquidity(recipient, tradingFeeRate, amount);
    }

    function removeLiquidity(
        address recipient,
        int16 tradingFeeRate,
        bytes calldata data
    ) external override nonReentrant returns (uint256 amount) {
        uint256 id = LpTokenLib.encodeId(tradingFeeRate);
        uint256 balanceBefore = lpToken.balanceOf(address(lpToken), id);

        IUSUMLiquidityCallback(msg.sender).removeLiquidityCallback(address(lpToken), data);

        uint256 lpTokenAmount = lpToken.balanceOf(address(lpToken), id) - balanceBefore;
        if (lpTokenAmount == 0) return 0;

        LpContext memory ctx = newLpContext();
        ctx.syncOracleVersion();

        amount = lpSlotSet.removeLiquidity(ctx, tradingFeeRate, lpTokenAmount);

        vault.onRemoveLiquidity(recipient, amount);

        lpToken.burn(address(lpToken), id, lpTokenAmount);

        emit RemoveLiquidity(recipient, tradingFeeRate, id, amount, lpTokenAmount);
    }

    function getSlotLiquidities(
        int16[] memory tradingFeeRates
    ) external view override returns (uint256[] memory amounts) {
        amounts = new uint256[](tradingFeeRates.length);
        for (uint i = 0; i < tradingFeeRates.length; i++) {
            amounts[i] = lpSlotSet.getSlotLiquidity(tradingFeeRates[i]);
        }
    }

    function getSlotFreeLiquidities(
        int16[] memory tradingFeeRates
    ) external view override returns (uint256[] memory amounts) {
        amounts = new uint256[](tradingFeeRates.length);
        for (uint i = 0; i < tradingFeeRates.length; i++) {
            amounts[i] = lpSlotSet.getSlotFreeLiquidity(tradingFeeRates[i]);
        }
    }

    function distributeEarningToSlots(uint256 earning, uint256 marketBalance) external onlyVault {
        lpSlotSet.distributeEarning(earning, marketBalance);
    }

    function calculateLpTokenMinting(int16 tradingFeeRate, uint256 amount) external view returns (uint256) {
        return lpSlotSet.calculateLpTokenMinting(newLpContext(), tradingFeeRate, amount);
    }

    function calculateLpTokenValue(int16 tradingFeeRate, uint256 lpTokenAmount) external view returns (uint256 amount) {
        amount = lpSlotSet.calculateLpTokenValue(newLpContext(), tradingFeeRate, lpTokenAmount);
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
