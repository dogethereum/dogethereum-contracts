// Idea: propose descendants and see if they should get invalidated as well

const utils = require('./utils');

const SEMI_APPROVED = 3;
const INVALID = 5;

contract('rejectClaim', (accounts) => {
    const owner = accounts[0];
    const submitter = accounts[1];
    const challenger = accounts[2];
    let claimManager;
    let battleManager;
    let superblocks;
    let scryptChecker;
    const initParentId = '0x0000000000000000000000000000000000000000000000000000000000000000';
    const initAccumulatedWork = 0;

    const superblock0Headers = [
        `010000000000000000000000000000000000000000000000000000000000000000000000696ad20e2dd4365c7459b4a4a5af743d5e92c6da3229e6532cd605f6533f2a5bdae5494dffff7f20020000000101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff1004ffff001d0104084e696e746f6e646fffffffff010058850c020000004341040184710fa689ad5023690c80f3a49c8f13f8d45b8c857fbcbc8bc4a8e4d3eb4b10f4d4604fa08dce601aaf0f470216fe1b51850b4acf21b179c45070ac7b03a9ac00000000`
    ];
    const superblock1Headers = [
        `03006200a573e91c1772076c0d40f70e4408c83a31705f296ae6e7629d4adcb5a360213dab28b02ecdb9232639dd1dbb9b600792522dc8e9bc646bc5c5f9937f78d9c8af924a7c5bffff7f20000000000101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff03510101ffffffff0100203d88792d00002321032af59b4b1ee8905f7f0a05b21e4b9ee2544426943166fb5b6514eb60c9764d2fac00000000`,
        `030062001289cca6cd675bdf850e4797b1c5aa75dfcb08620db6b11fddefe7d501438066e17b3f9241ba68893c84412e58b3e075a3514a9e0bf9a9206422ef9d93e34a9b934a7c5bffff7f20000000000101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff03520101ffffffff0100203d88792d00002321032af59b4b1ee8905f7f0a05b21e4b9ee2544426943166fb5b6514eb60c9764d2fac00000000`,
        `0300620032e6dfc66ff463c418d4374d5abd834be45a38bafaa965f46096749323ab541fe81dc218c6fdbfb9ddd7669988ba61bf36274e313e76fd286f5da68ff4ae5a71934a7c5bffff7f20010000000101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff03530101ffffffff0100203d88792d00002321032af59b4b1ee8905f7f0a05b21e4b9ee2544426943166fb5b6514eb60c9764d2fac00000000`
    ];
    const superblock2Headers = [
        `0300620017ef6b7e38934b15c641779f5d7fcc8e767b351b24cdd93c9a76f32293f516b55a7444496f80f7c8af68f21afd467bd2d7d64236e2d131044064bc4e86f684d3604c7c5bffff7f20030000000101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff03540101ffffffff0100203d88792d00002321032af59b4b1ee8905f7f0a05b21e4b9ee2544426943166fb5b6514eb60c9764d2fac00000000`,
        `030062002bab2afdbf73246dd998c604165d4cbd1bb49f1a3461f49029fe65656f25ec91c3897c75cc8c88e34f6aac5d9e4a2a4e32aaff1919600ab33e77ec6c0b68196c604c7c5bffff7f20000000000101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff03550101ffffffff0100203d88792d00002321032af59b4b1ee8905f7f0a05b21e4b9ee2544426943166fb5b6514eb60c9764d2fac00000000`,
        `03006200a3314bf530a27c1ecb928d10ad01c175544dcea272f4f5d8f83541c8ec68e8834ea79eedc151ff11427c9ad12c500b2a8e1c97cab035ccbcbb5bd2ea2e1de10c604c7c5bffff7f20000000000101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff03560101ffffffff0100203d88792d00002321032af59b4b1ee8905f7f0a05b21e4b9ee2544426943166fb5b6514eb60c9764d2fac00000000`
    ];
    const superblock3Headers = [
        `030062007557fe7044fa73ea104d18275300a418f1f10736d1b77ddda952107476aa3f47ee1ad1d2279ce2b2682647eb7aee3de5ad362fe05a5f2620709cf42db8c84339774d7c5bffff7f20000000000101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff03570101ffffffff0100203d88792d00002321032af59b4b1ee8905f7f0a05b21e4b9ee2544426943166fb5b6514eb60c9764d2fac00000000`,
        `03006200d59a7170a948a2e0b58c31b5cccb79b37686ca0b5a460d65e75273f9bc0d90deb0bbce23de660ab3f1e1b21b6e22919d8cf5e2f6b1de28e11611049f824503a1774d7c5bffff7f20010000000101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff03580101ffffffff0100203d88792d00002321032af59b4b1ee8905f7f0a05b21e4b9ee2544426943166fb5b6514eb60c9764d2fac00000000`,
        `03006200c62f797c15dd491c2bef442d0ba509fc98d47e9ab644ed3809fcabec58ba542f09e6142339f1e34aad3c95f593d66c9fc65f19b3319ec3d8363b9f8c695eab8c774d7c5bffff7f20020000000101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff03590101ffffffff0100203d88792d00002321032af59b4b1ee8905f7f0a05b21e4b9ee2544426943166fb5b6514eb60c9764d2fac00000000`
    ];
    const superblock4Headers = [
        `0300620046cd8831add01fdbfecff0cfaa4df27a50d31e7698f8f72ad11fbe796cf5bb6a646b600c2c0a43db62a71b476d7cf5fc5fe031b441882251dc0c4358d6e748a347e37e5bffff7f20030000000101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff035a0101ffffffff0100203d88792d00002321032af59b4b1ee8905f7f0a05b21e4b9ee2544426943166fb5b6514eb60c9764d2fac00000000`,
        `0300620062e0af0dfea7f405baf7b93caffe7a2dcf0a1168e5756695cbf8c40771d1621a4f016681e909ef55460b29dd99d153216fbddd56c02398720034e51c5ba452e347e37e5bffff7f20020000000101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff035b0101ffffffff0100203d88792d00002321032af59b4b1ee8905f7f0a05b21e4b9ee2544426943166fb5b6514eb60c9764d2fac00000000`,
        `030062002b026da0023e871a35b4a45eefcd24c17994a1ecea1117e24eb405da31c07ab6c338737444918707357e77c3eab47858a8359c7e037c98caa8a37591d546cdde47e37e5bffff7f20000000000101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff035c0101ffffffff0100203d88792d00002321032af59b4b1ee8905f7f0a05b21e4b9ee2544426943166fb5b6514eb60c9764d2fac00000000`
    ]

    const superblockR0Headers = [ superblock1Headers[0], superblock1Headers[1] ]; // this superblock should be semi-approved and then rejected
    const superblockR1Headers = [ superblock1Headers[2] ]; // this superblock should also be semi-approved and then rejected

    const superblockR0Hashes = superblockR0Headers.map(utils.calcBlockSha256Hash);
    const superblockR1Hashes = superblockR1Headers.map(utils.calcBlockSha256Hash);

    const superblock0 = utils.makeSuperblock(superblock0Headers, initParentId, 2);
    const superblock1 = utils.makeSuperblock(superblock1Headers, superblock0.superblockHash, 8);
    const superblock2 = utils.makeSuperblock(superblock2Headers, superblock1.superblockHash, 14);
    const superblock3 = utils.makeSuperblock(superblock3Headers, superblock2.superblockHash, 20);
    const superblock4 = utils.makeSuperblock(superblock4Headers, superblock3.superblockHash, 26);

    const superblockR0 = utils.makeSuperblock(superblockR0Headers, superblock0.superblockHash, 4);
    const superblockR1 = utils.makeSuperblock(superblockR1Headers, superblockR0.superblockHash, 6);

    describe('Propose superblocks and reject fork', () => {
        let superblock0Id;
        let superblock1Id;
        let superblock2Id;
        let superblock3Id;
        let superblockR0Id;

        let session1;

        before(async () => {
            ({
                superblocks,
                claimManager,
                battleManager,
                scryptChecker,
            } = await utils.initSuperblockChain({
                network: utils.DOGE_REGTEST,
                params: utils.OPTIONS_DOGE_REGTEST,
                dummyChecker: true,
                genesisSuperblock: superblock0,
                from: owner,
            }));

            //FIXME: ganache-cli creates the same transaction hash if two account send the same amount
            await claimManager.makeDeposit({ value: utils.DEPOSITS.MIN_PROPOSAL_DEPOSIT, from: submitter });
            await claimManager.makeDeposit({ value: utils.DEPOSITS.MIN_CHALLENGE_DEPOSIT, from: challenger });
        });

        it('Initialized', async () => {
            superblock0Id = superblock0.superblockHash;
            const best = await superblocks.getBestSuperblock();
            assert.equal(superblock0Id, best, 'Best superblock should match');
        });

        // Propose initial superblock
        it('Propose superblock 1', async () => {
            const result = await claimManager.proposeSuperblock(
                superblock1.merkleRoot,
                superblock1.accumulatedWork,
                superblock1.timestamp,
                superblock1.prevTimestamp,
                superblock1.lastHash,
                superblock1.lastBits,
                superblock1.parentId,
                { from: submitter },
            );
            const superblockClaimCreatedEvent = utils.findEvent(result.logs, 'SuperblockClaimCreated');
            assert.ok(superblockClaimCreatedEvent, 'New superblock proposed');
            superblock1Id = superblockClaimCreatedEvent.args.superblockHash;
        });

        it('Confirm superblock 1', async () => {
            await utils.blockchainTimeoutSeconds(2*utils.OPTIONS_DOGE_REGTEST.TIMEOUT);
            const result = await claimManager.checkClaimFinished(superblock1Id, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'SuperblockClaimSuccessful'), 'Superblock challenged');
            const best = await superblocks.getBestSuperblock();
            assert.equal(superblock1Id, best, 'Best superblock should match');
        });

        it('Claim does not exist', async () => {
            const result = await claimManager.rejectClaim(superblockR0.superblockHash, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'ErrorClaim'), 'Claim has not been made');
        });

        // Propose an alternate superblock
        it('Propose fork', async () => {
            const result = await claimManager.proposeSuperblock(
                superblockR0.merkleRoot,
                superblockR0.accumulatedWork,
                superblockR0.timestamp,
                superblockR0.prevTimestamp,
                superblockR0.lastHash,
                superblockR0.lastBits,
                superblockR0.parentId,
                { from: submitter },
            );
            const superblockClaimCreatedEvent = utils.findEvent(result.logs, 'SuperblockClaimCreated')
            assert.ok(superblockClaimCreatedEvent, 'New superblock proposed');
            superblockR0Id = superblockClaimCreatedEvent.args.superblockHash;
        });

        it('Missing confirmations after one superblock', async () => {
            const result = await claimManager.rejectClaim(superblockR0Id, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'ErrorClaim'), 'Error claim not raised despite missing confirmations');
        });

        // Propose two more superblocks
        it('Propose superblock 2', async () => {
            await claimManager.makeDeposit({ value: utils.DEPOSITS.MIN_PROPOSAL_DEPOSIT, from: submitter });
            const result = await claimManager.proposeSuperblock(
                superblock2.merkleRoot,
                superblock2.accumulatedWork,
                superblock2.timestamp,
                superblock2.prevTimestamp,
                superblock2.lastHash,
                superblock2.lastBits,
                superblock2.parentId,
                { from: submitter },
            );
            const superblockClaimCreatedEvent = utils.findEvent(result.logs, 'SuperblockClaimCreated');
            assert.ok(superblockClaimCreatedEvent, 'New superblock proposed');
            superblock2Id = superblockClaimCreatedEvent.args.superblockHash;
        });

        it('Confirm superblock 2', async () => {
            await utils.blockchainTimeoutSeconds(2*utils.OPTIONS_DOGE_REGTEST.TIMEOUT);
            const result = await claimManager.checkClaimFinished(superblock2Id, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'SuperblockClaimSuccessful'), 'Superblock challenged');
            const best = await superblocks.getBestSuperblock();
            assert.equal(superblock2Id, best, 'Best superblock should match');
        });

        it('Missing confirmations after two superblocks', async () => {
            const result = await claimManager.rejectClaim(superblockR0Id, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'ErrorClaim'), 'Error claim not raised despite missing confirmations');
        });

        it('Propose superblock 3', async () => {
            const result = await claimManager.proposeSuperblock(
                superblock3.merkleRoot,
                superblock3.accumulatedWork,
                superblock3.timestamp,
                superblock3.prevTimestamp,
                superblock3.lastHash,
                superblock3.lastBits,
                superblock3.parentId,
                { from: submitter },
            );
            const superblockClaimCreatedEvent = utils.findEvent(result.logs, 'SuperblockClaimCreated');
            assert.ok(superblockClaimCreatedEvent, 'New superblock proposed');
            superblock3Id = superblockClaimCreatedEvent.args.superblockHash;
        });

        it('Confirm superblock 3', async () => {
            await utils.blockchainTimeoutSeconds(2*utils.OPTIONS_DOGE_REGTEST.TIMEOUT);
            const result = await claimManager.checkClaimFinished(superblock3Id, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'SuperblockClaimSuccessful'), 'Superblock challenged');
            const best = await superblocks.getBestSuperblock();
            assert.equal(superblock3Id, best, 'Best superblock should match');
        });

        it('Propose superblock 4', async () => {
            const result = await claimManager.proposeSuperblock(
                superblock4.merkleRoot,
                superblock4.accumulatedWork,
                superblock4.timestamp,
                superblock4.prevTimestamp,
                superblock4.lastHash,
                superblock4.lastBits,
                superblock4.parentId,
                { from: submitter },
            );
            const superblockClaimCreatedEvent = utils.findEvent(result.logs, 'SuperblockClaimCreated');
            assert.ok(superblockClaimCreatedEvent, 'New superblock proposed');
            superblock4Id = superblockClaimCreatedEvent.args.superblockHash;
        });

        it('Confirm superblock 4', async () => {
            await utils.blockchainTimeoutSeconds(2*utils.OPTIONS_DOGE_REGTEST.TIMEOUT);
            const result = await claimManager.checkClaimFinished(superblock4Id, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'SuperblockClaimSuccessful'), 'Superblock challenged');
            const best = await superblocks.getBestSuperblock();
            assert.equal(superblock4Id, best, 'Best superblock should match');
        });

        // This should raise an error because the superblock is neither InBattle nor SemiApproved
        it('Try to reject without challenges', async () => {
            const result = await claimManager.rejectClaim(superblockR0Id);
            assert.ok(utils.findEvent(result.logs, 'ErrorClaim'), 'Error claim not raised despite bad status');
        });

        // Challenge fork
        it('Challenge fork', async () => {
            const result = await claimManager.challengeSuperblock(superblockR0Id, { from: challenger });
            const superblockClaimChallengedEvent = utils.findEvent(result.logs, 'SuperblockClaimChallenged');
            assert.ok(superblockClaimChallengedEvent, 'Superblock challenged');
            assert.equal(superblockR0Id, superblockClaimChallengedEvent.args.superblockHash);
            const verificationGameStartedEvent = utils.findEvent(result.logs, 'VerificationGameStarted');
            assert.ok(verificationGameStartedEvent, 'Battle started');
            session1 = verificationGameStartedEvent.args.sessionId;
        });

        // Don't reject claim if it's undecided
        it('Try to reject undecided claim', async () => {
            const result = await claimManager.rejectClaim(superblockR0Id, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'ErrorClaim'), 'Error claim not raised despite undecided claim');
        });

        it('Query and verify hashes', async () => {
            await claimManager.makeDeposit({ value: utils.DEPOSITS.RESPOND_MERKLE_COST, from: challenger });
            result = await battleManager.queryMerkleRootHashes(superblockR0Id, session1, { from: challenger });
            assert.ok(utils.findEvent(result.logs, 'QueryMerkleRootHashes'), 'Query merkle root hashes');

            await claimManager.makeDeposit({ value: utils.DEPOSITS.VERIFY_SUPERBLOCK_COST, from: submitter });
            result = await battleManager.respondMerkleRootHashes(superblockR0Id, session1, superblockR0Hashes, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'RespondMerkleRootHashes'), 'Respond merkle root hashes');
        });

        it('Query and reply block header', async () => {
            let scryptHash;
            await claimManager.makeDeposit({ value: utils.DEPOSITS.RESPOND_HEADER_COST, from: challenger });
            result = await battleManager.queryBlockHeader(superblockR0Id, session1, superblockR0Hashes[0], { from: challenger });
            assert.ok(utils.findEvent(result.logs, 'QueryBlockHeader'), 'Query block header');

            scryptHash = `0x${utils.calcHeaderPoW(superblockR0Headers[0])}`;
            await claimManager.makeDeposit({ value: utils.DEPOSITS.VERIFY_SUPERBLOCK_COST, from: submitter });
            result = await battleManager.respondBlockHeader(superblockR0Id, session1, scryptHash, `0x${superblockR0Headers[0]}`, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'RespondBlockHeader'), 'Respond block header');

            await claimManager.makeDeposit({ value: utils.DEPOSITS.RESPOND_HEADER_COST, from: challenger });
            result = await battleManager.queryBlockHeader(superblockR0Id, session1, superblockR0Hashes[1], { from: challenger });
            assert.ok(utils.findEvent(result.logs, 'QueryBlockHeader'), 'Query block header');

            scryptHash = `0x${utils.calcHeaderPoW(superblockR0Headers[1])}`;
            await claimManager.makeDeposit({ value: utils.DEPOSITS.VERIFY_SUPERBLOCK_COST, from: submitter });
            result = await battleManager.respondBlockHeader(superblockR0Id, session1, scryptHash, `0x${superblockR0Headers[1]}`, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'RespondBlockHeader'), 'Respond block header');
        });

        it('Verify forked superblock', async () => {
            result = await battleManager.verifySuperblock(session1, { from: challenger });
            assert.ok(utils.findEvent(result.logs, 'ChallengerConvicted'), 'Challenger not convicted despite fork being initially valid');
        });

        // Call rejectClaim on superblocks that aren't semi approved
        it('Try to reject unconfirmed superblock', async () => {
            result = await claimManager.rejectClaim(superblockR0Id, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'ErrorClaim'), 'Error claim not raised despite bad superblock status');
        });

        it('Confirm forked superblock', async () => {
            await utils.blockchainTimeoutSeconds(2*utils.OPTIONS_DOGE_REGTEST.TIMEOUT);
            result = await claimManager.checkClaimFinished(superblockR0Id, { from: challenger });
            assert.ok(utils.findEvent(result.logs, 'SuperblockClaimPending'), 'Superblock challenged');
            const status = await superblocks.getSuperblockStatus(superblockR0Id);
            assert.equal(status.toNumber(), SEMI_APPROVED, 'Superblock was not semi-approved');
        });

        // Propose another superblock in the fork
        it('Propose superblock R1', async () => {
            const result = await claimManager.proposeSuperblock(
                superblockR1.merkleRoot,
                superblockR1.accumulatedWork,
                superblockR1.timestamp,
                superblockR1.prevTimestamp,
                superblockR1.lastHash,
                superblockR1.lastBits,
                superblockR1.parentId,
                { from: submitter },
            );
            assert.equal(result.logs[1].event, 'SuperblockClaimCreated', 'New superblock proposed');
            superblockR1Id = result.logs[1].args.superblockHash;
        });

        it('Confirm superblock R1', async () => {
            await utils.blockchainTimeoutSeconds(2*utils.OPTIONS_DOGE_REGTEST.TIMEOUT);
            const result = await claimManager.checkClaimFinished(superblockR1Id, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'SuperblockClaimPending'), 'Superblock challenged');
            const status = await superblocks.getSuperblockStatus(superblockR1Id);
            assert.equal(status.toNumber(), SEMI_APPROVED, 'Superblock was not semi-approved');
        });

        // Invalidate superblock and reject claim
        it('Reject superblock R0', async () => {
            const result = await claimManager.rejectClaim(superblockR0Id, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'SuperblockClaimFailed'), 'SuperblockClaimFailed event not found');
            assert.ok(utils.findEvent(result.logs, 'DepositUnbonded'), 'DepositUnbonded event not found');
            const status = await superblocks.getSuperblockStatus(superblockR0Id);
            assert.equal(status.toNumber(), INVALID, 'Superblock was not invalidated');
        });

        it('Reject superblock R1', async () => {
            const result = await claimManager.rejectClaim(superblockR1Id, { from: submitter });
            assert.ok(utils.findEvent(result.logs, 'SuperblockClaimFailed'), 'SuperblockClaimFailed event not found');
            const status = await superblocks.getSuperblockStatus(superblockR1Id);
            assert.equal(status.toNumber(), INVALID, 'Superblock was not invalidated');
        });
    });
});
