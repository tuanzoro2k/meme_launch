// SPDX-License-Identifier: MIT
//   /$$$$$$    /$$     /$$                                           /$$   /$$             /$$                                       /$$
//  /$$__  $$  | $$    | $$                                          | $$$ | $$            | $$                                      | $$
// | $$  \ $$ /$$$$$$  | $$$$$$$   /$$$$$$  /$$$$$$$   /$$$$$$       | $$$$| $$  /$$$$$$  /$$$$$$   /$$  /$$  /$$  /$$$$$$   /$$$$$$ | $$   /$$
// | $$$$$$$$|_  $$_/  | $$__  $$ /$$__  $$| $$__  $$ /$$__  $$      | $$ $$ $$ /$$__  $$|_  $$_/  | $$ | $$ | $$ /$$__  $$ /$$__  $$| $$  /$$/
// | $$__  $$  | $$    | $$  \ $$| $$$$$$$$| $$  \ $$| $$$$$$$$      | $$  $$$$| $$$$$$$$  | $$    | $$ | $$ | $$| $$  \ $$| $$  \__/| $$$$$$/
// | $$  | $$  | $$ /$$| $$  | $$| $$_____/| $$  | $$| $$_____/      | $$\  $$$| $$_____/  | $$ /$$| $$ | $$ | $$| $$  | $$| $$      | $$_  $$
// | $$  | $$  |  $$$$/| $$  | $$|  $$$$$$$| $$  | $$|  $$$$$$$      | $$ \  $$|  $$$$$$$  |  $$$$/|  $$$$$/$$$$/|  $$$$$$/| $$      | $$ \  $$
// |__/  |__/   \___/  |__/  |__/ \_______/|__/  |__/ \_______/      |__/  \__/ \_______/   \___/   \_____/\___/  \______/ |__/      |__/  \__/
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV2Pair } from "contracts/interfaces/IUniswapV2Pair.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { LibAtheneAppStorage, AtheneAppStorage } from "contracts/libraries/LibAtheneAppStorage.sol";

library LibAthene {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    function setAdmin(address newAdmin) internal {
        AtheneAppStorage storage ds = LibAtheneAppStorage.diamondStorage();
        address previousAdmin = ds.masterConfig.admin;
        ds.masterConfig.admin = newAdmin;
        emit OwnershipTransferred(previousAdmin, newAdmin);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "Athene: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "Athene: INSUFFICIENT_LIQUIDITY"
        );
        amountOut = (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "Athene: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "Athene: INSUFFICIENT_LIQUIDITY"
        );
        amountIn = ((reserveIn * amountOut) / (reserveOut - amountOut)) + 1;
    }

    function getPoolTokenBalance(address token)
        internal
        view
        returns (uint256)
    {
        return IERC20(token).balanceOf(address(this));
    }

    function getReserves(IUniswapV2Pair pair, address currency)
        internal
        view
        returns (uint112 quoteReserve, uint112 baseReserve)
    {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        (quoteReserve, baseReserve) = currency == pair.token0()
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    function safeApprove(
        address token,
        address spender,
        uint256 amount
    ) internal {
        IERC20(token).safeApprove(spender, 0);
        IERC20(token).safeApprove(spender, amount);
    }

    function safeTransfer(
        address token,
        address to,
        uint256 amount
    ) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    function safeDepositAndTransfer(
        address weth,
        address to,
        uint256 amount
    ) internal {
        IWETH(weth).deposit{ value: amount }();
        safeTransfer(weth, to, amount);
    }

    function burn(address token, uint256 amount) internal {
        IERC20(token).safeTransfer(address(0xdead), amount);
    }

    function calculateRate(uint256 baseAmount, uint256 quoteAmount)
        internal
        pure
        returns (uint256)
    {
        return (baseAmount * 1e18) / quoteAmount;
    }

    function convertCurrencyToToken(uint256 amount, uint256 rate)
        internal
        pure
        returns (uint256)
    {
        return (amount * rate) / 1e18;
    }

    function convertTokenToCurrency(uint256 amount, uint256 rate)
        internal
        pure
        returns (uint256)
    {
        return (amount * 1e18) / rate;
    }
}
