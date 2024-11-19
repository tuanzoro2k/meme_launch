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
uint256 constant FEE_DENOMINATOR = 1e4;

struct AtheneMasterConfig {
    address admin;
    uint256 feeBps;
    address feeReceiver;
    uint256 refBps;
    address wethAddress;
    bool paused;
}

struct AthenePoolConfig {
    uint256 index;
    uint256 initialVirtualBaseReserve;
    uint256 initialVirtualQuoteReserve;
    uint256 totalSellingBaseAmount;
    uint256 maxListingBaseAmount;
    uint256 maxListingQuoteAmount;
    uint256 defaultListingRate;
    uint256 listingFee;
}

struct AthenePoolInfo {
    uint256 id;
    address owner;
    address token;
    address router;
    string poolDetails;
    uint8 state; //actice,paused, closed
    uint256 virtualBaseReserve;
    uint256 virtualQuoteReserve;
    uint256 minBaseReserve;
    uint256 minQuoteReserve;
    uint256 maxListingBaseAmount;
    uint256 maxListingQuoteAmount;
    uint256 defaultListingRate;
    uint256 listingFee;
    uint256 startTime;
    uint256 listedAt;
    uint256 buyFeeRate;
    uint256 sellFeeRate;
    uint256 maxBuyAmount;
    uint256 delayBuyTime;
    bytes32 whitelistMerkleRoot;
}

struct AtheneAppStorage {
    AtheneMasterConfig masterConfig;
    EnumerableSet.AddressSet operators;
    EnumerableSet.AddressSet routers;
    EnumerableSet.UintSet poolConfigIndexes;
    mapping(uint256 => AthenePoolConfig) poolConfigMapping;
    EnumerableSet.AddressSet tokens;
    mapping(address => AthenePoolInfo) poolInfoMapping;
    mapping(address => mapping(address => uint256)) userLastBuyAt;
}

library LibAtheneAppStorage {
    function diamondStorage()
        internal
        pure
        returns (AtheneAppStorage storage ds)
    {
        assembly {
            ds.slot := 0
        }
    }
}

contract AtheneBase {
    using EnumerableSet for EnumerableSet.AddressSet;

    AtheneAppStorage internal s;

    modifier onlyAdmin() {
        require(msg.sender == s.masterConfig.admin, "Athene: Unauthorized");
        _;
    }

    modifier onlyOperator() {
        enforceIsAdminOrOperator();
        _;
    }

    modifier notPaused() {
        require(!s.masterConfig.paused, "Athene: Paused");
        _;
    }

    function enforceIsAdminOrOperator() internal view {
        require(
            msg.sender == s.masterConfig.admin ||
                s.operators.contains(msg.sender),
            "Athene: Unauthorized"
        );
    }
}