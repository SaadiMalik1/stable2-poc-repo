// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILookupTable {
    struct PriceData {
        uint256 precision;
        uint256 lowPrice;
        uint256 lowPriceJ;
        uint256 lowPriceI;
        uint256 highPrice;
        uint256 highPriceJ;
        uint256 highPriceI;
    }
    function getRatiosFromPriceLiquidity(uint256) external view returns (PriceData memory);
    function getRatiosFromPriceSwap(uint256) external view returns (PriceData memory);
    function getAParameter() external view returns (uint256);
}
