'use strict'

// ENV VARS:
//
// RANGE_MIN
// RANGE_MAX
// INTERVAL
// HOST
const dgram = require('dgram');
const RANGE_MIN = parseInt(process.env.RANGE_MIN);
const RANGE_MAX = parseInt(process.env.RANGE_MAX);
const HOST = process.env.HOST;
const CONNECTION_TIMEOUT = 10000;

if (!RANGE_MIN || isNaN(RANGE_MIN) || !RANGE_MAX || isNaN(RANGE_MAX)) {
  console.error("Invalid port range");
  return process.exit(0);
}

const INTERVAL = parseInt(process.env.INTERVAL) || 10;
const targets = [];

let COUNTER = 0;
let EXPECTED = Math.round((RANGE_MAX - RANGE_MIN)/INTERVAL);
console.log(`Checking range ${RANGE_MIN}:${RANGE_MAX}. Expect output near: ${EXPECTED}`);

const isOpen = (port) => {
  let socket;

  const closeSocket = () => {
    if (socket && socket.close) {
      try {
        socket.close((err) => {
          //ignore;
          return;
        });
      } catch (err) {
        //ignore;
        return;

      }
    }
  }

  const pingPong = () => {
    return new Promise((resolve) => {
      socket = dgram.createSocket('udp4');
      socket.on('error', (err) => {
        closeSocket();
        return resolve(false);
      });
      socket.on('message', (msg, rinfo) => {
        if (msg == 'pong') {
          COUNTER++;
          console.debug(`${HOST}:${port}/udp is OPEN`);
          closeSocket();
          return resolve(true);
        }
      });

      socket.send('ping', port, HOST);
    });
  }

  const failOver = () => {
    return new Promise((resolve) => {
      setTimeout(() => {
        closeSocket();
        return resolve(false)
      }, CONNECTION_TIMEOUT);
    });
  };

  return Promise.race([pingPong(), failOver()]);
};

let port = RANGE_MIN;
while (port < RANGE_MAX) {
  targets.push(port);
  port += INTERVAL;
}

const chain = targets.map(p => isOpen(p));

Promise.all(chain).then(() => {
  console.log(`OPEN: ${COUNTER}`);

  if (COUNTER < EXPECTED * 0.9) {
    process.exit(1);
  } else {
    process.exit(0);
  }
});
