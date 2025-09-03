// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

abstract contract ProportionalLPToken2 {
    function getReserves() public view virtual returns (uint256[] memory reserves) {
        address[] memory tokens = getTokens();
        reserves = new uint256[](tokens.length);
        for (uint i; i < tokens.length; ++i) {
            reserves[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
    }
    function getTokens() public view virtual returns (address[] memory);
}
