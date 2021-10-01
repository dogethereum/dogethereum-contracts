import hre from "hardhat";
import { assert } from "chai";
import type { Contract } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { deployFixture, deployContract } from "../deploy";

import {
  // calcBlockSha256Hash,
  makeSuperblock,
  isolateTests,
} from "./utils";

describe("DogeSuperblocks2", function () {
  let accounts: SignerWithAddress[];
  let superblockClaims: SignerWithAddress;
  let user: SignerWithAddress;
  let superblocks: Contract;

  isolateTests();

  before(async function () {
    accounts = await hre.ethers.getSigners();
    superblockClaims = accounts[1];
    user = accounts[2];

    const dogethereum = await deployFixture(hre);
    superblocks = await deployContract("DogeSuperblocks", [], hre, {
      signer: accounts[0],
      libraries: {
        DogeMessageLibrary: dogethereum.dogeMessageLibrary.address,
      },
    });
    await superblocks.setSuperblockClaims(superblockClaims.address);
  });

  const headers = [
    `03016200241bb260a8b2ffd509982c8230475e8c012f5bb41036ed7caa97905ec2c66fb25e2f04306e21065b956b5726e1f1dfed1a468b7309dff926628c53f453c53142b14655564c6e041b0000000001000000010000000000000000000000000000000000000000000000000000000000000000ffffffff6403449e0de4b883e5bda9e7a59ee4bb99e9b1bcfabe6d6d2eb40132424f2d742e503a6052788225449011e7ca46d5ce3be2189aab6f40f940000000f09f909f4d696e6564206279206c7463303031000000000000000000000000000000000000000000003de7050001c8abbe95000000001976a914aa3750aa18b8a0f3f0590731e1fab934856680cf88acc92c61360f08ad87f772eb16bdd893a49bf2f02bb4a3bcb8e3605b9046bb0200000000000531c3275dc3dcb07bcf550a77d5c63b29959d034536ab5afeac74c36c37727dcd5752dd9effcbda9c1e5ddc17aa1f1a984192d834b8ff5a1a60e9efd55bf94f1532391099740d20947b24a3556a61602d43e8eabc8ebdba8152459c3a3f24b5c5276a9eed0dbd8b253cef989c0b3a91ed6c2cfba17488646287cb1a8b31d20a7e808778fa84ff3413c05b7debab62b8385fa7625d5c3db31775911b54f86ddbf000000000062900000000000000000000000000000000000000000000000000000000000000463ceed131958d98aee29089d1cf38b9728b224512e51ca3a8b1189d5ed03d0709b68fd6e328528f2a29ec7fb077c834fbf0f14c371fafcfb27444017fbf5b26fdb884bed8ad6a4bded36fc89ed8b05a6c6c0ae1cfd5fe37eb3021b32a1e29042b7a2e142329e7d0d0bffcb5cc338621a576b49d4d32991000b8d4ac793bc1f50800d93cbb266b6d9cf068dea7fdb153f648f673583e0c196985ab21d576e86c280000000300000071fad47a6bcb4f483da2562d7e1afeb03bfa07a4540365fbf2ef3db5be41598057f99a71e88ddc60bdd708d004c740b816a55a924759e4de63649d21546584c0e9465556358c011b12ebae8e`,
    `0301620008d2149a4c09211274a5d4aa6664e3744316ec2753c2dd8f8ce120107f553b16f577311cf1a9718fa8d03bd7489867d7c3766f8b4ea6e0556de22a25b35d6c23ce4755569535041b0000000001000000010000000000000000000000000000000000000000000000000000000000000000ffffffff3f03449e0d04565547cf2cfabe6d6da47a2bd785497c80460cee1c98e619495798c42cb26f59d83264bba1b84001c3400000000000000008160025482c000000ffffffff0190f4e495000000001976a91457757ed3d226faf12bd43983896ec81e7fca369a88ac00000000c4169f0102d6b4ea63ffa02f68b4b645930c517fce3fef5e8e389d0c18533b9506f3798f240748c042e9b6074526232c818a192df3016a2f8c04835c336db4335ffbf3c336ec1fe51ef9e6e60460c3902d84e3c672a91001d63aa2a22edb0485cc5f7a0fccf78eacfd7023e7b260bf83347f05503ee357d02d3919419aa819288e3d250bd0b3332b25f5cf78e0983e73f5a0b0af951b6119c6f8b8aa1b7192695891417d01f52fad8802638f1590be80bac364ae5a7737c182d604af2e7937ef2e7e7b197151c3525785a6b12b47e73fe3541498c6f407f6279e184d1533b464c60000000006c6ea0f7aad9bf51b3934d6cba36ec25f3fe9849709abd3f44248d78c0bc505d0a631474a1d2dfc29be55058d230afcd4a1d3f0eba12bdd4a2f78346f1b7495bf7d24db2bfa41474bfb2f877d688fac5faa5e10a2808cf9de307370b93352e54894857d3e08918f70395d9206410fbfa942f1a889aa5ab8188ec33c2f6e207dc7a2376894b5181d8d6d1127bf0d19c715089a73cbc25fd09d493c41f1fe9339dd010103373a1abe9e97481fbdaff392c3cf9eeffeca9ba04ef21240aa50126672380000000300000071fad47a6bcb4f483da2562d7e1afeb03bfa07a4540365fbf2ef3db5be4159805196f9b2a4ff0d9a7ff0dd81f8401cf21ca9694e0b5b6f482186a9c0ed3e660bcf475556358c011bfce10a64`,
    `03016200a1477c2168cf76ad6e3525a8ab7e952df235f9d43a583d1bf7ed48ffe6e7451e0db1e5eca6fb65734c7ee1d724d84228e1837f65c55c2b2589abbbd0f3180ce2e3475556742c061b0000000001000000010000000000000000000000000000000000000000000000000000000000000000ffffffff4c03449e0d04e54755560803e05184dbc42500fabe6d6de531ecc51b2f1888a5de9ce91fed445883e55f1dc1b58d5e3a7684cb56f9945c40000000000000000d2f6e6f64655374726174756d2f0000000001209a0a95000000001976a9145da2560b857f5ba7874de4a1173e67b4d509c46688ac000000004990d6bdc68f086c4a82d90d683046a40d3c546609c368aecc5bc807806edc0903ad4c94d66fa017fe2a75da68fc0a9b84394bf147022deeae001cde7d53d2a480eb32313884371daf6cafbe0e00f264721ad9be2cace3fc838826d2e0f299978f1ae1d13cb5bf47b14651bee13e885f2129654d9106ae04c35684e22a558e9f5b00000000060000000000000000000000000000000000000000000000000000000000000000e2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf97d24db2bfa41474bfb2f877d688fac5faa5e10a2808cf9de307370b93352e54894857d3e08918f70395d9206410fbfa942f1a889aa5ab8188ec33c2f6e207dc778b6e34efd0a4749b771cfe3f5876e880f0d851ebb93a4dab5062a5975a1aa3e11b1acbc3b0b041473bf1f16421df844ba2f1e157add8f2cdbd8e0e0b816f1ad380000000300000071fad47a6bcb4f483da2562d7e1afeb03bfa07a4540365fbf2ef3db5be415980616cb8630c8a108d4ff80240d6adbbd77190369c1b024b9db99b8d1f229191e62b465556358c011b3d099516`,
    `0301620029b451ad79429fc1fd26109331ee83b858a5335952b5754993b1922d29dc2ed7c38be4f98012dedeb9372926959ca82247784933badf7b94d308d96eb195c090ec47555616c3051b0000000001000000010000000000000000000000000000000000000000000000000000000000000000ffffffff6403449e0de4b883e5bda9e7a59ee4bb99e9b1bcfabe6d6dc5eb29e28e7c54b269858b1f5b278b74eed3cbda1cf7dd506429d94f346ca9e740000000f09f909f4d696e656420627920636169726f6e670000000000000000000000000000000000000000002800000001b83af495000000001976a914aa3750aa18b8a0f3f0590731e1fab934856680cf88ac3d757a337f51482ded52a98d026b2aab20d4bd6bcedc3be5823471eada6e0300000000000631c3275dc3dcb07bcf550a77d5c63b29959d034536ab5afeac74c36c37727dcdce2b8079e87c60509d7ee92a0821d75800115f8877b5ab2a81a8b4400cf959cdcf457944488908b9f39527ac492dc490fab9b6548fb693ed38073466395fe9c659cbb38b6e245c52ea756e3d77514f23ea3e1ff4f16e0e4d9886ab3f3e1a0b0a47a0102b4ef760f0e7cbc4a53302c14d38704ee49b5fd0dfd17309ff97ba2a61729a8880632134ae072c6693b465b084086f4a2750bd86044814cb0a3fd5d12900000000062900000000000000000000000000000000000000000000000000000000000000463ceed131958d98aee29089d1cf38b9728b224512e51ca3a8b1189d5ed03d0709b68fd6e328528f2a29ec7fb077c834fbf0f14c371fafcfb27444017fbf5b26fdb884bed8ad6a4bded36fc89ed8b05a6c6c0ae1cfd5fe37eb3021b32a1e29042b7a2e142329e7d0d0bffcb5cc338621a576b49d4d32991000b8d4ac793bc1f583718a099fd33ba7cbb8e3c233e86d76375c354fa3189e5df3203fbd4f4d417c280000000300000071fad47a6bcb4f483da2562d7e1afeb03bfa07a4540365fbf2ef3db5be415980b2b87463d388a3682b24d2172f71908de64e875867df17abbf42a225b24d922d27485556358c011ba66aad20`,
    `02016200427b118bc209c9ff10f50a25181410276720ba4bb2d6e001d2897671ebd3cfe43983c016d7643b77b2bab44314d6411c68634813c2ae1a2eb4894321c609e93cb7485556932f051b0000000002000000010000000000000000000000000000000000000000000000000000000000000000ffffffff5403449e0d2cfabe6d6dbaac4ffbf483b312f20c87896d4651b22b5da8ad1fae296b733926353e066ec201000000000000002fe585abe5ae9de6b1a0203862616f6368692e636f6d2f0100000076fc0f023d010000000000000110ae0f96000000001976a9149659e4bc4b884ae48b9e8e70e22b9b7dea9ef24788ac0000000002c4e323fc827d020a0d179b3d39489ce1d2c8391eaa715248a4f836fccea12107f3798f240748c042e9b6074526232c818a192df3016a2f8c04835c336db4335ffbf3c336ec1fe51ef9e6e60460c3902d84e3c672a91001d63aa2a22edb0485cca78d32071fabf1ebc844fb2c9f37630394ef405bcc4a9211170fd7db6ebf9069c4e1386a0c75901ffa5cfc53d5e02c843508586b38ee9ede0fea5379968b0418e30c2eda83fedb03c5d1f0485d301f34fe2740ec3106891fb8041abb85d73ff2e8a0855c3d58afc5f8f3aea6c176f960e7b08dab000627c5adc09e9169da742d6e799841f20c5bcd121c0df05bcf57ab79a77b181340a440292c66539fbebee30000000000000000000300000071fad47a6bcb4f483da2562d7e1afeb03bfa07a4540365fbf2ef3db5be415980daaadd9da1da6c858fdfd94c8e297f695a6c575b65e215a8888aa9ae6cb1352bb6485556358c011bfeffbb00`,
  ];
  // const hashes = headers.map(calcBlockSha256Hash);
  const initParentId =
    "0x0000000000000000000000000000000000000000000000000000000000000000";
  const initAccumulatedWork = 0;
  const genesisSuperblock = makeSuperblock(
    headers,
    initParentId,
    initAccumulatedWork
  );

  it("Initialize", async function () {
    await superblocks
      .connect(user)
      .initialize(
        genesisSuperblock.merkleRoot,
        genesisSuperblock.accumulatedWork,
        genesisSuperblock.timestamp,
        genesisSuperblock.prevTimestamp,
        genesisSuperblock.lastHash,
        genesisSuperblock.lastBits,
        genesisSuperblock.parentId
      );

    const best = await superblocks.getBestSuperblock();
    assert.equal(
      best,
      genesisSuperblock.superblockHash,
      "Best superblock updated"
    );

    const locator = await superblocks.getSuperblockLocator();
    assert.equal(locator.length, 9, "Superblock locator");
    assert.equal(
      locator[0],
      genesisSuperblock.superblockHash,
      "Superblock locator 0"
    );
    assert.equal(
      locator[1],
      genesisSuperblock.superblockHash,
      "Superblock locator 1"
    );
    assert.equal(
      locator[2],
      genesisSuperblock.superblockHash,
      "Superblock locator 2"
    );
    assert.equal(
      locator[8],
      genesisSuperblock.superblockHash,
      "Superblock locator 8"
    );

    const height = await superblocks.getSuperblockHeight(best);
    assert.equal(height, 1, "Superblock height");

    const superblock = await superblocks.getSuperblock(best);
    assert.equal(
      superblock.blocksMerkleRoot,
      genesisSuperblock.merkleRoot,
      "Merkle root"
    );
    assert.equal(
      superblock.accumulatedWork,
      genesisSuperblock.accumulatedWork,
      "Accumulated work"
    );
    assert.equal(
      superblock.timestamp,
      genesisSuperblock.timestamp,
      "Last block timestamp"
    );
    assert.equal(
      superblock.prevTimestamp,
      genesisSuperblock.prevTimestamp,
      "Previous to the last block timestamp"
    );
    assert.equal(
      superblock.lastHash,
      genesisSuperblock.lastHash,
      "Last block hash"
    );
    assert.equal(
      superblock.lastBits,
      genesisSuperblock.lastBits,
      "Last block difficulty bits"
    );
    assert.equal(
      superblock.parentId,
      genesisSuperblock.parentId,
      "Parent superblock"
    );
    assert.equal(superblock.submitter, user.address, "Submitter");
    assert.equal(superblock.status, 4, "Superblock status"); // Approved
  });
});