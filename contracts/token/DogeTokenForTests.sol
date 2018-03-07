pragma solidity ^0.4.19;

import "./DogeToken.sol";

contract DogeTokenForTests is DogeToken {

    function DogeTokenForTests(address trustedDogeRelay, bytes20 recipientDogethereum) public DogeToken(trustedDogeRelay, recipientDogethereum) {

    }

    function assign(address _to, uint256 _value) public {
        balances[_to] += _value;
    }

    function addUtxo(uint value, uint txHash, uint16 outputIndex) public {
        utxos.push(Utxo(value, txHash, outputIndex));
    }

    function getUnlocksPendingInvestorProof(uint index) public view returns (address from, string dogeAddress, uint value, uint timestamp, uint32[] selectedUtxos, uint fee) {
    	Unlock unlock = unlocksPendingInvestorProof[index];
        from = unlock.from;
        dogeAddress = unlock.dogeAddress;
        value = unlock.value;
        timestamp = unlock.timestamp;
        selectedUtxos = unlock.selectedUtxos;
        fee = unlock.fee;
    }


}
