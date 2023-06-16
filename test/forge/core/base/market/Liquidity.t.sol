// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {BaseSetup} from "./BaseSetup.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {Fixed18Lib} from "@equilibria/root/number/types/Fixed18.sol";
import {IChromaticLiquidityCallback} from "@chromatic-protocol/contracts/core/interfaces/callback/IChromaticLiquidityCallback.sol";
import {LpReceipt} from "@chromatic-protocol/contracts/core/libraries/LpReceipt.sol";
import "forge-std/console.sol";

contract LiquidityTest is BaseSetup, IChromaticLiquidityCallback {


    function setUp() public override {
        super.setUp();
    }

    function testAddAndRemoveLiquidity() public {
        uint256 addLongAmount = 10 ether;
        uint256 addShortAmount = 20 ether;
        uint256 removeLongAmount = 7 ether;
        uint256 removeShortAmount = 5 ether;

        // set oracle version to 1
        oracleProvider.increaseVersion(Fixed18Lib.from(1));

        // add liquidity $10 to 0.01% long bin at oracle version 1
        LpReceipt memory receipt1 = market.addLiquidity(
            address(this),
            1,
            abi.encode(addLongAmount)
        );
        assertEq(addLongAmount, usdc.balanceOf(address(vault)));
        assertEq(0, vault.makerBalances(address(usdc)));
        assertEq(0, vault.makerMarketBalances(address(market)));
        assertEq(0, market.getBinLiquidity(1));
        assertEq(0, clbToken.balanceOf(address(market), receipt1.clbTokenId()));

        // set oracle version to 2
        oracleProvider.increaseVersion(Fixed18Lib.from(1));

        // settle oracle version 2
        market.settle();
        assertEq(addLongAmount, usdc.balanceOf(address(vault)));
        assertEq(addLongAmount, vault.makerBalances(address(usdc)));
        assertEq(addLongAmount, vault.makerMarketBalances(address(market)));
        assertEq(addLongAmount, market.getBinLiquidity(1));
        assertEq(addLongAmount, clbToken.balanceOf(address(market), receipt1.clbTokenId()));

        // claim liquidity at oracle version 2
        market.claimLiquidity(receipt1.id, bytes(""));
        assertEq(0, clbToken.balanceOf(address(market), receipt1.clbTokenId()));
        assertEq(addLongAmount, clbToken.balanceOf(address(this), receipt1.clbTokenId()));

        // add liquidity $20 to 0.1% short bin at oracle version 2
        LpReceipt memory receipt2 = market.addLiquidity(
            address(this),
            -10,
            abi.encode(addShortAmount)
        );
        assertEq(addLongAmount + addShortAmount, usdc.balanceOf(address(vault)));
        assertEq(addLongAmount, vault.makerBalances(address(usdc)));
        assertEq(addLongAmount, vault.makerMarketBalances(address(market)));
        assertEq(0, market.getBinLiquidity(-10));
        assertEq(0, clbToken.balanceOf(address(market), receipt2.clbTokenId()));

        // set oracle version to 3
        oracleProvider.increaseVersion(Fixed18Lib.from(1));

        // settle oracle version 3
        market.settle();
        assertEq(addLongAmount + addShortAmount, usdc.balanceOf(address(vault)));
        assertEq(addLongAmount + addShortAmount, vault.makerBalances(address(usdc)));
        assertEq(addLongAmount + addShortAmount, vault.makerMarketBalances(address(market)));
        assertEq(addShortAmount, market.getBinLiquidity(-10));
        assertEq(addShortAmount, clbToken.balanceOf(address(market), receipt2.clbTokenId()));

        // claim liquidity at oracle version 3
        market.claimLiquidity(receipt2.id, bytes(""));
        assertEq(0, clbToken.balanceOf(address(market), receipt2.clbTokenId()));
        assertEq(addShortAmount, clbToken.balanceOf(address(this), receipt2.clbTokenId()));

        // remove liquidity $7 from 0.01% long bin at oracle version 3
        LpReceipt memory receipt3 = market.removeLiquidity(
            address(this),
            1,
            abi.encode(removeLongAmount)
        );
        assertEq(addLongAmount + addShortAmount, usdc.balanceOf(address(vault)));
        assertEq(addLongAmount + addShortAmount, vault.makerBalances(address(usdc)));
        assertEq(addLongAmount + addShortAmount, vault.makerMarketBalances(address(market)));
        assertEq(addLongAmount, market.getBinLiquidity(1));
        assertEq(removeLongAmount, clbToken.balanceOf(address(market), receipt3.clbTokenId()));

        // set oracle version to 4
        oracleProvider.increaseVersion(Fixed18Lib.from(1));

        // settle oracle version 4
        market.settle();
        assertEq(addLongAmount + addShortAmount, usdc.balanceOf(address(vault)));
        assertEq(
            addLongAmount + addShortAmount - removeLongAmount,
            vault.makerBalances(address(usdc))
        );
        assertEq(
            addLongAmount + addShortAmount - removeLongAmount,
            vault.makerMarketBalances(address(market))
        );
        assertEq(addLongAmount - removeLongAmount, market.getBinLiquidity(1));
        assertEq(0, clbToken.balanceOf(address(market), receipt3.clbTokenId()));

        // withdraw liquidity at oracle version 4
        uint256 beforeAt4 = usdc.balanceOf(address(this));
        market.withdrawLiquidity(receipt3.id, bytes(""));
        assertEq(addLongAmount + addShortAmount - removeLongAmount, usdc.balanceOf(address(vault)));
        assertEq(0, clbToken.balanceOf(address(market), receipt3.clbTokenId()));
        assertEq(beforeAt4 + removeLongAmount, usdc.balanceOf(address(this)));
        assertEq(
            addLongAmount - removeLongAmount,
            clbToken.balanceOf(address(this), receipt3.clbTokenId())
        );

        // remove liquidity $5 from 0.1% short bin at oracle version 4
        LpReceipt memory receipt4 = market.removeLiquidity(
            address(this),
            -10,
            abi.encode(removeShortAmount)
        );
        assertEq(addLongAmount + addShortAmount - removeLongAmount, usdc.balanceOf(address(vault)));
        assertEq(
            addLongAmount + addShortAmount - removeLongAmount,
            vault.makerBalances(address(usdc))
        );
        assertEq(
            addLongAmount + addShortAmount - removeLongAmount,
            vault.makerMarketBalances(address(market))
        );
        assertEq(addShortAmount, market.getBinLiquidity(-10));
        assertEq(removeShortAmount, clbToken.balanceOf(address(market), receipt4.clbTokenId()));

        // set oracle version to 5
        oracleProvider.increaseVersion(Fixed18Lib.from(1));

        // settle oracle version 5
        market.settle();
        assertEq(addLongAmount + addShortAmount - removeLongAmount, usdc.balanceOf(address(vault)));
        assertEq(
            addLongAmount + addShortAmount - removeLongAmount - removeShortAmount,
            vault.makerBalances(address(usdc))
        );
        assertEq(
            addLongAmount + addShortAmount - removeLongAmount - removeShortAmount,
            vault.makerMarketBalances(address(market))
        );
        assertEq(addShortAmount - removeShortAmount, market.getBinLiquidity(-10));
        assertEq(0, clbToken.balanceOf(address(market), receipt4.clbTokenId()));

        // withdraw liquidity at oracle version 5
        uint256 beforeAt5 = usdc.balanceOf(address(this));
        market.withdrawLiquidity(receipt4.id, bytes(""));
        assertEq(
            addLongAmount + addShortAmount - removeLongAmount - removeShortAmount,
            usdc.balanceOf(address(vault))
        );
        assertEq(0, clbToken.balanceOf(address(market), receipt4.clbTokenId()));
        assertEq(beforeAt5 + removeShortAmount, usdc.balanceOf(address(this)));
        assertEq(
            addShortAmount - removeShortAmount,
            clbToken.balanceOf(address(this), receipt4.clbTokenId())
        );
    }

    function testDistributeMarketEarning() public {
        uint256 addLongAmount = 10 ether;
        uint256 addShortAmount = 20 ether;
        uint256 earning = 10 ether;
        uint256 keeperFee = 1 ether;

        // prepare keeperFeePayer
        address(keeperFeePayer).call{value: keeperFee}("");

        // set oracle version to 1
        oracleProvider.increaseVersion(Fixed18Lib.from(1));

        // add liquidity $10 to 0.01% long bin
        market.addLiquidity(address(this), 1, abi.encode(addLongAmount));
        // add liquidity $20 to 0.1% short bin
        market.addLiquidity(address(this), -10, abi.encode(addShortAmount));

        // set oracle version to 2
        oracleProvider.increaseVersion(Fixed18Lib.from(1));

        // settle oracle version 2
        market.settle();

        // set markint earning
        usdc.transfer(address(vault), earning);
        vault.setPendingMarketEarnings(address(market), earning);

        // distribute market earning
        vault.distributeMarketEarning(address(market), keeperFee);

        // asserts
        assertEq(
            addLongAmount + addShortAmount + earning - keeperFee,
            usdc.balanceOf(address(vault))
        );
        assertEq(
            addLongAmount + addShortAmount + earning - keeperFee,
            vault.makerBalances(address(usdc))
        );
        assertEq(
            addLongAmount + addShortAmount + earning - keeperFee,
            vault.makerMarketBalances(address(market))
        );
        assertEq(addLongAmount + 3 ether, market.getBinLiquidity(1));
        assertEq(addShortAmount + 6 ether, market.getBinLiquidity(-10));
    }

    // implement IChromaticLiquidityCallback

    function addLiquidityCallback(
        address settlementToken,
        address vault,
        bytes calldata data
    ) external {
        uint256 amount = abi.decode(data, (uint256));
        usdc.transfer(vault, amount);
    }

    function claimLiquidityCallback(uint256 receiptId, bytes calldata data) external {}

    function removeLiquidityCallback(
        address clbToken,
        uint256 clbTokenId,
        bytes calldata data
    ) external {
        uint256 amount = abi.decode(data, (uint256));
        IERC1155(clbToken).safeTransferFrom(address(this), msg.sender, clbTokenId, amount, bytes(""));
    }

    function withdrawLiquidityCallback(uint256 receiptId, bytes calldata data) external {}

    // implement IERC1155Receiver

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
