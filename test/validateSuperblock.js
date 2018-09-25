const DogeClaimManager = artifacts.require('DogeClaimManager');
const DogeBattleManager = artifacts.require('DogeBattleManager');
const DogeSuperblocks = artifacts.require('DogeSuperblocks');
const ScryptCheckerDummy = artifacts.require('ScryptCheckerDummy');
const utils = require('./utils');

contract('validateSuperblocks', (accounts) => {
  const owner = accounts[0];
  const submitter = accounts[1];
  const challenger = accounts[2];
  let claimManager;
  let superblocks;
  let scryptChecker;
  let scryptVerifier;
  let scryptRunner;

  let ClaimManagerEvents;

  describe('Validation superblock fields', () => {
    let superblock0;
    let superblock1;
    let superblock2;
    let claim1;
    let sessionId;
    let superblockHash;
    let plaintext;

    const genesisHeaders = [
      `03016200ed1775274b69640ff5c197de7fb46222c516c913c0d4229c8b9ee75f48d44176f42a0cdc4b298be486f280afd46ee81af0656eaf604c84cda65be522c7b2d47a9eb958568a93051b0000000001000000010000000000000000000000000000000000000000000000000000000000000000ffffffff4c034fa30d04a0b95856080360f87cfedf0300fabe6d6d4136bc0f5506042fd2bd9e7a6064438ae5a6c41070c91ab88f51f77f1393133f40000000000000000d2f6e6f64655374726174756d2f000000000100f90295000000001976a9145da2560b857f5ba7874de4a1173e67b4d509c46688ac0000000037af78fe582d969a976955e8ebdf132c137fd1e4fa4e1eb5bd65b8a28b4d9bae0000000000060000000000000000000000000000000000000000000000000000000000000000e2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf97d24db2bfa41474bfb2f877d688fac5faa5e10a2808cf9de307370b93352e54894857d3e08918f70395d9206410fbfa942f1a889aa5ab8188ec33c2f6e207dc7103fce20ded169912287c22ecbe0763e2dc5384c5f0df35badf49ea183b60b3649d27f8a11b46c6ba31c62ba3263888e8755c130367592e3a6d69d92b150073238000000030000001b78253b80f240a768a9d74b17bb9e98abd82df96dc42370d14a28a7e1c1bfe24a0e980080e4680e62deffe1bab1db7969d8b49fabcaddba795a1b704af2b25e14b9585651a3011be6741c81`,
      `03016200519b073f01b8e21f9c85f641208532c4b0ea4b6fe1c073d785e98f36368db00230d12c3b1705c2d537dfb7e1bc7752552d90ed58a4de0472811abc7be48c18e5aeb95856bf7b051b0000000001000000010000000000000000000000000000000000000000000000000000000000000000ffffffff48034fa30dfabe6d6dceb3043181029fec3c58d430ccea0653138c0617ab51842024b7dc25877f63f1080000000000000004bab9585608081afdb79a2b0000092f7374726174756d2f000000000100f90295000000001976a91431bde7e496852dac06ff518e111a3adac6c6fba988ac00000000b114dabae52185d04b0b5bda1c12c9c8bd520cc7bad6d97b90a20b9eba9ab7d90000000000030000000000000000000000000000000000000000000000000000000000000000e2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf91521a64399d2cd5db1152d46dabe4781eadbb2ca7bfa59485b79d070a1c9181f00000000030000001b78253b80f240a768a9d74b17bb9e98abd82df96dc42370d14a28a7e1c1bfe2da78d7e7cad0b68c52a05291e777c2b7af5b092ccfde1ab34f21c1971924fc0220b9585651a3011bb52b416a`,
    ];
    const initAccumulatedWork = 0;
    const initParentHash = '0x0000000000000000000000000000000000000000000000000000000000000000';
    const genesisSuperblock = utils.makeSuperblock(genesisHeaders, initParentHash, initAccumulatedWork);

    const headers = [
      `0301620016b7300e237895979caad3d04123b0641240dcac7ee01758456be8f51b68f4e2b456112e2083f097e1a1f3b3e0617e107f1de109ed53ac957c2819930006c2efd4b95856c406051b0000000001000000010000000000000000000000000000000000000000000000000000000000000000ffffffff64034fa30de4b883e5bda9e7a59ee4bb99e9b1bcfabe6d6d5dd639b701320efea34651298f0a4cced16fa7cb9a9a0453a063aa8ac23c571640000000f09f909f4d696e65642062792061733139363430323033380000000000000000000000000000000000010000000100f90295000000001976a914aa3750aa18b8a0f3f0590731e1fab934856680cf88ac6a96e9361841a88789b9dd87ab35fdc191fd625400fcc745a33d87f733280100000000000000000000062900000000000000000000000000000000000000000000000000000000000000463ceed131958d98aee29089d1cf38b9728b224512e51ca3a8b1189d5ed03d0709b68fd6e328528f2a29ec7fb077c834fbf0f14c371fafcfb27444017fbf5b26fdb884bed8ad6a4bded36fc89ed8b05a6c6c0ae1cfd5fe37eb3021b32a1e29042b7a2e142329e7d0d0bffcb5cc338621a576b49d4d32991000b8d4ac793bc1f57d4796a803f909e354b2d08060e2c5fc590f8416351619f2ea57a05ab486307428000000030000001b78253b80f240a768a9d74b17bb9e98abd82df96dc42370d14a28a7e1c1bfe2e4f6aacd1b1897e9887a39f6bc4f839794cf2e75235f83b91883d7c74fe3518ad4b9585651a3011b3947b274`,
    ];
    const hashes = headers.map(header => utils.calcBlockSha256Hash(header));
    const proposedSuperblock = utils.makeSuperblock(headers,
      genesisSuperblock.superblockHash,
      genesisSuperblock.accumulatedWork,
      genesisSuperblock.timestamp,
    );

    beforeEach(async () => {
      ({
        superblocks,
        claimManager,
        battleManager,
        scryptChecker,
      } = await utils.initSuperblockChain({
        dummyChecker: false,
        genesisSuperblock,
        params: utils.SUPERBLOCK_TIMES_DOGE_REGTEST,
        from: owner,
      }));
      superblock0 = genesisSuperblock.superblockHash;
      const best = await superblocks.getBestSuperblock();
      assert.equal(superblock0, best, 'Best superblock should match');
      await claimManager.makeDeposit({ value: 10, from: submitter });
      await claimManager.makeDeposit({ value: 11, from: challenger });

    });
    it('Confirm superblock with one header', async () => {
      result = await claimManager.proposeSuperblock(
        proposedSuperblock.merkleRoot,
        proposedSuperblock.accumulatedWork,
        proposedSuperblock.timestamp,
        proposedSuperblock.prevTimestamp,
        proposedSuperblock.lastHash,
        proposedSuperblock.lastBits,
        proposedSuperblock.parentId,
        { from: submitter },
      );
      const superblockClaimCreatedEvent = utils.findEvent(result.logs, 'SuperblockClaimCreated');
      assert.ok(superblockClaimCreatedEvent, 'New superblock proposed');
      superblock1 = superblockClaimCreatedEvent.args.superblockHash;
      claim1 = superblock1;

      result = await claimManager.challengeSuperblock(superblock1, { from: challenger });
      const superblockClaimChallengedEvent = utils.findEvent(result.logs, 'SuperblockClaimChallenged');
      assert.ok(superblockClaimChallengedEvent, 'Superblock challenged');
      assert.equal(claim1, superblockClaimChallengedEvent.args.superblockHash);
      const verificationGameStartedEvent = utils.findEvent(result.logs, 'VerificationGameStarted');
      assert.ok(verificationGameStartedEvent, 'Battle started');
      session1 = verificationGameStartedEvent.args.sessionId;

      result = await battleManager.queryMerkleRootHashes(superblock1, session1, { from: challenger });
      assert.ok(utils.findEvent(result.logs, 'QueryMerkleRootHashes'), 'Query merkle root hashes');
      result = await battleManager.respondMerkleRootHashes(superblock1, session1, hashes, { from: submitter });
      assert.ok(utils.findEvent(result.logs, 'RespondMerkleRootHashes'), 'Respond merkle root hashes');

      result = await battleManager.queryBlockHeader(superblock1, session1, hashes[0], { from: challenger });
      assert.ok(utils.findEvent(result.logs, 'QueryBlockHeader'), 'Query block header');
      scryptHash = `0x${utils.calcHeaderPoW(headers[0])}`;
      result = await battleManager.respondBlockHeader(superblock1, session1, scryptHash, `0x${headers[0]}`, { from: submitter });
      assert.ok(utils.findEvent(result.logs, 'RespondBlockHeader'), 'Respond block header');

      // Verify superblock
      result = await battleManager.verifySuperblock(session1, { from: submitter });
      assert.ok(utils.findEvent(result.logs, 'ChallengerConvicted'), 'Challenger failed');

      // Confirm superblock
      await utils.blockchainTimeoutSeconds(2*utils.SUPERBLOCK_TIMES_DOGE_REGTEST.TIMEOUT);
      result = await claimManager.checkClaimFinished(superblock1, { from: submitter });
      assert.ok(utils.findEvent(result.logs, 'SuperblockClaimPending'), 'Superblock semi approved');
    });
    it('Reject invalid block bits', async () => {
      result = await claimManager.proposeSuperblock(
        proposedSuperblock.merkleRoot,
        proposedSuperblock.accumulatedWork,
        proposedSuperblock.timestamp,
        proposedSuperblock.prevTimestamp,
        proposedSuperblock.lastHash,
        0, // proposedSuperblock.lastBits,
        proposedSuperblock.parentId,
        { from: submitter },
      );
      const superblockClaimCreatedEvent = utils.findEvent(result.logs, 'SuperblockClaimCreated');
      assert.ok(superblockClaimCreatedEvent, 'New superblock proposed');
      superblock1 = superblockClaimCreatedEvent.args.superblockHash;
      claim1 = superblock1;

      result = await claimManager.challengeSuperblock(superblock1, { from: challenger });
      const superblockClaimChallengedEvent = utils.findEvent(result.logs, 'SuperblockClaimChallenged');
      assert.ok(superblockClaimChallengedEvent, 'Superblock challenged');
      assert.equal(claim1, superblockClaimChallengedEvent.args.superblockHash);
      const verificationGameStartedEvent = utils.findEvent(result.logs, 'VerificationGameStarted');
      assert.ok(verificationGameStartedEvent, 'Battle started');
      session1 = verificationGameStartedEvent.args.sessionId;

      result = await battleManager.queryMerkleRootHashes(superblock1, session1, { from: challenger });
      assert.ok(utils.findEvent(result.logs, 'QueryMerkleRootHashes'), 'Query merkle root hashes');
      result = await battleManager.respondMerkleRootHashes(superblock1, session1, hashes, { from: submitter });
      assert.ok(utils.findEvent(result.logs, 'RespondMerkleRootHashes'), 'Respond merkle root hashes');

      result = await battleManager.queryBlockHeader(superblock1, session1, hashes[0], { from: challenger });
      assert.ok(utils.findEvent(result.logs, 'QueryBlockHeader'), 'Query block header');
      scryptHash = `0x${utils.calcHeaderPoW(headers[0])}`;
      result = await battleManager.respondBlockHeader(superblock1, session1, scryptHash, `0x${headers[0]}`, { from: submitter });
      assert.ok(utils.findEvent(result.logs, 'RespondBlockHeader'), 'Respond block header');

      // Verify superblock
      result = await battleManager.verifySuperblock(session1, { from: challenger });
      const errorBattleEvent = utils.findEvent(result.logs, 'ErrorBattle');
      assert.ok(errorBattleEvent, 'Error verifying superblock');
      assert.equal(errorBattleEvent.args.err, '50130', 'Bad bits');
      assert.ok(utils.findEvent(result.logs, 'SubmitterConvicted'), 'Submitter failed');

      // Confirm superblock
      await utils.blockchainTimeoutSeconds(2*utils.SUPERBLOCK_TIMES_DOGE_REGTEST.TIMEOUT);
      result = await claimManager.checkClaimFinished(superblock1, { from: challenger });
      assert.ok(utils.findEvent(result.logs, 'SuperblockClaimFailed'), 'Superblock rejected');
    });
    it('Reject invalid prev timestamp', async () => {
      result = await claimManager.proposeSuperblock(
        proposedSuperblock.merkleRoot,
        proposedSuperblock.accumulatedWork,
        proposedSuperblock.timestamp,
        0, // proposedSuperblock.prevTimestamp,
        proposedSuperblock.lastHash,
        proposedSuperblock.lastBits,
        proposedSuperblock.parentId,
        { from: submitter },
      );
      const superblockClaimCreatedEvent = utils.findEvent(result.logs, 'SuperblockClaimCreated');
      assert.ok(superblockClaimCreatedEvent, 'New superblock proposed');
      superblock1 = superblockClaimCreatedEvent.args.superblockHash;
      claim1 = superblock1;

      result = await claimManager.challengeSuperblock(superblock1, { from: challenger });
      const superblockClaimChallengedEvent = utils.findEvent(result.logs, 'SuperblockClaimChallenged');
      assert.ok(superblockClaimChallengedEvent, 'Superblock challenged');
      assert.equal(claim1, superblockClaimChallengedEvent.args.superblockHash);
      const verificationGameStartedEvent = utils.findEvent(result.logs, 'VerificationGameStarted');
      assert.ok(verificationGameStartedEvent, 'Battle started');
      session1 = verificationGameStartedEvent.args.sessionId;

      result = await battleManager.queryMerkleRootHashes(superblock1, session1, { from: challenger });
      assert.ok(utils.findEvent(result.logs, 'QueryMerkleRootHashes'), 'Query merkle root hashes');
      result = await battleManager.respondMerkleRootHashes(superblock1, session1, hashes, { from: submitter });
      assert.ok(utils.findEvent(result.logs, 'RespondMerkleRootHashes'), 'Respond merkle root hashes');

      result = await battleManager.queryBlockHeader(superblock1, session1, hashes[0], { from: challenger });
      assert.ok(utils.findEvent(result.logs, 'QueryBlockHeader'), 'Query block header');
      scryptHash = `0x${utils.calcHeaderPoW(headers[0])}`;
      result = await battleManager.respondBlockHeader(superblock1, session1, scryptHash, `0x${headers[0]}`, { from: submitter });
      assert.ok(utils.findEvent(result.logs, 'RespondBlockHeader'), 'Respond block header');

      // Verify superblock
      result = await battleManager.verifySuperblock(session1, { from: challenger });
      const errorBattleEvent = utils.findEvent(result.logs, 'ErrorBattle');
      assert.ok(errorBattleEvent, 'Error verifying superblock');
      assert.equal(errorBattleEvent.args.err, '50035', 'Bad timestamp');
      assert.ok(utils.findEvent(result.logs, 'SubmitterConvicted'), 'Submitter failed');

      // Confirm superblock
      await utils.blockchainTimeoutSeconds(2*utils.SUPERBLOCK_TIMES_DOGE_REGTEST.TIMEOUT);
      result = await claimManager.checkClaimFinished(superblock1, { from: challenger });
      assert.ok(utils.findEvent(result.logs, 'SuperblockClaimFailed'), 'Superblock rejected');
    });
    it('Reject invalid timestamp', async () => {
      result = await claimManager.proposeSuperblock(
        proposedSuperblock.merkleRoot,
        proposedSuperblock.accumulatedWork,
        proposedSuperblock.timestamp + 1,
        proposedSuperblock.prevTimestamp,
        proposedSuperblock.lastHash,
        proposedSuperblock.lastBits,
        proposedSuperblock.parentId,
        { from: submitter },
      );
      const superblockClaimCreatedEvent = utils.findEvent(result.logs, 'SuperblockClaimCreated');
      assert.ok(superblockClaimCreatedEvent, 'New superblock proposed');
      superblock1 = superblockClaimCreatedEvent.args.superblockHash;
      claim1 = superblock1;

      result = await claimManager.challengeSuperblock(superblock1, { from: challenger });
      const superblockClaimChallengedEvent = utils.findEvent(result.logs, 'SuperblockClaimChallenged');
      assert.ok(superblockClaimChallengedEvent, 'Superblock challenged');
      assert.equal(claim1, superblockClaimChallengedEvent.args.superblockHash);
      const verificationGameStartedEvent = utils.findEvent(result.logs, 'VerificationGameStarted');
      assert.ok(verificationGameStartedEvent, 'Battle started');
      session1 = verificationGameStartedEvent.args.sessionId;

      result = await battleManager.queryMerkleRootHashes(superblock1, session1, { from: challenger });
      assert.ok(utils.findEvent(result.logs, 'QueryMerkleRootHashes'), 'Query merkle root hashes');
      result = await battleManager.respondMerkleRootHashes(superblock1, session1, hashes, { from: submitter });
      assert.ok(utils.findEvent(result.logs, 'RespondMerkleRootHashes'), 'Respond merkle root hashes');

      result = await battleManager.queryBlockHeader(superblock1, session1, hashes[0], { from: challenger });
      assert.ok(utils.findEvent(result.logs, 'QueryBlockHeader'), 'Query block header');
      scryptHash = `0x${utils.calcHeaderPoW(headers[0])}`;
      result = await battleManager.respondBlockHeader(superblock1, session1, scryptHash, `0x${headers[0]}`, { from: submitter });
      assert.ok(utils.findEvent(result.logs, 'RespondBlockHeader'), 'Respond block header');

      // Verify superblock
      result = await battleManager.verifySuperblock(session1, { from: challenger });
      const errorBattleEvent = utils.findEvent(result.logs, 'ErrorBattle');
      assert.ok(errorBattleEvent, 'Error verifying superblock');
      assert.equal(errorBattleEvent.args.err, '50035', 'Bad timestamp');
      assert.ok(utils.findEvent(result.logs, 'SubmitterConvicted'), 'Submitter failed');

      // Confirm superblock
      await utils.blockchainTimeoutSeconds(2*utils.SUPERBLOCK_TIMES_DOGE_REGTEST.TIMEOUT);
      result = await claimManager.checkClaimFinished(superblock1, { from: challenger });
      assert.ok(utils.findEvent(result.logs, 'SuperblockClaimFailed'), 'Superblock rejected');
    });
    it('Reject invalid last hash', async () => {
      result = await claimManager.proposeSuperblock(
        proposedSuperblock.merkleRoot,
        proposedSuperblock.accumulatedWork,
        proposedSuperblock.timestamp + 1,
        proposedSuperblock.prevTimestamp,
        0, // proposedSuperblock.lastHash,
        proposedSuperblock.lastBits,
        proposedSuperblock.parentId,
        { from: submitter },
      );
      const superblockClaimCreatedEvent = utils.findEvent(result.logs, 'SuperblockClaimCreated');
      assert.ok(superblockClaimCreatedEvent, 'New superblock proposed');
      superblock1 = superblockClaimCreatedEvent.args.superblockHash;
      claim1 = superblock1;

      result = await claimManager.challengeSuperblock(superblock1, { from: challenger });
      const superblockClaimChallengedEvent = utils.findEvent(result.logs, 'SuperblockClaimChallenged');
      assert.ok(superblockClaimChallengedEvent, 'Superblock challenged');
      assert.equal(claim1, superblockClaimChallengedEvent.args.superblockHash);
      const verificationGameStartedEvent = utils.findEvent(result.logs, 'VerificationGameStarted');
      assert.ok(verificationGameStartedEvent, 'Battle started');
      session1 = verificationGameStartedEvent.args.sessionId;

      result = await battleManager.queryMerkleRootHashes(superblock1, session1, { from: challenger });
      assert.ok(utils.findEvent(result.logs, 'QueryMerkleRootHashes'), 'Query merkle root hashes');
      result = await battleManager.respondMerkleRootHashes(superblock1, session1, hashes, { from: submitter });
      const errorBattleEvent = utils.findEvent(result.logs, 'ErrorBattle');
      assert.ok(errorBattleEvent, 'Respond merkle root hashes');
      assert.equal(errorBattleEvent.args.err, '50150', 'Bad last hash');

      await utils.blockchainTimeoutSeconds(2*utils.SUPERBLOCK_TIMES_DOGE_REGTEST.TIMEOUT);
      result = await battleManager.timeout(session1, { from: challenger });
      assert.ok(utils.findEvent(result.logs, 'SubmitterConvicted'), 'Submitter failed');

      result = await claimManager.checkClaimFinished(superblock1, { from: challenger });
      assert.ok(utils.findEvent(result.logs, 'SuperblockClaimFailed'), 'Superblock rejected');
    });
  });
});
