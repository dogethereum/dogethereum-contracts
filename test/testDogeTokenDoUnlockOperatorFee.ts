import hre from "hardhat";
import { assert } from "chai";
import type { Contract } from "ethers";

import { deployFixture } from "../deploy";

import { base58ToBytes20, isolateTests } from "./utils";


describe('testDogeTokenDoUnlockOperatorFee', function() {
  let dogeToken: Contract;
  let accounts: string[];

  isolateTests();

  before(async () => {
    const dogethereum = await deployFixture(hre);
    dogeToken = dogethereum.dogeToken;

    accounts = (await hre.ethers.getSigners()).map((signer) => signer.address);
  });

  it('doUnlock pays operator fee', async () => {
    const operatorPublicKeyHash = `0x4d905b4b815d483cdfabcd292c6f86509d0fad82`;
    const operatorEthAddress = accounts[3];
    await dogeToken.addOperatorSimple(operatorPublicKeyHash, operatorEthAddress);

    await dogeToken.assign(accounts[0], 20000000000);
    const balance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(balance, 20000000000, `DogeToken's ${accounts[0]} balance is not the expected one`);

    await dogeToken.addUtxo(operatorPublicKeyHash, 20000000000, 1, 10);
    const utxo = await dogeToken.getUtxo(operatorPublicKeyHash, 0);
    assert.equal(utxo.value.toNumber(), 20000000000, `Utxo value is not the expected one`);

    const dogeAddress = base58ToBytes20("DHx8ZyJJuiFM5xAHFypfz1k6bd2X85xNMy");
    await dogeToken.doUnlock(dogeAddress, 15000000000, operatorPublicKeyHash);

    const unlockPendingInvestorProof = await dogeToken.getUnlockPendingInvestorProof(0);
    assert.equal(unlockPendingInvestorProof.operatorFee.toNumber(), 150000000, `Unlock operator fee is not the expected one`);
    const operatorTokenBalance = await dogeToken.balanceOf(operatorEthAddress);
    assert.equal(operatorTokenBalance.toNumber(), 150000000, `DogeToken's operator balance after unlock is not the expected one`);
  });
});
