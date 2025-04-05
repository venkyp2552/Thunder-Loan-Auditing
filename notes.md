<!-- ~391 nSLOC

## Terms

1. Liquidity-Provider : Someone who deposits money into protocol to rewarded or earn intrest in returns.
2. Where is intrest or retruns coming? 
   1. TSwap : from swapping fees
   2. Thunder Loan: fees frm loans?
   
Slither
Aderyn

#My Views:
1. IFalsLoanReceiver.sol file importing IThunderLoan.sol interface buts its used anywhere.
2. Its used in MockFalshLoanReceiver file 
   1.Here 
import { IFlashLoanReceiver, IThunderLoan } from "../../src/interfaces/IFlashLoanReceiver.sol"; instead of this we should do like
   import { IFlashLoanReceiver } from "../../src/interfaces/IFlashLoanReceiver.sol";
   import { IThunderLoan } from "../../src/interfaces/IThunderLoan.sol";

   2.


# Potential attack Vectors 

# Ideas

# Questions
Q: Why are we using TSwapPool.sol?What does that have to do with flash loans? -->
