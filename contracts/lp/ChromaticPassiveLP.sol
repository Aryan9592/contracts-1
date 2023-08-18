// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/interfaces/IERC1155.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IChromaticMarket} from "@chromatic-protocol/contracts/core/interfaces/IChromaticMarket.sol";
import {IChromaticLiquidityCallback} from "@chromatic-protocol/contracts/core/interfaces/callback/IChromaticLiquidityCallback.sol";
import {LpReceipt} from "@chromatic-protocol/contracts/core/libraries/LpReceipt.sol";
import {CLBTokenLib} from "@chromatic-protocol/contracts/core/libraries/CLBTokenLib.sol";
import {IChromaticLP} from "@chromatic-protocol/contracts/lp/interfaces/IChromaticLP.sol";
import {ChromaticLPReceipt, ChromaticLPAction} from "@chromatic-protocol/contracts/lp/libraries/ChromaticLPReceipt.sol";

uint16 constant BPS = 10000;

contract ChromaticPassiveLP is IChromaticLP, IChromaticLiquidityCallback, ERC20 {
    using Math for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    struct AddLiquidityBatchCallbackData {
        address provider;
        uint256 liquidityAmount;
        uint256 holdingAmount;
    }

    struct RemoveLiquidityBatchCallbackData {
        address provider;
        uint256 lpTokenAmount;
        uint256[] clbTokenAmounts;
    }

    IChromaticMarket public immutable market;
    uint16 public immutable utilizationBPS;
    int16[] public feeRates;
    mapping(int16 => uint16) public distributionRates; // feeRate => distributionRate
    mapping(uint256 => ChromaticLPReceipt) public receipts; // receiptId => receipt
    mapping(uint256 => address) _providerMap; // receiptId => provider
    mapping(address => EnumerableSet.UintSet) _providerReceiptIds; // provider => receiptIds
    mapping(uint256 => EnumerableSet.UintSet) _lpReceiptMap; // receiptId => lpReceiptIds
    // mapping(int16 => uint256) _removingCLBTokenAmounts; // feeRate => clbTokenAmount
    mapping(int16 => uint256) _swapTokenAmount; // feeRate => tokenAmount (used temporarily within a transaction)
    mapping(int16 => uint256) _swapCLBTokenAmount; // feeRate => clbTokenAmount (used temporarily within a transaction)
    uint256 _receiptId;

    error NotMarket();
    error NotImplemeted();
    error NotExistChromaticLPReceipt();

    modifier verifyCallback() {
        if (address(market) != msg.sender) revert NotMarket();
        _;
    }

    constructor(
        IChromaticMarket _market,
        uint16 _utilizationBPS,
        int16[] memory _feeRates,
        uint16[] memory _distributionRates
    ) ERC20("", "") {
        require(_utilizationBPS <= BPS, "ChromaticPassiveLP: invalid arguments");
        require(
            _feeRates.length == _distributionRates.length,
            "ChromaticPassiveLP: invalid arguments"
        );

        market = _market;
        utilizationBPS = _utilizationBPS;
        feeRates = _feeRates;

        uint16 totalRate;
        for (uint256 i; i < _distributionRates.length; ) {
            distributionRates[_feeRates[i]] = _distributionRates[i];
            totalRate += _distributionRates[i];

            unchecked {
                i++;
            }
        }
        feeRates = _feeRates;

        require(totalRate == BPS, "ChromaticPassiveLP: sum of distribution rate is not 100%");
    }

    /**
     * @inheritdoc IChromaticLP
     */
    function markets() external view override returns (address[] memory _markets) {
        _markets = new address[](1);
        _markets[0] = address(market);
    }

    /**
     * @inheritdoc IChromaticLP
     */
    function settlementToken() external view override returns (address) {
        return address(market.settlementToken());
    }

    /**
     * @inheritdoc IChromaticLP
     */
    function lpToken() external view override returns (address) {
        return address(this);
    }

    /**
     * @inheritdoc IChromaticLP
     */
    function addLiquidity(
        uint256 amount,
        address recipient
    ) external override returns (ChromaticLPReceipt memory receipt) {
        (uint256[] memory amounts, uint256 liquidityAmount) = _distributeAmount(
            amount.mulDiv(utilizationBPS, BPS)
        );

        LpReceipt[] memory lpReceipts = market.addLiquidityBatch(
            recipient,
            feeRates,
            amounts,
            abi.encode(
                AddLiquidityBatchCallbackData({
                    provider: msg.sender,
                    liquidityAmount: liquidityAmount,
                    holdingAmount: amount - liquidityAmount
                })
            )
        );

        receipt = ChromaticLPReceipt({
            id: nextReceiptId(),
            oracleVersion: lpReceipts[0].oracleVersion,
            amount: amount,
            recipient: recipient,
            action: ChromaticLPAction.ADD_LIQUIDITY
        });

        receipts[receipt.id] = receipt;
        EnumerableSet.UintSet storage lpReceiptIdSet = _lpReceiptMap[receipt.id];
        for (uint256 i; i < lpReceipts.length; ) {
            lpReceiptIdSet.add(lpReceipts[i].id);

            unchecked {
                i++;
            }
        }

        emit AddLiquidity({
            receiptId: receipt.id,
            recipient: recipient,
            oracleVersion: receipt.oracleVersion,
            amount: amount
        });
    }

    /**
     * @inheritdoc IChromaticLP
     */
    function claimLiquidity(uint256 receiptId) external override {
        ChromaticLPReceipt memory receipt = receipts[receiptId];
        if (receipt.id == 0) revert NotExistChromaticLPReceipt();

        _clearSwapAmounts();

        // v1 = balacnesBefore...

        market.claimLiquidityBatch(_lpReceiptMap[receiptId].values(), bytes(""));

        // v2 = balacnesAfter...

        // x + v1 : totalSupply = x + v2 : totalSupply + mint
        // lpTokenAmount = (amount / (value - amount)) * lpTokenTotalSupply

        /*
        uint256 _value = value();
        uint256 _totalSupply = totalSupply();
        uint256 lpTokenAmount = _totalSupply == 0
            ? receipt.amount
            : receipt.amount.mulDiv(
                _totalSupply,
                _value + 1000 < receipt.amount ? 1000 : _value - receipt.amount
            );
        _mint(receipt.recipient, lpTokenAmount);

        emit ClaimLiquidity({receiptId: receipt.id, lpTokenAmount: lpTokenAmount});
        */
    }

    /**
     * @inheritdoc IChromaticLP
     */
    function removeLiquidity(
        uint256 lpTokenAmount,
        address recipient
    ) external override returns (ChromaticLPReceipt memory receipt) {
        int16[] memory _feeRates = feeRates;

        address[] memory _owners = new address[](_feeRates.length);
        uint256[] memory _clbTokenIds = new uint256[](_feeRates.length);
        for (uint256 i; i < _feeRates.length; ) {
            _owners[i] = address(this);
            _clbTokenIds[i] = CLBTokenLib.encodeId(_feeRates[i]);

            unchecked {
                i++;
            }
        }
        uint256[] memory _clbTokenBalances = IERC1155(market.clbToken()).balanceOfBatch(
            _owners,
            _clbTokenIds
        );

        uint256[] memory clbTokenAmounts = new uint256[](_clbTokenBalances.length);
        for (uint256 i; i < _clbTokenBalances.length; ) {
            clbTokenAmounts[i] = _clbTokenBalances[i].mulDiv(
                lpTokenAmount,
                totalSupply(),
                Math.Rounding.Up
            );

            unchecked {
                i++;
            }
        }

        LpReceipt[] memory lpReceipts = market.removeLiquidityBatch(
            recipient,
            _feeRates,
            clbTokenAmounts,
            abi.encode(
                RemoveLiquidityBatchCallbackData({
                    provider: msg.sender,
                    lpTokenAmount: lpTokenAmount,
                    clbTokenAmounts: clbTokenAmounts
                })
            )
        );

        receipt = ChromaticLPReceipt({
            id: nextReceiptId(),
            oracleVersion: lpReceipts[0].oracleVersion,
            amount: lpTokenAmount,
            recipient: recipient,
            action: ChromaticLPAction.REMOVE_LIQUIDITY
        });

        receipts[receipt.id] = receipt;
        EnumerableSet.UintSet storage lpReceiptIdSet = _lpReceiptMap[receipt.id];
        for (uint256 i; i < lpReceipts.length; ) {
            lpReceiptIdSet.add(lpReceipts[i].id);

            unchecked {
                i++;
            }
        }

        emit RemoveLiquidity({
            receiptId: receipt.id,
            recipient: recipient,
            oracleVersion: receipt.oracleVersion,
            lpTokenAmount: lpTokenAmount
        });
    }

    /**
     * @inheritdoc IChromaticLP
     */
    function withdrawLiquidity(uint256 receiptId) external override {}

    /**
     * @inheritdoc IChromaticLP
     */
    function getReceipts(
        address owner
    ) external view override returns (ChromaticLPReceipt[] memory) {}

    function nextReceiptId() private returns (uint256 id) {
        id = ++_receiptId;
    }

    function _distributeAmount(
        uint256 amount
    ) private view returns (uint256[] memory amounts, uint256 totalAmount) {
        int16[] memory _feeRates = feeRates;
        amounts = new uint256[](_feeRates.length);
        for (uint256 i = 0; i < _feeRates.length; ) {
            uint256 _amount = amount.mulDiv(distributionRates[_feeRates[i]], BPS);

            amounts[i] = _amount;
            totalAmount += _amount;

            unchecked {
                i++;
            }
        }
    }

    function _clearSwapAmounts() private {
        int16[] memory _feeRates = feeRates;
        for (uint256 i; i < _feeRates.length; ) {
            int16 _feeRate = _feeRates[i];
            delete _swapTokenAmount[_feeRate];
            delete _swapCLBTokenAmount[_feeRate];

            unchecked {
                i++;
            }
        }
    }

    /**
     * @inheritdoc ERC20
     */
    function name() public view virtual override returns (string memory) {
        return
            string(abi.encodePacked("ChromaticPassiveLP - ", _tokenSymbol(), " - ", _indexName()));
    }

    /**
     * @inheritdoc ERC20
     */
    function symbol() public view virtual override returns (string memory) {
        return string(abi.encodePacked("cp", _tokenSymbol(), " - ", _indexName()));
    }

    /**
     * @inheritdoc ERC20
     */
    function decimals() public view virtual override returns (uint8) {
        return market.settlementToken().decimals();
    }

    function _tokenSymbol() private view returns (string memory) {
        return market.settlementToken().symbol();
    }

    function _indexName() private view returns (string memory) {
        return market.oracleProvider().description();
    }

    /**
     * @inheritdoc IChromaticLiquidityCallback
     * @dev not implemented
     */
    function addLiquidityCallback(address, address, bytes calldata) external pure override {
        revert NotImplemeted();
    }

    /**
     * @inheritdoc IChromaticLiquidityCallback
     */
    function addLiquidityBatchCallback(
        address _settlementToken,
        address vault,
        bytes calldata data
    ) external override verifyCallback {
        AddLiquidityBatchCallbackData memory callbackData = abi.decode(
            data,
            (AddLiquidityBatchCallbackData)
        );
        //slither-disable-next-line arbitrary-send-erc20
        SafeERC20.safeTransferFrom(
            IERC20(_settlementToken),
            callbackData.provider,
            vault,
            callbackData.liquidityAmount
        );
        SafeERC20.safeTransferFrom(
            IERC20(_settlementToken),
            callbackData.provider,
            address(this),
            callbackData.holdingAmount
        );
    }

    /**
     * @inheritdoc IChromaticLiquidityCallback
     * @dev not implemented
     */
    function claimLiquidityCallback(
        uint256,
        int16,
        uint256,
        uint256,
        bytes calldata
    ) external pure override {
        revert NotImplemeted();
    }

    /**
     * @inheritdoc IChromaticLiquidityCallback
     */
    function claimLiquidityBatchCallback(
        uint256[] calldata receiptIds,
        int16[] calldata _feeRates,
        uint256[] calldata depositedAmounts,
        uint256[] calldata mintedCLBTokenAmounts,
        bytes calldata
    ) external override verifyCallback {
        for (uint256 i; i < receiptIds.length; ) {
            uint256 receiptId = receiptIds[i];
            address provider = _providerMap[receiptId];

            //slither-disable-next-line unused-return
            _providerReceiptIds[provider].remove(receiptId);
            delete _providerMap[receiptId];
            delete receipts[receiptId];

            unchecked {
                i++;
            }
        }
    }

    /**
     * @inheritdoc IChromaticLiquidityCallback
     * @dev not implemented
     */
    function removeLiquidityCallback(address, uint256, bytes calldata) external pure override {
        revert NotImplemeted();
    }

    /**
     * @inheritdoc IChromaticLiquidityCallback
     */
    function removeLiquidityBatchCallback(
        address clbToken,
        uint256[] calldata clbTokenIds,
        bytes calldata data
    ) external override verifyCallback {
        RemoveLiquidityBatchCallbackData memory callbackData = abi.decode(
            data,
            (RemoveLiquidityBatchCallbackData)
        );

        SafeERC20.safeTransferFrom(
            IERC20(this),
            callbackData.provider,
            address(this),
            callbackData.lpTokenAmount
        );
        IERC1155(clbToken).safeBatchTransferFrom(
            address(this),
            msg.sender, // market
            clbTokenIds,
            callbackData.clbTokenAmounts,
            bytes("")
        );
    }

    /**
     * @inheritdoc IChromaticLiquidityCallback
     * @dev not implemented
     */
    function withdrawLiquidityCallback(
        uint256,
        int16,
        uint256,
        uint256,
        bytes calldata
    ) external pure override {
        revert NotImplemeted();
    }

    /**
     * @inheritdoc IChromaticLiquidityCallback
     */
    function withdrawLiquidityBatchCallback(
        uint256[] calldata receiptIds,
        int16[] calldata _feeRates,
        uint256[] calldata withdrawnAmounts,
        uint256[] calldata burnedCLBTokenAmounts,
        bytes calldata
    ) external override verifyCallback {
        for (uint256 i; i < receiptIds.length; ) {
            uint256 receiptId = receiptIds[i];
            address provider = _providerMap[receiptId];

            //slither-disable-next-line unused-return
            _providerReceiptIds[provider].remove(receiptId);
            delete _providerMap[receiptId];
            delete receipts[receiptId];

            unchecked {
                i++;
            }
        }
    }
}
