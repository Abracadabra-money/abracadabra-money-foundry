// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "BoringSolidity/BoringOwnable.sol";
import "BoringSolidity/libraries/BoringERC20.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/IAnyswapRouter.sol";
import "interfaces/ICauldronV1.sol";
import "interfaces/ICauldronV2.sol";
import "interfaces/ICauldronFeeBridger.sol";
import "libraries/SafeApprove.sol";

contract CauldronFeeWithdrawer is BoringOwnable {
    using BoringERC20 for IERC20;
    using SafeApprove for IERC20;

    event LogOperatorChanged(address indexed operator, bool previous, bool current);
    event LogSwappingRecipientChanged(address indexed recipient, bool previous, bool current);
    event LogAllowedSwapTokenOutChanged(IERC20 indexed token, bool previous, bool current);
    event LogMimWithdrawn(IBentoBoxV1 indexed bentoBox, uint256 amount);
    event LogMimTotalWithdrawn(uint256 amount);
    event LogSwapMimTransfer(uint256 amounIn, uint256 amountOut, IERC20 tokenOut);
    event LogBentoBoxChanged(IBentoBoxV1 indexed bentoBox, bool previous, bool current);
    event LogCauldronChanged(address indexed cauldron, bool previous, bool current);
    event LogBridgeableTokenChanged(IERC20 indexed token, bool previous, bool current);
    event LogParametersChanged(address indexed swapper, address indexed mimProvider, ICauldronFeeBridger indexed bridger);

    error ErrUnsupportedToken(IERC20 tokenOut);
    error ErrNotOperator(address operator);
    error ErrSwapFailed();
    error ErrInvalidFeeTo(address masterContract);
    error ErrInsufficientAmountOut(uint256 amountOut);
    error ErrInvalidSwappingRecipient(address recipient);
    error ErrNoBridger();

    struct CauldronInfo {
        address cauldron;
        address masterContract;
        IBentoBoxV1 bentoBox;
        uint8 version;
    }

    IERC20 public immutable mim;

    address public swapper;
    address public mimProvider;
    ICauldronFeeBridger public bridger;

    mapping(IERC20 => bool) public swapTokenOutEnabled;
    mapping(IERC20 => bool) public bridgeableTokens;

    mapping(address => bool) public operators;
    mapping(address => bool) public swappingRecipients;

    CauldronInfo[] public cauldronInfos;
    IBentoBoxV1[] public bentoBoxes;

    modifier onlyOperators() {
        if (msg.sender != owner && !operators[msg.sender]) {
            revert ErrNotOperator(msg.sender);
        }
        _;
    }

    constructor(IERC20 _mim) {
        mim = _mim;
    }

    function bentoBoxesCount() external view returns (uint256) {
        return bentoBoxes.length;
    }

    function cauldronInfosCount() external view returns (uint256) {
        return cauldronInfos.length;
    }

    function withdraw() external {
        for (uint256 i = 0; i < cauldronInfos.length; i++) {
            CauldronInfo memory info = cauldronInfos[i];

            if (ICauldronV1(info.masterContract).feeTo() != address(this)) {
                revert ErrInvalidFeeTo(info.masterContract);
            }

            ICauldronV1(info.cauldron).accrue();
            uint256 feesEarned;
            IBentoBoxV1 bentoBox = info.bentoBox;

            if (info.version == 1) {
                (, feesEarned) = ICauldronV1(info.cauldron).accrueInfo();
            } else if (info.version >= 2) {
                (, feesEarned, ) = ICauldronV2(info.cauldron).accrueInfo();
            }

            uint256 cauldronMimAmount = bentoBox.toAmount(mim, bentoBox.balanceOf(mim, info.cauldron), false);
            if (feesEarned > cauldronMimAmount) {
                // only transfer the required mim amount
                uint256 diff = feesEarned - cauldronMimAmount;
                mim.safeTransferFrom(mimProvider, address(bentoBox), diff);
                bentoBox.deposit(mim, address(bentoBox), info.cauldron, diff, 0);
            }

            ICauldronV1(info.cauldron).withdrawFees();
        }

        uint256 amount = withdrawAllMimFromBentoBoxes();
        emit LogMimTotalWithdrawn(amount);
    }

    function withdrawAllMimFromBentoBoxes() public returns (uint256 totalAmount) {
        for (uint256 i = 0; i < bentoBoxes.length; i++) {
            uint256 share = bentoBoxes[i].balanceOf(mim, address(this));
            (uint256 amount, ) = bentoBoxes[i].withdraw(mim, address(this), address(this), 0, share);
            totalAmount += amount;

            emit LogMimWithdrawn(bentoBoxes[i], amount);
        }
    }

    function swapMimAndTransfer(
        uint256 amountOutMin,
        IERC20 tokenOut,
        address recipient,
        bytes calldata data
    ) external onlyOperators {
        if (!swapTokenOutEnabled[tokenOut]) {
            revert ErrUnsupportedToken(tokenOut);
        }
        if (!swappingRecipients[recipient]) {
            revert ErrInvalidSwappingRecipient(recipient);
        }

        uint256 amountInBefore = mim.balanceOf(address(this));
        uint256 amountOutBefore = tokenOut.balanceOf(address(this));

        (bool success, ) = swapper.call(data);
        if (!success) {
            revert ErrSwapFailed();
        }

        uint256 amountOut = tokenOut.balanceOf(address(this)) - amountOutBefore;
        if (amountOut < amountOutMin) {
            revert ErrInsufficientAmountOut(amountOut);
        }

        uint256 amountIn = amountInBefore - mim.balanceOf(address(this));
        tokenOut.safeTransfer(recipient, amountOut);

        emit LogSwapMimTransfer(amountIn, amountOut, tokenOut);
    }

    function bridgeAll(IERC20 token) external onlyOperators {
        if (!bridgeableTokens[token]) {
            revert ErrUnsupportedToken(token);
        }

        _bridge(token, token.balanceOf(address(this)));
    }

    function bridge(IERC20 token, uint256 amount) external onlyOperators {
        if (!bridgeableTokens[token]) {
            revert ErrUnsupportedToken(token);
        }

        if (address(bridger) == address(0)) {
            revert ErrNoBridger();
        }

        _bridge(token, amount);
    }

    function _bridge(IERC20 token, uint256 amount) private {
        token.safeTransfer(address(bridger), amount);
        bridger.bridge(token, amount);
    }

    function setCauldron(
        address cauldron,
        uint8 version,
        bool enabled
    ) external onlyOwner {
        _setCauldron(cauldron, version, enabled);
    }

    function setCauldrons(
        address[] memory cauldrons,
        uint8[] memory versions,
        bool[] memory enabled
    ) external onlyOwner {
        for (uint256 i = 0; i < cauldrons.length; i++) {
            _setCauldron(cauldrons[i], versions[i], enabled[i]);
        }
    }

    function _setCauldron(
        address cauldron,
        uint8 version,
        bool enabled
    ) private {
        bool previousEnabled;

        for (uint256 i = 0; i < cauldronInfos.length; i++) {
            if (cauldronInfos[i].cauldron == cauldron) {
                cauldronInfos[i] = cauldronInfos[cauldronInfos.length - 1];
                cauldronInfos.pop();
                break;
            }
        }

        if (enabled) {
            cauldronInfos.push(
                CauldronInfo({
                    cauldron: cauldron,
                    masterContract: address(ICauldronV1(cauldron).masterContract()),
                    bentoBox: IBentoBoxV1(ICauldronV1(cauldron).bentoBox()),
                    version: version
                })
            );
        }

        emit LogCauldronChanged(cauldron, previousEnabled, enabled);
    }

    function setOperator(address operator, bool enabled) external onlyOwner {
        emit LogOperatorChanged(operator, operators[operator], enabled);
        operators[operator] = enabled;
    }

    function setSwappingRecipient(address recipient, bool enabled) external onlyOwner {
        emit LogSwappingRecipientChanged(recipient, swappingRecipients[recipient], enabled);
        swappingRecipients[recipient] = enabled;
    }

    function setSwapTokenOut(IERC20 token, bool enabled) external onlyOwner {
        emit LogAllowedSwapTokenOutChanged(token, swapTokenOutEnabled[token], enabled);
        swapTokenOutEnabled[token] = enabled;
    }

    function setBridgeableToken(IERC20 token, bool enabled) external onlyOwner {
        emit LogBridgeableTokenChanged(token, bridgeableTokens[token], enabled);
        bridgeableTokens[token] = enabled;
    }

    function setParameters(
        address _swapper,
        address _mimProvider,
        ICauldronFeeBridger _bridger
    ) external onlyOwner {
        if (_swapper != swapper) {
            if (swapper != address(0)) {
                mim.approve(swapper, 0);
            }

            mim.approve(_swapper, type(uint256).max);
            swapper = _swapper;
        }

        mimProvider = _mimProvider;
        bridger = _bridger;

        emit LogParametersChanged(_swapper, _mimProvider, _bridger);
    }

    function setBentoBox(IBentoBoxV1 bentoBox, bool enabled) external onlyOwner {
        bool previousEnabled;

        for (uint256 i = 0; i < bentoBoxes.length; i++) {
            if (bentoBoxes[i] == bentoBox) {
                bentoBoxes[i] = bentoBoxes[bentoBoxes.length - 1];
                bentoBoxes.pop();
                previousEnabled = true;
                break;
            }
        }

        if (enabled) {
            bentoBoxes.push(bentoBox);
        }

        emit LogBentoBoxChanged(bentoBox, previousEnabled, enabled);
    }

    function rescueTokens(
        IERC20 token,
        address to,
        uint256 amount
    ) external onlyOwner {
        token.safeTransfer(to, amount);
    }

    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external onlyOwner returns (bool success, bytes memory result) {
        // solhint-disable-next-line avoid-low-level-calls
        (success, result) = to.call{value: value}(data);
    }
}
