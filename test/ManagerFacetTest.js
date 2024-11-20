
const { expect } = require("chai");
const { ethers } = require("hardhat")
const { getSelectors, FacetCutAction } = require('../scripts/libraries/diamond.js')


describe("ManagerFacet", () => {
  let atheneDiamond;
  let owner;
  let operator1;
  let operator2;
  let router1;
  let router2;
  before(async function () {
    [owner, operator1, operator2, router1, router2] = await ethers.getSigners();
    const DiamondInit = await ethers.getContractFactory('DiamondInit')
    const diamondInit = await DiamondInit.deploy()
    await diamondInit.deployed()
    console.log('DiamondInit deployed:', diamondInit.address)

    // Deploy facets and set the `facetCuts` variable
    console.log('')
    console.log('Deploying facets')
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
  });

  it("Should allow setting masterconfig", async () => {

    const managerFacet = await ethers.getContractAt('ManagerFacet', atheneDiamond.address)
    const wethAddress = "0xa084b43e09c74E401b7500c3D30a1B569e4934AD"
    const feeReceiver = "0xa084b43e09c74E401b7500c3D30a1B569e4934AD"
    const feeBps = 50
    const refBps = 50
    const tx = await managerFacet.setMasterConfig(wethAddress, feeReceiver, feeBps, refBps)
    await tx.wait();

    // Check if new config is set correctly
    const currentConfig = await managerFacet.getMasterConfig();
    expect(currentConfig.wethAddress).to.be.equal(wethAddress)
    expect(currentConfig.feeReceiver).to.be.equal(wethAddress)
    expect(currentConfig.feeBps).to.be.equal(feeBps)
    expect(currentConfig.refBps).to.be.equal(refBps)
  });


  it("show allow setting paused", async () => {
    const managerFacet = await ethers.getContractAt('ManagerFacet', atheneDiamond.address)
    const tx = await managerFacet.setPaused(true)
    await tx.wait();

    expect(await managerFacet.isPaused()).to.be.equal(true)
  })

  //Pool config
  it("show allow setting pool config", async () => {
    const managerFacet = await ethers.getContractAt('ManagerFacet', atheneDiamond.address)

    const index = 1
    const athenePoolConfig = {
      index: 1,
      initialVirtualBaseReserve: 1000,
      initialVirtualQuoteReserve: 2000,
      totalSellingBaseAmount: 1000,
      maxListingBaseAmount: 10000,
      maxListingQuoteAmount: 10000,
      defaultListingRate: 50,
      listingFee: 10
    }

    const tx = await managerFacet.setPoolConfig(index, athenePoolConfig);
    await tx.wait()

    const currentPoolConfig = await managerFacet.getPoolConfig(1);
    expect(currentPoolConfig.index).to.be.equal(1)
    expect(currentPoolConfig.initialVirtualBaseReserve).to.be.equal(1000)
    expect(currentPoolConfig.initialVirtualQuoteReserve).to.be.equal(2000)
    expect(currentPoolConfig.totalSellingBaseAmount).to.be.equal(1000)
    expect(currentPoolConfig.maxListingBaseAmount).to.be.equal(10000)
    expect(currentPoolConfig.maxListingQuoteAmount).to.be.equal(10000)
    expect(currentPoolConfig.defaultListingRate).to.be.equal(50)
    expect(currentPoolConfig.listingFee).to.be.equal(10)
  })

  it("should remove setting pool config", async () => {
    const managerFacet = await ethers.getContractAt('ManagerFacet', atheneDiamond.address)
    const tx = await managerFacet.removePoolConfig(1);
    await tx.wait()

    await expect(managerFacet.getPoolConfig(1)).to.be.revertedWith("ManagerFacet: Invalid config");
  })

  //Operators
  it("should allow setting operators", async () => {
    const managerFacet = await ethers.getContractAt('ManagerFacet', atheneDiamond.address);

    const tx = await managerFacet.setOperators([operator1.address, operator2.address], true);
    await tx.wait();

    const operators = await managerFacet.getOperators();
    console.log(operators)
    expect(operators.includes(operator1.address)).to.be.true;
    expect(operators.includes(operator2.address)).to.be.true;
  });

  it("should allow removing operators", async () => {
    const managerFacet = await ethers.getContractAt('ManagerFacet', atheneDiamond.address);

    const txRemove = await managerFacet.setOperators([operator2.address], false);
    await txRemove.wait();

    const operators = await managerFacet.getOperators();
    expect(operators.includes(operator2.address)).to.be.false;
  });

  //Routers
  it("should allow setting whitelisted routers", async () => {
    const managerFacet = await ethers.getContractAt('ManagerFacet', atheneDiamond.address);

    const tx = await managerFacet.setWhitelistedRouters([router1.address, router2.address], true);
    await tx.wait();

    const routers = await managerFacet.getRouters();
    expect(routers.includes(router1.address)).to.be.true;
    expect(routers.includes(router2.address)).to.be.true;
  });

  it("should allow removing whitelisted routers", async () => {
    const managerFacet = await ethers.getContractAt('ManagerFacet', atheneDiamond.address);

    const txRemove = await managerFacet.setWhitelistedRouters([router2.address], false);
    await txRemove.wait();

    const routers = await managerFacet.getRouters();
    expect(routers.includes(router2.address)).to.be.false;
  });

  //Pool state
  it("should allow setting pool state", async () => {
    const managerFacet = await ethers.getContractAt('ManagerFacet', atheneDiamond.address);

    const token = "0x1234567890123456789012345678901234567890";

    const tx = await managerFacet.setPoolState(token, 1); // Assuming 1 represents an active state
    await tx.wait();

    const poolInfo = await managerFacet.getPoolInfo(token);
    expect(poolInfo.state).to.equal(1);
  });

  it("should not allow changing pool state if not admin or operator", async () => {
    const managerFacet = await ethers.getContractAt('ManagerFacet', atheneDiamond.address);

    const token = "0x09876543210987654321098765432109876543210";

    // Non-admin/non-operator tries to change state
    await expect(managerFacet.setPoolState(token, 1))
      .to.be.revertedWith("ManagerFacet: Not admin or operator");
  });

  it("show allow setting admin", async () => {
    const managerFacet = await ethers.getContractAt('ManagerFacet', atheneDiamond.address)
    const tx = await managerFacet.setAdmin("0xa084b43e09c74E401b7500c3D30a1B569e4934AD")
    await tx.wait();

    const currentConfig = await managerFacet.getMasterConfig();
    expect(currentConfig.admin).to.be.equal("0xa084b43e09c74E401b7500c3D30a1B569e4934AD")
  })
});


