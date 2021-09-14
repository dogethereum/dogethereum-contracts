import hre from "hardhat";
import { assert } from "chai";
import type { Contract, ContractTransaction } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { deployFixture } from "../deploy";

import {
  base58ToBytes20,
  expectFailure,
  isolateTests,
  isolateEachTest,
} from "./utils";

describe("DogeToken::doUnlock fails when it should", function () {
  let dogeToken: Contract;
  let accounts: string[];
  const operatorPublicKeyHash = `0x4d905b4b815d483cdfabcd292c6f86509d0fad82`;
  const dogeAddress = base58ToBytes20("DHx8ZyJJuiFM5xAHFypfz1k6bd2X85xNMy");

  isolateTests();
  isolateEachTest();

  before(async function () {
    const dogethereum = await deployFixture(hre);
    dogeToken = dogethereum.dogeToken;

    accounts = (await hre.ethers.getSigners()).map((signer) => signer.address);
    await dogeToken.assign(accounts[0], 3000000000);
  });

  describe(`With unregistered operator`, async function () {
    it(`fails unlock when requesting an amount below min value.`, async function () {
      await expectFailure(
        () => dogeToken.doUnlock(dogeAddress, 200000000, operatorPublicKeyHash),
        (error) => {
          assert.include(error.message, "Can't unlock small amounts");
        }
      );
    });

    it(`fails unlock when requesting an amount greater than user balance.`, async function () {
      await expectFailure(
        () =>
          dogeToken.doUnlock(dogeAddress, 200000000000, operatorPublicKeyHash),
        (error) => {
          assert.include(
            error.message,
            "User doesn't have enough token balance"
          );
        }
      );
    });

    it(`fails when unlocking with an unregistered operator`, async function () {
      await expectFailure(
        () =>
          dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash),
        (error) => {
          assert.include(error.message, "Operator is not registered");
        }
      );
    });
  });

  describe(`With registered operator`, async function () {
    before(async function () {
      const operatorEthAddress = accounts[3];
      await dogeToken.addOperatorSimple(
        operatorPublicKeyHash,
        operatorEthAddress
      );
    });

    it(`fails when unlocking with an operator that doesn't have enough balance`, async function () {
      await expectFailure(
        () =>
          dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash),
        (error) => {
          assert.include(error.message, "Operator doesn't have enough balance");
        }
      );
    });

    it(`fails when unlocking without any available utxos`, async function () {
      // This is an unrealistic scenario since ERR_UNLOCK_OPERATOR_BALANCE should have been returned before.
      // TODO: is this test useful?
      await dogeToken.addDogeAvailableBalance(
        operatorPublicKeyHash,
        1000000000
      );
      await expectFailure(
        () =>
          dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash),
        (error) => {
          assert.include(error.message, "No available UTXOs for this operator");
        }
      );
    });

    it(`fails unlock when available utxos do not cover requested value`, async function () {
      // This is an unrealistic scenario since ERR_UNLOCK_OPERATOR_BALANCE should have been returned before.
      // TODO: is this test useful?
      await dogeToken.addUtxo(operatorPublicKeyHash, 100000000, 1, 10);
      await dogeToken.addDogeAvailableBalance(
        operatorPublicKeyHash,
        2400000000
      );
      await expectFailure(
        () =>
          dogeToken.doUnlock(dogeAddress, 2500000000, operatorPublicKeyHash),
        (error) => {
          assert.include(
            error.message,
            "Available UTXOs don't cover requested unlock amount"
          );
        }
      );
    });

    it(`fails unlock when value to send is less than fee`, async function () {
      const utxoValue = 100000000;
      const utxoAmount = 10;
      for (let i = 0; i < utxoAmount; i++) {
        await dogeToken.addUtxo(operatorPublicKeyHash, utxoValue, 1, 10);
      }
      await expectFailure(
        () =>
          dogeToken.doUnlock(
            dogeAddress,
            utxoValue * utxoAmount,
            operatorPublicKeyHash
          ),
        (error) => {
          assert.include(
            error.message,
            "Requested unlock amount can't cover tx fees."
          );
        }
      );
    });
  });
});
