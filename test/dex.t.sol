// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DEX} from "../src/dex.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract DEXTest is Test {
    DEX public dex;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address public alice = address(0x1);
    address public bob = address(0x2);

    function setUp() public {
        // Deploy tokens
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");

        // Deploy DEX
        dex = new DEX(address(tokenA), address(tokenB));

        // Mint tokens to alice and bob
        tokenA.mint(alice, 10_000 * 10 ** 18);
        tokenB.mint(alice, 10_000 * 10 ** 18);
        tokenA.mint(bob, 10_000 * 10 ** 18);
        tokenB.mint(bob, 10_000 * 10 ** 18);

        // Give approvals
        vm.startPrank(alice);
        tokenA.approve(address(dex), type(uint256).max);
        tokenB.approve(address(dex), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.approve(address(dex), type(uint256).max);
        tokenB.approve(address(dex), type(uint256).max);
        vm.stopPrank();
    }

    // ============ ADD LIQUIDITY TESTS ============

    function test_AddLiquidity_Genesis() public {
        vm.startPrank(alice);

        uint256 amountA = 1000 * 10 ** 18;
        uint256 amountB = 2000 * 10 ** 18;

        uint256 shares = dex.addLiquidity(amountA, amountB);

        // Check shares minted (should be sqrt(1000 * 2000) * 10^18)
        uint256 expectedShares = 1414213562373095048801; // sqrt(2_000_000) * 10^18
        assertEq(shares, expectedShares, "Incorrect shares minted");

        // Check reserves updated
        assertEq(dex.reserveA(), amountA, "Reserve A incorrect");
        assertEq(dex.reserveB(), amountB, "Reserve B incorrect");

        // Check total supply
        assertEq(dex.totalSupply(), expectedShares, "Total supply incorrect");

        // Check user balance
        assertEq(dex.balanceOf(alice), expectedShares, "User shares incorrect");

        vm.stopPrank();
    }

    function test_AddLiquidity_Subsequent() public {
        // Alice adds initial liquidity
        vm.startPrank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);
        vm.stopPrank();

        // Bob adds liquidity at same ratio
        vm.startPrank(bob);
        uint256 amountA = 500 * 10 ** 18;
        uint256 amountB = 1000 * 10 ** 18;

        uint256 totalSupplyBefore = dex.totalSupply();
        uint256 shares = dex.addLiquidity(amountA, amountB);

        // Check shares are proportional (should be 0.5 * totalSupply)
        uint256 expectedShares = totalSupplyBefore / 2;
        assertEq(shares, expectedShares, "Incorrect proportional shares");

        vm.stopPrank();
    }

    function test_AddLiquidity_RevertsOnZeroAmount() public {
        vm.startPrank(alice);

        vm.expectRevert("Amount A must not be zero");
        dex.addLiquidity(0, 1000 * 10 ** 18);

        vm.expectRevert("Amount B must not be zero");
        dex.addLiquidity(1000 * 10 ** 18, 0);

        vm.stopPrank();
    }

    // ============ REMOVE LIQUIDITY TESTS ============

    function test_RemoveLiquidity_Full() public {
        // Alice adds liquidity
        vm.startPrank(alice);
        uint256 shares = dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);

        // Record balances before
        uint256 aliceTokenABefore = tokenA.balanceOf(alice);
        uint256 aliceTokenBBefore = tokenB.balanceOf(alice);

        // Remove all liquidity
        (uint256 amountA, uint256 amountB) = dex.removeLiquidity(shares);

        // Check amounts returned
        assertEq(amountA, 1000 * 10 ** 18, "Incorrect amountA returned");
        assertEq(amountB, 2000 * 10 ** 18, "Incorrect amountB returned");

        // Check reserves are zero
        assertEq(dex.reserveA(), 0, "Reserve A should be zero");
        assertEq(dex.reserveB(), 0, "Reserve B should be zero");

        // Check total supply is zero
        assertEq(dex.totalSupply(), 0, "Total supply should be zero");

        // Check alice got tokens back
        assertEq(tokenA.balanceOf(alice), aliceTokenABefore + amountA, "Alice didn't receive tokenA");
        assertEq(tokenB.balanceOf(alice), aliceTokenBBefore + amountB, "Alice didn't receive tokenB");

        vm.stopPrank();
    }

    function test_RemoveLiquidity_Partial() public {
        // Alice adds liquidity
        vm.startPrank(alice);
        uint256 shares = dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);

        // Remove half
        uint256 sharesToRemove = shares / 2;
        (uint256 amountA, uint256 amountB) = dex.removeLiquidity(sharesToRemove);

        // Should get back ~half of each token
        assertApproxEqAbs(amountA, 500 * 10 ** 18, 1, "Incorrect amountA");
        assertApproxEqAbs(amountB, 1000 * 10 ** 18, 1, "Incorrect amountB");

        // Check reserves reduced by half
        assertApproxEqAbs(dex.reserveA(), 500 * 10 ** 18, 1, "Reserve A incorrect");
        assertApproxEqAbs(dex.reserveB(), 1000 * 10 ** 18, 1, "Reserve B incorrect");

        vm.stopPrank();
    }

    function test_RemoveLiquidity_RevertsOnInsufficientShares() public {
        vm.startPrank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);

        vm.expectRevert("Insufficient shares");
        dex.removeLiquidity(999999 * 10 ** 18); // More than alice has

        vm.stopPrank();
    }

    // ============ SWAP TESTS ============

    function test_Swap_TokenAForTokenB() public {
        // Alice adds liquidity
        vm.startPrank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);
        vm.stopPrank();

        // Bob swaps 100 tokenA for tokenB
        vm.startPrank(bob);
        uint256 amountIn = 100 * 10 ** 18;
        uint256 minAmountOut = 0; // No slippage protection for this test
        uint256 deadline = block.timestamp + 1 hours; // ← Added deadline

        uint256 bobTokenBBefore = tokenB.balanceOf(bob);

        uint256 amountOut = dex.swap(amountIn, minAmountOut, address(tokenA), deadline);

        // Calculate expected output
        uint256 expectedOut = (amountIn * 997 * 2000 * 10 ** 18) / (1000 * 10 ** 18 * 1000 + amountIn * 997);

        assertApproxEqAbs(amountOut, expectedOut, 10 ** 15, "Incorrect swap output");

        // Check bob received tokens
        assertEq(tokenB.balanceOf(bob), bobTokenBBefore + amountOut, "Bob didn't receive tokens");

        // Check reserves updated
        assertEq(dex.reserveA(), 1100 * 10 ** 18, "Reserve A incorrect");
        assertApproxEqAbs(dex.reserveB(), 2000 * 10 ** 18 - amountOut, 1, "Reserve B incorrect");

        vm.stopPrank();
    }

    function test_Swap_TokenBForTokenA() public {
        // Alice adds liquidity
        vm.startPrank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);
        vm.stopPrank();

        // Bob swaps 200 tokenB for tokenA
        vm.startPrank(bob);
        uint256 amountIn = 200 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours; // ← Added deadline

        uint256 amountOut = dex.swap(amountIn, 0, address(tokenB), deadline);

        // Calculate expected output
        uint256 expectedOut = (amountIn * 997 * 1000 * 10 ** 18) / (2000 * 10 ** 18 * 1000 + amountIn * 997);

        assertApproxEqAbs(amountOut, expectedOut, 10 ** 15, "Incorrect swap output");

        vm.stopPrank();
    }

    function test_Swap_RevertsOnSlippageExceeded() public {
        vm.startPrank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 amountIn = 100 * 10 ** 18;
        uint256 minAmountOut = 200 * 10 ** 18; // Unrealistic expectation
        uint256 deadline = block.timestamp + 1 hours; // ← Added deadline

        vm.expectRevert("Slippage exceeded");
        dex.swap(amountIn, minAmountOut, address(tokenA), deadline);

        vm.stopPrank();
    }

    function test_Swap_RevertsOnInvalidToken() public {
        vm.startPrank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 deadline = block.timestamp + 1 hours; // ← Added deadline

        vm.expectRevert("Invalid token");
        dex.swap(100 * 10 ** 18, 0, address(0xdead), deadline);

        vm.stopPrank();
    }

    function test_Swap_RevertsOnExpiredDeadline() public {
        // ← New test for deadline feature!
        vm.startPrank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 deadline = block.timestamp - 1; // Deadline in the past

        vm.expectRevert("Transaction expired");
        dex.swap(100 * 10 ** 18, 0, address(tokenA), deadline);

        vm.stopPrank();
    }

    // ============ GET AMOUNT OUT TESTS ============

    function test_GetAmountOut_MatchesActualSwap() public {
        // ← New test for view function!
        vm.prank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);

        uint256 amountIn = 100 * 10 ** 18;

        // Get preview
        uint256 expectedOut = dex.getAmountOut(amountIn, address(tokenA));

        // Perform actual swap
        vm.prank(bob);
        uint256 actualOut = dex.swap(amountIn, 0, address(tokenA), block.timestamp + 1 hours);

        // They should match
        assertEq(actualOut, expectedOut, "Preview doesn't match actual swap");
    }

    function test_GetAmountOut_RevertsOnInvalidToken() public {
        vm.prank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);

        vm.expectRevert("Invalid token");
        dex.getAmountOut(100 * 10 ** 18, address(0xdead));
    }

    // ============ CONSTANT PRODUCT INVARIANT TEST ============

    function test_ConstantProduct_MaintainedAfterSwap() public {
        // Add liquidity
        vm.prank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);

        uint256 kBefore = dex.reserveA() * dex.reserveB();

        // Perform swap
        vm.prank(bob);
        dex.swap(100 * 10 ** 18, 0, address(tokenA), block.timestamp + 1 hours);

        uint256 kAfter = dex.reserveA() * dex.reserveB();

        // k should increase slightly due to fees
        assertGe(kAfter, kBefore, "Constant product should increase with fees");
    }

    // ============ FUZZ TESTS ============

    function testFuzz_AddLiquidity(uint256 amountA, uint256 amountB) public {
        // Bound inputs to reasonable ranges
        amountA = bound(amountA, 1000, 1_000 * 10 ** 18);
        amountB = bound(amountB, 1000, 1_000 * 10 ** 18);

        vm.startPrank(alice);
        uint256 shares = dex.addLiquidity(amountA, amountB);

        // Basic invariants
        assertGt(shares, 0, "Shares should be > 0");
        assertEq(dex.reserveA(), amountA, "Reserve A mismatch");
        assertEq(dex.reserveB(), amountB, "Reserve B mismatch");
        assertEq(dex.balanceOf(alice), shares, "Balance mismatch");

        vm.stopPrank();
    }

    function testFuzz_Swap(uint256 amountIn) public {
        // Setup pool
        vm.prank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);

        // Bound swap amount (don't drain pool)
        amountIn = bound(amountIn, 1 * 10 ** 16, 100 * 10 ** 18);

        vm.startPrank(bob);

        uint256 kBefore = dex.reserveA() * dex.reserveB();
        uint256 amountOut = dex.swap(amountIn, 0, address(tokenA), block.timestamp + 1 hours);
        uint256 kAfter = dex.reserveA() * dex.reserveB();

        // Invariants
        assertGt(amountOut, 0, "Output should be > 0");
        assertGe(kAfter, kBefore, "k should not decrease");

        vm.stopPrank();
    }
}
