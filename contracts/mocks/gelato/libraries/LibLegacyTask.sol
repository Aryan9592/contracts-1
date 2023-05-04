// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {LibDataTypes} from "./LibDataTypes.sol";
import {ILegacyAutomate} from "../interfaces/ILegacyAutomate.sol";

/**
 * @notice Library to keep task creation methods backwards compatible.
 * @notice Legacy create task methods can be found in ILegacyAutomate.sol
 */
library LibLegacyTask {
    /**
     * @notice Use legacy Automate create task calldata to construct
     * arguments that conforms to current create task format.
     *
     * @param _funcSig Function signature of calldata.
     * @param _callData Calldata that was passed from fallback function.
     */
    function getCreateTaskArg(bytes4 _funcSig, bytes calldata _callData)
        internal
        pure
        returns (
            address execAddress,
            bytes memory execData,
            LibDataTypes.ModuleData memory moduleData,
            address feeToken
        )
    {
        if (_funcSig == ILegacyAutomate.createTask.selector) {
            (execAddress, execData, moduleData, feeToken) = _resolveCreateTask(
                _callData[4:]
            );
        } else if (
            _funcSig == ILegacyAutomate.createTaskNoPrepayment.selector
        ) {
            (
                execAddress,
                execData,
                moduleData,
                feeToken
            ) = _resolveCreateTaskNoPrepayment(_callData[4:]);
        } else if (_funcSig == ILegacyAutomate.createTimedTask.selector) {
            (
                execAddress,
                execData,
                moduleData,
                feeToken
            ) = _resolveCreateTimedTask(_callData[4:]);
        } else revert("Automate.fallback: Function not found");
    }

    function _resolveCreateTask(bytes calldata _callDataSliced)
        private
        pure
        returns (
            address execAddress,
            bytes memory execData,
            LibDataTypes.ModuleData memory moduleData,
            address feeToken
        )
    {
        bytes4 execSelector;
        address resolverAddress;
        bytes memory resolverData;

        (execAddress, execSelector, resolverAddress, resolverData) = abi.decode(
            _callDataSliced,
            (address, bytes4, address, bytes)
        );

        LibDataTypes.Module[] memory modules = new LibDataTypes.Module[](1);
        modules[0] = LibDataTypes.Module.RESOLVER;

        bytes[] memory args = new bytes[](1);
        args[0] = abi.encode(resolverAddress, resolverData);

        moduleData = LibDataTypes.ModuleData(modules, args);

        execData = abi.encodePacked(execSelector);
        feeToken = address(0);
    }

    function _resolveCreateTaskNoPrepayment(bytes calldata _callDataSliced)
        private
        pure
        returns (
            address execAddress,
            bytes memory execData,
            LibDataTypes.ModuleData memory moduleData,
            address feeToken
        )
    {
        bytes4 execSelector;
        address resolverAddress;
        bytes memory resolverData;

        (
            execAddress,
            execSelector,
            resolverAddress,
            resolverData,
            feeToken
        ) = abi.decode(
            _callDataSliced,
            (address, bytes4, address, bytes, address)
        );

        LibDataTypes.Module[] memory modules = new LibDataTypes.Module[](1);
        modules[0] = LibDataTypes.Module.RESOLVER;

        bytes[] memory args = new bytes[](1);
        args[0] = abi.encode(resolverAddress, resolverData);

        moduleData = LibDataTypes.ModuleData(modules, args);

        execData = abi.encodePacked(execSelector);
    }

    function _resolveCreateTimedTask(bytes calldata _callDataSliced)
        private
        pure
        returns (
            address execAddress,
            bytes memory execData,
            LibDataTypes.ModuleData memory moduleData,
            address feeToken
        )
    {
        bytes memory resolverModuleArgs;
        bytes memory timeModuleArgs;
        (
            execAddress,
            execData,
            feeToken,
            resolverModuleArgs,
            timeModuleArgs
        ) = _decodeTimedTaskCallData(_callDataSliced);
        LibDataTypes.Module[] memory modules = new LibDataTypes.Module[](2);
        modules[0] = LibDataTypes.Module.RESOLVER;
        modules[1] = LibDataTypes.Module.TIME;

        bytes[] memory args = new bytes[](2);
        args[0] = resolverModuleArgs;
        args[1] = timeModuleArgs;

        moduleData = LibDataTypes.ModuleData(modules, args);
    }

    function _decodeTimedTaskCallData(bytes calldata _callDataSliced)
        private
        pure
        returns (
            address,
            bytes memory,
            address,
            bytes memory,
            bytes memory
        )
    {
        (
            uint128 startTime,
            uint128 interval,
            address execAddress,
            bytes4 execSelector,
            address resolverAddress,
            bytes memory resolverData,
            address feeToken,
            bool useTreasury
        ) = abi.decode(
                _callDataSliced,
                (
                    uint128,
                    uint128,
                    address,
                    bytes4,
                    address,
                    bytes,
                    address,
                    bool
                )
            );

        return (
            execAddress,
            abi.encodePacked(execSelector),
            feeToken = useTreasury ? address(0) : feeToken,
            abi.encode(resolverAddress, resolverData),
            abi.encode(startTime, interval)
        );
    }
}
