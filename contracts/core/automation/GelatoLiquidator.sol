// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0 <0.9.0;

import {IChromaticMarketFactory} from "@chromatic-protocol/contracts/core/interfaces/IChromaticMarketFactory.sol";
import {ILiquidator} from "@chromatic-protocol/contracts/core/interfaces/ILiquidator.sol";
import {IMarketLiquidate} from "@chromatic-protocol/contracts/core/interfaces/market/IMarketLiquidate.sol";
import {AutomateReady} from "@chromatic-protocol/contracts/core/automation/gelato/AutomateReady.sol";
import {ModuleData, Module, IAutomate} from "@chromatic-protocol/contracts/core/automation/gelato/Types.sol";
import {LiquidatorBase} from "@chromatic-protocol/contracts/core/automation/LiquidatorBase.sol";

/**
 * @title GelatoLiquidator
 * @dev A contract that handles the liquidation and claiming of positions in Chromatic markets.
 *      It extends the AutomateReady contracts and implements the ILiquidator interface.
 */
contract GelatoLiquidator is LiquidatorBase, AutomateReady {
    uint256 private constant DEFAULT_LIQUIDATION_INTERVAL = 1 minutes;
    uint256 private constant DEFAULT_CLAIM_INTERVAL = 1 days;

    uint256 public liquidationInterval;
    uint256 public claimInterval;

    mapping(address => mapping(uint256 => bytes32)) private _liquidationTaskIds;
    mapping(address => mapping(uint256 => bytes32)) private _claimPositionTaskIds;

    /**
     * @notice Emitted when the liquidation task interval is updated.
     * @param interval The new liquidation task interval.
     */
    event UpdateLiquidationInterval(uint256 indexed interval);

    /**
     * @notice Emitted when the claim task interval is updated.
     * @param interval The new claim task interval.
     */
    event UpdateClaimInterval(uint256 indexed interval);

    /**
     * @dev Constructor function.
     * @param _factory The address of the Chromatic Market Factory contract.
     * @param _automate The address of the Gelato Automate contract.
     * @param opsProxyFactory The address of the Ops Proxy Factory contract.
     */
    constructor(
        IChromaticMarketFactory _factory,
        address _automate,
        address opsProxyFactory
    ) LiquidatorBase(_factory) AutomateReady(_automate, address(this), opsProxyFactory) {
        liquidationInterval = DEFAULT_LIQUIDATION_INTERVAL;
        claimInterval = DEFAULT_CLAIM_INTERVAL;
    }

    /**
     * @notice Updates the liquidation task interval.
     * @param interval The new liquidation task interval.
     */
    function updateLiquidationInterval(uint256 interval) external onlyDao {
        liquidationInterval = interval;
        emit UpdateLiquidationInterval(interval);
    }

    /**
     * @notice Updates the claim task interval.
     * @param interval The new claim task interval.
     */
    function updateClaimInterval(uint256 interval) external onlyDao {
        claimInterval = interval;
        emit UpdateClaimInterval(interval);
    }

    /**
     * @inheritdoc ILiquidator
     * @dev Can only be called by a registered market.
     */
    function createLiquidationTask(uint256 positionId) external override onlyMarket {
        _createTask(_liquidationTaskIds, positionId, this.resolveLiquidation, liquidationInterval);
    }

    /**
     * @inheritdoc ILiquidator
     * @dev Can only be called by a registered market.
     */
    function cancelLiquidationTask(uint256 positionId) external override onlyMarket {
        _cancelTask(_liquidationTaskIds, positionId);
    }

    /**
     * @inheritdoc ILiquidator
     */
    function resolveLiquidation(
        address _market,
        uint256 positionId
    ) external view override returns (bool canExec, bytes memory execPayload) {
        if (IMarketLiquidate(_market).checkLiquidation(positionId)) {
            return (true, abi.encodeCall(this.liquidate, (_market, positionId)));
        }

        return (false, bytes(""));
    }

    /**
     * @inheritdoc ILiquidator
     * @dev Can only be called by a registered market.
     */
    function createClaimPositionTask(uint256 positionId) external override onlyMarket {
        _createTask(_claimPositionTaskIds, positionId, this.resolveClaimPosition, claimInterval);
    }

    /**
     * @inheritdoc ILiquidator
     * @dev Can only be called by a registered market.
     */
    function cancelClaimPositionTask(uint256 positionId) external override onlyMarket {
        _cancelTask(_claimPositionTaskIds, positionId);
    }

    /**
     * @inheritdoc ILiquidator
     */
    function resolveClaimPosition(
        address _market,
        uint256 positionId
    ) external view override returns (bool canExec, bytes memory execPayload) {
        if (IMarketLiquidate(_market).checkClaimPosition(positionId)) {
            return (true, abi.encodeCall(this.claimPosition, (_market, positionId)));
        }

        return (false, "");
    }

    /**
     * @dev Internal function to create a Gelato task for liquidation or claim position.
     * @param registry The mapping to store task IDs.
     * @param positionId The ID of the position.
     * @param resolve The resolve function to be called by the Gelato automation system.
     * @param interval The interval between task executions.
     */
    function _createTask(
        mapping(address => mapping(uint256 => bytes32)) storage registry,
        uint256 positionId,
        function(address, uint256) external view returns (bool, bytes memory) resolve,
        uint256 interval
    ) internal {
        address market = msg.sender;
        if (registry[market][positionId] != bytes32(0)) {
            return;
        }

        ModuleData memory moduleData = ModuleData({modules: new Module[](3), args: new bytes[](3)});

        moduleData.modules[0] = Module.RESOLVER;
        moduleData.modules[1] = Module.TIME;
        moduleData.modules[2] = Module.PROXY;
        moduleData.args[0] = abi.encode(
            address(this),
            abi.encodeCall(resolve, (market, positionId))
        );
        moduleData.args[1] = abi.encode(uint128(block.timestamp + interval), uint128(interval));
        moduleData.args[2] = bytes("");

        registry[market][positionId] = automate.createTask(
            address(this),
            abi.encode(this.liquidate.selector),
            moduleData,
            ETH
        );
    }

    /**
     * @dev Internal function to cancel a Gelato task.
     * @param registry The mapping storing task IDs.
     * @param positionId The ID of the position.
     */
    function _cancelTask(
        mapping(address => mapping(uint256 => bytes32)) storage registry,
        uint256 positionId
    ) internal {
        address market = msg.sender;
        bytes32 taskId = registry[market][positionId];
        if (taskId != bytes32(0)) {
            automate.cancelTask(taskId);
            delete registry[market][positionId];
        }
    }

    function getLiquidationTaskId(
        address market,
        uint256 positionId
    ) external view returns (bytes32 taskId) {
        taskId = _liquidationTaskIds[market][positionId];
    }

    function getClaimPositionTaskId(
        address market,
        uint256 positionId
    ) external view returns (bytes32 taskId) {
        taskId = _claimPositionTaskIds[market][positionId];
    }

    function _getFeeInfo() internal view override returns (uint256 fee, address feePayee) {
        (fee, ) = _getFeeDetails();
        feePayee = automate.gelato();
    }
}
