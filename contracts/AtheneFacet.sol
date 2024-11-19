// SPDX-License-Identifier: MIT
//   /$$$$$$    /$$     /$$                                           /$$   /$$             /$$                                       /$$
//  /$$__  $$  | $$    | $$                                          | $$$ | $$            | $$                                      | $$
// | $$  \ $$ /$$$$$$  | $$$$$$$   /$$$$$$  /$$$$$$$   /$$$$$$       | $$$$| $$  /$$$$$$  /$$$$$$   /$$  /$$  /$$  /$$$$$$   /$$$$$$ | $$   /$$
// | $$$$$$$$|_  $$_/  | $$__  $$ /$$__  $$| $$__  $$ /$$__  $$      | $$ $$ $$ /$$__  $$|_  $$_/  | $$ | $$ | $$ /$$__  $$ /$$__  $$| $$  /$$/
// | $$__  $$  | $$    | $$  \ $$| $$$$$$$$| $$  \ $$| $$$$$$$$      | $$  $$$$| $$$$$$$$  | $$    | $$ | $$ | $$| $$  \ $$| $$  \__/| $$$$$$/
// | $$  | $$  | $$ /$$| $$  | $$| $$_____/| $$  | $$| $$_____/      | $$\  $$$| $$_____/  | $$ /$$| $$ | $$ | $$| $$  | $$| $$      | $$_  $$
// | $$  | $$  |  $$$$/| $$  | $$|  $$$$$$$| $$  | $$|  $$$$$$$      | $$ \  $$|  $$$$$$$  |  $$$$/|  $$$$$/$$$$/|  $$$$$$/| $$      | $$ \  $$
// |__/  |__/   \___/  |__/  |__/ \_______/|__/  |__/ \_______/      |__/  \__/ \_______/   \___/   \_____/\___/  \______/ |__/      |__/  \__/
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {AtheneToken} from "contracts/AtheneToken.sol";
import {AtheneBase, AthenePoolInfo, AthenePoolConfig, FEE_DENOMINATOR} from "contracts/libraries/LibAtheneAppStorage.sol";
import {LibAthene} from "contracts/libraries/LibAthene.sol";
import {IUniswapV2Factory} from "contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "contracts/interfaces/IUniswapV2Router02.sol";

