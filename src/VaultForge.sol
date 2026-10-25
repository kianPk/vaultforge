// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";

/// @title VaultForge
/// @notice Production-shaped ERC-4626 vault with a single active strategy,
///         performance fees, role-gated ops, and pause/guardian controls.
contract VaultForge is ERC4626, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    IStrategy public strategy;
    address public feeRecipient;

    /// @dev Performance fee in bps taken on harvested profit (max 2000 = 20%).
    uint16 public performanceFeeBps;
    uint16 public constant MAX_PERFORMANCE_FEE_BPS = 2000;

    uint256 public totalHarvested;
    uint256 public totalFees;

    /// @notice Hard cap on totalAssets (0 = uncapped).
    uint256 public depositCap;
    /// @notice Max assets deployable into the active strategy (0 = uncapped).
    uint256 public strategyCap;
    /// @notice Target fraction of NAV kept in the strategy, in bps (e.g. 8000 = 80%).
    uint16 public debtRatioBps;
    /// @notice High-water share price (1e18 scale) for reporting.
    uint256 public highWaterSharePrice;

    event StrategyUpdated(address indexed previous, address indexed next);
    event Harvested(uint256 profit, uint256 fee, uint256 timestamp);
    event PerformanceFeeUpdated(uint16 bps);
    event FeeRecipientUpdated(address indexed recipient);
    event Allocated(uint256 amount);
    event Recalled(uint256 amount);
    event DepositCapUpdated(uint256 cap);
    event StrategyCapUpdated(uint256 cap);
    event DebtRatioUpdated(uint16 bps);
    event Rebalanced(uint256 idle, uint256 deployed, uint256 targetDeployed);

    error InvalidFee();
    error InvalidAddress();
    error StrategyAssetMismatch();
    error ZeroAmount();
    error DepositCapExceeded();
    error StrategyCapExceeded();
    error InvalidDebtRatio();

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        address feeRecipient_,
        uint16 performanceFeeBps_
    ) ERC20(name_, symbol_) ERC4626(asset_) {
        if (admin_ == address(0) || feeRecipient_ == address(0)) revert InvalidAddress();
        if (performanceFeeBps_ > MAX_PERFORMANCE_FEE_BPS) revert InvalidFee();

        feeRecipient = feeRecipient_;
        performanceFeeBps = performanceFeeBps_;
        debtRatioBps = 8_000;
        highWaterSharePrice = 1e18;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(STRATEGIST_ROLE, admin_);
        _grantRole(GUARDIAN_ROLE, admin_);
    }

    // ─── Views ───────────────────────────────────────────────────────────────

    /// @inheritdoc ERC4626
    function totalAssets() public view override returns (uint256) {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        uint256 deployed = address(strategy) == address(0) ? 0 : strategy.totalAssets();
        return idle + deployed;
    }

    function idleAssets() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function deployedAssets() public view returns (uint256) {
        return address(strategy) == address(0) ? 0 : strategy.totalAssets();
    }

    /// @notice Share price scaled by 1e18 (assets per share).
    function sharePrice() public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 1e18;
        return (totalAssets() * 1e18) / supply;
    }

    function _enforceCap(uint256 assetsIn) internal view {
        if (depositCap == 0) return;
        if (totalAssets() + assetsIn > depositCap) revert DepositCapExceeded();
    }

    // ─── User entry points ───────────────────────────────────────────────────

    function deposit(uint256 assets, address receiver)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        _enforceCap(assets);
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        _enforceCap(previewMint(shares));
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner);
    }

    /// @dev Pull from strategy if idle liquidity is insufficient.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        uint256 idle = idleAssets();
        if (assets > idle) {
            uint256 needed = assets - idle;
            if (address(strategy) != address(0)) {
                strategy.withdraw(needed);
            }
        }
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    // ─── Strategist ops ──────────────────────────────────────────────────────

    function setStrategy(address next)
        external
        onlyRole(STRATEGIST_ROLE)
    {
        if (next == address(0)) revert InvalidAddress();
        if (IStrategy(next).asset() != asset()) revert StrategyAssetMismatch();
        if (IStrategy(next).vault() != address(this)) revert InvalidAddress();

        address prev = address(strategy);
        if (prev != address(0)) {
            uint256 bal = strategy.totalAssets();
            if (bal > 0) strategy.withdraw(bal);
        }

        strategy = IStrategy(next);
        emit StrategyUpdated(prev, next);
    }

    function allocate(uint256 amount) external onlyRole(STRATEGIST_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (address(strategy) == address(0)) revert InvalidAddress();
        _enforceStrategyCap(amount);
        IERC20(asset()).forceApprove(address(strategy), amount);
        strategy.deposit(amount);
        emit Allocated(amount);
    }

    function recall(uint256 amount) external onlyRole(STRATEGIST_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (address(strategy) == address(0)) revert InvalidAddress();
        uint256 got = strategy.withdraw(amount);
        emit Recalled(got);
    }

    function harvest()
        external
        onlyRole(STRATEGIST_ROLE)
        nonReentrant
        returns (uint256 profit, uint256 fee)
    {
        if (address(strategy) == address(0)) revert InvalidAddress();
        uint256 beforeAssets = totalAssets();
        strategy.harvest();
        uint256 afterAssets = totalAssets();
        if (afterAssets > beforeAssets) {
            profit = afterAssets - beforeAssets;
            fee = (profit * performanceFeeBps) / 10_000;
            if (fee > 0) {
                uint256 feeShares = convertToShares(fee);
                _mint(feeRecipient, feeShares);
                totalFees += fee;
            }
            totalHarvested += profit;
        }
        emit Harvested(profit, fee, block.timestamp);
    }

    function setPerformanceFeeBps(uint16 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > MAX_PERFORMANCE_FEE_BPS) revert InvalidFee();
        performanceFeeBps = bps;
        emit PerformanceFeeUpdated(bps);
    }

    function setFeeRecipient(address recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert InvalidAddress();
        feeRecipient = recipient;
        emit FeeRecipientUpdated(recipient);
    }

    function setDepositCap(uint256 cap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        depositCap = cap;
        emit DepositCapUpdated(cap);
    }

    function setStrategyCap(uint256 cap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyCap = cap;
        emit StrategyCapUpdated(cap);
    }

    function _enforceStrategyCap(uint256 additionalDeploy) internal view {
        if (strategyCap == 0) return;
        if (deployedAssets() + additionalDeploy > strategyCap) revert StrategyCapExceeded();
    }

    function setDebtRatioBps(uint16 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > 10_000) revert InvalidDebtRatio();
        debtRatioBps = bps;
        emit DebtRatioUpdated(bps);
    }

    /// @notice Move idle/deployed liquidity toward `debtRatioBps` of NAV.
    function rebalance() external onlyRole(STRATEGIST_ROLE) nonReentrant {
        if (address(strategy) == address(0)) revert InvalidAddress();
        uint256 nav = totalAssets();
        uint256 target = (nav * debtRatioBps) / 10_000;
        uint256 deployed = deployedAssets();
        if (deployed < target) {
            uint256 need = target - deployed;
            uint256 idle = idleAssets();
            uint256 move = need > idle ? idle : need;
            if (move > 0) {
                _enforceStrategyCap(move);
                IERC20(asset()).forceApprove(address(strategy), move);
                strategy.deposit(move);
            }
        } else if (deployed > target) {
            strategy.withdraw(deployed - target);
        }
        uint256 price = sharePrice();
        if (price > highWaterSharePrice) highWaterSharePrice = price;
        emit Rebalanced(idleAssets(), deployedAssets(), target);
    }

    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
