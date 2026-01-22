// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DEX} from "../src/dex.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

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

        // Check shares minted
        // Total = sqrt(1000 * 2000) * 10^18 = 1414213562373095048801
        // Locked = 1000
        // Alice gets = Total - 1000
        uint256 expectedTotal = 1414213562373095048801;
        uint256 expectedAliceShares = expectedTotal - 1000;

        assertEq(shares, expectedAliceShares, "Incorrect shares minted");

        // Check reserves updated
        assertEq(dex.reserveA(), amountA, "Reserve A incorrect");
        assertEq(dex.reserveB(), amountB, "Reserve B incorrect");

        // Check total supply (includes locked shares)
        assertEq(dex.totalSupply(), expectedTotal, "Total supply incorrect");

        // Check user balance (excludes locked shares)
        assertEq(dex.balanceOf(alice), expectedAliceShares, "User shares incorrect");

        // Check locked shares
        assertEq(dex.balanceOf(address(0)), 1000, "Locked shares incorrect");

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

        // Alice can only remove her shares, not the locked 1000 shares
        // So she gets: (her_shares / total_supply) * reserve
        uint256 totalSupplyAfterAdd = dex.totalSupply() + shares; // Need to add back since we removed
        uint256 expectedAmountA = (shares * 1000 * 10 ** 18) / totalSupplyAfterAdd;
        uint256 expectedAmountB = (shares * 2000 * 10 ** 18) / totalSupplyAfterAdd;

        // Check amounts returned (allow small rounding error)
        assertApproxEqAbs(amountA, expectedAmountA, 1000, "Incorrect amountA returned");
        assertApproxEqAbs(amountB, expectedAmountB, 1000, "Incorrect amountB returned");

        // Reserves should have 1000 shares worth left (locked)
        assertGt(dex.reserveA(), 0, "Reserve A should not be zero (locked shares remain)");
        assertGt(dex.reserveB(), 0, "Reserve B should not be zero (locked shares remain)");

        // Check total supply has Alice's shares removed but locked shares remain
        assertEq(dex.totalSupply(), 1000, "Total supply should be 1000 (locked shares)");

        // Check alice got tokens back
        assertEq(tokenA.balanceOf(alice), aliceTokenABefore + amountA, "Alice didn't receive tokenA");
        assertEq(tokenB.balanceOf(alice), aliceTokenBBefore + amountB, "Alice didn't receive tokenB");

        vm.stopPrank();
    }

    function test_RemoveLiquidity_Partial() public {
        // Alice adds liquidity
        vm.startPrank(alice);
        uint256 shares = dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);

        // Remove half of Alice's shares
        uint256 sharesToRemove = shares / 2;
        (uint256 amountA, uint256 amountB) = dex.removeLiquidity(sharesToRemove);

        // Calculate expected amounts
        uint256 totalSupply = shares + 1000; // Alice's shares + locked
        uint256 expectedAmountA = (sharesToRemove * 1000 * 10 ** 18) / totalSupply;
        uint256 expectedAmountB = (sharesToRemove * 2000 * 10 ** 18) / totalSupply;

        // Should get back proportional amount
        assertApproxEqAbs(amountA, expectedAmountA, 1000, "Incorrect amountA");
        assertApproxEqAbs(amountB, expectedAmountB, 1000, "Incorrect amountB");

        // Check reserves reduced proportionally
        uint256 expectedReserveA = 1000 * 10 ** 18 - amountA;
        uint256 expectedReserveB = 2000 * 10 ** 18 - amountB;

        assertApproxEqAbs(dex.reserveA(), expectedReserveA, 1000, "Reserve A incorrect");
        assertApproxEqAbs(dex.reserveB(), expectedReserveB, 1000, "Reserve B incorrect");

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
        // Bound to what Alice has AND ensure sqrt is > 1000 (MINIMUM_LIQUIDITY)
        // sqrt(amountA * amountB) > 1000
        // So we need amountA * amountB > 1_000_000
        amountA = bound(amountA, 1001, 10_000 * 10 ** 18);
        amountB = bound(amountB, 1001, 10_000 * 10 ** 18);

        // Ensure sqrt will be > 1000
        uint256 sqrtProduct = Math.sqrt(amountA * amountB);
        vm.assume(sqrtProduct > 1000);

        vm.startPrank(alice);
        uint256 shares = dex.addLiquidity(amountA, amountB);

        // Basic invariants
        assertGt(shares, 0, "Shares should be > 0");
        assertEq(dex.reserveA(), amountA, "Reserve A mismatch");
        assertEq(dex.reserveB(), amountB, "Reserve B mismatch");

        // Alice should have shares (less 1000 locked on first deposit)
        uint256 expectedShares = sqrtProduct - 1000;
        assertEq(dex.balanceOf(alice), expectedShares, "Balance mismatch");

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

    // Test minimum liquidity lock
    function test_MinimumLiquidityLock() public {
        vm.startPrank(alice);

        uint256 amountA = 1000 * 10 ** 18;
        uint256 amountB = 2000 * 10 ** 18;

        uint256 shares = dex.addLiquidity(amountA, amountB);

        // Check that 1000 shares are locked
        assertEq(dex.balanceOf(address(0)), 1000, "Minimum liquidity not locked");

        // Check alice got remaining shares
        uint256 expectedTotal = Math.sqrt(amountA * amountB);
        assertEq(shares, expectedTotal - 1000, "Alice should get total - locked");

        vm.stopPrank();
    }

    function test_MinimumLiquidityLock_RevertsOnTooSmall() public {
        vm.startPrank(alice);

        // Try to add very small amounts (sqrt would be < 1000)
        vm.expectRevert("Insufficient initial liquidity");
        dex.addLiquidity(10, 10);

        vm.stopPrank();
    }

    // Test view functions
    function test_GetReserves() public {
        vm.prank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);

        (uint256 resA, uint256 resB) = dex.getReserves();
        assertEq(resA, 1000 * 10 ** 18, "Reserve A mismatch");
        assertEq(resB, 2000 * 10 ** 18, "Reserve B mismatch");
    }

    function test_GetPriceAInB() public {
        vm.prank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);

        uint256 price = dex.getPriceAInB();
        assertEq(price, 2 * 10 ** 18, "Price should be 2e18");
    }

    function test_GetPriceBInA() public {
        vm.prank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);

        uint256 price = dex.getPriceBInA();
        assertEq(price, 0.5 * 10 ** 18, "Price should be 0.5e18");
    }

    function test_GetPoolInfo() public {
        vm.prank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);

        (uint256 resA, uint256 resB, uint256 supply, uint256 priceAB, uint256 priceBA) = dex.getPoolInfo();

        assertEq(resA, 1000 * 10 ** 18, "Reserve A");
        assertEq(resB, 2000 * 10 ** 18, "Reserve B");
        assertGt(supply, 1000, "Total supply > minimum");
        assertEq(priceAB, 2 * 10 ** 18, "Price AB");
        assertEq(priceBA, 0.5 * 10 ** 18, "Price BA");
    }

    function test_GetLPValue() public {
        vm.prank(alice);
        uint256 shares = dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);

        (uint256 userShares, uint256 valueA, uint256 valueB) = dex.getLPValue(alice);

        assertEq(userShares, shares, "Shares mismatch");

        // Calculate expected values
        // Alice owns shares/(shares+1000) of the pool
        uint256 totalSupply = shares + 1000;
        uint256 expectedValueA = (shares * 1000 * 10 ** 18) / totalSupply;
        uint256 expectedValueB = (shares * 2000 * 10 ** 18) / totalSupply;

        assertApproxEqAbs(valueA, expectedValueA, 1000, "Value A mismatch");
        assertApproxEqAbs(valueB, expectedValueB, 1000, "Value B mismatch");
    }

    // ============ View Function Edge Cases ============

    function test_GetPriceAInB_RevertsOnNoLiquidity() public {
        // Don't add any liquidity
        vm.expectRevert("No liquidity");
        dex.getPriceAInB();
    }

    function test_GetPriceBInA_RevertsOnNoLiquidity() public {
        vm.expectRevert("No liquidity");
        dex.getPriceBInA();
    }

    function test_GetPrice_RevertsOnNoLiquidity() public {
        vm.expectRevert("No liquidity");
        dex.getPrice(address(tokenA));
    }

    function test_GetPrice_RevertsOnInvalidToken() public {
        vm.prank(alice);
        dex.addLiquidity(1000 * 10 ** 18, 2000 * 10 ** 18);

        vm.expectRevert("Invalid token");
        dex.getPrice(address(0xdead));
    }

    function test_GetPoolInfo_WithNoLiquidity() public {
        (uint256 resA, uint256 resB, uint256 supply, uint256 priceAB, uint256 priceBA) = dex.getPoolInfo();

        assertEq(resA, 0, "Reserve A should be 0");
        assertEq(resB, 0, "Reserve B should be 0");
        assertEq(supply, 0, "Supply should be 0");
        assertEq(priceAB, 0, "Price AB should be 0");
        assertEq(priceBA, 0, "Price BA should be 0");
    }

    function test_GetLPValue_WithNoLiquidity() public {
        (uint256 shares, uint256 valueA, uint256 valueB) = dex.getLPValue(alice);

        assertEq(shares, 0, "Shares should be 0");
        assertEq(valueA, 0, "Value A should be 0");
        assertEq(valueB, 0, "Value B should be 0");
    }

    function test_GetReserves_WithNoLiquidity() public {
        (uint256 resA, uint256 resB) = dex.getReserves();
        assertEq(resA, 0, "Reserve A should be 0");
        assertEq(resB, 0, "Reserve B should be 0");
    }

    function test_GetAmountOut_RevertsOnInsufficientLiquidity() public {
        vm.expectRevert("Insufficient liquidity");
        dex.getAmountOut(100 * 10 ** 18, address(tokenA));
    }

    function test_MultipleDepositsAndWithdrawals_MaintainsInvariant() public {
        // Alice deposit 1
        vm.startPrank(alice);
        uint256 shares1 = dex.addLiquidity(1000e18, 2000e18);

        // Bob deposit 2
        vm.startPrank(bob);
        uint256 shares2 = dex.addLiquidity(500e18, 1000e18);

        // Charlie swaps
        vm.startPrank(alice);
        dex.swap(100e18, 0, address(tokenA), block.timestamp + 1 hours);

        // Alice withdraws
        (uint256 amountA, uint256 amountB) = dex.removeLiquidity(shares1 / 2);

        // Verify: k should still be valid
        uint256 k = dex.reserveA() * dex.reserveB();
        assertGt(k, 0);

        // Verify: Bob can still withdraw his shares
        vm.startPrank(bob);
        (uint256 bobA, uint256 bobB) = dex.removeLiquidity(shares2);
        assertGt(bobA, 0);
        assertGt(bobB, 0);
    }

    function test_AddLiquidity_ExtremeImbalance() public {
        vm.startPrank(alice);

        // First deposit: balanced
        dex.addLiquidity(1000e18, 1000e18);

        // Second deposit: extremely imbalanced (10:1)
        uint256 shares = dex.addLiquidity(1000e18, 100e18); // 10:1 ratio

        // Should only get shares based on the "weaker" side
        // This tests that Math.min() works correctly
        assertGt(shares, 0);
        assertLt(shares, (1000e18 * dex.totalSupply()) / 1000e18); // Can't exceed single-token ratio
    }

    function test_Swap_PriceImpact() public {
        vm.prank(alice);
        dex.addLiquidity(1000e18, 1000e18); // 1:1 ratio

        // Small swap: price impact should be minimal
        uint256 smallOut = dex.getAmountOut(1e18, address(tokenA));

        // Larger swap: price impact should be significant
        uint256 largeOut = dex.getAmountOut(100e18, address(tokenA));

        // largeOut per unit should be less than smallOut per unit
        uint256 smallPricePerUnit = (smallOut * 1e18) / 1e18;
        uint256 largePricePerUnit = (largeOut * 1e18) / 100e18;

        assertLt(largePricePerUnit, smallPricePerUnit, "No price impact detected");
    }

    function test_Swap_RevertsWithoutApproval() public {
        vm.startPrank(alice);
        dex.addLiquidity(1000e18, 2000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        // Bob doesn't approve, tries to swap
        tokenA.approve(address(dex), 0); // Revoke approval

        vm.expectRevert(); // SafeERC20 will revert
        dex.swap(100e18, 0, address(tokenA), block.timestamp + 1 hours);
    }
}
