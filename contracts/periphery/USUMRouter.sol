// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IUSUMMarketFactory} from "@usum/core/interfaces/IUSUMMarketFactory.sol";
import {IUSUMMarket} from "@usum/core/interfaces/IUSUMMarket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {Position} from "@usum/core/libraries/Position.sol";
import {LpReceipt} from "@usum/core/libraries/LpReceipt.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {IUSUMRouter} from "@usum/periphery/interfaces/IUSUMRouter.sol";
import {VerifyCallback} from "@usum/periphery/base/VerifyCallback.sol";
import {AccountFactory} from "@usum/periphery/AccountFactory.sol";
import {Account} from "@usum/periphery/Account.sol";

contract USUMRouter is IUSUMRouter, VerifyCallback, Ownable {
    using SignedMath for int256;
    using EnumerableSet for EnumerableSet.UintSet;

    struct AddLiquidityCallbackData {
        address provider;
        uint256 amount;
    }

    struct ClaimLiquidityCallbackData {
        address provider;
    }

    struct RemoveLiquidityCallbackData {
        address provider;
        uint256 lpTokenAmount;
    }

    struct WithdrawLiquidityCallbackData {
        address provider;
    }

    AccountFactory accountFactory;
    mapping(address => mapping(address => EnumerableSet.UintSet)) private receiptIds; // market => provider => receiptIds

    error NotExistLpReceipt();

    function initialize(AccountFactory _accountFactory, address _marketFactory) external onlyOwner {
        accountFactory = _accountFactory;
        marketFactory = _marketFactory;
    }

    function addLiquidityCallback(
        address settlementToken,
        address vault,
        bytes calldata data
    ) external override verifyCallback {
        AddLiquidityCallbackData memory callbackData = abi.decode(data, (AddLiquidityCallbackData));
        SafeERC20.safeTransferFrom(
            IERC20(settlementToken),
            callbackData.provider,
            vault,
            callbackData.amount
        );
    }

    function claimLiquidityCallback(
        uint256 receiptId,
        bytes calldata data
    ) external override verifyCallback {
        ClaimLiquidityCallbackData memory callbackData = abi.decode(
            data,
            (ClaimLiquidityCallbackData)
        );
        receiptIds[msg.sender][callbackData.provider].remove(receiptId);
    }

    function removeLiquidityCallback(
        address lpToken,
        uint256 lpTokenId,
        bytes calldata data
    ) external override verifyCallback {
        RemoveLiquidityCallbackData memory callbackData = abi.decode(
            data,
            (RemoveLiquidityCallbackData)
        );
        IERC1155(lpToken).safeTransferFrom(
            callbackData.provider,
            msg.sender, // market
            lpTokenId,
            callbackData.lpTokenAmount,
            bytes("")
        );
    }

    function withdrawLiquidityCallback(
        uint256 receiptId,
        bytes calldata data
    ) external override verifyCallback {
        WithdrawLiquidityCallbackData memory callbackData = abi.decode(
            data,
            (WithdrawLiquidityCallbackData)
        );
        receiptIds[msg.sender][callbackData.provider].remove(receiptId);
    }

    function openPosition(
        address market,
        int224 qty,
        uint32 leverage,
        uint256 takerMargin,
        uint256 makerMargin,
        uint256 maxAllowableTradingFee
    ) external override returns (Position memory) {
        return
            _getAccount(msg.sender).openPosition(
                market,
                qty,
                leverage,
                takerMargin,
                makerMargin,
                maxAllowableTradingFee
            );
    }

    function closePosition(address market, uint256 positionId) external override {
        _getAccount(msg.sender).closePosition(market, positionId);
    }

    function claimPosition(address market, uint256 positionId) external override {
        _getAccount(msg.sender).claimPosition(market, positionId);
    }

    function addLiquidity(
        address market,
        int16 feeRate,
        uint256 amount,
        address recipient
    ) external override returns (LpReceipt memory receipt) {
        receipt = IUSUMMarket(market).addLiquidity(
            recipient,
            feeRate,
            abi.encode(AddLiquidityCallbackData({provider: msg.sender, amount: amount}))
        );
        receiptIds[market][msg.sender].add(receipt.id);
    }

    function claimLiquidity(address market, uint256 receiptId) external override {
        address provider = msg.sender;
        if (!receiptIds[market][provider].contains(receiptId)) revert NotExistLpReceipt();

        IUSUMMarket(market).claimLiquidity(
            receiptId,
            abi.encode(ClaimLiquidityCallbackData({provider: provider}))
        );
    }

    function removeLiquidity(
        address market,
        int16 feeRate,
        uint256 lpTokenAmount,
        address recipient
    ) external override returns (LpReceipt memory receipt) {
        receipt = IUSUMMarket(market).removeLiquidity(
            recipient,
            feeRate,
            abi.encode(
                RemoveLiquidityCallbackData({provider: msg.sender, lpTokenAmount: lpTokenAmount})
            )
        );
        receiptIds[market][msg.sender].add(receipt.id);
    }

    function withdrawLiquidity(address market, uint256 receiptId) external override {
        address provider = msg.sender;
        if (!receiptIds[market][provider].contains(receiptId)) revert NotExistLpReceipt();

        IUSUMMarket(market).withdrawLiquidity(
            receiptId,
            abi.encode(WithdrawLiquidityCallbackData({provider: provider}))
        );
    }

    function getAccount() external view override returns (address) {
        return accountFactory.getAccount(msg.sender);
    }

    function _getAccount(address owner) internal view returns (Account) {
        return Account(accountFactory.getAccount(owner));
    }
}
