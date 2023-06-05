// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IChromaticMarket} from "@chromatic/core/interfaces/IChromaticMarket.sol";
import {IChromaticTradeCallback} from "@chromatic/core/interfaces/callback/IChromaticTradeCallback.sol";
import {Position} from "@chromatic/core/libraries/Position.sol";
import {IAccount} from "@chromatic/periphery/interfaces/IAccount.sol";
import {VerifyCallback} from "@chromatic/periphery/base/VerifyCallback.sol";

contract Account is IAccount, VerifyCallback {
    using EnumerableSet for EnumerableSet.UintSet;

    address owner;
    address private router;
    bool isInitialized;

    mapping(address => EnumerableSet.UintSet) private positionIds;

    error NotRouter();
    error NotOwner();
    error AlreadyInitialized();
    error NotEnoughBalance();
    error NotExistPosition();

    modifier onlyRouter() {
        if (msg.sender != router) revert NotRouter();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function initialize(address _owner, address _router, address _marketFactory) external {
        if (isInitialized) revert AlreadyInitialized();
        owner = _owner;
        router = _router;
        isInitialized = true;
        marketFactory = _marketFactory;
    }

    function balance(address quote) public view returns (uint256) {
        return IERC20(quote).balanceOf(address(this));
    }

    function withdraw(address quote, uint256 amount) external onlyOwner {
        if (balance(quote) < amount) revert NotEnoughBalance();
        SafeERC20.safeTransfer(IERC20(quote), owner, amount);
    }

    function transferMargin(
        uint256 marginRequired,
        address marketAddress,
        address settlementToken
    ) external onlyRouter {
        if (balance(settlementToken) < marginRequired) revert NotEnoughBalance();

        SafeERC20.safeTransfer(IERC20(settlementToken), marketAddress, marginRequired);
    }

    function addPositionId(address market, uint256 positionId) internal {
        positionIds[market].add(positionId);
    }

    function removePositionId(address market, uint256 positionId) internal {
        positionIds[market].remove(positionId);
    }

    function hasPositionId(address market, uint256 id) public view returns (bool) {
        return positionIds[market].contains(id);
    }

    function getPositionIds(address market) external view returns (uint256[] memory) {
        return positionIds[market].values();
    }

    function openPosition(
        address marketAddress,
        int224 qty,
        uint32 leverage,
        uint256 takerMargin,
        uint256 makerMargin,
        uint256 maxAllowableTradingFee
    ) external onlyRouter returns (Position memory position) {
        position = IChromaticMarket(marketAddress).openPosition(
            qty,
            leverage,
            takerMargin,
            makerMargin,
            maxAllowableTradingFee,
            bytes("")
        );
        addPositionId(marketAddress, position.id);
    }

    function closePosition(address marketAddress, uint256 positionId) external override onlyRouter {
        if (!hasPositionId(marketAddress, positionId)) revert NotExistPosition();

        IChromaticMarket(marketAddress).closePosition(positionId);
    }

    function claimPosition(address marketAddress, uint256 positionId) external override onlyRouter {
        if (!hasPositionId(marketAddress, positionId)) revert NotExistPosition();

        IChromaticMarket(marketAddress).claimPosition(positionId, address(this), bytes(""));
    }

    function openPositionCallback(
        address settlementToken,
        address vault,
        uint256 marginRequired,
        bytes calldata data
    ) external override verifyCallback {
        if (balance(settlementToken) < marginRequired) revert NotEnoughBalance();

        SafeERC20.safeTransfer(IERC20(settlementToken), vault, marginRequired);
    }

    function claimPositionCallback(
        uint256 positionId,
        bytes calldata data
    ) external override verifyCallback {
        removePositionId(msg.sender, positionId);
    }
}
