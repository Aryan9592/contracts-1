// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {Fixed18} from "@equilibria/root/number/types/Fixed18.sol";
import {IOracleProvider} from "@usum/core/interfaces/IOracleProvider.sol";

contract OracleProviderMock is IOracleProvider {
    mapping(uint256 => OracleVersion) oracleVersions;
    uint256 private latestVersion;

    error InvalidVersion();

    function increaseVersion(Fixed18 price) public {
        latestVersion++;

        IOracleProvider.OracleVersion memory oracleVersion;
        oracleVersion.version = latestVersion;
        oracleVersion.timestamp = block.timestamp;
        oracleVersion.price = price;
        oracleVersions[latestVersion] = oracleVersion;
    }

    function sync() external override returns (OracleVersion memory) {
        return oracleVersions[latestVersion];
    }

    function currentVersion()
        external
        view
        override
        returns (OracleVersion memory)
    {
        return oracleVersions[latestVersion];
    }

    function atVersion(
        uint256 version
    ) external view override returns (OracleVersion memory oracleVersion) {
        oracleVersion = oracleVersions[version];
        if (version != oracleVersion.version) revert InvalidVersion();
    }

    function description() external pure override returns (string memory) {
        return "ETH / USD";
    }

    function atVersions(
        uint256[] calldata versions
    ) external view returns (OracleVersion[] memory) {}
}
