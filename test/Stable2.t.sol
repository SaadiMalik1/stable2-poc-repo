// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Stable2} from "src/Stable2.sol";
import {MockLookupTable} from "./mocks/MockLookupTable.sol";

contract Stable2Test is Test {
    Stable2 internal stable2;
    MockLookupTable internal lut;

    uint256 internal constant A = 100;

    function setUp() public {
        lut = new MockLookupTable(A);
        stable2 = new Stable2(address(lut));
    }

    /**
     * @notice This test proves that specific, highly imbalanced reserves cause the
     * calcLpTokenSupply function to fail to converge, resulting in a revert.
     * This demonstrates a conditional Denial of Service vulnerability.
     */
    function test_PoC_Fails_WhenOscillating() public {
        // These highly imbalanced reserve values trigger the non-convergence.
        uint256[] memory reserves = new uint256[](2);
        reserves[0] = 500_000e18;
        reserves[1] = 1_988_011_988_011_988_011;

        bytes memory data = abi.encode(uint256(18), uint256(18));

        // Expect the transaction to revert with the non-convergence error.
        vm.expectRevert("Non convergence: calcLpTokenSupply");
        stable2.calcLpTokenSupply(reserves, data);
    }

    /**
     * @notice This test demonstrates that the contract functions correctly under
     * normal, balanced conditions, confirming the conditional nature of the DoS.
     */
    function test_Succeeds_With_Normal_Reserves() public view {
        // Use reserves that are close to balanced.
        uint256[] memory reserves = new uint256[](2);
        reserves[0] = 1_000_000e18;
        reserves[1] = 1_000_001e18;

        bytes memory data = abi.encode(uint256(18), uint256(18));

        // The call should succeed and not revert.
        uint256 lpTokenSupply = stable2.calcLpTokenSupply(reserves, data);

        // Assert that we get a sensible, non-zero result.
        // The exact value is complex, so we just check it's close to the sum.
        assertApproxEqAbs(lpTokenSupply, 2_000_001e18, 1e12);
    }
}