contract AtheneFacet is AtheneBase, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using MerkleProof for bytes32[];

    struct CreatePoolParams {
        string name;
        string symbol;
        string poolDetails;
        uint256 configIndex;
        address router;
        uint256 startTime;
        uint256 buyFeeRate;
        uint256 sellFeeRate;
        uint256 maxBuyAmount;
        uint256 delayBuyTime;
        bytes32 merkleRoot;
        uint256 initialBuyAmount;
    }

    event TokenCreated(
        address indexed token,
        address indexed user,
        uint256 baseReserve,
        uint256 quoteReserve,
        uint256 timestamp
    );
    event Trade(
        address indexed token,
        address indexed user,
        uint256 amountIn,
        uint256 amountOut,
        bool isBuy,
        uint256 baseReserve,
        uint256 quoteReserve,
        uint256 timestamp
    );
    event ReadyToList(address indexed token, uint256 timestamp);
    event Finalize(address indexed token, address pair, uint256 timestamp);

    function createPool(
        CreatePoolParams memory params
    ) external payable notPaused {
        require(s.routers.contains(params.router), "AtheneFacet: Invalid router");

        AthenePoolConfig memory config = s.poolConfigMapping[params.configIndex];
        require(
            config.initialVirtualBaseReserve > 0,
            "AtheneFacet: Invalid config"
        );
        require(
            params.buyFeeRate <= FEE_DENOMINATOR &&
                params.sellFeeRate <= FEE_DENOMINATOR,
            "AtheneFacet: Invalid fee rate"
        );

        AtheneToken token = new AtheneToken(
            params.name,
            params.symbol,
            address(this)
        );

        s.poolInfoMapping[address(token)] = AthenePoolInfo({
            id: s.tokens.length(),
            owner: msg.sender,
            token: address(token),
            router: params.router,
            poolDetails: params.poolDetails,
            state: 0,
            virtualBaseReserve: config.initialVirtualBaseReserve,
            virtualQuoteReserve: config.initialVirtualQuoteReserve,
            minBaseReserve: config.initialVirtualBaseReserve -
                config.totalSellingBaseAmount,
            minQuoteReserve: config.initialVirtualQuoteReserve,
            maxListingBaseAmount: config.maxListingBaseAmount,
            maxListingQuoteAmount: config.maxListingQuoteAmount,
            defaultListingRate: config.defaultListingRate,
            listingFee: config.listingFee,
            startTime: params.startTime,
            listedAt: 0,
            buyFeeRate: params.buyFeeRate,
            sellFeeRate: params.sellFeeRate,
            maxBuyAmount: params.maxBuyAmount,
            delayBuyTime: params.delayBuyTime,
            whitelistMerkleRoot: params.merkleRoot
        });

        s.tokens.add(address(token));

        emit TokenCreated(
            address(token),
            msg.sender,
            config.initialVirtualBaseReserve,
            config.initialVirtualQuoteReserve,
            block.timestamp
        );

        if (params.initialBuyAmount > 0) {
            (, uint256 minAmountOut, , , ) = getAmountOut(
                address(token),
                params.initialBuyAmount,
                true
            );
            _buy(
                address(token),
                address(0),
                params.initialBuyAmount,
                minAmountOut,
                new bytes32[](0),
                true
            );
        }
    }

    function buy(
        address token,
        address referrer,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes32[] memory proof
    ) external payable notPaused nonReentrant {
        _buy(token, referrer, amountIn, minAmountOut, proof, false);
    }

    function _buy(
        address token,
        address referrer,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes32[] memory proof,
        bool isInitial
    ) internal {
        AthenePoolInfo storage poolInfo = s.poolInfoMapping[token];
        require(poolInfo.token != address(0), "AtheneFacet: Invalid pool");
        if (!isInitial) {
            require(
                block.timestamp >= poolInfo.startTime,
                "AtheneFacet: Not started"
            );
            require(
                poolInfo.maxBuyAmount == 0 || amountIn <= poolInfo.maxBuyAmount,
                "AtheneFacet: Exceeded max buy"
            );
            if (poolInfo.whitelistMerkleRoot != 0) {
                require(
                    proof.verify(
                        poolInfo.whitelistMerkleRoot,
                        keccak256(abi.encodePacked(msg.sender))
                    ),
                    "AtheneFacet: Not in whitelist"
                );
            }
        }
        require(
            poolInfo.state == 0 && poolInfo.listedAt == 0,
            "AtheneFacet: Invalid state"
        );
        require(
            poolInfo.virtualBaseReserve > poolInfo.minBaseReserve,
            "AtheneFacet: Insufficient liquidity"
        );

        if (poolInfo.delayBuyTime > 0) {
            require(
                s.userLastBuyAt[poolInfo.token][msg.sender] +
                    poolInfo.delayBuyTime <=
                    block.timestamp,
                "AtheneFacet: Buy on cooldown"
            );
        }
        s.userLastBuyAt[poolInfo.token][msg.sender] = block.timestamp;

        (
            uint256 amountOut,
            ,
            uint256 totalFee,
            uint256 platformFee,
            uint256 tradeFee
        ) = _getAmountOutWithPoolInfo(poolInfo, amountIn, true);
        require(
            amountIn + totalFee == msg.value,
            "AtheneFacet: Invalid input amount"
        );

        require(
            amountOut >= minAmountOut,
            "AtheneFacet: Insufficient output amount"
        );

        _takeFee(platformFee, tradeFee, poolInfo.owner, referrer);

        poolInfo.virtualQuoteReserve += amountIn;
        poolInfo.virtualBaseReserve -= amountOut;

        require(
            poolInfo.virtualBaseReserve >= poolInfo.minBaseReserve,
            "AtheneFacet: Invalid base reserve calculation"
        );

        LibAthene.safeTransfer(poolInfo.token, msg.sender, amountOut);
        require(
            LibAthene.getPoolTokenBalance(poolInfo.token) >=
                poolInfo.maxListingBaseAmount,
            "AtheneFacet: Invalid remaining base tokens"
        );

        emit Trade(
            poolInfo.token,
            msg.sender,
            amountIn,
            amountOut,
            true,
            poolInfo.virtualBaseReserve,
            poolInfo.virtualQuoteReserve,
            block.timestamp
        );

        if (poolInfo.virtualBaseReserve == poolInfo.minBaseReserve) {
            emit ReadyToList(poolInfo.token, block.timestamp);
        }
    }

    function sell(
        address token,
        address referrer,
        uint256 amountIn,
        uint256 minAmountOut
    ) external notPaused nonReentrant {
        AthenePoolInfo storage poolInfo = s.poolInfoMapping[token];
        require(poolInfo.token != address(0), "AtheneFacet: INVALID_POOL");
        require(
            block.timestamp >= poolInfo.startTime,
            "AtheneFacet: Not started"
        );
        if (poolInfo.state == 0) {
            require(
                poolInfo.virtualBaseReserve > poolInfo.minBaseReserve &&
                    poolInfo.listedAt == 0,
                "AtheneFacet: Insufficient liquidity"
            );
        }

        (
            uint256 amountOut,
            uint256 actualAmountOut,
            ,
            uint256 platformFee,
            uint256 tradeFee
        ) = _getAmountOutWithPoolInfo(poolInfo, amountIn, false);

        require(
            actualAmountOut >= minAmountOut,
            "AtheneFacet: Insufficient output amount"
        );

        _takeFee(platformFee, tradeFee, poolInfo.owner, referrer);

        poolInfo.virtualBaseReserve += amountIn;
        poolInfo.virtualQuoteReserve -= amountOut;

        require(
            poolInfo.virtualQuoteReserve >= poolInfo.minQuoteReserve,
            "AtheneFacet: Invalid quote reserve calculation"
        );

        LibAthene.safeTransferFrom(
            poolInfo.token,
            msg.sender,
            address(this),
            amountIn
        );
        payable(msg.sender).transfer(actualAmountOut);

        emit Trade(
            poolInfo.token,
            msg.sender,
            amountIn,
            actualAmountOut,
            false,
            poolInfo.virtualBaseReserve,
            poolInfo.virtualQuoteReserve,
            block.timestamp
        );
    }

    function addLiquidity(address token) external notPaused {
        AthenePoolInfo storage poolInfo = s.poolInfoMapping[token];
        require(
            poolInfo.listedAt == 0 &&
                poolInfo.state == 0 &&
                poolInfo.virtualBaseReserve == poolInfo.minBaseReserve,
            "AtheneFacet: Invalid state"
        );
        poolInfo.listedAt = block.timestamp;

        uint256 totalQuoteAllocation = poolInfo.virtualQuoteReserve -
            poolInfo.minQuoteReserve;
        uint256 currentGlobalBalance = address(this).balance;

        payable(s.masterConfig.feeReceiver).transfer(poolInfo.listingFee);

        (
            uint256 rate,
            uint256 listingBaseAmount,
            uint256 listingQuoteAmount
        ) = _calculateReserveRatesAndLiquidity(poolInfo);

        LibAthene.safeApprove(
            poolInfo.token,
            poolInfo.router,
            poolInfo.maxListingBaseAmount
        );
        IUniswapV2Router02 router = IUniswapV2Router02(poolInfo.router);
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        address pairAddress = factory.getPair(
            poolInfo.token,
            s.masterConfig.wethAddress
        );
        if (pairAddress == address(0)) {
            pairAddress = factory.createPair(
                poolInfo.token,
                s.masterConfig.wethAddress
            );
        }

        _addLiquidityWithRate(
            s.masterConfig.feeReceiver,
            s.masterConfig.wethAddress,
            poolInfo,
            router,
            pairAddress,
            rate,
            listingBaseAmount,
            listingQuoteAmount
        );

        uint256 remainingTokens = LibAthene.getPoolTokenBalance(poolInfo.token);
        if (remainingTokens > 0) {
            LibAthene.burn(poolInfo.token, remainingTokens);
        }

        require(
            currentGlobalBalance - address(this).balance <=
                totalQuoteAllocation,
            "AtheneFacet: Inconsistent balance"
        );

        emit Finalize(poolInfo.token, pairAddress, block.timestamp);
    }

    function _calculateReserveRatesAndLiquidity(
        AthenePoolInfo memory poolInfo
    )
        internal
        pure
        returns (
            uint256 reserveRate,
            uint256 listingBaseAmount,
            uint256 listingQuoteAmount
        )
    {
        listingQuoteAmount =
            poolInfo.virtualQuoteReserve -
            poolInfo.minQuoteReserve -
            poolInfo.listingFee;
        listingBaseAmount = poolInfo.maxListingBaseAmount;

        reserveRate = LibAthene.calculateRate(
            listingBaseAmount,
            listingQuoteAmount
        );
    }

    function _addLiquidityWithRate(
        address feeReceiver,
        address wethAddress,
        AthenePoolInfo storage poolInfo,
        IUniswapV2Router02 router,
        address pairAddress,
        uint256 rate,
        uint256 listingBaseAmount,
        uint256 listingQuoteAmount
    ) internal {
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        pair.skim(feeReceiver);

        (uint256 quoteReserve, uint256 baseReserve) = LibAthene.getReserves(
            pair,
            wethAddress
        );

        if (quoteReserve == 0 && baseReserve == 0) {
            // Only pair has been created, no liquidity
            // Do nothing, we can use the original liquidity amounts
            router.addLiquidityETH{value: listingQuoteAmount}(
                poolInfo.token,
                listingBaseAmount,
                listingBaseAmount,
                listingQuoteAmount,
                address(0),
                block.timestamp
            );
        } else if (quoteReserve > 0 && baseReserve == 0) {
            // Someone sent some WETH into pair
            // 2 cases there:
            // - The WETH in the pair is less than or equal to the WETH listing amount:
            //   In this case we calculate how many additional tokens we need to send into the pair,
            //   Then add liquidity with both values subtracting the existing liquidity
            // - The WETH in the pair is more than the WETH listing amount:
            //   In this case just send all the listing tokens into the pair, and not add liquidity
            _addLiquidityHasQuoteReserve(
                wethAddress,
                poolInfo.token,
                router,
                pair,
                rate,
                quoteReserve,
                listingBaseAmount,
                listingQuoteAmount
            );
        } else if (quoteReserve == 0 && baseReserve > 0) {
            // Someone sent some tokens into pair
            // 2 cases there:
            // - The tokens in the pair are less than or equal to the token listing amount:
            //   In this case we calculate how many additional WETH we need to send into the pair,
            //   Then add liquidity with both values subtracting the existing liquidity
            // - The tokens in the pair is more than the token listing amount:
            //   In this case just send all the listing WETH into the pair, and not add liquidity
            _addLiquidityHasBaseReserve(
                wethAddress,
                poolInfo.token,
                router,
                pair,
                rate,
                baseReserve,
                listingBaseAmount,
                listingQuoteAmount
            );
        } else if (quoteReserve > 0 && baseReserve > 0) {
            // Pair already has liquidity
            _addLiquidityHasBothReserves(
                wethAddress,
                poolInfo.token,
                router,
                pair,
                rate,
                baseReserve,
                quoteReserve,
                listingBaseAmount,
                listingQuoteAmount
            );
        }
    }

    function _addLiquidityHasQuoteReserve(
        address wethAddress,
        address token,
        IUniswapV2Router02 router,
        IUniswapV2Pair pair,
        uint256 rate,
        uint256 quoteReserve,
        uint256 listingBaseAmount,
        uint256 listingQuoteAmount
    ) internal {
        uint256 additionalTokens = LibAthene.convertCurrencyToToken(
            quoteReserve,
            rate
        );

        uint256 minBaseAmount = listingBaseAmount;
        uint256 minQuoteAmount = listingQuoteAmount;

        if (additionalTokens == 0) {
            additionalTokens = 1e18;
            uint256 additionalWeth = LibAthene.convertTokenToCurrency(
                additionalTokens,
                rate
            );
            LibAthene.safeDepositAndTransfer(
                wethAddress,
                address(pair),
                additionalWeth - quoteReserve
            );
            LibAthene.safeTransfer(token, address(pair), additionalTokens);
            pair.sync();

            listingBaseAmount = listingBaseAmount - additionalTokens;
            listingQuoteAmount = listingQuoteAmount - additionalWeth;

            // Since uniswap perform quote on tokenB which is ETH, we need to do the same
            minBaseAmount = listingBaseAmount;
            minQuoteAmount = router.quote(
                listingBaseAmount,
                additionalTokens,
                additionalWeth
            );
            if (minQuoteAmount > listingQuoteAmount) {
                minQuoteAmount = listingQuoteAmount;
                minBaseAmount = router.quote(
                    listingQuoteAmount,
                    additionalWeth,
                    additionalTokens
                );
            }
        } else {
            require(
                additionalTokens < listingBaseAmount,
                "AtheneFacet: Invalid reserves"
            );
            LibAthene.safeTransfer(token, address(pair), additionalTokens);
            pair.sync();

            listingBaseAmount = listingBaseAmount - additionalTokens;
            listingQuoteAmount = listingQuoteAmount - quoteReserve;

            // Since uniswap perform quote on tokenB which is ETH, we need to do the same
            minBaseAmount = listingBaseAmount;
            minQuoteAmount = router.quote(
                listingBaseAmount,
                additionalTokens,
                quoteReserve
            );

            if (minQuoteAmount > listingQuoteAmount) {
                minQuoteAmount = listingQuoteAmount;
                minBaseAmount = router.quote(
                    listingQuoteAmount,
                    quoteReserve,
                    additionalTokens
                );
            }
        }

        if (minBaseAmount > listingBaseAmount) {
            minBaseAmount = listingBaseAmount;
        }
        if (minQuoteAmount > listingQuoteAmount) {
            minQuoteAmount = listingQuoteAmount;
        }

        router.addLiquidityETH{value: listingQuoteAmount}(
            token,
            listingBaseAmount,
            minBaseAmount,
            minQuoteAmount,
            address(0),
            block.timestamp
        );
    }

    function _addLiquidityHasBaseReserve(
        address wethAddress,
        address token,
        IUniswapV2Router02 router,
        IUniswapV2Pair pair,
        uint256 rate,
        uint256 baseReserve,
        uint256 listingBaseAmount,
        uint256 listingQuoteAmount
    ) internal {
        uint256 additionalWeth = LibAthene.convertTokenToCurrency(
            baseReserve,
            rate
        );

        uint256 minBaseAmount = listingBaseAmount;
        uint256 minQuoteAmount = listingQuoteAmount;

        if (additionalWeth == 0) {
            additionalWeth = 1;
            uint256 additionalTokens = LibAthene.convertCurrencyToToken(
                additionalWeth,
                rate
            );
            LibAthene.safeDepositAndTransfer(
                wethAddress,
                address(pair),
                additionalWeth
            );
            LibAthene.safeTransfer(
                token,
                address(pair),
                additionalTokens - baseReserve
            );
            pair.sync();

            listingBaseAmount = listingBaseAmount - additionalTokens;
            listingQuoteAmount = listingQuoteAmount - additionalWeth;

            minBaseAmount = listingBaseAmount;
            minQuoteAmount = router.quote(
                listingBaseAmount,
                additionalTokens,
                additionalWeth
            );

            if (minQuoteAmount > listingQuoteAmount) {
                minBaseAmount = router.quote(
                    listingQuoteAmount,
                    additionalWeth,
                    additionalTokens
                );
                minQuoteAmount = listingQuoteAmount;
            }
        } else {
            require(
                additionalWeth < listingQuoteAmount,
                "AtheneFacet: Invalid reserves"
            );

            LibAthene.safeDepositAndTransfer(
                wethAddress,
                address(pair),
                additionalWeth
            );
            pair.sync();

            listingBaseAmount = listingBaseAmount - baseReserve;
            listingQuoteAmount = listingQuoteAmount - additionalWeth;

            minBaseAmount = listingBaseAmount;
            minQuoteAmount = router.quote(
                listingBaseAmount,
                baseReserve,
                additionalWeth
            );

            if (minQuoteAmount > listingQuoteAmount) {
                minBaseAmount = router.quote(
                    listingQuoteAmount,
                    additionalWeth,
                    baseReserve
                );
                minQuoteAmount = listingQuoteAmount;
            }
        }

        if (minBaseAmount > listingBaseAmount) {
            minBaseAmount = listingBaseAmount;
        }
        if (minQuoteAmount > listingQuoteAmount) {
            minQuoteAmount = listingQuoteAmount;
        }

        router.addLiquidityETH{value: listingQuoteAmount}(
            token,
            listingBaseAmount,
            minBaseAmount,
            minQuoteAmount,
            address(0),
            block.timestamp
        );
    }

    function _addLiquidityHasBothReserves(
        address wethAddress,
        address token,
        IUniswapV2Router02 router,
        IUniswapV2Pair pair,
        uint256 rate,
        uint256 baseReserve,
        uint256 quoteReserve,
        uint256 listingBaseAmount,
        uint256 listingQuoteAmount
    ) internal {
        require(
            baseReserve < listingBaseAmount &&
                quoteReserve < listingQuoteAmount,
            "AtheneFacet: Invalid reserves"
        );

        uint256 additionalWeth = LibAthene.convertTokenToCurrency(
            baseReserve,
            rate
        );

        uint256 minBaseAmount = listingBaseAmount;
        uint256 minQuoteAmount = listingQuoteAmount;

        // We only process if the calculated WETH is 1/10 of the original listing WETH
        if (
            additionalWeth > quoteReserve &&
            additionalWeth <= listingQuoteAmount / 100
        ) {
            LibAthene.safeDepositAndTransfer(
                wethAddress,
                address(pair),
                additionalWeth - quoteReserve
            );
            pair.sync();

            listingBaseAmount = listingBaseAmount - baseReserve;
            listingQuoteAmount =
                listingQuoteAmount -
                (additionalWeth - quoteReserve);

            minBaseAmount = listingBaseAmount;
            minQuoteAmount = router.quote(
                listingBaseAmount,
                baseReserve,
                additionalWeth
            );

            if (minQuoteAmount > listingQuoteAmount) {
                minBaseAmount = router.quote(
                    listingQuoteAmount,
                    additionalWeth,
                    baseReserve
                );
                minQuoteAmount = listingQuoteAmount;
            }
        } else {
            uint256 additionalTokens = LibAthene.convertCurrencyToToken(
                quoteReserve,
                rate
            );

            require(
                additionalTokens < listingBaseAmount &&
                    additionalTokens > baseReserve,
                "AtheneFacet: Invalid reserves"
            );
            LibAthene.safeTransfer(
                token,
                address(pair),
                additionalTokens - baseReserve
            );
            pair.sync();

            listingBaseAmount =
                listingBaseAmount -
                (additionalTokens - baseReserve);
            listingQuoteAmount = listingQuoteAmount - quoteReserve;

            minBaseAmount = listingBaseAmount;
            minQuoteAmount = router.quote(
                listingBaseAmount,
                additionalTokens,
                quoteReserve
            );

            if (minQuoteAmount > listingQuoteAmount) {
                minBaseAmount = router.quote(
                    listingQuoteAmount,
                    quoteReserve,
                    additionalTokens
                );
                minQuoteAmount = listingQuoteAmount;
            }
        }

        if (minBaseAmount > listingBaseAmount) {
            minBaseAmount = listingBaseAmount;
        }
        if (minQuoteAmount > listingQuoteAmount) {
            minQuoteAmount = listingQuoteAmount;
        }

        router.addLiquidityETH{value: listingQuoteAmount}(
            token,
            listingBaseAmount,
            minBaseAmount,
            minQuoteAmount,
            address(0),
            block.timestamp
        );
    }

    function getAmountOut(
        address token,
        uint256 amountIn,
        bool isBuy
    )
        public
        view
        returns (
            uint256 amountOut,
            uint256 amountOutLessFee,
            uint256 totalFee,
            uint256 platformFee,
            uint256 tradeFee
        )
    {
        AthenePoolInfo memory poolInfo = s.poolInfoMapping[token];
        require(poolInfo.token != address(0), "AtheneFacet: Invalid pool");
        return _getAmountOutWithPoolInfo(poolInfo, amountIn, isBuy);
    }

    // function getAmountIn(address token, uint256 amountOut)
    //     public
    //     view
    //     returns (uint256)
    // {
    //     AthenePoolInfo memory poolInfo = s.poolInfoMapping[token];
    //     require(poolInfo.token != address(0), "AtheneFacet: Invalid pool");
    //     uint256 amountIn = LibAthene.getAmountIn(
    //         amountOut,
    //         poolInfo.virtualQuoteReserve,
    //         poolInfo.virtualBaseReserve
    //     );
    //     uint256 remaining = poolInfo.virtualQuoteReserve -
    //         poolInfo.minQuoteReserve;
    //     if (amountIn > remaining) {
    //         amountIn = remaining;
    //     }
    //     return amountIn;
    // }

    function _takeFee(
        uint256 platformFee,
        uint256 tradeFee,
        address owner,
        address referrer
    ) internal {
        uint256 referrerFee = 0;
        if (referrer != address(0)) {
            referrerFee =
                (platformFee * s.masterConfig.refBps) /
                FEE_DENOMINATOR;
            payable(referrer).transfer(referrerFee);
        }
        payable(s.masterConfig.feeReceiver).transfer(platformFee - referrerFee);

        if (tradeFee > 0) {
            payable(owner).transfer(tradeFee);
        }
    }

    function _getAmountOutWithPoolInfo(
        AthenePoolInfo memory poolInfo,
        uint256 amountIn,
        bool isBuy
    )
        internal
        view
        returns (
            uint256 amountOut,
            uint256 amountOutLessFee,
            uint256 totalFee,
            uint256 platformFee,
            uint256 tradeFee
        )
    {
        if (isBuy) {
            platformFee = (amountIn * s.masterConfig.feeBps) / FEE_DENOMINATOR;
            tradeFee = (amountIn * poolInfo.buyFeeRate) / FEE_DENOMINATOR;
            totalFee = platformFee + tradeFee;
        }
        amountOut = LibAthene.getAmountOut(
            amountIn,
            isBuy ? poolInfo.virtualQuoteReserve : poolInfo.virtualBaseReserve,
            isBuy ? poolInfo.virtualBaseReserve : poolInfo.virtualQuoteReserve
        );
        uint256 remaining = 0;
        if (isBuy) {
            remaining = poolInfo.virtualBaseReserve - poolInfo.minBaseReserve;
        } else {
            remaining = poolInfo.virtualQuoteReserve - poolInfo.minQuoteReserve;
        }
        if (amountOut > remaining) {
            amountOut = remaining;
        }
        amountOutLessFee = amountOut;
        if (!isBuy) {
            platformFee = (amountOut * s.masterConfig.feeBps) / FEE_DENOMINATOR;
            tradeFee =
                ((amountOut - platformFee) * poolInfo.sellFeeRate) /
                FEE_DENOMINATOR;
            totalFee = platformFee + tradeFee;
            amountOutLessFee = amountOut - totalFee;
        }
    }
}




