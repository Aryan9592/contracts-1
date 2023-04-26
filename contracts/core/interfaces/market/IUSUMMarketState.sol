// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0 <0.9.0;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IOracleProvider} from "@usum/core/interfaces/IOracleProvider.sol";
import {IUSUMMarketFactory} from "@usum/core/interfaces/IUSUMMarketFactory.sol";
import {IUSUMLiquidator} from "@usum/core/interfaces/IUSUMLiquidator.sol";
import {IKeeperFeePayer} from "@usum/core/interfaces/IKeeperFeePayer.sol";

interface IUSUMMarketState {
    function factory() external view returns (IUSUMMarketFactory);

    function settlementToken() external view returns (IERC20Metadata);

    function oracleProvider() external view returns (IOracleProvider);

    function liquidator() external view returns (IUSUMLiquidator);

    function keeperFeePayer() external view returns (IKeeperFeePayer);
}
