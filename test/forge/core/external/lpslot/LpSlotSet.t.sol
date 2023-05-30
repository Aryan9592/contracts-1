// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {Test} from 'forge-std/Test.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Fixed18Lib} from '@equilibria/root/number/types/Fixed18.sol';
import {Position} from '@usum/core/libraries/Position.sol';
import {QTY_PRECISION, LEVERAGE_PRECISION} from '@usum/core/libraries/PositionUtil.sol';
import {LpContext} from '@usum/core/libraries/LpContext.sol';
import {LpSlotMargin} from '@usum/core/libraries/LpSlotMargin.sol';
import {LpSlot, LpSlotLib} from '@usum/core/external/lpslot/LpSlot.sol';
import {LpSlotSet} from '@usum/core/external/lpslot/LpSlotSet.sol';
import {IOracleProvider} from '@usum/core/interfaces/IOracleProvider.sol';
import {IUSUMVault} from '@usum/core/interfaces/IUSUMVault.sol';
import {IUSUMMarket} from '@usum/core/interfaces/IUSUMMarket.sol';

contract LpSlotSetTest is Test {
    using SafeCast for uint256;
    using LpSlotLib for LpSlot;

    IOracleProvider provider;
    IUSUMVault vault;
    IUSUMMarket market;
    LpSlotSet slotSet;

    function setUp() public {
        provider = IOracleProvider(address(1));
        vault = IUSUMVault(address(2));
        market = IUSUMMarket(address(3));

        vm.mockCall(address(vault), abi.encodeWithSelector(vault.getPendingSlotShare.selector), abi.encode(0));

        vm.mockCall(address(market), abi.encodeWithSelector(market.oracleProvider.selector), abi.encode(provider));
        vm.mockCall(address(market), abi.encodeWithSelector(market.vault.selector), abi.encode(vault));

        slotSet._longSlots[1].total = 1000 ether;
        slotSet._longSlots[2].total = 1000 ether;
    }

    function testPrepareSlotMargins() public {
        LpContext memory ctx = _newLpContext();
        Position memory position = _newPosition();

        position.setSlotMargins(slotSet.prepareSlotMargins(position.qty, 1500 ether));

        assertEq(position.leveragedQty(ctx), 1500 ether);
        assertEq(position._slotMargins[0].tradingFeeRate, 1);
        assertEq(position._slotMargins[0].amount, 1000 ether);
        assertEq(position._slotMargins[0].tradingFee(), 0.1 ether);
        assertEq(position._slotMargins[1].tradingFeeRate, 2);
        assertEq(position._slotMargins[1].amount, 500 ether);
        assertEq(position._slotMargins[1].tradingFee(), 0.1 ether);
    }

    function testAcceptOpenPosition() public {
        LpContext memory ctx = _newLpContext();
        Position memory position = _newPosition();
        position.setSlotMargins(slotSet.prepareSlotMargins(position.qty, 1500 ether));

        slotSet.acceptOpenPosition(ctx, position);

        assertEq(slotSet._longSlots[1].total, 1000.1 ether);
        assertEq(slotSet._longSlots[1].freeLiquidity(), 0.1 ether);
        assertEq(slotSet._longSlots[2].total, 1000.1 ether);
        assertEq(slotSet._longSlots[2].freeLiquidity(), 500.1 ether);
    }

    function testCloseOpenPosition_whenSameRound() public {
        LpContext memory ctx = _newLpContext();
        Position memory position = _newPosition();
        position.setSlotMargins(slotSet.prepareSlotMargins(position.qty, 1500 ether));
        slotSet.acceptOpenPosition(ctx, position);

        ctx._currentVersionCache.version = 1;
        ctx._currentVersionCache.timestamp = 1;
        position.closeVersion = ctx._currentVersionCache.version;
        position.closeTimestamp = ctx._currentVersionCache.timestamp;

        slotSet.acceptClosePosition(ctx, position);
        slotSet.acceptClaimPosition(ctx, position, 0);

        assertEq(slotSet._longSlots[1].total, 1000.1 ether);
        assertEq(slotSet._longSlots[1].freeLiquidity(), 1000.1 ether);
        assertEq(slotSet._longSlots[2].total, 1000.1 ether);
        assertEq(slotSet._longSlots[2].freeLiquidity(), 1000.1 ether);
    }

    function testCloseOpenPosition_whenNextRoundWithTakerProfit() public {
        LpContext memory ctx = _newLpContext();
        Position memory position = _newPosition();
        position.setSlotMargins(slotSet.prepareSlotMargins(position.qty, 1500 ether));
        slotSet.acceptOpenPosition(ctx, position);

        ctx._currentVersionCache.version = 2;
        ctx._currentVersionCache.timestamp = 2;
        ctx._currentVersionCache.price = Fixed18Lib.from(110);
        position.closeVersion = ctx._currentVersionCache.version;
        position.closeTimestamp = ctx._currentVersionCache.timestamp;

        slotSet.acceptClosePosition(ctx, position);
        slotSet.acceptClaimPosition(ctx, position, 150 ether);

        assertEq(slotSet._longSlots[1].total, 900.1 ether);
        assertEq(slotSet._longSlots[1].freeLiquidity(), 900.1 ether);
        assertEq(slotSet._longSlots[2].total, 950.1 ether);
        assertEq(slotSet._longSlots[2].freeLiquidity(), 950.1 ether);
    }

    function testCloseOpenPosition_whenNextRoundWithTakerLoss() public {
        LpContext memory ctx = _newLpContext();
        Position memory position = _newPosition();
        position.setSlotMargins(slotSet.prepareSlotMargins(position.qty, 1500 ether));
        slotSet.acceptOpenPosition(ctx, position);

        ctx._currentVersionCache.version = 2;
        ctx._currentVersionCache.timestamp = 2;
        ctx._currentVersionCache.price = Fixed18Lib.from(90);
        position.closeVersion = ctx._currentVersionCache.version;
        position.closeTimestamp = ctx._currentVersionCache.timestamp;

        slotSet.acceptClosePosition(ctx, position);
        slotSet.acceptClaimPosition(ctx, position, -150 ether);

        assertEq(slotSet._longSlots[1].total, 1100.1 ether);
        assertEq(slotSet._longSlots[1].freeLiquidity(), 1100.1 ether);
        assertEq(slotSet._longSlots[2].total, 1050.1 ether);
        assertEq(slotSet._longSlots[2].freeLiquidity(), 1050.1 ether);
    }

    function testAddLiquidity() public {
        LpContext memory ctx = _newLpContext();
        ctx._currentVersionCache.version = 2;
        ctx._currentVersionCache.timestamp = 2;
        ctx._currentVersionCache.price = Fixed18Lib.from(90);

        uint256 liquidity = slotSet.addLiquidity(ctx, 1, 100 ether, 1000 ether);

        assertEq(liquidity, 100 ether);
        assertEq(slotSet._longSlots[1].total, 1100 ether);
    }

    function testRemoveLiquidity() public {
        LpContext memory ctx = _newLpContext();
        ctx._currentVersionCache.version = 2;
        ctx._currentVersionCache.timestamp = 2;
        ctx._currentVersionCache.price = Fixed18Lib.from(90);

        uint256 amount = slotSet.removeLiquidity(ctx, 1, 100 ether, 1000 ether);

        assertEq(amount, 100 ether);
        assertEq(slotSet._longSlots[1].total, 900 ether);
    }

    function _newLpContext() private view returns (LpContext memory ctx) {
        ctx.market = market;
        ctx.tokenPrecision = 10 ** 18;
    }

    function _newPosition() private pure returns (Position memory) {
        return
            Position({
                id: 1,
                openVersion: 1,
                closeVersion: 0,
                qty: int224(150 * QTY_PRECISION.toInt256()),
                leverage: uint32(10 * LEVERAGE_PRECISION),
                takerMargin: 150 ether,
                openTimestamp: 1,
                closeTimestamp: 0,
                owner: address(0),
                _slotMargins: new LpSlotMargin[](0)
            });
    }
}
