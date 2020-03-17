pragma solidity 0.5.16;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../contracts/DogeParser/DogeMessageLibrary.sol";

contract TestDogeMessageLibrary {

    function testFlip32BytesLargeNumber() public {
        uint expected = 0x201f1e1d1c1b1a191817161514131211100f0e0d0c0b0a090807060504030201;
        Assert.equal(DogeMessageLibrary.flip32Bytes(0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20), expected, "flip32Bytes failed");
    }

}
