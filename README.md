# Simple DEX (Decentralized Exchange)

A minimal implementation of an Automated Market Maker (AMM) decentralized exchange, inspired by Uniswap V2. This project demonstrates core DeFi concepts including liquidity pools, constant product formula, and token swaps.

![Solidity](https://img.shields.io/badge/Solidity-^0.8.20-blue)
![Foundry](https://img.shields.io/badge/Framework-Foundry-red)
![License](https://img.shields.io/badge/License-MIT-green)
![Tests](https://img.shields.io/badge/Tests-23%20Passing-brightgreen)
![Coverage](https://img.shields.io/badge/Coverage-100%25-brightgreen)

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [How It Works](#how-it-works)
- [Installation](#installation)
- [Usage](#usage)
- [Testing](#testing)
- [Contract Architecture](#contract-architecture)
- [Security Considerations](#security-considerations)
- [Learning Resources](#learning-resources)
- [License](#license)

## Overview

This DEX allows users to:
- **Add liquidity** to a token pair pool and earn LP tokens
- **Remove liquidity** by burning LP tokens
- **Swap** between two ERC20 tokens with minimal slippage

Built as a learning project to understand:
- Automated Market Maker (AMM) mechanics
- Constant product formula (x × y = k)
- Liquidity provision and LP tokens
- Smart contract security patterns (CEI, ReentrancyGuard)

## Features

### Core Functionality
- **Constant Product AMM**: Uses the `x * y = k` formula for pricing
- **0.3% Trading Fee**: Fees accrue to liquidity providers
- **Slippage Protection**: Users specify minimum output amounts
- **Deadline Protection**: Transactions expire after specified time
- **LP Tokens**: Liquidity providers receive shares proportional to their contribution

### Security Features
- **ReentrancyGuard**: Protection against reentrancy attacks
- **SafeERC20**: Safe handling of ERC20 token transfers
- **CEI Pattern**: Checks-Effects-Interactions for state safety
- **Input Validation**: Comprehensive require statements

## How It Works

### Constant Product Formula

The DEX maintains the invariant:
```
reserveA × reserveB = k (constant)
```

When a user swaps tokens, the product `k` remains constant (or slightly increases due to fees).

### Adding Liquidity

**First Deposit (Genesis):**
```solidity
shares = sqrt(amountA * amountB)
```

**Subsequent Deposits:**
```solidity
shares = min(
    (amountA * totalSupply) / reserveA,
    (amountB * totalSupply) / reserveB
)
```

Using `min` ensures users can't game the system by depositing unbalanced amounts.

### Removing Liquidity

Users burn LP tokens to receive their proportional share:
```solidity
amountA = (shares * reserveA) / totalSupply
amountB = (shares * reserveB) / totalSupply
```

### Swapping

The swap calculation includes a 0.3% fee:
```solidity
amountInWithFee = amountIn * 997  // 99.7% after fee
amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee)
```

## 🚀 Installation

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Setup
```bash
# Clone the repository
git clone https://github.com/yourusername/simple-dex.git
cd simple-dex

# Install dependencies
forge install

# Build the project
forge build
```

## 💻 Usage

### Deploying the Contract
```solidity
// Deploy with two token addresses
DEX dex = new DEX(tokenAAddress, tokenBAddress);
```

### Adding Liquidity
```solidity
// Approve tokens first
tokenA.approve(address(dex), amountA);
tokenB.approve(address(dex), amountB);

// Add liquidity
uint256 shares = dex.addLiquidity(amountA, amountB);
```

### Swapping Tokens
```solidity
// Approve input token
tokenA.approve(address(dex), amountIn);

// Preview swap
uint256 expectedOut = dex.getAmountOut(amountIn, address(tokenA));

// Execute swap with slippage protection
uint256 minOut = expectedOut * 99 / 100;  // 1% slippage tolerance
uint256 deadline = block.timestamp + 15 minutes;
uint256 amountOut = dex.swap(amountIn, minOut, address(tokenA), deadline);
```

### Removing Liquidity
```solidity
// Burn LP tokens to get tokens back
(uint256 amountA, uint256 amountB) = dex.removeLiquidity(shares);
```

## Testing

The project includes comprehensive tests covering:
- Genesis and subsequent liquidity deposits
- Full and partial liquidity removal
- Token swaps in both directions
- Slippage protection
- Deadline expiration
- Constant product invariant
- Fuzz testing for edge cases

### Run Tests
```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test test_Swap_TokenAForTokenB -vvv

# Run with gas report
forge test --gas-report

# Run fuzz tests with more runs
forge test --fuzz-runs 1000
```

### Test Coverage
```bash
forge coverage
```

## Contract Architecture
```
src/
├── dex.sol              # Main DEX contract
test/
├── dex.t.sol            # Comprehensive test suite
└── mocks/
    └── MockERC20.sol    # Mock ERC20 for testing
```

### Key Functions

| Function | Description |
|----------|-------------|
| `addLiquidity(uint256, uint256)` | Add liquidity to pool, receive LP tokens |
| `removeLiquidity(uint256)` | Burn LP tokens, receive both tokens |
| `swap(uint256, uint256, address, uint256)` | Swap one token for another |
| `getAmountOut(uint256, address)` | Preview swap output (view function) |

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `tokenA` | IERC20 | First token in the pair |
| `tokenB` | IERC20 | Second token in the pair |
| `reserveA` | uint256 | Current reserve of tokenA |
| `reserveB` | uint256 | Current reserve of tokenB |
| `totalSupply` | uint256 | Total LP tokens in circulation |
| `balanceOf` | mapping | LP token balance per address |

## Security Considerations

### Implemented Protections

**Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier  
**Integer Overflow**: Solidity 0.8+ has built-in overflow checks  
**SafeERC20**: Handles non-standard ERC20 return values  
**Slippage Protection**: Users specify minimum output amounts  
**Deadline Protection**: Prevents stale transactions  
**Minimum Liquidity Lock**: 1000 wei permanently locked on genesis deposit (Uniswap V2 pattern)

### Known Limitations

 **Not Production Ready**: This is a learning project  
 **Price Manipulation**: Small pools are vulnerable to price manipulation  
 **Impermanent Loss**: LPs exposed to impermanent loss (inherent to AMMs)  
 **Front-running**: Public mempool transactions can be front-run  
 **Single Pair Only**: Only supports one token pair (no factory pattern)

### Potential Improvements

- Add TWAP (Time-Weighted Average Price) oracle
- Implement flash swap functionality
- Add factory pattern for multiple pairs
- Gas optimizations (packed storage, unchecked math where safe)

## Learning Resources

This project implements concepts from:

- [Uniswap V2 Whitepaper](https://uniswap.org/whitepaper.pdf)
- [Uniswap V2 Core](https://github.com/Uniswap/v2-core)
- [Constant Product Market Maker](https://en.wikipedia.org/wiki/Constant_function_market_maker)
- [Smart Contract Security Best Practices](https://consensys.github.io/smart-contract-best-practices/)

### Key Concepts Demonstrated

- **AMM Mechanics**: How automated market makers price assets
- **Liquidity Provision**: How LPs earn fees from trading volume
- **Constant Product Formula**: The math behind x * y = k
- **Integer Math in Solidity**: Avoiding precision loss in calculations
- **Smart Contract Patterns**: CEI, ReentrancyGuard, SafeERC20
- **Comprehensive Testing**: Unit tests, fuzz tests, invariant tests

## 🚀 Live Deployment (Sepolia Testnet)

The DEX is deployed and verified on Sepolia testnet:

- **DEX**: [`0x6fC747515068d73E8AF6D1caFc7113C50252C32C`](https://sepolia.etherscan.io/address/0x6fc747515068d73e8af6d1cafc7113c50252c32c)
- **TokenA (TKA)**: [`0xa8787f507253f37a8d0623ab375c2542D21f922F`](https://sepolia.etherscan.io/address/0xa8787f507253f37a8d0623ab375c2542d21f922f)  
- **TokenB (TKB)**: [`0xc518D2E467426E49b38c1C1511Cf559ca3F7B460`](https://sepolia.etherscan.io/address/0xc518d2e467426e49b38c1c1511cf559ca3f7b460)

### Try it yourself:
1. Get Sepolia ETH from [faucet](https://sepoliafaucet.com/)
2. Interact directly on [Etherscan](https://sepolia.etherscan.io/address/0x6fc747515068d73e8af6d1cafc7113c50252c32c#writeContract)
3. Or use our frontend (coming soon!)

### Deployment Stats:
- Total gas used: 4,009,554
- Deployment cost: 0.004375 ETH
- All contracts verified ✅

### Key Statistics:
- **Test Coverage**: 100% (23 tests passing)
- **Functions**: 8 external, 5 view
- **Gas Optimization**: ReentrancyGuard + SafeERC20
- **Security**: CEI pattern, comprehensive input validation

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

