// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { VmSafe } from "forge-std/Vm.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { LPMath } from "contracts/src/libraries/LPMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockHyperdrive, MockHyperdriveTarget0, MockHyperdriveTarget1 } from "contracts/test/MockHyperdrive.sol";
import { BaseTest } from "test/utils/BaseTest.sol";
import { ETH } from "test/utils/Constants.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract HyperdriveTest is BaseTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    ERC20Mintable baseToken;
    IHyperdrive hyperdrive;

    uint256 internal constant INITIAL_SHARE_PRICE = ONE;
    uint256 internal constant MINIMUM_SHARE_RESERVES = ONE;
    uint256 internal constant MINIMUM_TRANSACTION_AMOUNT = 0.001e18;
    uint256 internal constant CHECKPOINT_DURATION = 1 days;
    uint256 internal constant POSITION_DURATION = 365 days;

    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(alice);

        // Instantiate the base token.
        baseToken = new ERC20Mintable("Base", "BASE", 18, address(0), false);

        // Instantiate Hyperdrive.
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        deploy(alice, config);
        vm.stopPrank();
        vm.startPrank(governance);
        hyperdrive.setPauser(pauser, true);

        // If this isn't a forked environment, advance time so that Hyperdrive
        // can look back more than a position duration. We assume that fork
        // tests are using a sufficiently recent block that this won't be an
        // issue.
        if (!isForked) {
            vm.warp(POSITION_DURATION * 3);
        }
    }

    function deploy(
        address deployer,
        IHyperdrive.PoolConfig memory _config
    ) internal {
        vm.stopPrank();
        vm.startPrank(deployer);
        hyperdrive = IHyperdrive(address(new MockHyperdrive(_config)));
    }

    function deploy(
        address deployer,
        uint256 apr,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceLPFee,
        uint256 governanceZombieFee
    ) internal {
        deploy(
            deployer,
            apr,
            INITIAL_SHARE_PRICE,
            curveFee,
            flatFee,
            governanceLPFee,
            governanceZombieFee
        );
    }

    function deploy(
        address deployer,
        uint256 apr,
        uint256 initialVaultSharePrice,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceLPFee,
        uint256 governanceZombieFee
    ) internal {
        IHyperdrive.PoolConfig memory config = testConfig(
            apr,
            POSITION_DURATION
        );
        config.initialVaultSharePrice = initialVaultSharePrice;
        config.fees.curve = curveFee;
        config.fees.flat = flatFee;
        config.fees.governanceLP = governanceLPFee;
        config.fees.governanceZombie = governanceZombieFee;
        deploy(deployer, config);
    }

    function testConfig(
        uint256 fixedRate,
        uint256 positionDuration
    ) internal view returns (IHyperdrive.PoolConfig memory _config) {
        IHyperdrive.PoolDeployConfig memory _deployConfig = testDeployConfig(
            fixedRate,
            positionDuration
        );

        _config.baseToken = _deployConfig.baseToken;
        _config.linkerFactory = _deployConfig.linkerFactory;
        _config.linkerCodeHash = _deployConfig.linkerCodeHash;
        _config.minimumShareReserves = _deployConfig.minimumShareReserves;
        _config.minimumTransactionAmount = _deployConfig
            .minimumTransactionAmount;
        _config.positionDuration = _deployConfig.positionDuration;
        _config.checkpointDuration = _deployConfig.checkpointDuration;
        _config.timeStretch = _deployConfig.timeStretch;
        _config.governance = _deployConfig.governance;
        _config.feeCollector = _deployConfig.feeCollector;
        _config.fees = _deployConfig.fees;

        _config.initialVaultSharePrice = ONE;
    }

    function testDeployConfig(
        uint256 fixedRate,
        uint256 positionDuration
    ) internal view returns (IHyperdrive.PoolDeployConfig memory) {
        IHyperdrive.Fees memory fees = IHyperdrive.Fees({
            curve: 0,
            flat: 0,
            governanceLP: 0,
            governanceZombie: 0
        });
        return
            IHyperdrive.PoolDeployConfig({
                baseToken: IERC20(address(baseToken)),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0),
                minimumShareReserves: MINIMUM_SHARE_RESERVES,
                minimumTransactionAmount: MINIMUM_TRANSACTION_AMOUNT,
                positionDuration: positionDuration,
                checkpointDuration: CHECKPOINT_DURATION,
                timeStretch: HyperdriveUtils.calculateTimeStretch(
                    fixedRate,
                    positionDuration
                ),
                governance: governance,
                feeCollector: feeCollector,
                fees: fees
            });
    }

    /// Actions ///

    // Overrides for functions that initiate deposits.
    struct DepositOverrides {
        // A boolean flag specifying whether or not the underlying should be used.
        bool asBase;
        // The amount of tokens the action should prepare to deposit. Note that
        // the actual deposit amount will still be specified by the action being
        // called; however, this is the amount that will be minted as a
        // convenience. In the case of ETH, this is the amount that will be
        // transferred into the YieldSource, which allows us to test ETH
        // reentrancy.
        uint256 depositAmount;
        // The minimum share price that will be accepted. It may not be used by
        // some actions.
        uint256 minVaultSharePrice;
        // This is the slippage parameter that defines a lower bound on the
        // quantity being measured. It may not be used by some actions.
        uint256 minSlippage;
        // This is the slippage parameter that defines an upper bound on the
        // quantity being measured. It may not be used by some actions.
        uint256 maxSlippage;
        // The extra data to pass to the yield source.
        bytes extraData;
    }

    // Overrides for functions that initiate withdrawals.
    struct WithdrawalOverrides {
        // A boolean flag specifying whether or not the underlying should be used.
        bool asBase;
        // This is the slippage parameter that defines a lower bound on the
        // quantity being measured.
        uint256 minSlippage;
        // The extra data to pass to the yield source.
        bytes extraData;
    }

    function initialize(
        address lp,
        uint256 apr,
        uint256 contribution,
        DepositOverrides memory overrides
    ) internal returns (uint256 lpShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Initialize the pool.
        if (
            address(hyperdrive.getPoolConfig().baseToken) == address(ETH) &&
            overrides.asBase
        ) {
            return
                hyperdrive.initialize{ value: overrides.depositAmount }(
                    contribution,
                    apr,
                    IHyperdrive.Options({
                        destination: lp,
                        asBase: overrides.asBase,
                        extraData: overrides.extraData
                    })
                );
        } else {
            baseToken.mint(overrides.depositAmount);
            baseToken.approve(address(hyperdrive), overrides.depositAmount);
            return
                hyperdrive.initialize(
                    contribution,
                    apr,
                    IHyperdrive.Options({
                        destination: lp,
                        asBase: overrides.asBase,
                        extraData: overrides.extraData
                    })
                );
        }
    }

    function initialize(
        address lp,
        uint256 apr,
        uint256 contribution
    ) internal returns (uint256 lpShares) {
        return
            initialize(
                lp,
                apr,
                contribution,
                DepositOverrides({
                    asBase: true,
                    depositAmount: contribution,
                    minVaultSharePrice: 0, // unused
                    minSlippage: 0, // unused
                    maxSlippage: type(uint256).max, // unused
                    extraData: new bytes(0) // unused
                })
            );
    }

    function initialize(
        address lp,
        uint256 apr,
        uint256 contribution,
        bool asBase
    ) internal returns (uint256 lpShares) {
        return
            initialize(
                lp,
                apr,
                contribution,
                DepositOverrides({
                    asBase: asBase,
                    depositAmount: contribution,
                    minVaultSharePrice: 0, // unused
                    minSlippage: 0, // unused
                    maxSlippage: type(uint256).max, // unused
                    extraData: new bytes(0) // unused
                })
            );
    }

    function addLiquidity(
        address lp,
        uint256 contribution,
        DepositOverrides memory overrides
    ) internal returns (uint256 lpShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Add liquidity to the pool.
        if (
            address(hyperdrive.getPoolConfig().baseToken) == address(ETH) &&
            overrides.asBase
        ) {
            return
                hyperdrive.addLiquidity{ value: overrides.depositAmount }(
                    contribution,
                    overrides.minSlippage, // min spot rate
                    overrides.maxSlippage, // max spot rate
                    IHyperdrive.Options({
                        destination: lp,
                        asBase: overrides.asBase,
                        extraData: overrides.extraData
                    })
                );
        } else {
            baseToken.mint(overrides.depositAmount);
            baseToken.approve(address(hyperdrive), overrides.depositAmount);
            return
                hyperdrive.addLiquidity(
                    contribution,
                    overrides.minSlippage, // min spot rate
                    overrides.maxSlippage, // max spot rate
                    IHyperdrive.Options({
                        destination: lp,
                        asBase: overrides.asBase,
                        extraData: overrides.extraData
                    })
                );
        }
    }

    function addLiquidity(
        address lp,
        uint256 contribution
    ) internal returns (uint256 lpShares) {
        return
            addLiquidity(
                lp,
                contribution,
                DepositOverrides({
                    asBase: true,
                    depositAmount: contribution,
                    minVaultSharePrice: 0, // unused
                    minSlippage: 0, // min spot rate of 0
                    maxSlippage: type(uint256).max, // max spot rate of uint256 max
                    extraData: new bytes(0) // unused
                })
            );
    }

    function addLiquidity(
        address lp,
        uint256 contribution,
        bool asBase
    ) internal returns (uint256 lpShares) {
        return
            addLiquidity(
                lp,
                contribution,
                DepositOverrides({
                    asBase: asBase,
                    depositAmount: contribution,
                    minVaultSharePrice: 0, // unused
                    minSlippage: 0, // min spot rate of 0
                    maxSlippage: type(uint256).max, // max spot rate of uint256 max
                    extraData: new bytes(0) // unused
                })
            );
    }

    function removeLiquidity(
        address lp,
        uint256 shares,
        WithdrawalOverrides memory overrides
    ) internal returns (uint256 baseProceeds, uint256 withdrawalShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Remove liquidity from the pool.
        return
            hyperdrive.removeLiquidity(
                shares,
                overrides.minSlippage, // min base proceeds
                IHyperdrive.Options({
                    destination: lp,
                    asBase: overrides.asBase,
                    extraData: overrides.extraData
                })
            );
    }

    function removeLiquidity(
        address lp,
        uint256 shares
    ) internal returns (uint256 baseProceeds, uint256 withdrawalShares) {
        return
            removeLiquidity(
                lp,
                shares,
                WithdrawalOverrides({
                    asBase: true,
                    minSlippage: 0, // min base proceeds of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    function removeLiquidity(
        address lp,
        uint256 shares,
        bool asBase
    ) internal returns (uint256 baseProceeds, uint256 withdrawalShares) {
        return
            removeLiquidity(
                lp,
                shares,
                WithdrawalOverrides({
                    asBase: asBase,
                    minSlippage: 0, // min base proceeds of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    function redeemWithdrawalShares(
        address lp,
        uint256 shares,
        WithdrawalOverrides memory overrides
    ) internal returns (uint256 baseProceeds, uint256 sharesRedeemed) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Redeem the withdrawal shares.
        return
            hyperdrive.redeemWithdrawalShares(
                shares,
                overrides.minSlippage, // min output per share
                IHyperdrive.Options({
                    destination: lp,
                    asBase: overrides.asBase,
                    extraData: overrides.extraData
                })
            );
    }

    function redeemWithdrawalShares(
        address lp,
        uint256 shares
    ) internal returns (uint256 baseProceeds, uint256 sharesRedeemed) {
        return
            redeemWithdrawalShares(
                lp,
                shares,
                WithdrawalOverrides({
                    asBase: true,
                    minSlippage: 0, // min output per share of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    function redeemWithdrawalShares(
        address lp,
        uint256 shares,
        bool asBase
    ) internal returns (uint256 baseProceeds, uint256 sharesRedeemed) {
        return
            redeemWithdrawalShares(
                lp,
                shares,
                WithdrawalOverrides({
                    asBase: asBase,
                    minSlippage: 0, // min output per share of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    function openLong(
        address trader,
        uint256 baseAmount,
        DepositOverrides memory overrides
    ) internal returns (uint256 maturityTime, uint256 bondProceeds) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the long.
        hyperdrive.getPoolConfig();
        if (
            address(hyperdrive.getPoolConfig().baseToken) == address(ETH) &&
            overrides.asBase
        ) {
            return
                hyperdrive.openLong{ value: overrides.depositAmount }(
                    baseAmount,
                    overrides.minSlippage, // min bond proceeds
                    overrides.minVaultSharePrice,
                    IHyperdrive.Options({
                        destination: trader,
                        asBase: overrides.asBase,
                        extraData: overrides.extraData
                    })
                );
        } else {
            baseToken.mint(baseAmount);
            baseToken.approve(address(hyperdrive), baseAmount);
            return
                hyperdrive.openLong(
                    baseAmount,
                    overrides.minSlippage, // min bond proceeds
                    overrides.minVaultSharePrice,
                    IHyperdrive.Options({
                        destination: trader,
                        asBase: overrides.asBase,
                        extraData: overrides.extraData
                    })
                );
        }
    }

    function openLong(
        address trader,
        uint256 baseAmount
    ) internal returns (uint256 maturityTime, uint256 bondAmount) {
        return
            openLong(
                trader,
                baseAmount,
                DepositOverrides({
                    asBase: true,
                    depositAmount: baseAmount,
                    minVaultSharePrice: 0, // min share price of 0
                    minSlippage: baseAmount, // min bond proceeds of baseAmount
                    maxSlippage: type(uint256).max, // unused
                    extraData: new bytes(0) // unused
                })
            );
    }

    function openLong(
        address trader,
        uint256 baseAmount,
        bool asBase
    ) internal returns (uint256 maturityTime, uint256 bondAmount) {
        return
            openLong(
                trader,
                baseAmount,
                DepositOverrides({
                    asBase: asBase,
                    depositAmount: baseAmount,
                    minVaultSharePrice: 0, // min share price of 0
                    minSlippage: baseAmount, // min bond proceeds of baseAmount
                    maxSlippage: type(uint256).max, // unused
                    extraData: new bytes(0) // unused
                })
            );
    }

    function closeLong(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount,
        WithdrawalOverrides memory overrides
    ) internal returns (uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Close the long.
        return
            hyperdrive.closeLong(
                maturityTime,
                bondAmount,
                overrides.minSlippage, // min base proceeds
                IHyperdrive.Options({
                    destination: trader,
                    asBase: overrides.asBase,
                    extraData: overrides.extraData
                })
            );
    }

    function closeLong(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount
    ) internal returns (uint256 baseAmount) {
        return
            closeLong(
                trader,
                maturityTime,
                bondAmount,
                WithdrawalOverrides({
                    asBase: true,
                    minSlippage: 0, // min base proceeds of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    function closeLong(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount,
        bool asBase
    ) internal returns (uint256 baseAmount) {
        return
            closeLong(
                trader,
                maturityTime,
                bondAmount,
                WithdrawalOverrides({
                    asBase: asBase,
                    minSlippage: 0, // min base proceeds of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    function openShort(
        address trader,
        uint256 bondAmount,
        DepositOverrides memory overrides
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the short.
        maturityTime = HyperdriveUtils.maturityTimeFromLatestCheckpoint(
            hyperdrive
        );
        if (
            address(hyperdrive.getPoolConfig().baseToken) == address(ETH) &&
            overrides.asBase
        ) {
            (maturityTime, baseAmount) = hyperdrive.openShort{
                value: overrides.depositAmount
            }(
                bondAmount,
                overrides.maxSlippage, // max base payment
                overrides.minVaultSharePrice,
                IHyperdrive.Options({
                    destination: trader,
                    asBase: overrides.asBase,
                    extraData: overrides.extraData
                })
            );
        } else {
            baseToken.mint(overrides.depositAmount);
            baseToken.approve(address(hyperdrive), overrides.maxSlippage);
            (maturityTime, baseAmount) = hyperdrive.openShort(
                bondAmount,
                overrides.maxSlippage, // max base payment
                overrides.minVaultSharePrice,
                IHyperdrive.Options({
                    destination: trader,
                    asBase: overrides.asBase,
                    extraData: overrides.extraData
                })
            );
            baseToken.burn(overrides.depositAmount - baseAmount);
        }

        return (maturityTime, baseAmount);
    }

    function openShort(
        address trader,
        uint256 bondAmount
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        return
            openShort(
                trader,
                bondAmount,
                DepositOverrides({
                    asBase: true,
                    depositAmount: bondAmount,
                    minVaultSharePrice: 0, // min share price of 0
                    minSlippage: 0, // unused
                    maxSlippage: bondAmount, // max base payment of bondAmount
                    extraData: new bytes(0) // unused
                })
            );
    }

    function openShort(
        address trader,
        uint256 bondAmount,
        bool asBase
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        return
            openShort(
                trader,
                bondAmount,
                DepositOverrides({
                    asBase: asBase,
                    depositAmount: bondAmount,
                    minVaultSharePrice: 0, // min share price of 0
                    minSlippage: 0, // unused
                    maxSlippage: bondAmount, // max base payment of bondAmount
                    extraData: new bytes(0) // unused
                })
            );
    }

    function closeShort(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount,
        WithdrawalOverrides memory overrides
    ) internal returns (uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Close the short.
        return
            hyperdrive.closeShort(
                maturityTime,
                bondAmount,
                overrides.minSlippage, // min base proceeds
                IHyperdrive.Options({
                    destination: trader,
                    asBase: overrides.asBase,
                    extraData: overrides.extraData
                })
            );
    }

    function closeShort(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount
    ) internal returns (uint256 baseAmount) {
        return
            closeShort(
                trader,
                maturityTime,
                bondAmount,
                WithdrawalOverrides({
                    asBase: true,
                    minSlippage: 0, // min base proceeds of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    function closeShort(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount,
        bool asBase
    ) internal returns (uint256 baseAmount) {
        return
            closeShort(
                trader,
                maturityTime,
                bondAmount,
                WithdrawalOverrides({
                    asBase: asBase,
                    minSlippage: 0, // min base proceeds of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    /// Utils ///

    function advanceTime(uint256 time, int256 variableRate) internal virtual {
        MockHyperdrive(address(hyperdrive)).accrue(time, variableRate);
        vm.warp(block.timestamp + time);
    }

    function advanceTimeWithCheckpoints(
        uint256 time,
        int256 variableRate
    ) internal virtual {
        uint256 startTimeElapsed = block.timestamp;
        // Note: if time % CHECKPOINT_DURATION != 0 then it ends up
        // advancing time to the next checkpoint.
        while (block.timestamp - startTimeElapsed < time) {
            advanceTime(CHECKPOINT_DURATION, variableRate);
            hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));
        }
    }

    function advanceTimeWithCheckpoints2(
        uint256 time,
        int256 variableRate
    ) internal virtual {
        if (time % CHECKPOINT_DURATION == 0) {
            advanceTimeWithCheckpoints(time, variableRate);
        } else if (time < CHECKPOINT_DURATION) {
            advanceTime(time, variableRate);
        } else {
            // time > CHECKPOINT_DURATION
            uint256 startTimeElapsed = block.timestamp;
            while (
                block.timestamp - startTimeElapsed + CHECKPOINT_DURATION < time
            ) {
                advanceTime(CHECKPOINT_DURATION, variableRate);
                hyperdrive.checkpoint(
                    HyperdriveUtils.latestCheckpoint(hyperdrive)
                );
            }
            advanceTime(time % CHECKPOINT_DURATION, variableRate);
        }
    }

    function pause(bool paused) internal {
        vm.startPrank(pauser);
        hyperdrive.pause(paused);
        vm.stopPrank();
    }

    function estimateLongProceeds(
        uint256 bondAmount,
        uint256 normalizedTimeRemaining,
        uint256 openVaultSharePrice,
        uint256 closeVaultSharePrice
    ) internal view returns (uint256) {
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory poolConfig = hyperdrive.getPoolConfig();
        (, , uint256 shareProceeds) = HyperdriveMath.calculateCloseLong(
            poolInfo.shareReserves,
            poolInfo.bondReserves,
            bondAmount,
            normalizedTimeRemaining,
            poolConfig.timeStretch,
            poolInfo.vaultSharePrice,
            poolConfig.initialVaultSharePrice
        );
        if (closeVaultSharePrice < openVaultSharePrice) {
            shareProceeds = shareProceeds.mulDivDown(
                closeVaultSharePrice,
                openVaultSharePrice
            );
        }
        return shareProceeds.mulDivDown(poolInfo.vaultSharePrice, 1e18);
    }

    function estimateShortProceeds(
        uint256 shortAmount,
        int256 variableRate,
        uint256 normalizedTimeRemaining,
        uint256 timeElapsed
    ) internal view returns (uint256) {
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory poolConfig = hyperdrive.getPoolConfig();

        (, , uint256 expectedSharePayment) = HyperdriveMath.calculateCloseShort(
            poolInfo.shareReserves,
            poolInfo.bondReserves,
            shortAmount,
            normalizedTimeRemaining,
            poolConfig.timeStretch,
            poolInfo.vaultSharePrice,
            poolConfig.initialVaultSharePrice
        );
        (, int256 expectedInterest) = HyperdriveUtils.calculateCompoundInterest(
            shortAmount,
            variableRate,
            timeElapsed
        );
        int256 delta = int256(
            shortAmount - poolInfo.vaultSharePrice.mulDown(expectedSharePayment)
        );
        if (delta + expectedInterest > 0) {
            return uint256(delta + expectedInterest);
        } else {
            return 0;
        }
    }

    function calculateExpectedRemoveLiquidityProceeds(
        uint256 _lpShares
    ) internal view returns (uint256 baseProceeds, uint256 withdrawalShares) {
        // Apply the LP shares that will be removed to the withdrawal shares
        // outstanding and calculate the results of distributing excess idle.
        LPMath.DistributeExcessIdleParams memory params = hyperdrive
            .getDistributeExcessIdleParams();
        params.activeLpTotalSupply -= _lpShares;
        params.withdrawalSharesTotalSupply += _lpShares;
        (uint256 withdrawalSharesRedeemed, uint256 shareProceeds) = LPMath
            .calculateDistributeExcessIdle(params);
        return (
            shareProceeds.mulDown(hyperdrive.getPoolInfo().vaultSharePrice),
            _lpShares - withdrawalSharesRedeemed
        );
    }

    /// Event Utils ///

    event Deployed(
        uint256 indexed version,
        address hyperdrive,
        IHyperdrive.PoolDeployConfig config,
        bytes extraData
    );

    event Initialize(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 vaultSharePrice,
        uint256 apr
    );

    event AddLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 vaultSharePrice,
        uint256 lpSharePrice
    );

    event RemoveLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 vaultSharePrice,
        uint256 withdrawalShareAmount,
        uint256 lpSharePrice
    );

    event RedeemWithdrawalShares(
        address indexed provider,
        uint256 withdrawalShareAmount,
        uint256 baseAmount,
        uint256 vaultSharePrice
    );

    event OpenLong(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 vaultSharePrice,
        uint256 bondAmount
    );

    event OpenShort(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 vaultSharePrice,
        uint256 bondAmount
    );

    event CloseLong(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 vaultSharePrice,
        uint256 bondAmount
    );

    event CloseShort(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 vaultSharePrice,
        uint256 bondAmount
    );

    event CreateCheckpoint(
        uint256 indexed checkpointTime,
        uint256 vaultSharePrice,
        uint256 maturedShorts,
        uint256 maturedLongs,
        uint256 lpSharePrice
    );

    event CollectGovernanceFee(
        address indexed collector,
        uint256 baseFees,
        uint256 vaultSharePrice
    );

    function verifyFactoryEvents(
        HyperdriveFactory factory,
        IHyperdrive _hyperdrive,
        address deployer,
        uint256 contribution,
        uint256 apr,
        uint256 minimumShareReserves,
        bytes memory expectedExtraData,
        uint256 tolerance
    ) internal {
        // Ensure that the correct `Deployed` and `Initialize` events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        // Verify that a single `Deployed` event was emitted.
        {
            VmSafe.Log[] memory filteredLogs = logs.filterLogs(
                Deployed.selector
            );
            assertEq(filteredLogs.length, 1);

            // Verify the event topics.
            assertEq(filteredLogs[0].topics[0], Deployed.selector);
            assertEq(
                uint256(filteredLogs[0].topics[1]),
                factory.versionCounter()
            );

            // Verify the event data.
            (
                address eventHyperdrive,
                IHyperdrive.PoolDeployConfig memory eventConfig,
                bytes memory eventExtraData
            ) = abi.decode(
                    filteredLogs[0].data,
                    (address, IHyperdrive.PoolDeployConfig, bytes)
                );
            assertEq(eventHyperdrive, address(_hyperdrive));

            IHyperdrive.PoolConfig memory poolConfig = _hyperdrive
                .getPoolConfig();

            assertEq(
                address(eventConfig.baseToken),
                address(poolConfig.baseToken)
            );
            assertEq(eventConfig.linkerFactory, poolConfig.linkerFactory);
            assertEq(eventConfig.linkerCodeHash, poolConfig.linkerCodeHash);
            assertEq(
                eventConfig.minimumShareReserves,
                poolConfig.minimumShareReserves
            );
            assertEq(
                eventConfig.minimumTransactionAmount,
                poolConfig.minimumTransactionAmount
            );
            assertEq(eventConfig.positionDuration, poolConfig.positionDuration);
            assertEq(
                eventConfig.checkpointDuration,
                poolConfig.checkpointDuration
            );
            assertEq(eventConfig.timeStretch, poolConfig.timeStretch);
            assertEq(eventConfig.governance, poolConfig.governance);
            assertEq(eventConfig.feeCollector, poolConfig.feeCollector);
            assertEq(eventConfig.fees.curve, poolConfig.fees.curve);
            assertEq(eventConfig.fees.flat, poolConfig.fees.flat);
            assertEq(
                eventConfig.fees.governanceLP,
                poolConfig.fees.governanceLP
            );
            assertEq(
                eventConfig.fees.governanceZombie,
                poolConfig.fees.governanceZombie
            );

            assertEq(
                keccak256(abi.encode(eventExtraData)),
                keccak256(abi.encode(expectedExtraData))
            );
        }

        // Verify that the second log is the expected `Initialize` event.
        {
            VmSafe.Log[] memory filteredLogs = Lib.filterLogs(
                logs,
                Initialize.selector
            );
            assertEq(filteredLogs.length, 1);

            // Verify the event topics.
            assertEq(filteredLogs[0].topics[0], Initialize.selector);
            assertEq(
                address(uint160(uint256(filteredLogs[0].topics[1]))),
                deployer
            );

            // Verify the event data.
            (
                uint256 eventLpAmount,
                uint256 eventBaseAmount,
                uint256 eventSharePrice,
                uint256 eventApr
            ) = abi.decode(
                    filteredLogs[0].data,
                    (uint256, uint256, uint256, uint256)
                );
            uint256 contribution_ = contribution;
            IHyperdrive hyperdrive_ = _hyperdrive;
            assertApproxEqAbs(
                eventLpAmount,
                contribution_.divDown(
                    hyperdrive_.getPoolConfig().initialVaultSharePrice
                ) - 2 * minimumShareReserves,
                tolerance
            );
            assertEq(eventBaseAmount, contribution_);
            assertEq(
                eventSharePrice,
                hyperdrive_.getPoolInfo().vaultSharePrice
            );
            assertEq(eventApr, apr);
        }
    }
}
