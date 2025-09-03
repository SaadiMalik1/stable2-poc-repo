// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBeanstalkWellFunction {
    function calcLpTokenSupply(uint256[] memory reserves, bytes memory data) external view returns (uint256 lpTokenSupply);
    function calcReserve(uint256[] memory reserves, uint256 j, uint256 lpTokenSupply, bytes memory data) external view returns (uint256 reserve);
    function calcReserveAtRatioLiquidity(uint256[] calldata reserves, uint256 j, uint256[] calldata ratios, bytes calldata data) external view returns (uint256);
}

interface IMultiFlowPumpWellFunction is IBeanstalkWellFunction {
    function calcRate(uint256[] memory reserves, uint256 i, uint256 j, bytes memory data) external view returns (uint256 rate);
    function ratioPrecision(uint256 j, bytes calldata data) external view returns (uint256 precision);
    function calcReserveAtRatioSwap(uint256[] calldata reserves, uint256 j, uint256[] calldata ratios, bytes calldata data) external view returns (uint256);
}
