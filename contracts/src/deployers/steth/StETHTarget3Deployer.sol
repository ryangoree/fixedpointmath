// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { StETHTarget3 } from "../../instances/steth/StETHTarget3.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";
import { ILido } from "../../interfaces/ILido.sol";

/// @author DELV
/// @title StETHTarget3Deployer
/// @notice The target3 deployer for the StETHHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StETHTarget3Deployer is IHyperdriveTargetDeployer {
    /// @notice The Lido contract.
    ILido public immutable lido;

    /// @notice Instanstiates the target3 deployer.
    /// @param _lido The Lido contract.
    constructor(ILido _lido) {
        lido = _lido;
    }

    /// @notice Deploys a target3 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @return The address of the newly deployed StETHTarget3 Instance.
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory // unused extra data
    ) external override returns (address) {
        // Deploy the StETHTarget3 instance.
        return address(new StETHTarget3(_config, lido));
    }
}
