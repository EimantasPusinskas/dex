// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title DEX - Decentralized Exchange
 * @author EP
 * @notice A simple AMM (Automated Market Maker) DEX implementing the constant product formula (x * y = k)
 * @dev This contract allows users to:
 *      - Add liquidity and receive LP tokens
 *      - Remove liquidity by burning LP tokens
 *      - Swap between two ERC20 tokens with a 0.3% fee
 *
 * Key Features:
 * - Constant product market maker (Uniswap V2 style)
 * - 0.3% trading fee that accrues to liquidity providers
 * - Reentrancy protection on all state-changing functions
 * - Slippage protection via minAmountOut parameter
 * - Transaction deadline to prevent stale transactions
 */
contract DEX is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    /// @notice The first token in the liquidity pool
    IERC20 public immutable tokenA;

    /// @notice The second token in the liquidity pool
    IERC20 public immutable tokenB;

    /// @notice Current reserve of tokenA in the pool
    uint256 public reserveA;

    /// @notice Current reserve of tokenB in the pool
    uint256 public reserveB;

    /// @notice Total supply of LP (Liquidity Provider) tokens
    uint256 public totalSupply;

    /// @notice Mapping of LP token balances for each address
    mapping(address => uint256) public balanceOf;

    // ============ Events ============

    /**
     * @notice Emitted when liquidity is added to the pool
     * @param provider Address of the liquidity provider
     * @param amountA Amount of tokenA added
     * @param amountB Amount of tokenB added
     * @param shares Amount of LP tokens minted
     */
    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 shares);

    /**
     * @notice Emitted when liquidity is removed from the pool
     * @param provider Address of the liquidity provider
     * @param amountA Amount of tokenA returned
     * @param amountB Amount of tokenB returned
     * @param shares Amount of LP tokens burned
     */
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 shares);

    /**
     * @notice Emitted when a swap occurs
     * @param sender Address that initiated the swap
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Amount of input tokens
     * @param amountOut Amount of output tokens
     */
    event Swap(
        address indexed sender, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    // ============ Constructor ============

    /**
     * @notice Initializes the DEX with two tokens
     * @param _tokenA Address of the first token
     * @param _tokenB Address of the second token
     */
    constructor(address _tokenA, address _tokenB) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    // ============ Liquidity Functions ============

    /**
     * @notice Add liquidity to the pool
     * @dev For the first deposit, LP tokens are calculated as sqrt(amountA * amountB)
     *      For subsequent deposits, LP tokens are proportional to the pool share
     *      Uses Math.min to prevent users from getting more shares than they deserve
     * @param _amountA Amount of tokenA to add
     * @param _amountB Amount of tokenB to add
     * @return shares Amount of LP tokens minted
     */
    function addLiquidity(uint256 _amountA, uint256 _amountB) external nonReentrant returns (uint256 shares) {
        // Checks: Validate input amounts
        require(_amountA > 0, "Amount A must not be zero");
        require(_amountB > 0, "Amount B must not be zero");

        // Calculate shares (liquidity tokens to mint)
        if (totalSupply == 0) {
            // Genesis deposit: Use geometric mean to prevent initial manipulation
            // sqrt(x * y) is used instead of x + y to make the initial ratio matter
            shares = Math.sqrt(_amountA * _amountB);
        } else {
            // Subsequent deposits: Mint shares proportional to pool increase
            // Reserves should never be 0 after initial deposit, but we check anyway
            require(reserveA > 0 && reserveB > 0, "Invalid reserves");

            // Calculate shares based on both tokens
            // sharesA = (amountA / reserveA) * totalSupply
            // sharesB = (amountB / reserveB) * totalSupply
            uint256 sharesA = (_amountA * totalSupply) / reserveA;
            uint256 sharesB = (_amountB * totalSupply) / reserveB;

            // Use minimum to ensure user is credited for the "weakest" side
            // This prevents users from gaming the system by depositing unbalanced amounts
            shares = Math.min(sharesA, sharesB);
        }

        // Ensure we're minting a non-zero amount of shares
        require(shares > 0, "Insufficient liquidity minted");

        // Effects: Update state variables (CEI pattern)
        balanceOf[msg.sender] += shares;
        totalSupply += shares;
        reserveA += _amountA;
        reserveB += _amountB;

        // Interactions: Transfer tokens from user (SafeERC20 handles return values)
        tokenA.safeTransferFrom(msg.sender, address(this), _amountA);
        tokenB.safeTransferFrom(msg.sender, address(this), _amountB);

        emit LiquidityAdded(msg.sender, _amountA, _amountB, shares);

        return shares;
    }

    /**
     * @notice Remove liquidity from the pool
     * @dev Burns LP tokens and returns proportional amounts of both tokens
     *      Amount returned = (shares / totalSupply) * reserve
     * @param _shares Amount of LP tokens to burn
     * @return amountA Amount of tokenA returned
     * @return amountB Amount of tokenB returned
     */
    function removeLiquidity(uint256 _shares) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        // Checks: Validate shares
        require(_shares > 0, "Insufficient shares");
        require(balanceOf[msg.sender] >= _shares, "Insufficient shares");

        // Calculate proportional amounts to return
        // User gets their % of the pool: (shares / totalSupply) * reserve
        amountA = (_shares * reserveA) / totalSupply;
        amountB = (_shares * reserveB) / totalSupply;

        // Prevent rounding to zero (edge case with very small shares)
        require(amountA > 0 && amountB > 0, "Insufficient liquidity burned");

        // Effects: Update state variables (CEI pattern)
        balanceOf[msg.sender] -= _shares;
        totalSupply -= _shares;
        reserveA -= amountA;
        reserveB -= amountB;

        // Interactions: Transfer tokens back to user
        tokenA.safeTransfer(msg.sender, amountA);
        tokenB.safeTransfer(msg.sender, amountB);

        emit LiquidityRemoved(msg.sender, amountA, amountB, _shares);

        return (amountA, amountB);
    }

    // ============ Swap Functions ============

    /**
     * @notice Swap one token for another
     * @dev Uses constant product formula: x * y = k
     *      Charges 0.3% fee (997/1000 of input goes to calculation)
     *      Formula: amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
     * @param amountIn Amount of input tokens
     * @param minAmountOut Minimum amount of output tokens (slippage protection)
     * @param tokenIn Address of input token (must be tokenA or tokenB)
     * @param deadline Unix timestamp after which transaction will revert
     * @return amountOut Amount of output tokens received
     */
    function swap(uint256 amountIn, uint256 minAmountOut, address tokenIn, uint256 deadline)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        // Checks: Validate inputs
        require(block.timestamp <= deadline, "Transaction expired");
        require(amountIn > 0, "Amount to swap must not be zero");
        require(tokenIn == address(tokenA) || tokenIn == address(tokenB), "Invalid token");
        require(reserveA > 0 && reserveB > 0, "Insufficient liquidity");

        // Determine swap direction
        bool isTokenA = tokenIn == address(tokenA);

        // Get correct reserves based on swap direction
        // If swapping tokenA → tokenB: reserveIn = reserveA, reserveOut = reserveB
        // If swapping tokenB → tokenA: reserveIn = reserveB, reserveOut = reserveA
        (uint256 reserveIn, uint256 reserveOut) = isTokenA ? (reserveA, reserveB) : (reserveB, reserveA);

        // Calculate output amount with 0.3% fee
        // Fee calculation: 997/1000 = 99.7% (0.3% fee goes to LPs)
        // Formula derivation:
        //   Before: reserveIn * reserveOut = k
        //   After:  (reserveIn + amountIn*0.997) * (reserveOut - amountOut) = k
        //   Solving for amountOut gives us the formula below
        uint256 amountInWithFee = amountIn * 997;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);

        // Verify slippage tolerance
        require(amountOut >= minAmountOut, "Slippage exceeded");
        require(amountOut > 0, "Insufficient output amount");

        // Effects: Update reserves (CEI pattern)
        if (isTokenA) {
            reserveA += amountIn;
            reserveB -= amountOut;
        } else {
            reserveB += amountIn;
            reserveA -= amountOut;
        }

        // Interactions: Transfer tokens
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20 tokenOut = isTokenA ? tokenB : tokenA;
        tokenOut.safeTransfer(msg.sender, amountOut);

        emit Swap(msg.sender, tokenIn, address(tokenOut), amountIn, amountOut);

        return amountOut;
    }

    // ============ View Functions ============

    /**
     * @notice Preview the output amount for a given swap
     * @dev This is a view function that doesn't modify state
     *      Useful for frontends to show users expected output before executing swap
     * @param amountIn Amount of input tokens
     * @param tokenIn Address of input token
     * @return amountOut Expected amount of output tokens
     */
    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256 amountOut) {
        require(tokenIn == address(tokenA) || tokenIn == address(tokenB), "Invalid token");
        require(reserveA > 0 && reserveB > 0, "Insufficient liquidity");

        bool isTokenA = tokenIn == address(tokenA);
        (uint256 reserveIn, uint256 reserveOut) = isTokenA ? (reserveA, reserveB) : (reserveB, reserveA);

        // Same calculation as swap() but without state changes
        uint256 amountInWithFee = amountIn * 997;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }
}
