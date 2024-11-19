
const { expect } = require("chai");
const { ethers } = require("hardhat")
const { getSelectors, FacetCutAction } = require('../scripts/libraries/diamond.js')


describe("ManagerFacet", function () {
  it("Should allow setting admin", async function () {
    const [owner, newAdmin] = await ethers.getSigners();

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
    const atheneDiamond = await AtheneDiamond.deploy(
      facetCuts,
      diamondArgs
    );
    await atheneDiamond.deployed()

    const managerFacet = await ethers.getContractAt('ManagerFacet', atheneDiamond.address)
    const tx = await managerFacet.setMasterConfig("0xa084b43e09c74E401b7500c3D30a1B569e4934AD", "0xa084b43e09c74E401b7500c3D30a1B569e4934AD", 50, 60)
    await tx.wait();

    // Check if new admin is set correctly
    const currentConfig = await managerFacet.getMasterConfig();
    console.log(currentConfig)
  });
});


