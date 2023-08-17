// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {ChromaticLPReceipt} from "@chromatic-protocol/contracts/lp/libraries/ChromaticLPReceipt.sol";

interface IChromaticLP {
    function markets() external view returns (address[] memory);

    function settlementToken() external view returns (address);

    function lpToken() external view returns (address);

    function addLiquidity(
        uint256 amount,
        address recipient
    ) external returns (ChromaticLPReceipt memory);

    function claminLiquidity(uint256 receiptId) external;

    function removeLiquidity(
        uint256 lpTokenAmount,
        address recipient
    ) external returns (ChromaticLPReceipt memory);

    function withdrawLiquidity(uint256 receiptId) external;

    function getReceipts(address owner) external view returns (ChromaticLPReceipt[] memory);
}
