// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILookupTable} from "src/interfaces/ILookupTable.sol";

contract MockLookupTable is ILookupTable {
    uint256 private _a;

    constructor(uint256 a_) {
        _a = a_;
    }

    function getAParameter() external view returns (uint256) {
        return _a;
    }

    function getRatiosFromPriceLiquidity(uint256) external pure returns (PriceData memory) {
        revert("Not implemented");
    }

    function getRatiosFromPriceSwap(uint256) external pure returns (PriceData memory) {
        revert("Not implemented");
    }
}
