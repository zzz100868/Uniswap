// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @notice 极简 ERC20，用于 AMM 测试（仅做 Demo）
// 人话：这是一个非常简单的 ERC20 实现，方便在测试中快速铸币与转账。
// - 不实现完整 ERC20 的所有安全检查，仅用于本地测试环境
contract SimpleToken {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint256 _initial) {
        // 部署时给部署者铸造初始代币
        name = _name;
        symbol = _symbol;
        _mint(msg.sender, _initial);
    }

    function _mint(address to, uint256 amount) internal {
        // 内部铸币函数，增加总供应并更新余额，触发 Transfer(0, to, amount)
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    // convenience for tests
    // 人话：对测试友好的外部铸币接口，任何人都可调用以简化测试场景
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        // 授权 spender 可以花费调用者指定数量的代币
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        // 直接转账
        require(balanceOf[msg.sender] >= amount, "Insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        // 授权转账：spender 使用 allowance 转移他人代币
        require(balanceOf[from] >= amount, "Insufficient");
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "Allowance");
        allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}