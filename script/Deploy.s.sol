// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/SimpleToken.sol";
import "../src/SimplePair.sol";

// 部署脚本（Foundry Script）
// 人话：这是一个简单的部署脚本，部署两个示例 ERC20 代币和一个 Pair 合约，方便在本地演示/测试。
contract DeployScript is Script {
    function run() external {
        // 开始广播交易（将使用 `anvil` 或者通过 RPC 的私钥）
        vm.startBroadcast();
        // 部署两个测试用代币，初始发行 10000 个（单位为 wei * 1e18）
        SimpleToken t0 = new SimpleToken("TokenA","TKA", 10000 ether);
        SimpleToken t1 = new SimpleToken("TokenB","TKB", 10000 ether);
        // 基于这两个代币创建一个简单的交易对合约
        SimplePair pair = new SimplePair(address(t0), address(t1));
        // 输出地址，便于在控制台看到部署结果
        console.log("TokenA:", address(t0));
        console.log("TokenB:", address(t1));
        console.log("Pair:", address(pair));
        // 停止广播
        vm.stopBroadcast();
    }
}