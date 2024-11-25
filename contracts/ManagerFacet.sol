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
import {LibDiamond} from "contracts/libraries/LibDiamond.sol";
import {AtheneBase, AthenePoolInfo, AthenePoolConfig, AtheneMasterConfig} from "contracts/libraries/LibAtheneAppStorage.sol";
import {LibAthene} from "contracts/libraries/LibAthene.sol";

contract ManagerFacet is AtheneBase {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    event PoolInfoUpdated(address indexed token, uint256 timestamp);

    function setAdmin(address newAdmin) external onlyAdmin {
        LibAthene.setAdmin(newAdmin);
    }

    function setPaused(bool paused) external onlyAdmin {
        s.masterConfig.paused = paused;
    }

    function setMasterConfig(
        address weth,
        address feeReceiver,
        uint256 feeBps,
        uint256 refBps,
        address poolToken
    ) external onlyAdmin {
        s.masterConfig.wethAddress = weth;
        s.masterConfig.feeReceiver = feeReceiver;
        s.masterConfig.feeBps = feeBps;
        s.masterConfig.refBps = refBps;
        s.masterConfig.poolToken = poolToken;
    }

    function getMasterConfig()
        external
        view
        returns (AtheneMasterConfig memory)
    {
        return s.masterConfig;
    }

    function setPoolConfig(
        uint256 index,
        AthenePoolConfig memory poolConfig
    ) external onlyAdmin {
        s.poolConfigIndexes.add(index);
        s.poolConfigMapping[index] = poolConfig;
    }

    function removePoolConfig(uint256 index) external onlyAdmin {
        s.poolConfigIndexes.remove(index);
        delete s.poolConfigMapping[index];
    }

    function getPoolConfig(
        uint256 index
    ) external view returns (AthenePoolConfig memory) {
        AthenePoolConfig memory config = s.poolConfigMapping[index];
        require(
            config.initialVirtualBaseReserve > 0,
            "ManagerFacet: Invalid config"
        );
        return config;
    }

    function getAllPoolConfigs()
        external
        view
        returns (AthenePoolConfig[] memory)
    {
        uint256 count = s.poolConfigIndexes.length();
        AthenePoolConfig[] memory configs = new AthenePoolConfig[](count);
        for (uint256 i = 0; i < count; i++) {
            configs[i] = s.poolConfigMapping[s.poolConfigIndexes.at(i)];
        }
        return configs;
    }

    function setOperators(
        address[] memory operators,
        bool add
    ) external onlyAdmin {
        for (uint256 i = 0; i < operators.length; i++) {
            if (add) {
                s.operators.add(operators[i]);
            } else {
                s.operators.remove(operators[i]);
            }
        }
    }

    function getOperators() external view returns (address[] memory) {
        return s.operators.values();
    }

    function setWhitelistedRouters(
        address[] memory routers,
        bool add
    ) external onlyAdmin {
        for (uint256 i = 0; i < routers.length; i++) {
            if (add) {
                s.routers.add(routers[i]);
            } else {
                s.routers.remove(routers[i]);
            }
        }
    }

    function getRouters() external view returns (address[] memory) {
        return s.routers.values();
    }

    function isPaused() external view returns (bool) {
        return s.masterConfig.paused;
    }

    function setPoolState(address token, uint8 state) external onlyOperator {
        AthenePoolInfo storage poolInfo = s.poolInfoMapping[token];
        require(poolInfo.token != address(0), "ManagerFacet: Invalid pool");
        poolInfo.state = state;

        emit PoolInfoUpdated(token, block.timestamp);
    }

    function setPoolDetails(address token, string memory details) external {
        AthenePoolInfo storage poolInfo = s.poolInfoMapping[token];
        require(poolInfo.token != address(0), "ManagerFacet: Invalid pool");
        if (poolInfo.owner != msg.sender) {
            enforceIsAdminOrOperator();
        }
        poolInfo.poolDetails = details;

        emit PoolInfoUpdated(token, block.timestamp);
    }

    function setWhitelist(address token, bytes32 root) external {
        AthenePoolInfo storage poolInfo = s.poolInfoMapping[token];
        require(poolInfo.token != address(0), "ManagerFacet: Invalid pool");
        if (poolInfo.owner != msg.sender) {
            enforceIsAdminOrOperator();
        }

        poolInfo.whitelistMerkleRoot = root;
    }

    function setDelayBuyTime(address token, uint256 delay) external {
        AthenePoolInfo storage poolInfo = s.poolInfoMapping[token];
        require(poolInfo.token != address(0), "ManagerFacet: Invalid pool");
        if (poolInfo.owner != msg.sender) {
            enforceIsAdminOrOperator();
        }

        poolInfo.delayBuyTime = delay;

        emit PoolInfoUpdated(token, block.timestamp);
    }

    function setMaxBuyAmount(address token, uint256 maxBuy) external {
        AthenePoolInfo storage poolInfo = s.poolInfoMapping[token];
        require(poolInfo.token != address(0), "ManagerFacet: Invalid pool");
        if (poolInfo.owner != msg.sender) {
            enforceIsAdminOrOperator();
        }

        poolInfo.maxBuyAmount = maxBuy;

        emit PoolInfoUpdated(token, block.timestamp);
    }

    function setFeeRate(
        address token,
        uint256 buyFeeRate,
        uint256 sellFeeRate
    ) external {
        AthenePoolInfo storage poolInfo = s.poolInfoMapping[token];
        require(poolInfo.token != address(0), "ManagerFacet: Invalid pool");
        if (poolInfo.owner != msg.sender) {
            enforceIsAdminOrOperator();
        }

        poolInfo.buyFeeRate = buyFeeRate;
        poolInfo.sellFeeRate = sellFeeRate;

        emit PoolInfoUpdated(token, block.timestamp);
    }

    function getPoolAt(
        uint256 index
    ) external view returns (AthenePoolInfo memory) {
        require(
            s.tokens.at(index) != address(0),
            "ManagerFacet: Invalid token index"
        );
        return getPoolInfo(s.tokens.at(index));
    }

    function getPoolInfo(
        address tokenAddress
    ) public view returns (AthenePoolInfo memory) {
        AthenePoolInfo memory poolInfo = s.poolInfoMapping[tokenAddress];
        require(
            poolInfo.token == tokenAddress,
            "ManagerFacet: Invalid token address"
        );
        return poolInfo;
    }

    function getPoolCount() external view returns (uint256) {
        return s.tokens.length();
    }

    function getUserLastBuyTime(
        address token,
        address user
    ) external view returns (uint256) {
        return s.userLastBuyAt[token][user];
    }
}
