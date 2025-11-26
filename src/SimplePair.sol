// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./SimpleToken.sol";

/// @notice 简化版 Uniswap V2 风格 Pair 合约（教学用途）
// 人话：这个合约实现了一个非常精简的恒定乘积 (x * y = k) 交易对。
// - 支持添加/移除流动性（mint / burn）并铸造 LP 代币
// - 支持 swap，按 0.3% 手续费校验 invariant（保证 x*y 不被破坏）
// 仅用于教学与本地测试，不推荐用于生产环境。
contract SimplePair {
    SimpleToken public token0;
    SimpleToken public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public totalSupply; // LP total supply
    mapping(address => uint256) public balanceOf; // LP balances

    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    event Mint(address indexed sender, uint amount0, uint amount1, uint liquidity);
    event Burn(address indexed sender, uint amount0, uint amount1, address to);
    event Swap(address indexed sender, uint amount0In, uint amount1In, uint amount0Out, uint amount1Out, address to);
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(address _token0, address _token1) {
        token0 = SimpleToken(_token0);
        token1 = SimpleToken(_token1);
    }

    function getReserves() public view returns (uint112, uint112) {
        return (reserve0, reserve1);
    }

    // add liquidity: caller must transfer tokens to this contract before calling
    function mint(address to) external returns (uint256 liquidity) {
        // 人话：mint 计算本次添加的 token0/token1 数量，根据当前 reserve 与 totalSupply 计算应向用户铸造的 LP 数量。
        // - 第一次添加会保留 MINIMUM_LIQUIDITY 避免移除导致除零
        // - 非首次按比例计算新增 LP
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;

        require(amount0 > 0 && amount1 > 0, "Insufficient amounts");

        if (totalSupply == 0) {
            uint256 _liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            totalSupply = MINIMUM_LIQUIDITY;
            balanceOf[address(0)] = MINIMUM_LIQUIDITY;
            totalSupply += _liquidity;
            balanceOf[to] += _liquidity;
            liquidity = _liquidity;
        } else {
            uint256 _liquidity0 = (amount0 * totalSupply) / reserve0;
            uint256 _liquidity1 = (amount1 * totalSupply) / reserve1;
            liquidity = _liquidity0 < _liquidity1 ? _liquidity0 : _liquidity1;
            require(liquidity > 0, "Insufficient liquidity minted");
            totalSupply += liquidity;
            balanceOf[to] += liquidity;
        }

        _update(uint112(balance0), uint112(balance1));
        emit Mint(msg.sender, amount0, amount1, liquidity);
    }

    // burn LP tokens: caller burns all their LP balance and receives underlying
    function burn(address to) external returns (uint256 amount0, uint256 amount1) {
        // 人话：burn 会把调用者持有的所有 LP 一次性赎回为 underlying token0/token1。
        // 实际项目中通常会让用户传入要 burn 的 LP 数量，而不是全部。
        uint256 liquidity = balanceOf[msg.sender];
        require(liquidity > 0, "No liquidity");

        uint256 _totalSupply = totalSupply;
        amount0 = (liquidity * reserve0) / _totalSupply;
        amount1 = (liquidity * reserve1) / _totalSupply;

        require(amount0 > 0 || amount1 > 0, "Insufficient amount");

        // burn
        balanceOf[msg.sender] -= liquidity;
        totalSupply -= liquidity;

        // transfer out
        require(token0.transfer(to, amount0), "Transfer0 failed");
        require(token1.transfer(to, amount1), "Transfer1 failed");

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        _update(uint112(balance0), uint112(balance1));
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // swap: caller must transfer input tokens to pair before calling swap
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external {
        // 人话：swap 实现乐观转账（先转出），再检查输入金额是否满足 invariant。
        // - 交易流程：用户先把输入代币转到该合约，然后调用 swap 指定输出数量。
        // - 合约把输出代币转出后，计算实际的 input（balance - (reserve - amountOut)），再校验 fee 后的乘积 >= 之前的乘积。
        // - 手续费按 0.3%（在校验时通过乘以 1000 并减去 3 * amountIn 实现）。
        require(amount0Out > 0 || amount1Out > 0, "Insufficient output amount");
        (uint112 _reserve0, uint112 _reserve1) = (reserve0, reserve1);
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "Insufficient liquidity");

        // optimistic transfer out
        if (amount0Out > 0) require(token0.transfer(to, amount0Out), "Transfer0 failed");
        if (amount1Out > 0) require(token1.transfer(to, amount1Out), "Transfer1 failed");

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        uint256 amount0In = balance0 > (_reserve0 - amount0Out) ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > (_reserve1 - amount1Out) ? balance1 - (_reserve1 - amount1Out) : 0;

        require(amount0In > 0 || amount1In > 0, "Insufficient input amount");

        // fee 0.3% : adjusted balances
        uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
        require(balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * uint256(_reserve1) * (1000 * 1000), "K");

        _update(uint112(balance0), uint112(balance1));
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function _update(uint112 balance0, uint112 balance1) private {
        // 人话：内部更新储备值并发出 Sync 事件，表示储备已与合约实际余额同步。
        reserve0 = balance0;
        reserve1 = balance1;
        blockTimestampLast = uint32(block.timestamp % 2**32);
        emit Sync(reserve0, reserve1);
    }

    // simple sqrt
    function sqrt(uint y) internal pure returns (uint z) {
        // 人话：简单的整数平方根实现，用于首次 mint 计算初始流动性。
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}