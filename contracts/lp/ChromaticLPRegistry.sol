// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IChromaticMarketFactory} from "@chromatic-protocol/contracts/core/interfaces/IChromaticMarketFactory.sol";
import {IChromaticLP} from "@chromatic-protocol/contracts/lp/interfaces/IChromaticLP.sol";

contract ChromaticLPRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    IChromaticMarketFactory public immutable factory;

    mapping(address => EnumerableSet.AddressSet) _lpsByMarket;
    mapping(address => EnumerableSet.AddressSet) _lpsBySettlementToken;

    event ChromaticLPRegistered(address indexed lp);
    event ChromaticLPUnregistered(address indexed lp);

    error OnlyAccessableByDao();

    modifier onlyDao() {
        if (msg.sender != factory.dao()) revert OnlyAccessableByDao();
        _;
    }

    constructor(IChromaticMarketFactory _factory) {
        factory = _factory;
    }

    function register(IChromaticLP lp) external onlyDao {
        address[] memory markets = lp.markets();
        for (uint256 i = 0; i < markets.length; i++) {
            _lpsByMarket[markets[i]].add(address(lp));
        }

        _lpsBySettlementToken[lp.settlementToken()].add(address(lp));

        emit ChromaticLPRegistered(address(lp));
    }

    function unregister(IChromaticLP lp) external onlyDao {
        address[] memory markets = lp.markets();
        for (uint256 i = 0; i < markets.length; i++) {
            _lpsByMarket[markets[i]].remove(address(lp));
        }

        _lpsBySettlementToken[lp.settlementToken()].remove(address(lp));

        emit ChromaticLPUnregistered(address(lp));
    }

    function lpListByMarket(address market) external view returns (address[] memory) {
        return _lpsByMarket[market].values();
    }

    function lpListBySettlementToken(address token) external view returns (address[] memory) {
        return _lpsBySettlementToken[token].values();
    }
}
