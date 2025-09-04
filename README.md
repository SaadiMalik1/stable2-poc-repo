# Critical Vulnerability in Stable2.sol: Permanent Fund Freezing via Unvalidated LUT Dependency

This repository contains a minimal, verifiable Proof of Concept (PoC) demonstrating a critical architectural vulnerability in the `Stable2.sol` Well function. The flaw lies in the contract's implicit trust of its Lookup Table (LUT) dependency, creating a single point of failure that can be exploited to permanently freeze all user funds within an affected Well.

This report demonstrates that the issue is not related to reserve imbalance, but rather to a lack of defensive programming and input validation.

## Summary of Vulnerabilities

The `Stable2` contract can be rendered permanently non-functional through two distinct vectors, both leading to the same catastrophic outcome: **permanent fund freezing**.

1.  **Vector A: Malicious or Faulty LUT (Design Flaw)**: The `Stable2` constructor accepts any address as a Lookup Table (LUT) without validation. If this LUT is malicious or misconfigured, it can force critical functions to revert with unhandled exceptions (e.g., division-by-zero, arithmetic underflow). **This PoC proves this vector works even with perfectly balanced reserves**, invalidating previous arguments that failures are only due to reserve imbalance.

2.  **Vector B: Extreme Reserve Imbalance (Implementation Flaw)**: Independent of the LUT, the core algorithm in `calcLpTokenSupply` fails to converge under certain highly imbalanced reserve conditions. This confirms a pattern of fragility where the contract does not handle edge cases gracefully.

## Impact: Permanent Freezing of Funds

Both vectors lead to a permanent Denial of Service (DoS). Core functions like `calcLpTokenSupply` and `calcReserveAtRatioSwap` are essential for all AMM operations. When they are made to revert, the following becomes impossible:
-   Swapping tokens
-   Adding liquidity
-   **Withdrawing liquidity**

All user funds are effectively trapped in the contract. Recovery is not possible through any standard user interaction and would require a privileged and complex governance action to upgrade the Well's implementation.

## The "Trusted LUT" Argument is a Red Herring

The argument that the LUT is a "trusted, governance-deployed component" does not mitigate this risk; it concentrates it. In security, trust is a vulnerability. This architecture introduces a single point of failure (SPOF) where the following scenarios lead to catastrophe:

-   **Governance Attack**: An exploit targeting the governance protocol could allow an attacker to deploy a malicious LUT.
-   **Private Key Compromise**: The compromise of a single governance multi-sig key could be enough to deploy a malicious LUT.
-   **Human Error**: A developer could accidentally deploy a LUT with incorrect parameters (e.g., `highPrice == lowPrice`), bricking every Well that uses it.

Robust contracts must be resilient and should not enter an irrecoverable state due to faulty data from an external dependency, trusted or not.

## Proof of Concept (PoC)

The included Foundry project (`UnifiedPoC.sol`) demonstrates all vectors in a single, self-contained test file.

### Reproduction Steps

1.  **Prerequisites:** Ensure [Foundry](https://getfoundry.sh) is installed.

2.  **Clone the repository:**
    ```sh
    git clone <your-repo-url>
    cd stable2-systemic-risk-poc
    ```

3.  **Install dependencies:**
    ```sh
    forge install
    ```

4.  **Run the tests:**
    ```sh
    forge test --match-contract UnifiedPoC -vv
    ```

### Expected Outcome

The test will deploy the `UnifiedPoC` contract and run four test functions. The output will show events confirming that the three attack vectors succeed in causing a revert, while the control test (normal operation) succeeds.

-   `runPoC_ImbalancedReserves` -> **SUCCESS**: Reverts as expected.
-   `runPoC_EqualPrices` -> **SUCCESS**: Reverts as expected.
-   `runPoC_InvertedJ` -> **SUCCESS**: Reverts as expected.
-   `runControl_NormalOperation` -> **SUCCESS**: Executes normally.

This provides undeniable proof of multiple pathways to a permanent fund freeze.

## Recommended Fixes

1.  **Validate LUT in `constructor`**: The `Stable2` constructor should call the prospective LUT and validate its parameters to prevent initialization with a faulty LUT.
2.  **Add In-line Validation**: Functions like `updateReserve` should include checks to prevent division-by-zero and other exceptions, even if the LUT is assumed to be correct.
    ```solidity
    function updateReserve(PriceData memory pd, uint256 reserve) internal pure returns (uint256) {
        uint256 priceDiff = pd.lutData.highPrice - pd.lutData.lowPrice;
        if (priceDiff == 0) { revert("InvalidLUTPriceRange"); } // Add this check
        
        if (pd.targetPrice > pd.currentPrice) {
            return reserve - pd.maxStepSize * (pd.targetPrice - pd.currentPrice) / priceDiff;
        } else {
            return reserve + pd.maxStepSize * (pd.currentPrice - pd.targetPrice) / priceDiff;
        }
    }
    ```
3.  **Improve Algorithm Robustness**: The core convergence algorithm in `calcLpTokenSupply` should be reviewed for numerical stability under a wider range of conditions.
