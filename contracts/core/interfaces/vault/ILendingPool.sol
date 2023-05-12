// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface ILendingPool {
    event FlashLoan(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 paid,
        uint256 paidToTakerPool,
        uint256 paidToMakerPool
    );

    function flashLoan(
        address token,
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external;
}
