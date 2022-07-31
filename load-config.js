let config;
try {
  // @ts-expect-error TS2307: we expect this file may not exist
  config = require('./config');
} catch (e) {
  let fs = require('fs');
  let process = require('process');
  let { join } = require('path');
  let root = process.env.ACTUAL_DATA ?? (fs.existsSync('/data') ? '/data' : __dirname);

  config = {
    mode: 'development',
    port: 5006,
    hostname: '0.0.0.0',
    serverFiles: join(root, 'server-files'),
    userFiles: join(root, 'user-files')
  };
}

module.exports = config;
