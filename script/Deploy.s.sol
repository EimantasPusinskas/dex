// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import Foundry's Script base contract
// This gives us vm.startBroadcast(), console.log(), etc.
import {Script, console} from "forge-std/Script.sol";

// Import your contracts
import {DEX} from "../src/dex.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

/**
 * @title DeployDEX
 * @notice Deployment script for DEX and test tokens
 * @dev Run with: forge script script/Deploy.s.sol:DeployDEX --rpc-url $SEPOLIA_RPC_URL --broadcast
 */
contract DeployDEX is Script {
    // This function is automatically called by Foundry
    function run() external {
        // ============ STEP 1: Get Deployer Info ============

        // Read private key from environment variable
        // This is YOUR private key from .env file
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Calculate the deployer's address from private key
        // This is YOUR MetaMask address
        address deployer = vm.addr(deployerPrivateKey);

        console.log("===========================================");
        console.log("Deploying contracts with account:", deployer);
        console.log("===========================================");

        // ============ STEP 2: Start Broadcasting Transactions ============

        // Everything after this line will be a REAL blockchain transaction
        // It costs gas and is permanent!
        vm.startBroadcast(deployerPrivateKey);

        // ============ STEP 3: Deploy Token A ============

        // Deploy first mock ERC20 token
        // Constructor parameters: (name, symbol)
        MockERC20 tokenA = new MockERC20("Token A", "TKA");

        // Log the deployed address
        console.log("TokenA deployed at:", address(tokenA));

        // ============ STEP 4: Deploy Token B ============

        // Deploy second mock ERC20 token
        MockERC20 tokenB = new MockERC20("Token B", "TKB");

        console.log("TokenB deployed at:", address(tokenB));

        // ============ STEP 5: Deploy DEX ============

        // Deploy the DEX contract
        // Constructor parameters: (tokenA address, tokenB address)
        DEX dex = new DEX(address(tokenA), address(tokenB));

        console.log("DEX deployed at:", address(dex));

        // ============ STEP 6: Optional - Mint Initial Tokens ============

        // Mint some tokens to deployer for testing
        // Each token starts with 1 million tokens minted to deployer (from MockERC20 constructor)
        // But we can mint more if needed:

        // Uncomment these if you want extra tokens:
        // tokenA.mint(deployer, 10_000 * 10**18);  // Mint 10,000 more TokenA
        // tokenB.mint(deployer, 10_000 * 10**18);  // Mint 10,000 more TokenB

        console.log("Deployer TokenA balance:", tokenA.balanceOf(deployer) / 10 ** 18, "TKA");
        console.log("Deployer TokenB balance:", tokenB.balanceOf(deployer) / 10 ** 18, "TKB");

        // ============ STEP 7: Stop Broadcasting ============

        // Stop broadcasting transactions
        // Anything after this is NOT sent to blockchain
        vm.stopBroadcast();

        // ============ STEP 8: Summary ============

        console.log("===========================================");
        console.log("Deployment Summary:");
        console.log("===========================================");
        console.log("Network: Sepolia Testnet");
        console.log("Deployer:", deployer);
        console.log("");
        console.log("Contract Addresses:");
        console.log("  TokenA:", address(tokenA));
        console.log("  TokenB:", address(tokenB));
        console.log("  DEX:   ", address(dex));
        console.log("===========================================");
        console.log("");
        console.log("Next Steps:");
        console.log("1. Verify on Etherscan:");
        console.log("   https://sepolia.etherscan.io/address/", address(dex));
        console.log("");
        console.log("2. Save these addresses for your frontend!");
        console.log("");
        console.log("3. Try interacting via Etherscan:");
        console.log("   - Approve tokens");
        console.log("   - Add liquidity");
        console.log("   - Perform swaps");
        console.log("===========================================");
    }
}
