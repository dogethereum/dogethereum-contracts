const DogeRelay = artifacts.require('DogeRelay');
const Set = artifacts.require('Set');
const DogeToken = artifacts.require('DogeToken');
const DogeTx = artifacts.require('DogeTx');
const ClaimManager = artifacts.require('ClaimManager')
const ScryptVerifier = artifacts.require('ScryptVerifier')
const ScryptRunner = artifacts.require('ScryptRunner')

const dogethereumRecipient = '0x0000000000000000000000000000000000000003';

async function makeDeploy(deployer, network, accounts) {
  try {
    await deployer.deploy(Set);
    await deployer.link(Set, DogeToken);
    await deployer.deploy(DogeTx);
    await deployer.link(DogeTx, DogeToken);

    await deployer.deploy(DogeRelay, 0);
    await deployer.deploy(DogeToken, DogeRelay.address, dogethereumRecipient);

    await deployer.deploy(ScryptVerifier);
    await deployer.deploy(ClaimManager, ScryptVerifier.address);

    const dogeRelay = DogeRelay.at(DogeRelay.address);
    await dogeRelay.setScryptChecker(ClaimManager.address);

    const claimManager = ClaimManager.at(ClaimManager.address);
    await claimManager.setDogeRelay(DogeRelay.address);
  } catch (err) {
    console.log(err);
    throw err;
  }
}

module.exports = (deployer, network, accounts) => {
  deployer.then(async () => {
    await makeDeploy(deployer, network, accounts);
  });
};
