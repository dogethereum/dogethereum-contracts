// 140 = 128 + 12 = 16*8 + 12 = 0x8c
const fs = require('fs');
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
        let claimManager;
        
        let dogeSuperblocksJSON = fs.readFileSync('./build/contracts/DogeSuperblocks.json', 'utf8');
        let dogeSuperblocksParsedJSON = JSON.parse(dogeSuperblocksJSON);
        let networks = dogeSuperblocksParsedJSON['networks'];
        let networkKey = Object.keys(networks)[0];
        let dogeSuperblocksAddress = networks[networkKey].address;
        
        // let dogeClaimManagerJSON = fs.readFileSync('./build/contracts/DogeClaimManager.json', 'utf8');
        // let dogeClaimManagerParsedJSON = JSON.parse(dogeClaimManagerJSON);
        // networks = dogeClaimManagerParsedJSON['networks'];
        // let claimManagerAddress = networks[networkKey].address;
        let claimManagerAddress;
        
        before(async() => {
            dogeSuperblocks = await DogeSuperblocks.at(dogeSuperblocksAddress);
            claimManagerAddress = await dogeSuperblocks.claimManager.call();
            claimManager = await DogeClaimManager.at(claimManagerAddress);
            
            // console.log(dogeSuperblocksAddress, claimManagerAddress);
            // await dogeSuperblocks.setClaimManager(claimManagerAddress);
        });
    
        let merkleRoot;
        let chainWork;
        let lastDogeBlockTime;
        let lastDogeBlockHash;
        let parentId;
        let superblockId;

        let bestSuperblock;
        let dogeSuperblocksClaimManager;
    
        it('Superblock 1', async() => {
            bestSuperblock = await dogeSuperblocks.getBestSuperblock();
            console.log(bestSuperblock);
            dogeSuperblocksClaimManager = await dogeSuperblocks.claimManager;
            
            await utils.mineBlocks(web3, 5);
            await claimManager.checkClaimFinished(superblock1Id);
            await utils.mineBlocks(web3, 5);
    
            merkleRoot = await dogeSuperblocks.getSuperblockMerkleRoot(superblock1Id);
            chainWork = await dogeSuperblocks.getSuperblockAccumulatedWork(superblock1Id);
            lastDogeBlockTime = await dogeSuperblocks.getSuperblockTimestamp(superblock1Id);
            lastDogeBlockHash = await dogeSuperblocks.getSuperblockLastHash(superblock1Id);
            parentId = await dogeSuperblocks.getSuperblockParentId(superblock1Id);
    
            assert.equal(merkleRoot, superblock1MerkleRoot, "Superblock 1 Merkle root does not match");
            assert.equal(chainWork.toNumber(), superblock1ChainWork, "Superblock 1 chain work does not match");
            assert.equal(lastDogeBlockTime, superblock1LastDogeBlockTime, "Superblock 1 last Doge block time does not match");
            assert.equal(lastDogeBlockHash, superblock1LastDogeBlockHash, "Superblock 1 last Doge block hash does not match");
            assert.equal(parentId, superblock1ParentId, "Superblock 1 parent ID does not match");
        });
    });
});