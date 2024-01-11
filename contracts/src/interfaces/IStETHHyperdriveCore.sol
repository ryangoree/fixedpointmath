// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "./IERC20.sol";
import { IHyperdriveCore } from "./IHyperdriveCore.sol";

interface IStETHHyperdriveCore is IHyperdriveCore {
    function sweep(IERC20 _target) external;
}
