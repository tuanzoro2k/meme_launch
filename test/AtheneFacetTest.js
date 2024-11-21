
const { expect } = require("chai");
const { ethers } = require("hardhat")
const { getSelectors, FacetCutAction } = require('../scripts/libraries/diamond.js')
const helpers = require("@nomicfoundation/hardhat-network-helpers");


describe("Athene Facet", () => {
    let atheneDiamond;
    let owner;
    let operator1;
    let operator2;
    let router1;
    let router2;
    let configIndex, startTime, buyFeeRate, sellFeeRate, maxBuyAmount, delayBuyTime, initialBuyAmount;
    const FEE_DENOMINATOR = 1e4;
    let atheneFacet
    let managerFacet
    let baseTokenAddress
    before(async function () {
        [owner, operator1, operator2, router1, router2] = await ethers.getSigners();
        const DiamondInit = await ethers.getContractFactory('DiamondInit')
        const diamondInit = await DiamondInit.deploy()
        await diamondInit.deployed()

        // Deploy facets and set the `facetCuts` variable
        const FacetNames = [
            'AtheneFacet',
            'ManagerFacet',
        ]
        // The `facetCuts` variable is the FacetCut[] that contains the functions to add during diamond deployment
        const facetCuts = []
        for (const FacetName of FacetNames) {
            const Facet = await ethers.getContractFactory(FacetName)
            const facet = await Facet.deploy()
            await facet.deployed()
            console.log(`${FacetName} deployed: ${facet.address}`)
            facetCuts.push({
                facetAddress: facet.address,
                action: FacetCutAction.Add,
                functionSelectors: getSelectors(facet)
            })
        }

        // Creating a function call
        // This call gets executed during deployment and can also be executed in upgrades
        // It is executed with delegatecall on the DiamondInit address.
        let functionCall = diamondInit.interface.encodeFunctionData('init')

        // Setting arguments that will be used in the diamond constructor
        const diamondArgs = {
            owner: owner.address,
            init: diamondInit.address,
            initCalldata: functionCall
        }

        // Deploy AtheneDiamond contract
        const AtheneDiamond = await ethers.getContractFactory("AtheneDiamond");
        atheneDiamond = await AtheneDiamond.deploy(
            facetCuts,
            diamondArgs
        );
        await atheneDiamond.deployed()

        // Set up initial values
        configIndex = 0;
        startTime = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
        buyFeeRate = 100; // 1%
        sellFeeRate = 200; // 2%
        maxBuyAmount = ethers.utils.parseEther("1000");
        delayBuyTime = 0; // 1 hour
        initialBuyAmount = ethers.utils.parseEther("100");

        atheneFacet = await ethers.getContractAt('AtheneFacet', atheneDiamond.address)
        managerFacet = await ethers.getContractAt('ManagerFacet', atheneDiamond.address)
        const wethAddress = "0xa084b43e09c74E401b7500c3D30a1B569e4934AD"
        const feeReceiver = "0xa084b43e09c74E401b7500c3D30a1B569e4934AD"
        const feeBps = 50
        const refBps = 50
        const tx = await managerFacet.setMasterConfig(wethAddress, feeReceiver, feeBps, refBps)
        await tx.wait()

        await managerFacet.setPoolConfig(configIndex, {
            index: configIndex,
            initialVirtualBaseReserve: ethers.utils.parseEther("1000"),
            initialVirtualQuoteReserve: ethers.utils.parseEther("1000"),
            totalSellingBaseAmount: ethers.utils.parseEther("500"),
            maxListingBaseAmount: ethers.utils.parseEther("500"),
            maxListingQuoteAmount: ethers.utils.parseEther("500"),
            defaultListingRate: 10000,
            listingFee: ethers.utils.parseEther("10"),
        });

        await managerFacet.setWhitelistedRouters([router1.address, router2.address], true);

        const tx2 = await atheneFacet.createPool({
            name: "Test Buy Token",
            symbol: "TEST",
            poolDetails: "This is a test pool",
            configIndex: configIndex,
            router: router1.address,
            startTime: startTime,
            buyFeeRate: buyFeeRate,
            sellFeeRate: sellFeeRate,
            maxBuyAmount: maxBuyAmount,
            delayBuyTime: delayBuyTime,
            merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
            initialBuyAmount: 0,
        });
        const receipt = await tx2.wait();
        // Extract the TokenCreated event from the logs
        const tokenCreatedEvent = receipt.events.find(event => event.event === "TokenCreated");

        baseTokenAddress = tokenCreatedEvent.args.token;
    });

    it("should create a new pool successfully without initialBuy", async function () {

        const tx = await atheneFacet.createPool({
            name: "Test Token",
            symbol: "TEST",
            poolDetails: "This is a test pool",
            configIndex: configIndex,
            router: router1.address,
            startTime: startTime,
            buyFeeRate: buyFeeRate,
            sellFeeRate: sellFeeRate,
            maxBuyAmount: maxBuyAmount,
            delayBuyTime: delayBuyTime,
            merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
            initialBuyAmount: 0,
        });

        const receipt = await tx.wait();
        // Extract the TokenCreated event from the logs
        const tokenCreatedEvent = receipt.events.find(event => event.event === "TokenCreated");
        expect(tokenCreatedEvent).to.not.be.undefined;

        const tokenAddress = tokenCreatedEvent.args.token;
        // Check if the token was created
        const token = await ethers.getContractAt('AtheneToken', tokenAddress);
        expect(await token.name()).to.equal("Test Token");
        expect(await token.symbol()).to.equal("TEST");

        // Check pool info
        const poolInfo = await managerFacet.getPoolInfo(tokenAddress);
        expect(poolInfo.owner).to.equal(owner.address);
        expect(poolInfo.token).to.equal(tokenAddress);
        expect(poolInfo.router).to.equal(router1.address);
        expect(poolInfo.poolDetails).to.equal("This is a test pool");
        expect(poolInfo.state).to.equal(0);
        expect(poolInfo.startTime).to.equal(startTime);
        expect(poolInfo.buyFeeRate).to.equal(buyFeeRate);
        expect(poolInfo.sellFeeRate).to.equal(sellFeeRate);
        expect(poolInfo.maxBuyAmount).to.equal(maxBuyAmount);
        expect(poolInfo.delayBuyTime).to.equal(delayBuyTime);
        expect(poolInfo.whitelistMerkleRoot).to.equal('0x0000000000000000000000000000000000000000000000000000000000000000');
    });

    it("should create a new pool successfully with initialBuy", async function () {
        const initialBuy = ethers.utils.parseEther('0.1');

        const masterConfig = await managerFacet.getMasterConfig()
        const totalFee = (initialBuy * masterConfig.feeBps) / FEE_DENOMINATOR + (initialBuy * buyFeeRate) / FEE_DENOMINATOR;
        const tx = await atheneFacet.createPool({
            name: "Test Token",
            symbol: "TEST",
            poolDetails: "This is a test pool",
            configIndex: configIndex,
            router: router1.address,
            startTime: startTime,
            buyFeeRate: buyFeeRate,
            sellFeeRate: sellFeeRate,
            maxBuyAmount: maxBuyAmount,
            delayBuyTime: delayBuyTime,
            merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
            initialBuyAmount: initialBuy,
        }, { value: initialBuy.add(totalFee) });

        const receipt = await tx.wait();
        // Extract the TokenCreated event from the logs
        const tokenCreatedEvent = receipt.events.find(event => event.event === "TokenCreated");
        expect(tokenCreatedEvent).to.not.be.undefined;

        const tokenAddress = tokenCreatedEvent.args.token;

        // Check if the token was created
        const token = await ethers.getContractAt('AtheneToken', tokenAddress);
        expect(await token.name()).to.equal("Test Token");
        expect(await token.symbol()).to.equal("TEST");

        // Check pool info

        const poolInfo = await managerFacet.getPoolInfo(tokenAddress);
        expect(poolInfo.owner).to.equal(owner.address);
        expect(poolInfo.token).to.equal(tokenAddress);
        expect(poolInfo.router).to.equal(router1.address);
        expect(poolInfo.poolDetails).to.equal("This is a test pool");
        expect(poolInfo.state).to.equal(0);
        expect(poolInfo.startTime).to.equal(startTime);
        expect(poolInfo.buyFeeRate).to.equal(buyFeeRate);
        expect(poolInfo.sellFeeRate).to.equal(sellFeeRate);
        expect(poolInfo.maxBuyAmount).to.equal(maxBuyAmount);
        expect(poolInfo.delayBuyTime).to.equal(delayBuyTime);
        expect(poolInfo.whitelistMerkleRoot).to.equal('0x0000000000000000000000000000000000000000000000000000000000000000');

        expect(Number(await token.balanceOf(owner.address))).to.be.greaterThan(0)
    });

    it("should revert if the router is invalid", async function () {
        await expect(
            atheneFacet.createPool({
                name: "Test Token",
                symbol: "TEST",
                poolDetails: "This is a test pool",
                configIndex: configIndex,
                router: operator1.address, // Invalid router
                startTime: startTime,
                buyFeeRate: buyFeeRate,
                sellFeeRate: sellFeeRate,
                maxBuyAmount: maxBuyAmount,
                delayBuyTime: delayBuyTime,
                merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
                initialBuyAmount: 0,
            })
        ).to.be.revertedWith("AtheneFacet: Invalid router");
    });

    it("should revert if the config index is invalid", async function () {
        await expect(
            atheneFacet.createPool({
                name: "Test Token",
                symbol: "TEST",
                poolDetails: "This is a test pool",
                configIndex: 1, // Invalid config index
                router: router1.address,
                startTime: startTime,
                buyFeeRate: buyFeeRate,
                sellFeeRate: sellFeeRate,
                maxBuyAmount: maxBuyAmount,
                delayBuyTime: delayBuyTime,
                merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
                initialBuyAmount: 0,
            })
        ).to.be.revertedWith("AtheneFacet: Invalid config");
    });

    it("should revert if the fee rates are invalid", async function () {
        await expect(
            atheneFacet.createPool({
                name: "Test Token",
                symbol: "TEST",
                poolDetails: "This is a test pool",
                configIndex: configIndex,
                router: router1.address,
                startTime: startTime,
                buyFeeRate: FEE_DENOMINATOR + 1, // Invalid fee rate
                sellFeeRate: sellFeeRate,
                maxBuyAmount: maxBuyAmount,
                delayBuyTime: delayBuyTime,
                merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
                initialBuyAmount: 0,
            })
        ).to.be.revertedWith("AtheneFacet: Invalid fee rate");
    });

    it("should revert if the initial buy amount is wrong", async function () {
        await expect(
            atheneFacet.createPool({
                name: "Test Token",
                symbol: "TEST",
                poolDetails: "This is a test pool",
                configIndex: configIndex,
                router: router1.address,
                startTime: startTime,
                buyFeeRate: buyFeeRate,
                sellFeeRate: sellFeeRate,
                maxBuyAmount: maxBuyAmount,
                delayBuyTime: delayBuyTime,
                merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
                initialBuyAmount: ethers.utils.parseEther("1000000"),
            })
        ).to.be.revertedWith("AtheneFacet: Invalid input amount");
    });

    //Buy
    it("buy should revert if pool has not started", async function () {
        const buyer = operator1;
        const amountIn = ethers.utils.parseEther("0.1");
        const { amountOut } = await atheneFacet.getAmountOut(baseTokenAddress, amountIn, true);
        const minAmountOut = amountOut.mul(95).div(100);

        // Act & Assert
        await expect(
            atheneFacet.connect(buyer).buy(baseTokenAddress, owner.address, amountIn, minAmountOut, [])
        ).to.be.revertedWith("AtheneFacet: Not started");
    });

    it("buy token successsfully", async function () {

        const buyer = operator1;
        const amountIn = ethers.utils.parseEther("0.1");
        const { amountOut, totalFee } = await atheneFacet.getAmountOut(baseTokenAddress, amountIn, true);
        const minAmountOut = amountOut.mul(95).div(100);


        await helpers.time.increase(3600)

        const tx2 = await atheneFacet.connect(buyer).buy(baseTokenAddress, owner.address, amountIn, minAmountOut, [], { value: amountIn.add(totalFee) })
        const poolInfo = await managerFacet.getPoolInfo(baseTokenAddress);
        const receipt2 = await tx2.wait();

        const buyToken = receipt2.events.find(event => event.event === "Trade");

        expect(buyToken.args.token).to.equal(baseTokenAddress)
        expect(buyToken.args.user).to.equal(buyer.address)
        expect(buyToken.args.amountIn).to.equal(amountIn)
        expect(buyToken.args.isBuy).to.equal(true)
        expect(buyToken.args.baseReserve).to.equal(poolInfo.virtualBaseReserve)
        expect(buyToken.args.quoteReserve).to.equal(poolInfo.virtualQuoteReserve)
    });

    it("buy should revert if max buy amount exceeded", async function () {
        const buyer = operator1;
        const amountIn = ethers.utils.parseEther("2000"); // Exceeds maxBuyAmount
        const { amountOut } = await atheneFacet.getAmountOut(baseTokenAddress, amountIn, true);
        const minAmountOut = amountOut.mul(95).div(100);

        await expect(
            atheneFacet.connect(buyer).buy(baseTokenAddress, owner.address, amountIn, minAmountOut, [])
        ).to.be.revertedWith("AtheneFacet: Exceeded max buy");
    });

    it("buy should revert if the pool is not exist", async function () {
        const buyer = operator1;
        const amountIn = ethers.utils.parseEther("2000");
        const { amountOut } = await atheneFacet.getAmountOut(baseTokenAddress, amountIn, true);
        const minAmountOut = amountOut.mul(95).div(100);

        await expect(
            atheneFacet.connect(buyer).buy(operator1.address, owner.address, amountIn, minAmountOut, []) //Invalid pool
        ).to.be.revertedWith("AtheneFacet: Invalid pool");
    })

    it("buy should revert if the state is invalid", async function () {
        const tx = await atheneFacet.createPool({
            name: "Test Token",
            symbol: "TEST",
            poolDetails: "This is a test pool",
            configIndex: configIndex,
            router: router1.address,
            startTime: startTime,
            buyFeeRate: buyFeeRate,
            sellFeeRate: sellFeeRate,
            maxBuyAmount: maxBuyAmount,
            delayBuyTime: delayBuyTime,
            merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
            initialBuyAmount: 0,
        });

        const receipt = await tx.wait();
        // Extract the TokenCreated event from the logs
        const tokenCreatedEvent = receipt.events.find(event => event.event === "TokenCreated");

        const tokenAddress = tokenCreatedEvent.args.token;

        await managerFacet.setPoolState(tokenAddress, 1);
        const buyer = operator1;
        const amountIn = ethers.utils.parseEther("0.1");
        const { amountOut } = await atheneFacet.getAmountOut(tokenAddress, amountIn, true);
        const minAmountOut = amountOut.mul(95).div(100);

        await expect(
            atheneFacet.connect(buyer).buy(tokenAddress, owner.address, amountIn, minAmountOut, []) //Invalid pool
        ).to.be.revertedWith("AtheneFacet: Invalid state");
    })

    it("buy should revert if the buy is on cool down", async function () {
        const tx = await atheneFacet.createPool({
            name: "Test Token",
            symbol: "TEST",
            poolDetails: "This is a test pool",
            configIndex: configIndex,
            router: router1.address,
            startTime: startTime,
            buyFeeRate: buyFeeRate,
            sellFeeRate: sellFeeRate,
            maxBuyAmount: maxBuyAmount,
            delayBuyTime: delayBuyTime,
            merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
            initialBuyAmount: 0,
        });

        const receipt = await tx.wait();
        // Extract the TokenCreated event from the logs
        const tokenCreatedEvent = receipt.events.find(event => event.event === "TokenCreated");

        const tokenAddress = tokenCreatedEvent.args.token;

        await managerFacet.setDelayBuyTime(tokenAddress, 10);
        const buyer = operator1;
        const amountIn = ethers.utils.parseEther("0.1");
        const { amountOut, totalFee } = await atheneFacet.getAmountOut(tokenAddress, amountIn, true);
        const minAmountOut = amountOut.mul(95).div(100);

        await atheneFacet.connect(buyer).buy(tokenAddress, owner.address, amountIn, minAmountOut, [], { value: amountIn.add(totalFee) })
        await expect(atheneFacet.connect(buyer).buy(tokenAddress, owner.address, amountIn, minAmountOut, [], { value: amountIn.add(totalFee) })).to.be.revertedWith("AtheneFacet: Buy on cooldown")

    })

    it("buy should revert if insufficient liquidity", async function () {
        const tx = await atheneFacet.createPool({
            name: "Test Token",
            symbol: "TEST",
            poolDetails: "This is a test pool",
            configIndex: configIndex,
            router: router1.address,
            startTime: startTime,
            buyFeeRate: buyFeeRate,
            sellFeeRate: sellFeeRate,
            maxBuyAmount: maxBuyAmount,
            delayBuyTime: delayBuyTime,
            merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
            initialBuyAmount: 0,
        });

        const receipt = await tx.wait();
        // Extract the TokenCreated event from the logs
        const tokenCreatedEvent = receipt.events.find(event => event.event === "TokenCreated");

        const tokenAddress = tokenCreatedEvent.args.token;

        await managerFacet.setDelayBuyTime(tokenAddress, 10);
        const buyer = operator1;
        const amountIn = ethers.utils.parseEther("1000");
        const { amountOut, totalFee } = await atheneFacet.getAmountOut(tokenAddress, amountIn, true);
        const minAmountOut = amountOut.mul(95).div(100);

        await atheneFacet.connect(buyer).buy(tokenAddress, owner.address, amountIn, minAmountOut, [], { value: amountIn.add(totalFee) })
        await expect(atheneFacet.connect(buyer).buy(tokenAddress, owner.address, amountIn, minAmountOut, [], { value: amountIn.add(totalFee) })).to.be.revertedWith("AtheneFacet: Insufficient liquidity")
    })


    //Sell
    it("sell should revert if the pool is not exist", async function () {
        const seller = operator1;
        const amountIn = ethers.utils.parseEther("0.1");
        const { amountOut } = await atheneFacet.getAmountOut(baseTokenAddress, amountIn, false);
        const minAmountOut = amountOut.mul(95).div(100);

        await expect(
            atheneFacet.connect(seller).sell(operator1.address, owner.address, amountIn, minAmountOut, []) //Invalid pool
        ).to.be.revertedWith("AtheneFacet: INVALID_POOL");
    })

    it("sell should revert if pool has not started", async function () {
        const tx = await atheneFacet.createPool({
            name: "Test Token",
            symbol: "TEST",
            poolDetails: "This is a test pool",
            configIndex: configIndex,
            router: router1.address,
            startTime: Math.floor(Date.now() / 1000) + 7200,
            buyFeeRate: buyFeeRate,
            sellFeeRate: sellFeeRate,
            maxBuyAmount: maxBuyAmount,
            delayBuyTime: delayBuyTime,
            merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
            initialBuyAmount: 0,
        });

        const receipt = await tx.wait();
        // Extract the TokenCreated event from the logs
        const tokenCreatedEvent = receipt.events.find(event => event.event === "TokenCreated");

        const tokenAddress = tokenCreatedEvent.args.token;

        const seller = operator1;
        const amountIn = ethers.utils.parseEther("0.1");
        const { amountOut } = await atheneFacet.getAmountOut(tokenAddress, amountIn, false);
        const minAmountOut = amountOut.mul(95).div(100);

        await expect(
            atheneFacet.connect(seller).sell(tokenAddress, owner.address, amountIn, minAmountOut, [])
        ).to.be.revertedWith("AtheneFacet: Not started");
    });

    it("sell token successfully", async function () {
        const seller = operator1;
        const amountIn = ethers.utils.parseEther("0.1");

        const buy = await atheneFacet.getAmountOut(baseTokenAddress, amountIn, true);
        const { amountOut } = await atheneFacet.getAmountOut(baseTokenAddress, amountIn, false);
        const minAmountOut = amountOut.mul(95).div(100);

        //buy token 
        await atheneFacet.connect(seller).buy(baseTokenAddress, owner.address, amountIn, 0, [], { value: amountIn.add(buy.totalFee) })
        // Approve the contract to spend tokens
        const token = await ethers.getContractAt('AtheneToken', baseTokenAddress);
        await token.connect(seller).approve(atheneDiamond.address, ethers.constants.MaxUint256);

        const tx = await atheneFacet.connect(seller).sell(baseTokenAddress, owner.address, amountIn, minAmountOut, [])
        const poolInfo = await managerFacet.getPoolInfo(baseTokenAddress);
        const receipt2 = await tx.wait();

        const sellToken = receipt2.events.find(event => event.event === "Trade");
        console.log(sellToken.args)

        expect(sellToken.args.token).to.equal(baseTokenAddress)
        expect(sellToken.args.user).to.equal(seller.address)
        expect(sellToken.args.amountIn).to.equal(amountIn)
        expect(sellToken.args.isBuy).to.equal(false)
        expect(sellToken.args.baseReserve).to.equal(poolInfo.virtualBaseReserve)
        expect(sellToken.args.quoteReserve).to.equal(poolInfo.virtualQuoteReserve)
    });


});


