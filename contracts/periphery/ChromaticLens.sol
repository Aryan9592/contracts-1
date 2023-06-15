// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {Fixed18, UFixed18, Fixed18Lib} from "@equilibria/root/number/types/Fixed18.sol";
import {IOracleProvider} from "@chromatic/oracle/interfaces/IOracleProvider.sol";
import {IChromaticMarket} from "@chromatic/core/interfaces/IChromaticMarket.sol";
import {ICLBToken} from "@chromatic/core/interfaces/ICLBToken.sol";
import {Position} from "@chromatic/core/libraries/Position.sol";
import {CLBTokenLib} from "@chromatic/core/libraries/CLBTokenLib.sol";
import {LpReceipt} from "@chromatic/core/libraries/LpReceipt.sol";
import {BPS, FEE_RATES_LENGTH} from "@chromatic/core/libraries/Constants.sol";
import {IChromaticRouter} from "@chromatic/periphery/interfaces/IChromaticRouter.sol";

/**
 * @title ChromaticLens
 * @dev A contract that provides utility functions for interacting with Chromatic markets.
 */
contract ChromaticLens is Multicall {
    using Math for uint256;

    struct CLBBalance {
        uint256 tokenId;
        uint256 balance;
        uint256 totalSupply;
        uint256 binValue;
    }

    struct LiquidityBinsParam {
        int16 tradingFeeRate;
        uint256 oracleVersion;
    }

    struct LiquidityBin {
        int16 tradingFeeRate;
        uint256 liquidity;
        uint256 freeLiquidity;
        uint256 clbTokenAmount;
        uint256 burningAmount;
        uint256 tokenAmount;
    }

    IChromaticRouter router;

    constructor(IChromaticRouter _router) {
        router = _router;
    }

    /**
     * @dev Retrieves the OracleVersion for the specified oracle version in the given Chromatic market.
     * @param market The address of the Chromatic market contract.
     * @param version An oracle versions.
     * @return oracleVersion The OracleVersion for the specified oracle version.
     */
    function oracleVersion(
        IChromaticMarket market,
        uint256 version
    ) external view returns (IOracleProvider.OracleVersion memory) {
        return market.oracleProvider().atVersion(version);
    }

    /**
     * @dev Retrieves the LP receipts for the specified owner in the given Chromatic market.
     * @param market The address of the Chromatic market contract.
     * @param owner The address of the LP token owner.
     * @return result An array of LpReceipt containing the LP receipts for the owner.
     */
    function lpReceipts(
        IChromaticMarket market,
        address owner
    ) public view returns (LpReceipt[] memory result) {
        uint256[] memory receiptIds = router.getLpReceiptIds(address(market), owner);

        result = new LpReceipt[](receiptIds.length);
        for (uint i = 0; i < receiptIds.length; i++) {
            result[i] = market.getLpReceipt(receiptIds[i]);
        }
    }

    /**
     * @dev Retrieves the CLB token balances for the specified owner in the given Chromatic market.
     * @param market The address of the Chromatic market contract.
     * @param owner The address of the CLB token owner.
     * @return An array of CLBBalance containing the CLB token balance information for the owner.
     */
    function clbBalanceOf(
        IChromaticMarket market,
        address owner
    ) external view returns (CLBBalance[] memory) {
        uint256[] memory tokenIds = CLBTokenLib.tokenIds();
        address[] memory accounts = new address[](tokenIds.length);
        // Set all accounts to the owner's address
        for (uint256 i = 0; i < accounts.length; i++) {
            accounts[i] = owner;
        }

        // Get balances of CLB tokens for the owner
        uint256[] memory balances = market.clbToken().balanceOfBatch(accounts, tokenIds);

        // Count the number of CLB tokens with non-zero balance
        uint256 effectiveCnt;
        for (uint256 i = 0; i < balances.length; i++) {
            if (balances[i] > 0) {
                effectiveCnt++;
            }
        }

        uint256[] memory effectiveBalances = new uint256[](effectiveCnt);
        uint256[] memory effectiveTokenIds = new uint256[](effectiveCnt);
        int16[] memory effectiveFeeRates = new int16[](effectiveCnt);
        for ((uint256 i, uint256 idx) = (0, 0); i < balances.length; i++) {
            if (balances[i] > 0) {
                effectiveBalances[idx] = balances[i];
                effectiveTokenIds[idx] = tokenIds[i];
                effectiveFeeRates[idx] = CLBTokenLib.decodeId(tokenIds[i]);
                idx++;
            }
        }

        uint256[] memory totalSupplies = market.clbToken().totalSupplyBatch(effectiveTokenIds);
        uint256[] memory binValues = market.getBinValues(effectiveFeeRates);

        // Populate the result array with CLB token balance information
        CLBBalance[] memory result = new CLBBalance[](effectiveCnt);
        for (uint256 i = 0; i < effectiveCnt; i++) {
            result[i] = CLBBalance({
                tokenId: effectiveTokenIds[i],
                balance: effectiveBalances[i],
                totalSupply: totalSupplies[i],
                binValue: binValues[i]
            });
        }

        return result;
    }

    /**
     * @dev Retrieves the liquidity information for each liquidity bin specified by the trading fee rates and Oracle versions in the given Chromatic market.
     * @param market The address of the Chromatic market contract.
     * @param params An array of LiquidityBinsParam containing the trading fee rates and Oracle versions.
     * @return results An array of LiquidityBin containing the liquidity information for each trading fee rate and Oracle version.
     */
    function liquidityBins(
        IChromaticMarket market,
        LiquidityBinsParam[] memory params
    ) external view returns (LiquidityBin[] memory results) {
        results = new LiquidityBin[](params.length);
        for (uint i = 0; i < params.length; i++) {
            uint256 liquidity = market.getBinLiquidity(params[i].tradingFeeRate);
            uint256 freeLiquidity = market.getBinFreeLiquidity(params[i].tradingFeeRate);
            (uint256 clbTokenAmount, uint256 burningAmount, uint256 tokenAmount) = market
                .getClaimBurning(params[i].tradingFeeRate, params[i].oracleVersion);
            results[i] = LiquidityBin(
                params[i].tradingFeeRate,
                liquidity,
                freeLiquidity,
                clbTokenAmount,
                burningAmount,
                tokenAmount
            );
        }
    }
}
