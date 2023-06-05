// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0 <0.9.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {Fixed18} from "@equilibria/root/number/types/Fixed18.sol";
import {UFixed18, UFixed18Lib} from "@equilibria/root/number/types/UFixed18.sol";
import {IOracleProvider} from "@chromatic/core/interfaces/IOracleProvider.sol";
import {Errors} from "@chromatic/core/libraries/Errors.sol";

uint256 constant QTY_DECIMALS = 4;
uint256 constant LEVERAGE_DECIMALS = 2;
uint256 constant QTY_PRECISION = 10 ** QTY_DECIMALS;
uint256 constant LEVERAGE_PRECISION = 10 ** LEVERAGE_DECIMALS;
uint256 constant QTY_LEVERAGE_PRECISION = QTY_PRECISION * LEVERAGE_PRECISION;

/**
 * @title PositionUtil
 * @notice Provides utility functions for managing positions
 */
library PositionUtil {
    using Math for uint256;
    using SafeCast for uint256;
    using SignedMath for int256;

    /**
     * @notice Returns next oracle version to settle
     * @dev It adds 1 to the `oracleVersion`
     *      and ensures that the `oracleVersion` is greater than 0 using a require statement.
     *      If the `oracleVersion` is not valid,
     *      it will trigger an error with the message `INVALID_ORACLE_VERSION`.
     * @param oracleVersion Input oracle version
     * @return uint256 Next oracle version to settle
     */
    function settleVersion(uint256 oracleVersion) internal pure returns (uint256) {
        require(oracleVersion > 0, Errors.INVALID_ORACLE_VERSION);
        return oracleVersion + 1;
    }

    /**
     * @notice Calculates the price of the position based on the `oracleVersion` to settle
     * @dev It calls another overloaded `settlePrice` function
     *      with an additional `OracleVersion` parameter,
     *      passing the `currentVersion` obtained from the `provider`
     * @param provider The oracle provider
     * @param oracleVersion The oracle version of position
     * @return UFixed18 The calculated price to settle
     */
    function settlePrice(
        IOracleProvider provider,
        uint256 oracleVersion
    ) internal view returns (UFixed18) {
        return settlePrice(provider, oracleVersion, provider.currentVersion());
    }

    /**
     * @notice Calculates the price of the position based on the `oracleVersion` to settle
     * @dev It calculates the price by considering the `settleVersion`
     *      and the `currentVersion` obtained from the `IOracleProvider`.
     *      It ensures that the settle version is not greater than the current version;
     *      otherwise, it triggers an error with the message `UNSETTLED_POSITION`.
     *      It retrieves the corresponding `OracleVersion` using `atVersion` from the `IOracleProvider`,
     *      and then calls `oraclePrice` to obtain the price.
     * @param provider The oracle provider
     * @param oracleVersion The oracle version of position
     * @param currentVersion The current oracle version
     * @return UFixed18 The calculated entry price to settle
     */
    function settlePrice(
        IOracleProvider provider,
        uint256 oracleVersion,
        IOracleProvider.OracleVersion memory currentVersion
    ) internal view returns (UFixed18) {
        uint256 _settleVersion = settleVersion(oracleVersion);
        require(_settleVersion <= currentVersion.version, Errors.UNSETTLED_POSITION);

        IOracleProvider.OracleVersion memory _oracleVersion = _settleVersion ==
            currentVersion.version
            ? currentVersion
            : provider.atVersion(_settleVersion);
        return oraclePrice(_oracleVersion);
    }

    /**
     * @notice Extracts the price value from an `OracleVersion` struct
     * @dev If the price is less than 0, it returns 0
     * @param oracleVersion The memory instance of `OracleVersion` struct
     * @return UFixed18 The price value of `oracleVersion`
     */
    function oraclePrice(
        IOracleProvider.OracleVersion memory oracleVersion
    ) internal pure returns (UFixed18) {
        return
            oracleVersion.price.sign() < 0
                ? UFixed18Lib.ZERO
                : UFixed18Lib.from(oracleVersion.price);
    }

    /**
     * @notice Calculates the profit or loss (PnL) for a position
     *         based on the leveraged quantity, entry price, and exit price
     * @dev It first calculates the price difference (`delta`) between the exit price and the entry price.
     *      If the leveraged quantity is negative, indicating short position,
     *      it adjusts the `delta` to reflect a negative change.
     *      The function then calculates the absolute PnL
     *      by multiplying the absolute value of the leveraged quantity
     *      with the absolute value of the `delta`, divided by the entry price.
     *      Finally, if `delta` is negative, indicating a loss,
     *      the absolute PnL is negated to represent a negative value.
     * @param leveragedQty The leveraged quantity of the position
     * @param _entryPrice The entry price of the position
     * @param _exitPrice The exit price of the position
     * @return int256 The profit or loss
     */
    function pnl(
        int256 leveragedQty, // as token precision
        UFixed18 _entryPrice,
        UFixed18 _exitPrice
    ) internal pure returns (int256) {
        int256 delta = _exitPrice.gt(_entryPrice)
            ? UFixed18.unwrap(_exitPrice.sub(_entryPrice)).toInt256()
            : -UFixed18.unwrap(_entryPrice.sub(_exitPrice)).toInt256();
        if (leveragedQty < 0) delta *= -1;

        int256 absPnl = leveragedQty
            .abs()
            .mulDiv(delta.abs(), UFixed18.unwrap(_entryPrice))
            .toInt256();

        return delta < 0 ? -absPnl : absPnl;
    }

    /**
     * @notice Verifies the validity of a position quantity added to the bin
     * @dev It ensures that the sign of the current quantity of the bin's position
     *      and the added quantity are same or zero.
     *      If the condition is not met, it triggers an error with the message `INVALID_POSITION_QTY`.
     * @param currentQty The current quantity of the bin's pending position
     * @param addedQty The position quantity added
     */
    function checkAddPositionQty(int256 currentQty, int256 addedQty) internal pure {
        require(
            !((currentQty > 0 && addedQty <= 0) || (currentQty < 0 && addedQty >= 0)),
            Errors.INVALID_POSITION_QTY
        );
    }

    /**
     * @notice Verifies the validity of a position quantity removed from the bin
     * @dev It ensures that the sign of the current quantity of the bin's position
     *      and the removed quantity are same or zero,
     *      and the absolute removed quantity is not greater than the absolute current quantity.
     *      If the condition is not met, it triggers an error with the message `INVALID_POSITION_QTY`.
     * @param currentQty The current quantity of the bin's position
     * @param removeQty The position quantity removed
     */
    function checkRemovePositionQty(int256 currentQty, int256 removeQty) internal pure {
        require(
            !((currentQty == 0) ||
                (removeQty == 0) ||
                (currentQty > 0 && removeQty > currentQty) ||
                (currentQty < 0 && removeQty < currentQty)),
            Errors.INVALID_POSITION_QTY
        );
    }

    /**
     * @notice Calculates the transaction amount based on the leveraged quantity and price
     * @param leveragedQty The leveraged quantity of the position
     * @param price The price of the position
     * @return uint256 The transaction amount
     */
    function transactionAmount(
        int256 leveragedQty,
        UFixed18 price
    ) internal pure returns (uint256) {
        return leveragedQty.abs().mulDiv(UFixed18.unwrap(price), UFixed18.unwrap(UFixed18Lib.ONE));
    }
}
