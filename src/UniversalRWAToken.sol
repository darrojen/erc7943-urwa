// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC7943Fungible is IERC165 {
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount);
    event Frozen(address indexed account, uint256 amount);

    error ERC7943CannotSend(address account);
    error ERC7943CannotReceive(address account);
    error ERC7943CannotTransfer(address from, address to, uint256 amount);
    error ERC7943InsufficientUnfrozenBalance(
        address account,
        uint256 amount,
        uint256 unfrozen
    );

    function forcedTransfer(address from, address to, uint256 amount)
        external
        returns (bool result);

    function setFrozenTokens(address account, uint256 amount)
        external
        returns (bool result);

    function canSend(address account) external view returns (bool allowed);
    function canReceive(address account) external view returns (bool allowed);
    function getFrozenTokens(address account) external view returns (uint256 amount);
    function canTransfer(address from, address to, uint256 amount)
        external
        view
        returns (bool allowed);
}

contract UniversalRWAToken is IERC7943Fungible {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) public allowlisted;
    mapping(address => uint256) private _frozenTokens;

    address public immutable admin;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event AllowlistUpdated(address indexed account, bool allowed);
    event TransferRejected(address indexed from, address indexed to, uint256 amount);

    error NotAdmin();
    error ZeroAddress();
    error ERC20InsufficientBalance(address account, uint256 balance, uint256 needed);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint256 initialSupply
    ) {
        name = tokenName;
        symbol = tokenSymbol;
        admin = msg.sender;
        allowlisted[msg.sender] = true;
        emit AllowlistUpdated(msg.sender, true);
        _mint(msg.sender, initialSupply);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (spender == address(0)) revert ZeroAddress();
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance < amount) {
            revert ERC20InsufficientAllowance(msg.sender, currentAllowance, amount);
        }

        _transfer(from, to, amount);

        unchecked {
            _allowances[from][msg.sender] = currentAllowance - amount;
        }
        emit Approval(from, msg.sender, currentAllowance - amount);
        return true;
    }

    function setAllowlist(address account, bool allowed) external onlyAdmin {
        if (account == address(0)) revert ZeroAddress();
        allowlisted[account] = allowed;
        emit AllowlistUpdated(account, allowed);
    }

    function canSend(address account) public view returns (bool allowed) {
        return allowlisted[account];
    }

    function canReceive(address account) public view returns (bool allowed) {
        return allowlisted[account];
    }

    function getFrozenTokens(address account) public view returns (uint256 amount) {
        return _frozenTokens[account];
    }

    function canTransfer(
        address from,
        address to,
        uint256 amount
    ) public view returns (bool allowed) {
        if (!canSend(from)) return false;
        if (!canReceive(to)) return false;

        uint256 balance = _balances[from];

        // Base-token balance checks are intentionally left to ERC-20 transfer logic.
        if (amount > balance) return true;

        uint256 frozen = _frozenTokens[from];
        uint256 unfrozen = balance > frozen ? balance - frozen : 0;

        return amount <= unfrozen;
    }

    function setFrozenTokens(
        address account,
        uint256 amount
    ) external onlyAdmin returns (bool result) {
        if (account == address(0)) revert ZeroAddress();
        _frozenTokens[account] = amount;
        emit Frozen(account, amount);
        return true;
    }

    function forcedTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyAdmin returns (bool result) {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        if (!canReceive(to)) revert ERC7943CannotReceive(to);

        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) {
            revert ERC20InsufficientBalance(from, fromBalance, amount);
        }

        uint256 frozen = _frozenTokens[from];
        if (frozen != 0) {
            uint256 unfrozenFrozen;
            if (amount >= frozen) {
                unfrozenFrozen = 0;
            } else {
                unfrozenFrozen = frozen - amount;
            }
            _frozenTokens[from] = unfrozenFrozen;
            emit Frozen(from, unfrozenFrozen);
        }

        _balances[from] = fromBalance - amount;
        _balances[to] += amount;

        emit Transfer(from, to, amount);
        emit ForcedTransfer(from, to, amount);
        return true;
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 ||
            interfaceId == type(IERC7943Fungible).interfaceId;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();

        if (!canSend(from)) revert ERC7943CannotSend(from);
        if (!canReceive(to)) revert ERC7943CannotReceive(to);

        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) {
            revert ERC20InsufficientBalance(from, fromBalance, amount);
        }

        uint256 frozen = _frozenTokens[from];
        uint256 unfrozen = fromBalance > frozen ? fromBalance - frozen : 0;

        if (amount > unfrozen) {
            revert ERC7943InsufficientUnfrozenBalance(from, amount, unfrozen);
        }

        if (!canTransfer(from, to, amount)) {
            emit TransferRejected(from, to, amount);
            revert ERC7943CannotTransfer(from, to, amount);
        }

        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;

        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}
