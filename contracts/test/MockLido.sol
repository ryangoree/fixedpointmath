// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { Authority } from "solmate/auth/Auth.sol";
import { MultiRolesAuthority } from "solmate/auth/authorities/MultiRolesAuthority.sol";
import { ILido } from "../src/interfaces/ILido.sol";
import { FixedPointMath } from "../src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "./ERC20Mintable.sol";

/// @author DELV
/// @title MockLido
/// @notice This mock yield source will accrue interest at a specified rate
///         Every stateful interaction will accrue interest, so the interest
///         accrual will approximate continuous compounding as the contract
///         is called more frequently.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MockLido is MultiRolesAuthority, ERC20Mintable {
    using FixedPointMath for uint256;

    // Interest State
    uint256 internal _rate;
    uint256 internal _lastUpdated;

    // Lido State
    uint256 totalPooledEther;
    uint256 totalShares;

    constructor(
        uint256 _initialRate,
        address _admin,
        bool _isCompetitionMode
    )
        ERC20Mintable(
            "Liquid staked Ether 2.0",
            "stETH",
            18,
            _admin,
            _isCompetitionMode
        )
    {
        _rate = _initialRate;
        _lastUpdated = block.timestamp;
    }

    /// Overrides ///

    function submit(address) external payable returns (uint256) {
        // Accrue interest.
        _accrue();

        // If this is the first deposit, mint shares 1:1.
        if (getTotalShares() == 0) {
            totalShares = msg.value;
            totalPooledEther = msg.value;
            _mint(msg.sender, msg.value);
            return msg.value;
        }

        // Calculate the amount of stETH shares that should be minted.
        uint256 shares = msg.value.mulDivDown(
            getTotalShares(),
            getTotalPooledEther()
        );

        // Update the Lido state.
        totalPooledEther += msg.value;
        totalShares += shares;

        // Mint the stETH tokens to the user.
        _mint(msg.sender, msg.value);

        return shares;
    }

    function transferShares(
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256) {
        // Accrue interest.
        _accrue();

        // Calculate the amount of tokens that should be transferred.
        uint256 tokenAmount = _sharesAmount.mulDivDown(
            getTotalPooledEther(),
            getTotalShares()
        );

        // Transfer the tokens to the user.
        transfer(_recipient, tokenAmount);

        return tokenAmount;
    }

    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256) {
        // Accrue interest.
        _accrue();

        // Calculate the amount of tokens that should be transferred.
        uint256 tokenAmount = _sharesAmount.mulDivDown(
            getTotalPooledEther(),
            getTotalShares()
        );

        // Transfer the tokens to the user.
        transferFrom(_sender, _recipient, tokenAmount);

        return tokenAmount;
    }

    function getBufferedEther() external pure returns (uint256) {
        return 0;
    }

    function getTotalPooledEther() public view returns (uint256) {
        return totalPooledEther + _getAccruedInterest();
    }

    function getTotalShares() public view returns (uint256) {
        return totalShares;
    }

    function sharesOf(address _account) external view returns (uint256) {
        uint256 tokenBalance = balanceOf[_account];
        return tokenBalance.mulDivDown(getTotalShares(), getTotalPooledEther());
    }

    /// Mock ///

    function setRate(uint256 _rate_) external requiresAuthDuringCompetition {
        _accrue();
        _rate = _rate_;
    }

    function getRate() external view returns (uint256) {
        return _rate;
    }

    function _accrue() internal {
        uint256 interest = _getAccruedInterest();
        if (interest > 0) {
            totalPooledEther += interest;
        }
        _lastUpdated = block.timestamp;
    }

    function _getAccruedInterest() internal view returns (uint256) {
        if (_rate == 0) {
            return 0;
        }

        // base_balance = base_balance * (1 + r * t)
        uint256 timeElapsed = (block.timestamp - _lastUpdated).divDown(
            365 days
        );
        uint256 accrued = totalPooledEther.mulDown(_rate.mulDown(timeElapsed));
        return accrued;
    }
}
