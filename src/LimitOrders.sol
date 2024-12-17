// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {IV3Factory} from "./interface/IV3Factory.sol";
import {IV3Pool} from "./interface/IV3Pool.sol";
import "./libraries/LiquidityAmounts.sol";
import "./libraries/TickMath.sol";
import "./libraries/TransferHelper.sol";
import "./structs/params.sol";
import "./structs/storage.sol";

contract LimitOrder {
    address internal owner;
    IV3Factory internal factory;

    mapping(address => bool) internal poolSet;
    mapping(address => bool) internal userSet;

    mapping(address => PoolInfo[]) internal poolKeys;
    mapping(address => PositionInfo[]) public userPositions;

    address[] internal pools;
    address[] internal users;

    constructor(address _factory) {
        factory = IV3Factory(_factory);
        owner = msg.sender;
    }

    function getUserPositions(
        address user
    ) public view returns (PositionInfo[] memory) {
        return userPositions[user];
    }

    function limitOrder(
        int24 target,
        address tokenFrom,
        address tokenTo,
        uint256 tokenAmount,
        uint24 fee
    ) public {
        IV3Pool pool = IV3Pool(
            factory.getPool(tokenFrom, tokenTo, fee)
        );
        bool zeroForOne = pool.token0() == tokenFrom ? true : false;

        (, int24 currentTick, , , , , ) = pool.slot0();

        require(target >= 0, "Invalid target");

        int24 tickLower;
        int24 tickUpper;
        int24 spacing = pool.tickSpacing();

        if (zeroForOne) {
            tickLower =
                (currentTick - (currentTick % spacing)) +
                spacing *
                target;
            tickUpper = tickLower + spacing;
        } else {
            tickUpper =
                (currentTick - (currentTick % spacing)) -
                spacing *
                target;
            tickLower = tickUpper - spacing;
        }

        uint128 amount = tokenFrom == pool.token0()
            ? LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                tokenAmount
            )
            : LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                tokenAmount
            );

        pool.mint(
            address(this),
            tickLower,
            tickUpper,
            amount,
            abi.encode(msg.sender, address(pool))
        );

        bytes32 poolKey = keccak256(
            abi.encodePacked(address(this), tickLower, tickUpper)
        );

        if (!poolSet[address(pool)]) {
            pools.push(address(pool));
            poolSet[address(pool)] = true;
        }
        if (!userSet[msg.sender]) {
            users.push(msg.sender);
            userSet[msg.sender] = true;
        }

        poolKeys[address(pool)].push(PoolInfo(poolKey, tickLower, tickUpper));

        userPositions[msg.sender].push(
            PositionInfo({
                pool: address(pool),
                owner: msg.sender,
                liquidity: amount,
                zeroForOne: zeroForOne,
                tickLower: tickLower,
                tickUpper: tickUpper
            })
        );
    }

    function adjustPosition(uint256 index, int24 target) public {
        PositionInfo memory position = userPositions[msg.sender][index];

        require(msg.sender == position.owner, "Unauthorized");

        IV3Pool pool = IV3Pool(position.pool);
        (uint256 amount0, uint256 amount1) = cancelPosition(index);
        position.zeroForOne
            ? limitOrder(target, pool.token0(), pool.token1(), amount0, pool.fee())
            : limitOrder(target, pool.token1(), pool.token0(), amount1, pool.fee());
    }

    function cancelPosition(
        uint256 index
    ) public returns (uint256 amount0, uint256 amount1) {
        PositionInfo memory position = userPositions[msg.sender][index];
        require(position.liquidity > 0, "Position closed");
        (amount0, amount1) = _close(msg.sender, index);
    }

    function closePosition(bytes[] memory params) public {
        for (uint i = 0; i < params.length; i++) {
            ClosePositionsParams memory param = abi.decode(
                params[i],
                (ClosePositionsParams)
            );
            PositionInfo memory position = userPositions[param.user][
                param.index
            ];
            if (position.liquidity > 0) {
                if (_checkPosition(position)) {
                    _close(param.user, param.index);
                }
            }
        }
    }

    function claimProtocolFees(bytes[] memory params) public {
        for (uint256 i = 0; i < params.length; i++) {
            ClaimProtocolFeesParams memory param = abi.decode(
                params[i],
                (ClaimProtocolFeesParams)
            );
            IV3Pool pool = IV3Pool(param.pool);
            pool.collect(
                owner,
                param.tickLower,
                param.tickUpper,
                param.fees0,
                param.fees1
            );
        }
    }

    function computeClosePositions() public view returns (bytes[] memory data) {
        address[] memory _users = users;
        uint256 count = 0;
        for (uint i = 0; i < _users.length; i++) {
            address user = _users[i];
            PositionInfo[] memory _userPositions = userPositions[user];
            for (uint j = 0; j < _userPositions.length; j++) {
                PositionInfo memory position = _userPositions[j];
                if (position.liquidity > 0) {
                    if (_checkPosition(position)) {
                        count++;
                    }
                }
            }
        }

        data = new bytes[](count);

        uint256 index = 0;
        for (uint i = 0; i < _users.length; i++) {
            address user = _users[i];
            PositionInfo[] memory _userPositions = userPositions[user];
            for (uint j = 0; j < _userPositions.length; j++) {
                PositionInfo memory position = _userPositions[j];
                if (position.liquidity > 0) {
                    if (_checkPosition(position)) {
                        data[index] = abi.encode(user, j);
                    }
                }
            }
        }
    }

    function computeClaimProtocolFeesParams()
        public
        view
        returns (bytes[] memory data)
    {
        address[] memory _pools = pools;

        uint256 count = 0;
        for (uint256 i = 0; i < _pools.length; i++) {
            IV3Pool pool = IV3Pool(_pools[i]);
            PoolInfo[] memory poolsInfo = poolKeys[address(pool)];
            for (uint256 j = 0; j < poolsInfo.length; j++) {
                PoolInfo memory poolInfo = poolsInfo[j];
                (, , , uint128 fees0, uint128 fees1) = pool.positions(
                    poolInfo.poolKey
                );
                if (fees0 > 0 || fees1 > 0) {
                    count++;
                }
            }
        }

        data = new bytes[](count);

        uint256 index = 0;
        for (uint256 i = 0; i < _pools.length; i++) {
            IV3Pool pool = IV3Pool(_pools[i]);
            PoolInfo[] memory poolsInfo = poolKeys[address(pool)];
            for (uint256 j = 0; j < poolsInfo.length; j++) {
                PoolInfo memory poolInfo = poolsInfo[j];
                (, , , uint128 fees0, uint128 fees1) = pool.positions(
                    poolInfo.poolKey
                );
                if (fees0 > 0 || fees1 > 0) {
                    data[index] = abi.encode(
                        address(pool),
                        poolInfo.tickLower,
                        poolInfo.tickUpper,
                        fees0,
                        fees1
                    );
                    index++;
                }
            }
        }
    }

    function _close(
        address user,
        uint256 index
    ) internal returns (uint256 amount0, uint256 amount1) {
        PositionInfo storage position = userPositions[user][index];

        (amount0, amount1) = _removeLiquidity(
            position.owner,
            position.liquidity,
            IV3Pool(position.pool),
            position.tickLower,
            position.tickUpper
        );

        userPositions[user][index] = PositionInfo({
            pool: position.pool,
            owner: position.owner,
            liquidity: 0,
            zeroForOne: false,
            tickLower: position.tickLower,
            tickUpper: position.tickUpper
        });
    }

    function _removeLiquidity(
        address to,
        uint128 amount,
        IV3Pool pool,
        int24 tickLower,
        int24 tickUpper
    ) internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = pool.burn(tickLower, tickUpper, amount);

        pool.collect(
            to,
            tickLower,
            tickUpper,
            uint128(amount0),
            uint128(amount1)
        );
    }

    function _checkPosition(
        PositionInfo memory position
    ) internal view returns (bool) {
        IV3Pool pool = IV3Pool(position.pool);
        (, int24 currentTick, , , , , ) = pool.slot0();
        return
            !position.zeroForOne
                ? currentTick < position.tickLower
                : currentTick > position.tickUpper;
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        (address user, address pool) = abi.decode(data, (address, address));
        require(msg.sender == pool, "Unauthorized");

        if (amount0Owed > 0) {
            TransferHelper.safeTransferFrom(
                IV3Pool(pool).token0(),
                user,
                pool,
                uint256(amount0Owed)
            );
        }
        if (amount1Owed > 0) {
            TransferHelper.safeTransferFrom(
                IV3Pool(pool).token1(),
                user,
                pool,
                uint256(amount1Owed)
            );
        }
    }
}
