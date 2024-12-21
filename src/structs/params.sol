// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct ClaimProtocolFeesParams {
    address pool;
    int24 tickLower;
    int24 tickUpper;
    uint128 fees0;
    uint128 fees1;
}

struct ClosePositionsParams {
    address user;
    uint256 index;
}

struct OrderParams {
    address pool;
    int24 target;
    bool zeroForOne;
    uint256 tokenAmount;
}
