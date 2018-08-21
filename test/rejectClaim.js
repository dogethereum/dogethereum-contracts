// Propose a superblock
// Propose three descendants and approve them
// Propose a single-superblock fork and semi-approve it
// Call rejectClaim on this fork; it should be rejected

// Idea: propose descendants and see if they should get invalidated as well

const utils = require('./utils');
const DogeClaimManager = artifacts.require('DogeClaimManager');
const DogeSuperblocks = artifacts.require('DogeSuperblocks');
const ScryptCheckerDummy = artifacts.require('ScryptCheckerDummy');
const ScryptVerifier = artifacts.require('ScryptVerifier');
const ClaimManager = artifacts.require('ClaimManager');

const SUPERBLOCK_TIMES_DOGE_REGTEST = {
  DURATION: 60,     // 1 minute
  DELAY: 60,        // 1 minute
  TIMEOUT: 5,       // 5 seconds
  CONFIRMATIONS: 2,  // Superblocks required to confirm semi approved superblock
};

const DOGE_MAINNET = 0;
const DOGE_TESTNET = 1;
const DOGE_REGTEST = 2;

contract('rejectClaim', (accounts) => {
    const owner = accounts[0];
    const submitter = accounts[1];
    const challenger = accounts[2];
    let claimManager;
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
    const superblockRHeaders = [
        `03006200a573e91c1772076c0d40f70e4408c83a31705f296ae6e7629d4adcb5a360213d_INSERTMERKLEROOTHERE_924a7c5bffff7f20000000000101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff03510101ffffffff0100203d88792d00002321032af59b4b1ee8905f7f0a05b21e4b9ee2544426943166fb5b6514eb60c9764d2fac00000000`
    ]; // this superblock should be rejected

    const superblock0 = utils.makeSuperblock(superblock0Headers, initParentId, initAccumulatedWork);
    const superblock1 = utils.makeSuperblock(superblock1Headers, superblock0.superblockId, superblock0.accumulatedWork);
    const superblock2 = utils.makeSuperblock(superblock2Headers, superblock1.superblockId, superblock1.accumulatedWork);
    const superblock3 = utils.makeSuperblock(superblock3Headers, superblock2.superblockId, superblock2.accumulatedWork);
    const superblockR = utils.makeSuperblock(superblockRHeaders, superblock0.superblockId, superblock0.accumulatedWork);

    // Copied from claimManager.js
    async function initSuperblocks(dummyChecker, genesisSuperblock) {
        superblocks = await DogeSuperblocks.new();
        claimManager = await DogeClaimManager.new(DOGE_MAINNET, superblocks.address, SUPERBLOCK_TIMES_DOGE_REGTEST.DURATION, SUPERBLOCK_TIMES_DOGE_REGTEST.DELAY, SUPERBLOCK_TIMES_DOGE_REGTEST.TIMEOUT, SUPERBLOCK_TIMES_DOGE_REGTEST.CONFIMATIONS);
        if (dummyChecker) {
            scryptChecker = await ScryptCheckerDummy.new(false);
        } else {
            const scryptVerifier = await ScryptVerifier.new();
            scryptChecker = await ClaimManager.new(scryptVerifier.address);
        }
        await superblocks.setClaimManager(claimManager.address);
        await claimManager.setScryptChecker(scryptChecker.address);
        await superblocks.initialize(
            genesisSuperblock.merkleRoot,
            genesisSuperblock.accumulatedWork,
            genesisSuperblock.timestamp,
            genesisSuperblock.prevTimestamp,
            genesisSuperblock.lastHash,
            genesisSuperblock.lastBits,
            genesisSuperblock.parentId,
            { from: owner },
        );
        //FIXME: ganache-cli creates the same transaction hash if two account send the same amount
        await claimManager.makeDeposit({ value: 10, from: submitter });
        await claimManager.makeDeposit({ value: 11, from: challenger });
    }

    describe.skip('Reject fork', () => {
        let superblock0Id;
        let superblock1Id;
        let superblock2Id;
        let superblock3Id;
        let superblockRId;

        before(async () => {
            await initSuperblocks(true, superblock0);
        });
        
        it('Initialized', async () => {
            superblock0Id = superblock0.superblockId;
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
            assert.equal(result.logs[1].event, 'SuperblockClaimCreated', 'New superblock proposed');
            superblock1Id = result.logs[1].args.superblockId;
        });

        it('Confirm superblock 1', async () => {
            await utils.timeoutSeconds(3*SUPERBLOCK_TIMES_DOGE_REGTEST.TIMEOUT);
            const result = await claimManager.checkClaimFinished(superblock1Id, { from: challenger });
            assert.equal(result.logs[1].event, 'SuperblockClaimSuccessful', 'Superblock challenged');
            const best = await superblocks.getBestSuperblock();
            assert.equal(superblock1Id, best, 'Best superblock should match');
        });

        // Propose two more superblocks
        it('Propose superblock 2', async () => {
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
            assert.equal(result.logs[1].event, 'SuperblockClaimCreated', 'New superblock proposed');
            superblock2Id = result.logs[1].args.superblockId;
        });

        it('Confirm superblock 2', async () => {
            await utils.timeoutSeconds(3*SUPERBLOCK_TIMES_DOGE_REGTEST.TIMEOUT);
            const result = await claimManager.checkClaimFinished(superblock2Id, { from: challenger });
            assert.equal(result.logs[1].event, 'SuperblockClaimSuccessful', 'Superblock challenged');
            const best = await superblocks.getBestSuperblock();
            assert.equal(superblock2Id, best, 'Best superblock should match');
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
            assert.equal(result.logs[1].event, 'SuperblockClaimCreated', 'New superblock proposed');
            superblock3Id = result.logs[1].args.superblockId;
        });

        it('Confirm superblock 3', async () => {
            await utils.timeoutSeconds(3*SUPERBLOCK_TIMES_DOGE_REGTEST.TIMEOUT);
            const result = await claimManager.checkClaimFinished(superblock3Id, { from: challenger });
            assert.equal(result.logs[1].event, 'SuperblockClaimSuccessful', 'Superblock challenged');
            const best = await superblocks.getBestSuperblock();
            assert.equal(superblock3Id, best, 'Best superblock should match');
        });

        // Propose an alternate superblock
        it('Propose fork', async () => {
            const result = await claimManager.proposeSuperblock(
                superblockR.merkleRoot,
                superblockR.accumulatedWork,
                superblockR.timestamp,
                superblockR.prevTimestamp,
                superblockR.lastHash,
                superblockR.lastBits,
                superblockR.parentId,
                { from: submitter },
            );
            assert.equal(result.logs[1].event, 'SuperblockClaimCreated', 'New superblock proposed');
            superblockRId = result.logs[1].args.superblockId;
        });

        // Invalidate alternate superblock
        it('Reject fork', async () => {
            const result = await claimManager.rejectClaim(superblockRId);
            assert.equal(result.logs[0].event, 'InvalidSuperblock', 'Superblock invalidated');
            assert.equal(result.logs[1].event, 'SuperblockClaimFailed', 'Superblock claim failed');
        });
    });
});