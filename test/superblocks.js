const crypto = require('crypto');
const keccak256 = require('js-sha3').keccak256;
const utils = require('./utils');
const Superblocks = artifacts.require('Superblocks');

contract('Superblocks', (accounts) => {
  let superblocks;
  before(async () => {
    superblocks = await Superblocks.deployed();
  });
  describe('Utils', () => {
    let hash;
    const zeroHashes = [];
    const oneHash = [
      "0x57a8a9a8de6131bf61f5d385318c10e29a5d826eed6adbdbeedc3a0539908ed4"
    ];
    const twoHashes = [
      "0x2e6e9539f02088efe5abb7082bb6e8ba8df68e1cca543af48f5cc93523bf7209",
      "0x5db4c5556edb6dffe30eb26811327678a54f74b7a3072f2834472ea30ee17360"
    ];
    const threeHashes = [
      "0x6bbe42a26ec5af04eb16da92131ddcd87df55d629d940eaa8f88c0ceb0b9ede6",
      "0xc2213074ba6cf84780030f9dc261fa31999c039811516aaf0fb8fd1e1a9fa0c3",
      "0xde3d260197746a0b509ffa4e05cc8b042f0a0ce472c20d75e17bf58815d395e1"
    ];
    const manyHashes = [
      "0xb2d645742da1443e2439dfe1ee5901aa74680ddd2f11be203595673be5cfc396",
      "0x75520841e64a8acdd669e453d0a55caa7082a35ec6406cf5e73b30cdf34ad0b6",
      "0x6a4a7fdf807e56a39ca842d3e3807e6639af4cf1d05cf6da6154a0b5170f7690",
      "0xde3d260197746a0b509ffa4e05cc8b042f0a0ce472c20d75e17bf58815d395e1",
      "0x6bbe42a26ec5af04eb16da92131ddcd87df55d629d940eaa8f88c0ceb0b9ede6",
      "0x50ab8816b4a1ffa5700ff26bb1fbacce5e3cb93978e57410cfabbe8819a45a4e",
      "0x2e6e9539f02088efe5abb7082bb6e8ba8df68e1cca543af48f5cc93523bf7209",
      "0x57a8a9a8de6131bf61f5d385318c10e29a5d826eed6adbdbeedc3a0539908ed4",
      "0xceace0419d93c9789498de2ed1e75db53143b730f18cff88660297759c719231",
      "0x0ce3bcd684f4f795e549a2ddd1f4c539e8d80813b232a448c56d6b28b74fe3ed",
      "0x5db4c5556edb6dffe30eb26811327678a54f74b7a3072f2834472ea30ee17360",
      "0x03d7be19e9e961691712fde9fd87b706c7d0768a207b84ef6ad1f81ffa90dec5",
      "0x8e5e221b22795d96d3de1cad930d7b131f37b6b9dfcccd3f745b08e6900ef1bd",
      "0xc2213074ba6cf84780030f9dc261fa31999c039811516aaf0fb8fd1e1a9fa0c3",
      "0x38d3dffed604f5a160b327ecde5147eb1aa46e3d154b98644cd2a39f0f9ab915"
    ]
    it('Make merkle', async () => {
      hash = await superblocks.makeMerkle(zeroHashes);
      assert.equal(hash, utils.makeMerkle(zeroHashes), 'Empty hashes array');
      hash = await superblocks.makeMerkle(oneHash);
      assert.equal(hash, utils.makeMerkle(oneHash), 'One hash array');
      hash = await superblocks.makeMerkle(twoHashes);
      assert.equal(hash, utils.makeMerkle(twoHashes), 'Two hashes array');
      hash = await superblocks.makeMerkle(threeHashes);
      assert.equal(hash, utils.makeMerkle(threeHashes), 'Three hashes array');
      hash = await superblocks.makeMerkle(manyHashes);
      assert.equal(hash, utils.makeMerkle(manyHashes), 'Many hashes array');
    });
    it('Superblock id', async () => {
      const superblockId = "0x4b93573044c1acca678af19f594129417cebe5b048eb5323d3ce542ba07387a6";
      const merkleRoot = "0xbc89818e52613f36d6cea2edba2c9417f01ee910250dbd85a8647a92e655996b";
      const accumulatedWork = "0x0000000000000000000000000000000000000000000000000000000000000001";
      const timestamp = "0x000000000000000000000000000000000000000000000000000000005ada05b9";
      const lastHash = "0xe0dd609916339ee7e12272cf5467cf5915d2d41a16816e7118116fb281337367";
      const parentId = "0xe70a134b97a4381e5b6c1f4ae0e1e3726b7284bf03506afacebf92401e255e97";
      const id = await superblocks.calcSuperblockId(merkleRoot, accumulatedWork, timestamp, lastHash, parentId);
      assert.equal(id, superblockId, "SuperblockId should match");
    });
  });
  describe('Statuses', () => {
    let id0;
    let id1;
    let id2;
    let id3;
    const merkleRoot = utils.makeMerkle([]);
    const accumulatedWork = 0;
    const timestamp = (new Date()).getTime() / 1000;
    const lastHash = '0x00';
    const parentHash = '0x00';
    it('Initialized', async () => {
      const result = await superblocks.initialize(merkleRoot, accumulatedWork, timestamp, lastHash, parentHash);
      assert.equal(result.logs[0].event, 'NewSuperblock', 'New superblock proposed');
      id0 = result.logs[0].args.superblockId;
    });
    it('Propose', async () => {
      const result = await superblocks.propose(merkleRoot, accumulatedWork, timestamp, lastHash, id0);
      assert.equal(result.logs[0].event, 'NewSuperblock', 'New superblock proposed');
      id1 = result.logs[0].args.superblockId;
    });
    it('Bad propose', async () => {
      const result = await superblocks.propose(merkleRoot, accumulatedWork, timestamp, lastHash, id0);
      assert.equal(result.logs[0].event, 'ErrorSuperblock', 'Superblock already exists');
    });
    it('Approve', async () => {
      const result = await superblocks.confirm(id1);
      assert.equal(result.logs[0].event, 'ApprovedSuperblock', 'Superblock confirmed');
    });
    it('Propose bis', async () => {
      const result = await superblocks.propose(merkleRoot, accumulatedWork, timestamp, lastHash, id1);
      assert.equal(result.logs[0].event, 'NewSuperblock', 'New superblock proposed');
      id2 = result.logs[0].args.superblockId;
    });
    it('Challenge', async () => {
      const result = await superblocks.challenge(id2);
      assert.equal(result.logs[0].event, 'ChallengeSuperblock', 'Superblock challenged');
    });
    it('Semi-Approve', async () => {
      const result = await superblocks.semiApprove(id2);
      assert.equal(result.logs[0].event, 'SemiApprovedSuperblock', 'Superblock semi-approved');
    });
    it('Approve bis', async () => {
      const result = await superblocks.confirm(id2);
      assert.equal(result.logs[0].event, 'ApprovedSuperblock', 'Superblock confirmed');
    });
    it('Invalidate bad', async () => {
      const result = await superblocks.invalidate(id2);
      assert.equal(result.logs[0].event, 'ErrorSuperblock', 'Superblock cannot invalidate');
    });
    it('Propose tris', async () => {
      const result = await superblocks.propose(merkleRoot, accumulatedWork, timestamp, lastHash, id2);
      assert.equal(result.logs[0].event, 'NewSuperblock', 'New superblock proposed');
      id3 = result.logs[0].args.superblockId;
    });
    it('Challenge bis', async () => {
      const result = await superblocks.challenge(id3);
      assert.equal(result.logs[0].event, 'ChallengeSuperblock', 'Superblock challenged');
    });
    it('Invalidate', async () => {
      const result = await superblocks.invalidate(id3);
      assert.equal(result.logs[0].event, 'InvalidSuperblock', 'Superblock invalidated');
    });
    it('Approve bad', async () => {
      const result = await superblocks.confirm(id3);
      assert.equal(result.logs[0].event, 'ErrorSuperblock', 'Superblock cannot approve');
    });
  });
});
