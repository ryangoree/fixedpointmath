// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { ForwarderFactory } from "contracts/src/ForwarderFactory.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveBase } from "contracts/src/HyperdriveBase.sol";
import { BaseTest } from "./BaseTest.sol";
import { MockHyperdrive, MockHyperdriveDataProvider } from "../mocks/MockHyperdrive.sol";
import { HyperdriveUtils } from "./HyperdriveUtils.sol";

contract HyperdriveTest is BaseTest {
    using FixedPointMath for uint256;

    ERC20Mintable baseToken;
    IHyperdrive hyperdrive;

    uint256 internal constant INITIAL_SHARE_PRICE = FixedPointMath.ONE_18;
    uint256 internal constant CHECKPOINT_DURATION = 1 days;
    uint256 internal constant POSITION_DURATION = 365 days;
    uint256 internal constant ORACLE_SIZE = 5;
    uint256 internal constant UPDATE_GAP = 1000;

    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(alice);

        // Instantiate the base token.
        baseToken = new ERC20Mintable();
        IHyperdrive.Fees memory fees = IHyperdrive.Fees({
            curve: 0,
            flat: 0,
            governance: 0
        });
        // Instantiate Hyperdrive.
        uint256 apr = 0.05e18;
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: baseToken,
            initialSharePrice: INITIAL_SHARE_PRICE,
            positionDuration: POSITION_DURATION,
            checkpointDuration: CHECKPOINT_DURATION,
            timeStretch: HyperdriveUtils.calculateTimeStretch(apr),
            governance: governance,
            feeCollector: governance,
            fees: fees,
            oracleSize: ORACLE_SIZE,
            updateGap: UPDATE_GAP
        });
        address dataProvider = address(new MockHyperdriveDataProvider(config));
        hyperdrive = IHyperdrive(
            address(new MockHyperdrive(config, dataProvider))
        );
        vm.stopPrank();
        vm.startPrank(governance);
        hyperdrive.setPauser(pauser, true);

        // Advance time so that Hyperdrive can look back more than a position
        // duration.
        vm.warp(POSITION_DURATION * 3);
    }

    function deploy(
        address deployer,
        uint256 apr,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceFee,
        address governance
    ) internal {
        vm.stopPrank();
        vm.startPrank(deployer);
        IHyperdrive.Fees memory fees = IHyperdrive.Fees({
            curve: curveFee,
            flat: flatFee,
            governance: governanceFee
        });
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: baseToken,
            initialSharePrice: INITIAL_SHARE_PRICE,
            positionDuration: POSITION_DURATION,
            checkpointDuration: CHECKPOINT_DURATION,
            timeStretch: HyperdriveUtils.calculateTimeStretch(apr),
            governance: governance,
            feeCollector: governance,
            fees: fees,
            oracleSize: ORACLE_SIZE,
            updateGap: UPDATE_GAP
        });
        address dataProvider = address(new MockHyperdriveDataProvider(config));
        hyperdrive = IHyperdrive(
            address(new MockHyperdrive(config, dataProvider))
        );
    }

    /// Actions ///

    function initialize(
        address lp,
        uint256 apr,
        uint256 contribution
    ) internal returns (uint256 lpShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Initialize the pool.
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        hyperdrive.initialize(contribution, apr, lp, true);

        return hyperdrive.balanceOf(AssetId._LP_ASSET_ID, lp);
    }

    function addLiquidity(
        address lp,
        uint256 contribution
    ) internal returns (uint256 lpShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Add liquidity to the pool.
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        hyperdrive.addLiquidity(contribution, 0, type(uint256).max, lp, true);

        return hyperdrive.balanceOf(AssetId._LP_ASSET_ID, lp);
    }

    function removeLiquidity(
        address lp,
        uint256 shares
    ) internal returns (uint256 baseProceeds, uint256 withdrawalShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Remove liquidity from the pool.
        uint256 baseBalanceBefore = baseToken.balanceOf(lp);
        uint256 withdrawalShareBalanceBefore = hyperdrive.balanceOf(
            AssetId._WITHDRAWAL_SHARE_ASSET_ID,
            lp
        );
        hyperdrive.removeLiquidity(shares, 0, lp, true);

        return (
            baseToken.balanceOf(lp) - baseBalanceBefore,
            hyperdrive.balanceOf(AssetId._WITHDRAWAL_SHARE_ASSET_ID, lp) -
                withdrawalShareBalanceBefore
        );
    }

    function redeemWithdrawalShares(
        address lp,
        uint256 shares
    ) internal returns (uint256 baseProceeds, uint256 sharesRedeemed) {
        return redeemWithdrawalShares(lp, shares, 0);
    }

    function redeemWithdrawalShares(
        address lp,
        uint256 shares,
        uint256 minOutputPerShare
    ) internal returns (uint256 baseProceeds, uint256 sharesRedeemed) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Redeem the withdrawal shares.
        return
            hyperdrive.redeemWithdrawalShares(
                shares,
                minOutputPerShare,
                lp,
                true
            );
    }

    function openLong(
        address trader,
        uint256 baseAmount
    ) internal returns (uint256 maturityTime, uint256 bondAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the long.
        maturityTime = HyperdriveUtils.maturityTimeFromLatestCheckpoint(
            hyperdrive
        );
        uint256 bondBalanceBefore = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            trader
        );
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, trader, true);

        uint256 bondBalanceAfter = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            trader
        );
        return (maturityTime, bondBalanceAfter.sub(bondBalanceBefore));
    }

    function closeLong(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount
    ) internal returns (uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Close the long.
        uint256 baseBalanceBefore = baseToken.balanceOf(trader);
        hyperdrive.closeLong(maturityTime, bondAmount, 0, trader, true);

        uint256 baseBalanceAfter = baseToken.balanceOf(trader);
        return baseBalanceAfter.sub(baseBalanceBefore);
    }

    function openShort(
        address trader,
        uint256 bondAmount
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the short
        maturityTime = HyperdriveUtils.maturityTimeFromLatestCheckpoint(
            hyperdrive
        );
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        uint256 baseBalanceBefore = baseToken.balanceOf(trader);
        hyperdrive.openShort(bondAmount, bondAmount, trader, true);

        baseAmount = baseBalanceBefore - baseToken.balanceOf(trader);
        baseToken.burn(bondAmount - baseAmount);
        return (maturityTime, baseAmount);
    }

    function closeShort(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount
    ) internal returns (uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Close the short
        uint256 baseBalanceBefore = baseToken.balanceOf(trader);
        hyperdrive.closeShort(maturityTime, bondAmount, 0, trader, true);

        return baseToken.balanceOf(trader) - baseBalanceBefore;
    }

    /// Utils ///

    function advanceTime(uint256 time, int256 apr) internal {
        MockHyperdrive(address(hyperdrive)).accrue(time, apr);
        vm.warp(block.timestamp + time);
    }

    function pause(bool paused) internal {
        vm.startPrank(pauser);
        hyperdrive.pause(paused);
        vm.stopPrank();
    }

    /// Event Utils ///

    event Initialize(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 apr
    );

    event AddLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount
    );

    event RemoveLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 withdrawalShareAmount
    );

    event RedeemWithdrawalShares(
        address indexed provider,
        uint256 withdrawalShareAmount,
        uint256 baseAmount
    );

    event OpenLong(
        address indexed trader,
        uint256 assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    event OpenShort(
        address indexed trader,
        uint256 assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    event CloseLong(
        address indexed trader,
        uint256 assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    event CloseShort(
        address indexed trader,
        uint256 assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );
}
