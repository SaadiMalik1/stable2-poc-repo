# Critical Vulnerability in Stable2.sol: Permanent Fund Freezing via Non-Convergence

This repository contains a minimal, verifiable Proof of Concept (PoC) demonstrating a critical vulnerability in the `Stable2.sol` Well function. The vulnerability allows for a conditional Denial of Service (DoS), leading to a **permanent freezing of all user funds** within the affected Well.

## Summary (TL;DR)

The `calcLpTokenSupply` function, which is essential for all core AMM operations, contains a critical flaw in its iterative convergence algorithm. Specific, achievable reserve balances can cause this function to fail its convergence checks, making it revert every time it is called. An attacker can trigger this state with a single, crafted swap. Once triggered, all subsequent interactions (swaps, adding/removing liquidity) will fail, permanently locking all assets in the contract until a privileged upgrade is performed.

## Vulnerability Details

### Mechanism

The `calcLpTokenSupply` function iteratively calculates the invariant `D` (the total LP supply). To prevent infinite loops in edge cases, it contains logic to detect if the calculation is oscillating between two values. This is handled by the `stableOscillation` boolean flag.

### The Flaw

The `stableOscillation` flag is incorrectly scoped. It is declared **inside** the `for` loop, which means its state is reset to `false` at the beginning of every single iteration. This completely disables the oscillation-handling mechanism, as it can never remember the result of the previous iteration.

**File:** `src/Stable2.sol`  
**Vulnerable Code (Lines 93-94 & 109-112):**
```solidity
// ...
function calcLpTokenSupply(...) public view returns (uint256 lpTokenSupply) {
    // ...
    for (uint256 i = 0; i < 255; i++) {
        bool stableOscillation; // BUG: Re-initialized to `false` every iteration (Line 94)
        // ...
        if (lpTokenSupply > prevReserves) {
            if (lpTokenSupply - prevReserves == 2) {
                if (stableOscillation) { // UNREACHABLE: This condition can never be true
                    return lpTokenSupply - 1;
                }
                stableOscillation = true;
            }
            // ...
        }
        // ...
    }
    revert("Non convergence: calcLpTokenSupply"); // The function reverts if convergence fails
}
