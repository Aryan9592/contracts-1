import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { helpers, prepareMarketTest } from "./testHelper";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import {
  addYears,
  differenceInYears,
  fromUnixTime,
  getUnixTime,
} from "date-fns";
import { PositionStructOutput } from "@usum/typechain-types/contracts/core/USUMMarket";
import { inspect } from "util";
import bluebird from "bluebird";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";

describe("position & account test", async function () {
  let testData: Awaited<ReturnType<typeof prepareMarketTest>>;
  const base = ethers.utils.parseEther("10000000");
  async function initialize() {
    testData = await prepareMarketTest();
    const { addLiquidity } = helpers(testData);
    await addLiquidity(base, 1);
    await addLiquidity(base.mul(5), 10);
    await addLiquidity(base, -1);
    await addLiquidity(base.mul(5), -10);
  }

  before(async () => {
    // market deploy
    await initialize();
  });

  it("open long position", async () => {
    const {
      traderAccount,
      market,
      traderRouter,
      oracleProvider,
      settlementToken,
    } = testData;
    const { updatePrice, openPosition } = helpers(testData);
    expect(await traderAccount.getPositionIds(market.address)).to.deep.equal(
      []
    );

    await updatePrice(1000);

    const { makerMargin, receipt } = await openPosition();
    console.log(receipt);

    const positionIds = await traderAccount.getPositionIds(market.address);
    console.log(positionIds);

    expect(positionIds.length).to.equal(1);
    const position = await market.getPosition(positionIds[0]);

    console.log("position", position);
    console.log("slot0 amount", position._slotMargins[0].amount);
    const slot0 = position._slotMargins.find((p) => p.tradingFeeRate == 1);
    console.log("slot0", slot0);
    expect(slot0?.amount).to.equal(base);
    const slot2 = position._slotMargins.find((p) => p.tradingFeeRate === 10);
    expect(slot2?.amount).to.equal(base.mul(4));
    const totalSlotMargin = position._slotMargins.reduce(
      (acc, curr) => acc.add(curr.amount),
      BigNumber.from(0)
    );
    expect(makerMargin).to.equal(totalSlotMargin);
  });

  it("open short position ", async () => {
    const {
      traderAccount,
      market,
      traderRouter,
      oracleProvider,
      settlementToken,
    } = testData;
    const { updatePrice, openPosition } = helpers(testData);
    await updatePrice(1000);
    const { makerMargin, receipt } = await openPosition({
      qty: -10,
    });
    console.log(receipt);
    //TODO assert result

    const positionIds = await traderAccount.getPositionIds(market.address);
    console.log(positionIds);

    expect(positionIds.length).to.equal(2);
    const position = await market.getPosition(positionIds[1]);

    console.log("position", position);
    console.log("slot0 amount", position._slotMargins[0].amount);
    const slot0 = position._slotMargins.find((p) => p.tradingFeeRate === 1);
    console.log("slot0", slot0);
    expect(slot0?.amount).to.equal(base);
    const slot2 = position._slotMargins.find((p) => p.tradingFeeRate === 10);
    expect(slot2?.amount).to.equal(base.mul(4));
    const totalSlotMargin = position._slotMargins.reduce(
      (acc, curr) => acc.add(curr.amount),
      BigNumber.from(0)
    );
    expect(makerMargin).to.equal(totalSlotMargin);
  });

  function getPnl(
    lvQty: BigNumber,
    entryPrice: BigNumber,
    exitPrice: BigNumber
  ) {
    console.log(
      "[getPnl]",
      `enrtyPrice ${ethers.utils.formatEther(
        entryPrice
      )} , exitPrice : ${ethers.utils.formatEther(exitPrice)}`
    );
    const delta = exitPrice.sub(entryPrice);
    return lvQty.mul(delta).div(entryPrice);
  }

  it("position info", async () => {
    //

    const {
      traderAccount,
      market,
      traderRouter,
      oracleProvider,
      settlementToken,
      marketFactory,
    } = testData;

    const { updatePrice, openPosition, awaitTx } = helpers(testData);
    await awaitTx(
      marketFactory.appendInterestRateRecord(
        settlementToken.address,
        1500,
        (await time.latest()) + 100
      )
    );

    await time.increase(101);
    // prevent IOV
    await updatePrice(0);
    const oraclePrices = [1000, 1100, 1300, 1200];
    await bluebird.each(oraclePrices, async (price) => {
      await openPosition();
      await updatePrice(price);
    });

    const positionIds = await traderAccount.getPositionIds(market.address);
    const positions = await market.getPositions(positionIds);
    const settleVersions = positions.map((e) => e.oracleVersion.add(1));
    const entryVersions = await oracleProvider.atVersions(settleVersions);
    const currentVersion = await oracleProvider.currentVersion();

    const settlementTokenDecimal = BigNumber.from(10).pow(
      await settlementToken.decimals()
    );
    const QTY_LEVERAGE_PRECISION = BigNumber.from(10).pow(6);

    const results = positions.reduce(
      (acc: any[], curr: PositionStructOutput) => {
        const entryPrice = entryVersions.find((v) =>
          v.version.eq(curr.oracleVersion.add(1))
        )?.price;
        if (!entryPrice)
          throw new Error("Not found oracle version for entry price");

        const currentPrice = currentVersion.price;
        const leveraged = curr.qty
          .abs()
          .mul(settlementTokenDecimal.mul(curr.leverage))
          .div(QTY_LEVERAGE_PRECISION);
        const leveragedQty = curr.qty.lt(0) ? leveraged.mul(-1) : leveraged;
        const makerMargin = curr._slotMargins
          .map((m) => m.amount)
          .reduce((a, b) => a.add(b));
        const pnl = acc.push({
          ...curr,
          pnl: getPnl(leveragedQty, entryPrice, currentPrice),
          leveragedQty: leveragedQty,
          entryPrice: entryPrice,
          makerMargin: makerMargin,
        });
        return acc;
      },
      []
    );

    results.map((r) =>
      console.log(
        `position id: ${r.id} pnl : ${ethers.utils.formatEther(r.pnl)}`
      )
    );

    results.map((r, index) => {
      const oraclePriceDiff =
        index != results.length
          ? BigNumber.from(
              oraclePrices[oraclePrices.length - 1] - oraclePrices[index]
            ).mul(10 ** 8)
          : BigNumber.from(0);
      expect(r.pnl).to.equal(
        r.leveragedQty.mul(oraclePriceDiff).div(r.entryPrice)
      );
      expect(
        parseFloat(r.pnl.toString()) / parseFloat(r.leveragedQty)
      ).to.equal(oraclePriceDiff.toNumber() / r.entryPrice.toNumber());
      console.log(
        `pnl ${
          (parseFloat(r.pnl.toString()) / parseFloat(r.leveragedQty)) * 100
        }%`
      );
    });

    // update interest fee to 20%
    await awaitTx(
      marketFactory.appendInterestRateRecord(
        settlementToken.address,
        2000,
        (await time.latest()) + 3600 * 24 * 36.5 // 36.5 day
      )
    );

    const currentTime = await time.increase(3600 * 24 * 36.5 - 1);

    const yearSecond = 3600 * 24 * 365;

    let txCnt = 0;

    const interestRates = await marketFactory.getInterestRateRecords(
      settlementToken.address
    );
    // console.log("fees", interestRates);

    await bluebird.each(results, async (r) => {
      const txTimestamp = currentTime + ++txCnt;
      const timeDiff = txTimestamp - r.timestamp;
      const tx = traderRouter.closePosition(
        market.address,
        r.id,
        ethers.constants.MaxUint256
      );

      const filteredFees = interestRates
        .filter((fee) => fee.beginTimestamp.lte(BigNumber.from(txTimestamp)))
        .sort((a, b) => b.beginTimestamp.sub(a.beginTimestamp).toNumber());

      let calculatedTime = txTimestamp;
      let interestFee = BigNumber.from(0);

      // get total interestFee 
      for (let fee of filteredFees) {
        const period =
          calculatedTime - Math.max(fee.beginTimestamp.toNumber(), r.timestamp);
        calculatedTime = fee.beginTimestamp.toNumber();

        interestFee = interestFee.add(
          r.makerMargin
            .mul(fee.annualRateBPS.mul(period))
            .div(yearSecond * 10000)
        );
        if (fee.beginTimestamp.lte(r.timestamp)) break;
      }

      console.log("expected interest", interestFee);

      await expect(tx)
        .to.emit(market, "ClosePosition")
        .withArgs(anyValue, anyValue, anyValue, r.pnl.sub(interestFee));
    });
  });
});
