// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {IOracleProvider, OracleVersion, Phase} from "@usum/core/interfaces/IOracleProvider.sol";
import {AggregatorV2V3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import {ChainlinkRoundLib} from "@usum/core/libraries/ChainlinkRoundLib.sol";

contract OracleProvider is IOracleProvider {
    Phase[] private phases;
    uint256 private lastSyncedRoundId;
    AggregatorV2V3Interface chainlinkPriceFeed;
    uint256 public immutable override pricePrecision;

    error InvalidVersion();

    constructor(address _chainlinkPriceFeed) {
        chainlinkPriceFeed = AggregatorV2V3Interface(_chainlinkPriceFeed);
        pricePrecision = 10 ** chainlinkPriceFeed.decimals();

        (uint80 roundId, , , , ) = chainlinkPriceFeed.latestRoundData();
        require(roundId > 0); // FIXME

        lastSyncedRoundId = roundId;
        phases.push(
            Phase({
                phaseId: ChainlinkRoundLib.getPhaseId(roundId),
                startingRoundId: roundId,
                startingVersion: 1
            })
        );
    }

    function syncVersion() external override returns (OracleVersion memory) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,

        ) = chainlinkPriceFeed.latestRoundData();

        // sync
        uint16 currentPhaseId = ChainlinkRoundLib.getPhaseId(roundId);
        uint256 syncedPhaseIndex = phases.length - 1;
        Phase storage lastSyncedPhase = phases[syncedPhaseIndex];
        uint256 newVersion;
        if (lastSyncedPhase.phaseId < currentPhaseId) {
            newVersion =
                lastSyncedPhase.startingVersion +
                lastSyncedRoundId -
                lastSyncedPhase.startingRoundId +
                1;

            phases.push(
                Phase({
                    phaseId: currentPhaseId,
                    startingRoundId: roundId,
                    startingVersion: newVersion
                })
            );
        } else {
            newVersion =
                lastSyncedPhase.startingVersion +
                roundId -
                lastSyncedPhase.startingRoundId;
        }
        if (lastSyncedRoundId != roundId) {
            lastSyncedRoundId = roundId;
            emit OracleVersionUpdated(newVersion, updatedAt, answer);
        }

        return
            OracleVersion({
                version: newVersion,
                price: answer,
                timestamp: updatedAt
            });
    }

    function currentVersion()
        external
        view
        override
        returns (OracleVersion memory)
    {
        //
        // lastSyncedRoundId
        uint256 syncedPhaseIndex = phases.length - 1;
        Phase storage lastSyncedPhase = phases[syncedPhaseIndex];
        uint256 version = lastSyncedPhase.startingVersion +
            lastSyncedRoundId -
            lastSyncedPhase.startingRoundId;

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,

        ) = chainlinkPriceFeed.getRoundData(uint80(lastSyncedRoundId));
        return
            OracleVersion({
                version: version,
                price: answer,
                timestamp: updatedAt
            });
    }

    function atVersion(
        uint256 oracleVersion
    ) external view override returns (OracleVersion memory) {
        // version
        uint80 roundId = calcRoundId(oracleVersion);
        if (roundId > lastSyncedRoundId || roundId == 0)
            revert InvalidVersion();

        (
            uint256 _1,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,

        ) = chainlinkPriceFeed.getRoundData(roundId);

        return
            OracleVersion({
                version: oracleVersion,
                price: answer,
                timestamp: updatedAt
            });
    }

    function calcRoundId(uint256 oracleVersion) internal view returns (uint80) {
        uint256 phaseIndex = phases.length - 1;
        while (phaseIndex >= 0) {
            Phase storage phase = phases[phaseIndex];
            if (oracleVersion < phase.startingVersion) {
                phaseIndex--;
                continue;
            }
            return
                uint80(
                    phase.startingRoundId +
                        (oracleVersion - phase.startingVersion)
                );
        }
        return 0;
    }

    function description() external view override returns (string memory) {
        return chainlinkPriceFeed.description();
    }
}
