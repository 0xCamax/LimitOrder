// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct PositionInfo {
    address pool;
    address owner;
    uint128 liquidity;
    bool zeroForOne;
    int24 tickLower;
    int24 tickUpper;
}

struct PoolInfo {
    bytes32 poolKey;
    int24 tickLower;
    int24 tickUpper;
}