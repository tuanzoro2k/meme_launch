
  const { expect } = require("chai");
  const {ethers} = require("hardhat")

  describe("ManagerFacet", function () {
    it("Should allow setting admin", async function () {
      const [owner, newAdmin] = await ethers.getSigners();
  
      // Deploy ManagerFacet contract
      const ManagerFacet = await ethers.getContractFactory("ManagerFacet");
      const managerFacet = await ManagerFacet.deploy();
      await managerFacet.deployed()

      console.log(managerFacet.address)
  
      // Deploy AtheneDiamond contract
      const AtheneDiamond = await ethers.getContractFactory("AtheneDiamond");
      const atheneDiamond = await AtheneDiamond.deploy(
        [
          {
            facetAddress: managerFacet.address,
            action: 0,
            functionSelectors: managerFacet.interface.encodeFunctionData("setAdmin", [owner.address]),
          },
        ],
        {
          owner: owner.address,
          init: managerFacet.address,
          initCalldata: managerFacet.interface.encodeFunctionData("setAdmin", [owner.address]),
        }
      );
  
      // Set new admin
      const tx = await atheneDiamond.setAdmin(newAdmin.address);
      await tx.wait();
  
      // Check if new admin is set correctly
      const currentAdmin = await atheneDiamond.getAdmin();
      expect(currentAdmin).to.equal(newAdmin.address);
    });
  });


