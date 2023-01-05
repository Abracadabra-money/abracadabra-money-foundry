// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "BoringSolidity/ERC20.sol";
import "interfaces/ICauldronV4.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/IRewarder.sol";
import "periphery/Operatable.sol";

contract MimCauldronDistributor is Operatable {
    event LogPaused(bool previous, bool current);
    event LogCauldronParameterChanged(ICauldronV4 indexed cauldron, uint256 targetApy);
    event LogFeeParametersChanged(address indexed feeCollector, uint88 _interest);

    error ErrInvalidFeePercent();
    error ErrPaused();
    error ErrInvalidTargetApy(uint256);

    /// @notice to compute the current apy, take the latest LogDistribution event
    struct CauldronInfo {
        ICauldronV4 cauldron;
        uint256 targetApyPerSecond;
        uint64 lastDistribution;
        // caching
        IOracle oracle;
        bytes oracleData;
        IBentoBoxV1 degenBox;
        IERC20 collateral;
        uint256 minTotalBorrowElastic;
        IRewarder rewarder;
    }

    uint256 public constant BIPS = 10_000;
    uint256 private constant INTEREST_PRECISION = 1e18;
    ERC20 public immutable mim;

    CauldronInfo[] public cauldronInfos;
    bool public paused;

    address public feeCollector;
    uint88 public interest;

    modifier notPaused() {
        if (paused) {
            revert ErrPaused();
        }
        _;
    }

    constructor(
        ERC20 _mim,
        address _feeCollector,
        uint88 _interest
    ) {
        mim = _mim;

        feeCollector = _feeCollector;
        interest = _interest;
        emit LogFeeParametersChanged(_feeCollector, _interest);
    }

    function setCauldronParameters(
        ICauldronV4 _cauldron,
        uint256 _targetApyBips,
        uint256 _minTotalBorrowElastic,
        IRewarder _rewarder
    ) external onlyOwner {
        if (_targetApyBips > BIPS) {
            revert ErrInvalidTargetApy(_targetApyBips);
        }

        int256 index = _findCauldronInfo(_cauldron);
        if (index >= 0) {
            if (_targetApyBips > 0) {
                cauldronInfos[uint256(index)].targetApyPerSecond = (_targetApyBips * 1e18) / 365 days;
            } else {
                cauldronInfos[uint256(index)] = cauldronInfos[cauldronInfos.length - 1];
                cauldronInfos.pop();
            }
        } else {
            cauldronInfos.push(
                CauldronInfo({
                    cauldron: _cauldron,
                    oracle: _cauldron.oracle(),
                    oracleData: _cauldron.oracleData(),
                    targetApyPerSecond: (_targetApyBips * 1e18) / 365 days,
                    lastDistribution: uint64(block.timestamp),
                    degenBox: IBentoBoxV1(_cauldron.bentoBox()),
                    collateral: _cauldron.collateral(),
                    minTotalBorrowElastic: _minTotalBorrowElastic,
                    rewarder: _rewarder
                })
            );
        }

        emit LogCauldronParameterChanged(_cauldron, _targetApyBips);
    }

    function getCauldronInfoCount() external view returns (uint256) {
        return cauldronInfos.length;
    }

    function _findCauldronInfo(ICauldronV4 _cauldron) private view returns (int256) {
        for (uint256 i = 0; i < cauldronInfos.length; i++) {
            if (cauldronInfos[i].cauldron == _cauldron) {
                return int256(i);
            }
        }

        return -1;
    }

    // take % apy on the collateral share and compute USD value with oracle
    // then take this amount and how much that is on the sum of all cauldron'S apy USD
    // lastDistributed can be manipulated to reduce treasury fees, therefore we require the operator only access here.
    // gmx rewards should be harvested before distribute is called.
    function distribute() public notPaused onlyOperators {
        uint256 amountAvailableToDistribute = mim.balanceOf(address(this));

        uint256[] memory distributionAllocations = new uint256[](cauldronInfos.length);

        // based on each cauldron's apy per second, the allocation of the current amount to be distributed.
        // this way amount distribution rate is controlled by each target apy and not all distributed
        // immediately
        uint256 idealTotalDistributionAllocation;
        uint256 idealFeeAmount;

        // Gather all stats needed for the subsequent distribution
        for (uint256 i = 0; i < cauldronInfos.length; i++) {
            CauldronInfo storage info = cauldronInfos[i];

            uint64 timeElapsed = uint64(block.timestamp) - info.lastDistribution;

            if (timeElapsed == 0) {
                continue;
            }

            // compute the cauldron's total collateral share value in usd
            uint256 totalCollateralAmount = info.degenBox.toAmount(info.collateral, info.cauldron.totalCollateralShare(), false);
            uint256 totalCollateralShareValue = (totalCollateralAmount * 1e18) / info.oracle.peekSpot(info.oracleData);
            info.cauldron.accrue();
            Rebase memory totalBorrow = info.cauldron.totalBorrow();

            if (totalCollateralShareValue > 0) {
                // calculate how much to distribute to this cauldron based on target apy per second versus how many time
                // has passed since the last distribution.
                distributionAllocations[i] = (info.targetApyPerSecond * totalCollateralShareValue * timeElapsed) / (BIPS * 1e18);
                idealTotalDistributionAllocation += distributionAllocations[i];
            }

            if (totalBorrow.elastic > 0) {
                idealFeeAmount += (uint256(interest) * uint256(totalBorrow.elastic) * timeElapsed) / INTEREST_PRECISION;
            }

            info.lastDistribution = uint64(block.timestamp);
        }

        if (idealTotalDistributionAllocation == 0) {
            return;
        }

        uint256 effectiveTotalDistributionAllocation = idealTotalDistributionAllocation;

        // starving, demands is higher than produced yields
        if (effectiveTotalDistributionAllocation > amountAvailableToDistribute) {
            effectiveTotalDistributionAllocation = amountAvailableToDistribute;
        } else if (effectiveTotalDistributionAllocation + idealFeeAmount <= amountAvailableToDistribute) {
            effectiveTotalDistributionAllocation = amountAvailableToDistribute - idealFeeAmount;
        }

        // Prorata the distribution along every cauldron asked apy so that every cauldron share the allocated amount.
        // Otherwise it would be first come first serve and some cauldrons might not receive anything.
        for (uint256 i = 0; i < cauldronInfos.length; i++) {
            CauldronInfo storage info = cauldronInfos[i];

            // take a share of the total requested distribution amount, in case of starving, take
            // a proportionnal share of it.
            uint256 distributionAmount = (distributionAllocations[i] * effectiveTotalDistributionAllocation) /
                idealTotalDistributionAllocation;

            if (distributionAmount > amountAvailableToDistribute) {
                distributionAmount = amountAvailableToDistribute;
            }

            if (distributionAmount > 0) {
                Rebase memory totalBorrow = info.cauldron.totalBorrow();

                if (info.rewarder != IRewarder(address(0))) {
                    mim.transfer(address(info.degenBox), distributionAmount);
                    info.degenBox.deposit(mim, address(info.degenBox), address(info.rewarder), distributionAmount, 0);
                    info.rewarder.updateReward(mim);
                    amountAvailableToDistribute -= distributionAmount;
                } else {
                    if (distributionAmount > totalBorrow.elastic) {
                        distributionAmount = totalBorrow.elastic;
                    }
                    if (totalBorrow.elastic - distributionAmount > info.minTotalBorrowElastic) {
                        mim.transfer(address(info.cauldron), distributionAmount);
                        info.cauldron.repayForAll(0, true);
                        amountAvailableToDistribute -= distributionAmount;
                    }
                }
            }
        }

        mim.transfer(feeCollector, amountAvailableToDistribute);
    }

    function setPaused(bool _paused) external onlyOwner {
        emit LogPaused(paused, _paused);
        paused = _paused;
    }
    
    function setFeeParameters(address _feeCollector, uint88 _interest) external onlyOwner {
        feeCollector = _feeCollector;
        interest = _interest;
        emit LogFeeParametersChanged(_feeCollector, _interest);
    }

    function withdraw() external onlyOwner {
        mim.transfer(owner, mim.balanceOf(address(this)));
    }
}
