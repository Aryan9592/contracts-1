// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

enum ChromaticLPAction {
    ADD_LIQUIDITY,
    REMOVE_LIQUIDITY
}

struct ChromaticLPReceipt {
    uint256 id;
    uint256 oracleVersion;
    uint256 amount;
    address recipient;
    ChromaticLPAction action;
}
