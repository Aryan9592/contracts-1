// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/AggregatorProxyInterface.sol";
import "./ChainlinkRound.sol";

/// @dev ChainlinkAggregator type
type ChainlinkAggregator is address;
using ChainlinkAggregatorLib for ChainlinkAggregator global;

/**
 * @title ChainlinkAggregatorLib
 * @notice Library that manages interfacing with the Chainlink Feed Aggregator Proxy.
 */
library ChainlinkAggregatorLib {
    /**
     * @notice Returns the decimal amount for a specific feed
     * @param self Chainlink Feed Aggregator to operate on
     * @return Decimal amount
     */
    function decimals(ChainlinkAggregator self) internal view returns (uint8) {
        return AggregatorProxyInterface(ChainlinkAggregator.unwrap(self)).decimals();
    }

    /**
     * @notice Returns the latest round data for a specific feed
     * @param self Chainlink Feed Aggregator to operate on
     * @return Latest round data
     */
    function getLatestRound(
        ChainlinkAggregator self
    ) internal view returns (ChainlinkRound memory) {
        //slither-disable-next-line unused-return
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = AggregatorProxyInterface(
            ChainlinkAggregator.unwrap(self)
        ).latestRoundData();
        return ChainlinkRound({roundId: roundId, timestamp: updatedAt, answer: answer});
    }

    /**
     * @notice Returns a specific round's data for a specific feed
     * @param self Chainlink Feed Aggregator to operate on
     * @param roundId The specific round to fetch data for
     * @return Specific round's data
     */
    function getRound(
        ChainlinkAggregator self,
        uint256 roundId
    ) internal view returns (ChainlinkRound memory) {
        //slither-disable-next-line unused-return
        (, int256 answer, , uint256 updatedAt, ) = AggregatorProxyInterface(
            ChainlinkAggregator.unwrap(self)
        ).getRoundData(uint80(roundId));
        return ChainlinkRound({roundId: roundId, timestamp: updatedAt, answer: answer});
    }

    /**
     * @notice Returns the round count and next phase starting round for the lastSyncedRound phase
     * @param self Chainlink Feed Aggregator to operate on
     * @param startingRoundId starting roundId for the aggregator proxy
     * @param lastSyncedRoundId last synced round ID for the proxy
     * @param latestRound latest round from the proxy
     * @return roundCount The number of rounds in the phase
     * @return nextPhaseStartingRoundId The starting round ID for the next phase
     */
    function getPhaseSwitchoverData(
        ChainlinkAggregator self,
        uint256 startingRoundId,
        uint256 lastSyncedRoundId,
        ChainlinkRound memory latestRound
    ) internal view returns (uint256 roundCount, uint256 nextPhaseStartingRoundId) {
        AggregatorProxyInterface proxy = AggregatorProxyInterface(ChainlinkAggregator.unwrap(self));

        // Try to get the immediate next round in the same phase. If this errors, we know that the phase has ended
        //slither-disable-next-line unused-return
        try proxy.getRoundData(uint80(lastSyncedRoundId + 1)) returns (
            uint80 nextRoundId,
            int256,
            uint256,
            uint256 nextUpdatedAt,
            uint80
        ) {
            // If the next round in this phase is before the latest round, then we can safely mark that
            // as the end of the phase, and the latestRound as the start of the new phase
            // Else the next round in this phase is _after_ the latest round, then we
            // fallthrough to search for the next starting round ID using the walkback logic
            if (nextRoundId == 0 || nextUpdatedAt == 0) {
                // Invalid round
                // pass
            } else if (nextUpdatedAt < latestRound.timestamp) {
                return ((nextRoundId - startingRoundId) + 1, latestRound.roundId);
            }
        } catch {
            // pass
        }

        // lastSyncedRound is the last round it's phase before latestRound, so we need to find where the next phase starts
        // The next phase should start at the round that is closest to but after lastSyncedRound.timestamp
        //slither-disable-next-line unused-return
        (, , , uint256 lastSyncedRoundTimestamp, ) = proxy.getRoundData(uint80(lastSyncedRoundId));
        nextPhaseStartingRoundId = latestRound.roundId;
        uint256 updatedAt = latestRound.timestamp;
        // Walk back in the new phase until we dip below the lastSyncedRound.timestamp
        while (updatedAt >= lastSyncedRoundTimestamp) {
            nextPhaseStartingRoundId--;
            //slither-disable-next-line unused-return
            (, , , updatedAt, ) = proxy.getRoundData(uint80(nextPhaseStartingRoundId));
        }

        return ((lastSyncedRoundId - startingRoundId) + 1, nextPhaseStartingRoundId + 1);
    }
}
