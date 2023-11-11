// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IForwarderFactory } from "../interfaces/IForwarderFactory.sol";
import { IMultiToken } from "../interfaces/IMultiToken.sol";
import { ERC20Forwarder } from "./ERC20Forwarder.sol";

/// @author DELV
/// @title ForwarderFactory
/// @notice Our MultiToken contract consists of fungible sub-tokens that
///         are similar to ERC20 tokens. In order to support ERC20 compatibility
///         we can deploy interfaces which are ERC20s.
/// @dev This factory deploys them using create2 so that the multi token can do
///      cheap verification of the interfaces before they access sensitive
///      functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ForwarderFactory is IForwarderFactory {
    // The transient state variables used in deployment
    // Note - It saves us a bit of gas to not fully zero them at any point
    IMultiToken private _token = IMultiToken(address(1));
    uint256 private _tokenId = 1;

    // For reference
    bytes32 public constant ERC20LINK_HASH =
        keccak256(type(ERC20Forwarder).creationCode);

    /// @notice Uses create2 to deploy a forwarder at a predictable address as
    ///         part of our ERC20 multitoken implementation.
    /// @param __token The multitoken which the forwarder should link to.
    /// @param __tokenId The id of the sub token from the multitoken which we are
    ///        creating an interface for.
    /// @return Returns the address of the deployed forwarder.
    function create(
        IMultiToken __token,
        uint256 __tokenId
    ) external returns (ERC20Forwarder) {
        // Set the transient state variables before deploy.
        _tokenId = __tokenId;
        _token = __token;

        // The salt is the _tokenId hashed with the multi token.
        bytes32 salt = keccak256(abi.encode(__token, __tokenId));

        // Deploy using create2 with that salt.
        ERC20Forwarder deployed = new ERC20Forwarder{ salt: salt }();

        // As a consistency check we check that this is in the right address.
        if (!(address(deployed) == getForwarder(__token, __tokenId))) {
            revert IHyperdrive.InvalidForwarderAddress();
        }

        // Reset the transient state.
        _token = IMultiToken(address(1));
        _tokenId = 1;

        // Return the deployed forwarder.
        return deployed;
    }

    /// @notice Returns the transient storage of this contract.
    /// @return Returns the stored multitoken address and the sub token id.
    function getDeployDetails() external view returns (IMultiToken, uint256) {
        return (_token, _tokenId);
    }

    /// @notice Helper to calculate expected forwarder contract addresses.
    /// @param __token The multitoken which the forwarder should link to.
    /// @param __tokenId The id of the sub token from the multitoken.
    /// @return The expected address of the forwarder.
    function getForwarder(
        IMultiToken __token,
        uint256 __tokenId
    ) public view returns (address) {
        // Get the salt and hash to predict the address.
        bytes32 salt = keccak256(abi.encode(__token, __tokenId));
        bytes32 addressBytes = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, ERC20LINK_HASH)
        );

        // Beautiful type safety from the solidity language.
        return address(uint160(uint256(addressBytes)));
    }
}
