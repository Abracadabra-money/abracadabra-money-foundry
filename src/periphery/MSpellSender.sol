// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "BoringSolidity/ERC20.sol";
import "BoringSolidity/libraries/BoringERC20.sol";
import "BoringSolidity/BoringOwnable.sol";
import "libraries/BokkyPooBahsDateTimeLibrary.sol"; // Thank you Bokky
import "interfaces/IAnyswapRouter.sol";
import "interfaces/ILayerZeroReceiver.sol";
import "interfaces/ICauldronFeeWithdrawer.sol";
import "interfaces/IMSpell.sol";

interface IResolver {
    function checker() external view returns (bool canExec, bytes memory execPayload);
}

contract MSpellSender is BoringOwnable, ILayerZeroReceiver, IResolver {
    using BoringERC20 for ERC20;

    /// EVENTS
    event LogSetOperator(address indexed operator, bool status);
    event LogAddRecipient(address indexed recipient, uint256 chainId, uint256 chainIdLZ);
    event LogBridgeToRecipient(address indexed recipient, uint256 amount, uint256 chainId);
    event LogSpellStakedReceived(uint16 srcChainId, uint32 timestamp, uint128 amount);
    event LogSetReporter(uint256 indexed chainIdLZ, bytes reporter);
    event LogChangePurchaser(address _purchaser, address _treasury, uint256 _treasuryPercentage);
    event LogSetWithdrawer(ICauldronFeeWithdrawer indexed previous, ICauldronFeeWithdrawer indexed current);

    /// CONSTANTS
    ERC20 private constant MIM = ERC20(0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3);
    ERC20 private constant SPELL = ERC20(0x090185f2135308BaD17527004364eBcC2D37e5F6);
    address private constant SSPELL = 0x26FA3fFFB6EfE8c1E69103aCb4044C26B9A106a9;
    address private constant ANY_MIM = 0xbbc4A8d076F4B1888fec42581B6fc58d242CF2D5;
    IAnyswapRouter private constant ANYSWAP_ROUTER = IAnyswapRouter(0x6b7a87899490EcE95443e979cA9485CBE7E71522);
    address private constant ENDPOINT = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;

    ICauldronFeeWithdrawer public withdrawer;
    address public sspellBuyBack = 0xfddfE525054efaAD204600d00CA86ADb1Cc2ea8a;
    address public treasury = 0xDF2C270f610Dc35d8fFDA5B453E74db5471E126B;
    uint256 public treasuryPercentage = 25;
    uint256 private constant PRECISION = 100;

    struct MSpellRecipients {
        address recipient;
        uint32 chainId;
        uint32 chainIdLZ;
        uint32 lastUpdated;
        uint128 amountStaked;
    }

    struct ActiveChain {
        uint8 isActive;
        uint32 position;
    }

    MSpellRecipients[] public recipients;
    mapping(uint256 => ActiveChain) public isActiveChain;
    mapping(uint256 => bytes) public mSpellReporter;
    mapping(address => bool) public isOperator;
    uint256 private lastDistributed;

    error NotNoon();
    error NotPastNoon();
    error NotUpdated(uint256);

    modifier onlyOperator() {
        require(isOperator[msg.sender], "only operator");
        _;
    }

    modifier onlyNoon() {
        uint256 hour = (block.timestamp / 1 hours) % 24;
        if (hour != 12) {
            revert NotNoon();
        }
        _;
    }

    modifier onlyPastNoon() {
        uint256 hour = (block.timestamp / 1 hours) % 24;
        if (hour != 13) {
            revert NotPastNoon();
        }
        _;
    }

    constructor() {
        MIM.approve(address(ANYSWAP_ROUTER), type(uint256).max);
    }

    function checker() external view override returns (bool canExec, bytes memory execPayload) {
        uint256 currentDay = BokkyPooBahsDateTimeLibrary.getDay(block.timestamp);

        if ((block.timestamp / 1 hours) % 24 != 13 && BokkyPooBahsDateTimeLibrary.getDay(lastDistributed) != currentDay) {
            return (false, bytes("Not Right Hour"));
        }

        uint256 length = recipients.length;
        for (uint256 i = 0; i < length; i++) {
            if (recipients[i].chainId != 1) {
                if (BokkyPooBahsDateTimeLibrary.getDay(uint256(recipients[i].lastUpdated)) != currentDay) {
                    return (false, bytes("Not Updated"));
                }
            }
        }

        execPayload = abi.encodeWithSelector(MSpellSender.bridgeMim.selector);
        return (true, execPayload);
    }

    function bridgeMim() external onlyPastNoon {
        uint256 summedRatio;
        uint256 totalAmount = MIM.balanceOf(address(withdrawer));
        uint256 amountToBeDistributed = totalAmount - (totalAmount * treasuryPercentage) / PRECISION;

        withdrawer.rescueTokens(MIM, address(this), amountToBeDistributed);
        withdrawer.rescueTokens(MIM, treasury, (totalAmount * treasuryPercentage) / PRECISION);

        uint256 currentDay = BokkyPooBahsDateTimeLibrary.getDay(block.timestamp);
        uint256 sspellAmount = SPELL.balanceOf(SSPELL);
        uint256 mspellAmount;
        uint256 length = recipients.length;
        for (uint256 i = 0; i < length; i++) {
            if (recipients[i].chainId != 1) {
                summedRatio += recipients[i].amountStaked;
                if (BokkyPooBahsDateTimeLibrary.getDay(uint256(recipients[i].lastUpdated)) != currentDay) {
                    revert NotUpdated(recipients[i].chainId);
                }
            } else {
                mspellAmount = SPELL.balanceOf(recipients[i].recipient);
                summedRatio += mspellAmount + sspellAmount;
            }
        }

        for (uint256 i = 0; i < length; i++) {
            if (recipients[i].chainId != 1) {
                uint256 amount = (amountToBeDistributed * recipients[i].amountStaked) / summedRatio;
                if (amount > 0) {
                    ANYSWAP_ROUTER.anySwapOutUnderlying(ANY_MIM, recipients[i].recipient, amount, recipients[i].chainId);
                    emit LogBridgeToRecipient(recipients[i].recipient, amount, recipients[i].chainId);
                }
            } else {
                uint256 amountMSpell = (amountToBeDistributed * mspellAmount) / summedRatio;
                uint256 amountsSpell = (amountToBeDistributed * sspellAmount) / summedRatio;

                MIM.transfer(recipients[i].recipient, amountMSpell);
                IMSpell(recipients[i].recipient).updateReward();
                MIM.transfer(sspellBuyBack, amountsSpell);
            }
        }

        lastDistributed = block.timestamp;
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64,
        bytes calldata _payload
    ) external onlyNoon {
        require(msg.sender == ENDPOINT);
        uint256 position = isActiveChain[uint256(_srcChainId)].position;
        MSpellRecipients storage recipient = recipients[position];
        require(
            _srcAddress.length == mSpellReporter[uint256(_srcChainId)].length &&
                keccak256(_srcAddress) == keccak256(mSpellReporter[uint256(_srcChainId)])
        );
        (uint32 timestamp, uint128 amount) = abi.decode(_payload, (uint32, uint128));
        recipient.amountStaked = amount;
        recipient.lastUpdated = timestamp;
        emit LogSpellStakedReceived(_srcChainId, timestamp, amount);
    }

    function addMSpellRecipient(
        address recipient,
        uint256 chainId,
        uint256 chainIdLZ
    ) external onlyOwner {
        require(isActiveChain[chainIdLZ].isActive == 0, "chainId already added");
        uint256 position = recipients.length;
        isActiveChain[chainIdLZ] = ActiveChain(1, uint32(position));
        recipients.push(MSpellRecipients(recipient, uint32(chainId), uint32(chainIdLZ), 0, 0));
        emit LogAddRecipient(recipient, chainId, chainIdLZ);
    }

    function setOperator(address operator, bool status) external onlyOwner {
        isOperator[operator] = status;
        emit LogSetOperator(operator, status);
    }

    function addReporter(bytes calldata reporter, uint256 chainIdLZ) external onlyOwner {
        mSpellReporter[chainIdLZ] = reporter;
        emit LogSetReporter(chainIdLZ, reporter);
    }

    function transferWithdrawer(address newOwner) external onlyOwner {
        withdrawer.transferOwnership(newOwner, true, false);
    }

    function changePurchaser(
        address _purchaser,
        address _treasury,
        uint256 _treasuryPercentage
    ) external onlyOwner {
        sspellBuyBack = _purchaser;
        treasury = _treasury;
        treasuryPercentage = _treasuryPercentage;
        emit LogChangePurchaser(_purchaser, _treasury, _treasuryPercentage);
    }

    function setWithdrawer(ICauldronFeeWithdrawer _withdrawer) external onlyOwner {
        emit LogSetWithdrawer(withdrawer, _withdrawer);
        withdrawer = _withdrawer;
    }
}
