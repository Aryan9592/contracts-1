// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {PositionUtil} from "@usum/core/libraries/PositionUtil.sol";
import {Position} from "@usum/core/libraries/Position.sol";
import {LpContext} from "@usum/core/libraries/LpContext.sol";
import {LpSlotMargin} from "@usum/core/libraries/LpSlotMargin.sol";
import {MarketValue} from "@usum/core/base/market/MarketValue.sol";
import {OracleVersion} from "@usum/core/interfaces/IOracleProvider.sol";
import {IUSUMTradeCallback} from "@usum/core/interfaces/callback/IUSUMTradeCallback.sol";

abstract contract Trade is MarketValue {
    using Math for uint256;
    using SafeCast for uint256;
    using SignedMath for int256;

    error ZeroTargetAmount();
    error TooSmallTakerMargin();

    error InvalidProfitStop();
    error InvalidLossCut();
    error LossCutNotRequired();
    error InvalidLeverage();
    error InvalidBasis();

    error NotEnoughMarginTransfered();
    error NotExistPosition();
    error NotPermitted();
    error ExceedMaxAllowableTradingFee();

    error ClosePositionCallbackError();

    event OpenPosition();
    event ClosePosition();

    struct ClosePositionInfo {
        int256 takerPosition;
        uint256 exitPrice;
        int256 takerPnl;
        uint256 totalFee;
        address recipient;
    }

    // constants
    // uint32 public constant MIN_LEVERAGE_BPS = uint32(BPS);
    // uint32 public constant MAX_LEVERAGE_BPS = 1000 * uint32(BPS);

    // uint16 public constant MIN_PROFITSTOP_BPS = 1; // 0.01%
    // uint16 public constant MAX_PROFITSTOP_BPS = type(uint16).max; // uint16(BPS); // 100%

    uint256 internal _positionId;

    function openPosition(
        int224 qty,
        uint32 leverage,
        uint256 takerMargin,
        uint256 makerMargin,
        uint256 maxAllowableTradingFee,
        bytes calldata data
    ) external nonReentrant returns (Position memory) {
        if (qty == 0) revert ZeroTargetAmount();
        if (
            takerMargin <
            factory.getMinimumTakerMargin(address(settlementToken))
        ) revert TooSmallTakerMargin();
        //TODO get slotmargin by using makerMargin

        LpContext memory ctx = newLpContext();
        Position memory position = newPosition(ctx, qty, leverage, takerMargin);

        position.setSlotMargins(
            lpSlotSet.prepareSlotMargins(position.qty, makerMargin)
        );

        // check trading fee
        uint256 tradingFee = position.tradingFee();

        if (tradingFee > maxAllowableTradingFee) {
            revert ExceedMaxAllowableTradingFee();
        }

        // call callback
        uint256 balanceBefore = settlementToken.balanceOf(address(vault));
        uint256 protocolFee = getProtocolFee(takerMargin);
        uint256 requiredMargin = takerMargin + protocolFee + tradingFee;
        IUSUMTradeCallback(msg.sender).openPositionCallback(
            address(settlementToken),
            address(vault),
            requiredMargin,
            data
        );
        // check margin settlementToken increased
        if (
            balanceBefore + requiredMargin <
            settlementToken.balanceOf(address(vault))
        ) revert NotEnoughMarginTransfered();

        lpSlotSet.acceptOpenPosition(ctx, position); // settle()

        vault.onOpenPosition(position.id, takerMargin, tradingFee, protocolFee);

        // write position
        position.storeTo(positions[position.id]);
        // create keeper task
        liquidator.createLiquidationTask(position.id);

        //TODO add event parameters
        emit OpenPosition();
        return position;
    }

    // can call keeper or onwer only
    function closePosition(
        uint256 positionId,
        address recipient, // EOA or account contract
        bytes calldata data
    ) external nonReentrant {
        Position memory position = positions[positionId];
        if (position.id == 0) revert NotExistPosition();
        // TODO caller keeper || owner
        if (position.owner != msg.sender) revert NotPermitted();
        uint256 marginTransferred = _closePosition(
            position,
            0,
            recipient,
            data
        );

        emit ClosePosition();
    }

    function _closePosition(
        Position memory position,
        uint256 usedKeeperFee, // TODO
        address recipient,
        bytes memory data
    ) internal returns (uint256 marginTransferred) {
        //TODO close position
        LpContext memory ctx = newLpContext();

        uint256 makerMargin = position.makerMargin();
        uint256 takerMargin = position.takerMargin - usedKeeperFee;
        uint256 settlmentAmount = takerMargin;

        uint256 interestFee = calculateInterest(
            makerMargin,
            position.timestamp,
            block.timestamp
        );
        int256 realizedPnl = position.pnl(ctx) - interestFee.toInt256();

        uint256 absRealizedPnl = realizedPnl.abs();
        if (realizedPnl > 0) {
            if (absRealizedPnl > makerMargin) {
                realizedPnl = makerMargin.toInt256();
                settlmentAmount += makerMargin;
            } else {
                settlmentAmount += absRealizedPnl;
            }
        } else {
            if (absRealizedPnl > takerMargin) {
                realizedPnl = -(takerMargin.toInt256());
                settlmentAmount = 0;
            } else {
                settlmentAmount -= absRealizedPnl;
            }
        }

        lpSlotSet.acceptClosePosition(ctx, position, realizedPnl);

        vault.onClosePosition(
            position.id,
            recipient,
            takerMargin,
            settlmentAmount
        );

        // TODO keeper == msg.sender => revert 시 정상처리 (강제청산)
        try
            IUSUMTradeCallback(position.owner).closePositionCallback(
                position.id,
                data
            )
        {} catch (bytes memory e /*lowLevelData*/) {
            if (msg.sender != address(liquidator)) {
                revert ClosePositionCallbackError();
            }
        }
        delete positions[position.id];

        liquidator.cancelLiquidationTask(position.id);

        return takerMargin;
    }

    function getProtocolFee(uint256 margin) public view returns (uint16) {
        // returns (protocolFeeRate)
        // FIXME: TBA
        return 0;
    }

    function newPosition(
        LpContext memory ctx,
        int224 qty,
        uint32 leverage,
        uint256 takerMargin
    ) private returns (Position memory) {
        return
            Position({
                id: ++_positionId,
                oracleVersion: ctx.currentOracleVersion().version,
                qty: qty, //
                leverage: leverage,
                timestamp: block.timestamp,
                takerMargin: takerMargin,
                owner: msg.sender,
                _slotMargins: new LpSlotMargin[](0)
            });
    }

    function liquidate(
        uint256 positionId,
        address keeper,
        uint256 keeperFee // native token amount
    ) external nonReentrant onlyLiquidator {
        Position memory position = positions[positionId];
        if (position.id == 0) revert NotExistPosition();
        if (!checkLiquidation(positionId)) return;

        uint256 usedKeeperFee = vault.transferKeeperFee(
            keeper,
            keeperFee,
            position.takerMargin
        );
        _closePosition(position, usedKeeperFee, position.owner, bytes(""));
    }

    function checkLiquidation(uint256 positionId) public view returns (bool) {
        Position memory position = positions[positionId];
        if (position.id == 0) return false;

        uint256 interestFee = calculateInterest(
            position.makerMargin(),
            position.timestamp,
            block.timestamp
        );

        int256 realizedPnl = position.pnl(newLpContext()) -
            interestFee.toInt256();
        uint256 absRealizedPnl = realizedPnl.abs();
        if (realizedPnl > 0 && absRealizedPnl >= position.makerMargin()) {
            //profit stop (taker side)
            return true;
        } else if (absRealizedPnl >= position.takerMargin) {
            // loss cut (taker side)
            return true;
        }
        return false;
    }

    function getPosition(
        uint256 positionId
    ) external view override returns (Position memory position) {
        position = positions[positionId];
    }
}
