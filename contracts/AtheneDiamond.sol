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

import {LibAthene} from "contracts/libraries/LibAthene.sol";
import {LibDiamond} from "contracts/libraries/LibDiamond.sol";
import {IDiamondCut} from "contracts/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "contracts/interfaces/IDiamondLoupe.sol";
import {IERC173} from "contracts/interfaces/IERC173.sol";
import {IERC165} from "contracts/interfaces/IERC165.sol";

// When no function exists for function called
error FunctionNotFound(bytes4 _functionSelector);

// This is used in diamond constructor
// more arguments are added to this struct
// this avoids stack too deep errors
struct DiamondArgs {
    address owner;
    address init;
    bytes initCalldata;
}

contract AtheneDiamond {
    constructor(
        IDiamondCut.FacetCut[] memory _diamondCut,
        DiamondArgs memory _args
    ) payable {
        LibAthene.setAdmin(_args.owner);
        LibDiamond.diamondCut(_diamondCut, _args.init, _args.initCalldata);
        // Code can be added here to perform actions and set state variables.
    }

    // Find facet for function that is called and execute the
    // function if a facet is found and return any value.
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds;
        bytes32 position = LibDiamond.DIAMOND_STORAGE_POSITION;
        // get diamond storage
        assembly {
            ds.slot := position
        }
        // get facet from function selector
        address facet = ds
            .facetAddressAndSelectorPosition[msg.sig]
            .facetAddress;
        if (facet == address(0)) {
            revert FunctionNotFound(msg.sig);
        }
        // Execute external function from facet using delegatecall and return any value.
        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            // execute function call using the facet
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {}
}