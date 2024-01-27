// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { HyperdriveAdmin } from "../internal/HyperdriveAdmin.sol";
import { HyperdriveCheckpoint } from "../internal/HyperdriveCheckpoint.sol";
import { HyperdriveLong } from "../internal/HyperdriveLong.sol";
import { HyperdriveLP } from "../internal/HyperdriveLP.sol";
import { HyperdriveMultiToken } from "../internal/HyperdriveMultiToken.sol";
import { HyperdriveShort } from "../internal/HyperdriveShort.sol";
import { HyperdriveStorage } from "../internal/HyperdriveStorage.sol";

/// @author DELV
/// @title HyperdriveTarget1
/// @notice Hyperdrive's target 1 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveTarget1 is
    HyperdriveAdmin,
    HyperdriveMultiToken,
    HyperdriveLP,
    HyperdriveLong,
    HyperdriveShort,
    HyperdriveCheckpoint
{
    /// @notice Instantiates target1.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveStorage(_config) {}

    /// LPs ///

    /// @notice Allows the first LP to initialize the market with a target APR.
    /// @param _contribution The amount of base to supply.
    /// @param _apr The target APR.
    /// @param _options The options that configure how the operation is settled.
    /// @return lpShares The initial number of LP shares created.
    function initialize(
        uint256 _contribution,
        uint256 _apr,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256 lpShares) {
        return _initialize(_contribution, _apr, _options);
    }

    /// @notice Allows LPs to supply liquidity for LP shares.
    /// @param _contribution The amount of base to supply.
    /// @param _minLpSharePrice The minimum LP share price the LP is willing
    ///        to accept for their shares. LP's incur negative slippage when
    ///        adding liquidity if there is a net curve position in the market,
    ///        so this allows LPs to protect themselves from high levels of
    ///        slippage.
    /// @param _minApr The minimum APR at which the LP is willing to supply.
    /// @param _maxApr The maximum APR at which the LP is willing to supply.
    /// @param _options The options that configure how the operation is settled.
    /// @return lpShares The number of LP tokens created.
    function addLiquidity(
        uint256 _contribution,
        uint256 _minLpSharePrice,
        uint256 _minApr,
        uint256 _maxApr,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256 lpShares) {
        return
            _addLiquidity(
                _contribution,
                _minLpSharePrice,
                _minApr,
                _maxApr,
                _options
            );
    }

    /// @notice Allows an LP to burn shares and withdraw from the pool.
    /// @param _lpShares The LP shares to burn.
    /// @param _minOutput The minium amount of the base token to receive.
    ///        NOTE: This value is likely to be less than the amount LP shares
    ///        are worth. The remainder is in short and long withdraw shares
    ///        which are hard to game the value of.
    /// @param _options The options that configure how the operation is settled.
    /// @return The amount the LP removing liquidity receives. The LP receives a
    ///         proportional amount of the pool's idle capital.
    /// @return The base that the LP receives buys out some of their LP shares,
    ///         but it may not be sufficient to fully buy the LP out. In this
    ///         case, the LP receives withdrawal shares equal in value to the
    ///         present value they are owed. As idle capital becomes available,
    ///         the pool will buy back these shares.
    function removeLiquidity(
        uint256 _lpShares,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) external returns (uint256, uint256) {
        return _removeLiquidity(_lpShares, _minOutput, _options);
    }

    /// @notice Redeems withdrawal shares by giving the LP a pro-rata amount of
    ///         the withdrawal pool's proceeds. This function redeems the
    ///         maximum amount of the specified withdrawal shares given the
    ///         amount of withdrawal shares ready to withdraw.
    /// @param _withdrawalShares The withdrawal shares to redeem.
    /// @param _minOutputPerShare The minimum amount of base the LP expects to
    ///        receive for each withdrawal share that is burned.
    /// @param _options The options that configure how the operation is settled.
    /// @return The amount the LP received.
    /// @return The amount of withdrawal shares that were redeemed.
    function redeemWithdrawalShares(
        uint256 _withdrawalShares,
        uint256 _minOutputPerShare,
        IHyperdrive.Options calldata _options
    ) external returns (uint256, uint256) {
        return
            _redeemWithdrawalShares(
                _withdrawalShares,
                _minOutputPerShare,
                _options
            );
    }
}
