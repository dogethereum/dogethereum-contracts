import hre from "hardhat";

import { deployFixture } from "../deploy";

// Mocha root hook for all test suites.
// Note that this was only tested with mocha v7.
// Later versions may require use of root hook plugins or global setup fixtures instead.
before(async function () {
    // We deploy before any test runs to ensure that the first snapshot taken
    // contains the deployed smart contracts.
    // This uses a side effect to work.
    await deployFixture(hre);
});
