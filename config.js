const fs = require('fs');

let config = {
  rpcpath: 'http://localhost:8545',
};

try {
  const localConfig = JSON.parse(fs.readFileSync('local_config.json'));
  config = { ...config, ...localConfig };
} catch (ex) {
  // Ignore missing local_config.json
}

module.exports = config;
