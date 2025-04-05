// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

//@audit-Info Un-Used import
//Its a bad practice to edit live code for test/mock,we must remove import from `MockFalsLoanReciver.sol`file
import { IThunderLoan } from "./IThunderLoan.sol";

/**
 * @dev Inspired by Aave:
 * https://github.com/aave/aave-v3-core/blob/master/contracts/flashloan/interfaces/IFlashLoanReceiver.sol
 */
interface IFlashLoanReceiver {
    //@audit Where is  the natspec?
    //q is the token, the token that's borrowing token?
    //q amount is amount of token?
    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    )
        external
        returns (bool);
}
