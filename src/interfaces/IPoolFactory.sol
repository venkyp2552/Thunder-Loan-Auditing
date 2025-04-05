// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

// e this is  probably the interface of TswapPool.sol contract
// q-answered why are we using ?
// we need use tswap contract for  calcualte the token fee
interface IPoolFactory {
    function getPool(address tokenAddress) external view returns (address);
}
