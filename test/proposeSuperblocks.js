// 140 = 128 + 12 = 16*8 + 12 = 0x8c
const utils = require('./utils');
const DogeSuperblocks = artifacts.require('DogeSuperblocks');
const DogeClaimManager = artifacts.require('DogeClaimManager');

let superblock1MerkleRoot = "0xda61d5c5561ad22bfb3e47e101e35ff4bc22fd15b7656bee8049e00ace2442ab";
let superblock1ChainWork = "0x8c";
let superblock1LastDogeBlockTime = 1522097137;
let superblock1LastDogeBlockHash = "0x31ef1f22a3a22838c4ada500b8240e9ca773d9d1da811c0210c7afce9bd7a46e";
let superblock1ParentId = "0x381be106bf5ac501957c128936ada535c863dcdb1f34180346979650df9f3e76";
let superblock1Id = "0x50cab91de36f8e3b04cf224bce69c06d80b109a380f3d16c94e661e254e5af82";

contract('DogeSuperblocks', (accounts) => {
    describe.skip('Superblock proposal integration test', function() {
        let dogeSuperblocks;
        const claimManager = accounts[1];
        
        before(async() => {
            dogeSuperblocks = await DogeSuperblocks.new();
            await dogeSuperblocks.setClaimManager(claimManager);
        });
    
        let merkleRoot;
        let chainWork;
        let lastDogeBlockTime;
        let lastDogeBlockHash;
        let parentId;
        let superblockId;
    
        it('Superblock 1', async() => {
            await claimManager.checkClaimFinished(superblock1Id, {from: accounts[2]});
    
            merkleRoot = await dogeSuperblocks.getSuperblockMerkleRoot(superblock1Id);
            chainWork = await dogeSuperblocks.getSuperblockAccumulatedWork(superblock1Id);
            lastDogeBlockTime = await dogeSuperblocks.getSuperblockTimestamp(superblock1Id);
            lastDogeBlockHash = await dogeSuperblocks.getSuperblockLastHash(superblock1Id);
            parentId = await dogeSuperblocks.getSuperblockParentId(superblock1Id);
    
            assert.equal(merkleRoot, superblock1MerkleRoot, "Superblock 1 Merkle root does not match");
            assert.equal(chainWork, superblock1ChainWork, "Superblock 1 chain work does not match");
            assert.equal(lastDogeBlockTime, superblock1LastDogeBlockTime, "Superblock 1 last Doge block time does not match");
            assert.equal(lastDogeBlockHash, superblock1LastDogeBlockHash, "Superblock 1 last Doge block hash does not match");
            assert.equal(parentId, superblock1ParentId, "Superblock 1 parent ID does not match");
        });
    });
});