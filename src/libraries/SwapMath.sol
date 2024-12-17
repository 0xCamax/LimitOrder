// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import './FullMath.sol';
import './SqrtPriceMath.sol';
import "./TickMath.sol";
import "./LiquidityAmounts.sol";

/// @title Computes the result of a swap within ticks
/// @notice Contains methods for computing the result of a swap within a single tick price range, i.e., a single tick.
library SwapMath {

    uint256 constant BASE_SCALE = 1e18;

    struct AmountDeltaParams {
        uint160 sqrtCurrentPrice;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidityDelta;
        uint256 tokenBalance;
    }

    function amounts(
        uint160 currentPrice,
        int24 tickLower,
        int24 tickUpper,
        uint256 tokenBalance
        ) internal pure returns (uint256 amount0ETH, uint256 amount1ETH){

        uint160 tickLowerPrice = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 tickUpperPrice = TickMath.getSqrtRatioAtTick(tickUpper);

        if(currentPrice < tickLowerPrice) {
            amount0ETH = tokenBalance;
            amount1ETH = 0;
            return (amount0ETH, amount1ETH);
        }
        if(currentPrice > tickUpperPrice){
            amount0ETH = 0;
            amount1ETH = tokenBalance;
            return (amount0ETH, amount1ETH);
        }
        if(currentPrice >= tickLowerPrice && currentPrice < tickUpperPrice){
            uint256 absDifA = currentPrice - tickLowerPrice;
            uint256 absDifB = tickUpperPrice - currentPrice;

            uint256 ratioA = absDifA * BASE_SCALE / (absDifA + absDifB);
            uint256 ratioB = absDifB * BASE_SCALE / (absDifA + absDifB);
            
            amount0ETH = tokenBalance * ratioB / BASE_SCALE;
            amount1ETH = tokenBalance - amount0ETH;

            if(amount0ETH < amount1ETH){
                amount1ETH = tokenBalance * ratioA / BASE_SCALE;
                amount0ETH = tokenBalance - amount1ETH;
                return (amount0ETH, amount1ETH);
            }
        }
    }

    function amountsDesired(uint160 currentPrice, int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1) internal pure returns (uint256 _amount0, uint256 _amount1){

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            currentPrice, 
            TickMath.getSqrtRatioAtTick(tickLower), 
            TickMath.getSqrtRatioAtTick(tickUpper), 
            amount0, 
            amount1);
        
        _amount0 = SqrtPriceMath.getAmount0Delta(
            currentPrice, 
            TickMath.getSqrtRatioAtTick(tickUpper), 
            liquidity, 
            false);

        _amount1 = SqrtPriceMath.getAmount1Delta(
            TickMath.getSqrtRatioAtTick(tickLower), 
            currentPrice, 
            liquidity, 
            false);
    }


    function getPrice(uint256 sqrtPrice, uint256 decimalA, uint256 decimalB) internal pure returns (uint256 priceA, uint256 priceB) {
        uint256 SCALE = 10 ** (decimalA - decimalB);
        uint256 DECIMALS_B = 10 ** decimalB;
        if(decimalA == decimalB){
            priceA = (sqrtPrice * BASE_SCALE / 2 ** 96) ** 2 / BASE_SCALE;
            priceB = BASE_SCALE / priceA;
        }
        if(decimalA != decimalB) {
            priceA = (sqrtPrice * BASE_SCALE / 2 ** 96) ** 2 / DECIMALS_B;
            priceB = BASE_SCALE * BASE_SCALE / priceA * DECIMALS_B / SCALE * DECIMALS_B;
        }
    }
}