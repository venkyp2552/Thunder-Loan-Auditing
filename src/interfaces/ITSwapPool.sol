// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

// q - Why are we only using the price of pool token in weth?
//We shouldn't be -> its a bug!
interface ITSwapPool {
    function getPriceOfOnePoolTokenInWeth() external view returns (uint256);
}
