// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

//@audit-Info IThunderLoan contract shuld be implemented by the Thunderloan contract!
interface IThunderLoan {
    //@audit-Low/Informational 
    function repay(address token, uint256 amount) external;
}
