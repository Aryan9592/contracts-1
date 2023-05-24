// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0 <0.9.0;
import {Position} from "@usum/core/libraries/Position.sol";

interface ITrade {
    error ZeroTargetAmount();
    error TooSmallTakerMargin();
    error NotEnoughMarginTransfered();
    error NotExistPosition();
    error NotPermitted();
    error AlreadyClosedPosition();
    error NotClaimablePosition();
    error ExceedMaxAllowableTradingFee();
    error ClaimPositionCallbackError();

    event OpenPosition(address indexed account, Position position);

    event ClosePosition(address indexed account, Position position);

    event ClaimPosition(
        address indexed account,
        Position position,
        int256 pnl,
        uint256 interest
    );

    event TransferProtocolFee(uint256 positionId, uint256 amount);

    event Liquidate(
        address indexed account,
        Position position,
        uint256 usedKeeperFee
    );

    function openPosition(
        int224 qty,
        uint32 leverage, // BPS
        uint256 takerMargin,
        uint256 makerMargin,
        uint256 maxAllowableTradingFee,
        bytes calldata data
    ) external returns (Position memory);

    function closePosition(uint256 positionId) external;

    function claimPosition(
        uint256 positionId,
        address recipient, // EOA or account contract
        bytes calldata data
    ) external;

    function getPositions(
        uint256[] calldata positionIds
    ) external view  returns (Position[] memory positions);
}
