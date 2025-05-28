// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "../lib/forge-std/src/Script.sol";
import {NftCardGame} from "../src/NftCardGame.sol";

contract DeployAVAXGods is Script {
    function run() external {
        string
            memory _metadataUri = "https://gateway.pinata.cloud/ipfs/QmX2ubhtBPtYw75Wrpv6HLb1fhbJqxrnbhDo1RViW3oVoi";

        // Load deployer key from .env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.addr(deployerPrivateKey);

        // Start broadcasting transaction with the deployer's private key
        vm.startBroadcast(deployerPrivateKey);

        // Pass both metadata URI and initial owner to constructor
        NftCardGame nftcardgame = new NftCardGame(initialOwner,_metadataUri);
        vm.stopBroadcast();
    }
}
