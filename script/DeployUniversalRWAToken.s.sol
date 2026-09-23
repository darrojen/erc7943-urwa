// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/UniversalRWAToken.sol";

contract DeployUniversalRWAToken is Script {
    function run() external returns (UniversalRWAToken token) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(1_000_000 ether));

        vm.startBroadcast(deployerPrivateKey);
        token = new UniversalRWAToken(
            "Universal RWA Token",
            "uRWA",
            initialSupply
        );
        vm.stopBroadcast();
    }
}
