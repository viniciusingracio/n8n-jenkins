'use strict'

const dgram = require('dgram');
const RANGE_MIN = parseInt(process.env.RANGE_MIN);
const RANGE_MAX = parseInt(process.env.RANGE_MAX);

if (!RANGE_MIN || isNaN(RANGE_MIN) || !RANGE_MAX || isNaN(RANGE_MAX)) {
  console.error("Invalid port range");
  return process.exit(1);
}
const INTERVAL = parseInt(process.env.INTERVAL) || 10;
const sockets = [];

const cleanup = () => {
  console.log("Cleaning up!")
  sockets.forEach(socket => {
    socket.close();
  });
};

let port = RANGE_MIN;
while (port < RANGE_MAX) {
  const socket = dgram.createSocket('udp4');
  socket.on('error', (err) => {
    console.error(`Socket error on port ${port}: \n${err.stack}`);
    socket.close();
  });
  socket.on('message', (msg, rinfo) => {
    const { address, port } = rinfo;
    console.log(`inbound: ${msg} from ${address}:${port} to ${socket.address().port}`);
    if (msg == 'ping') {
      socket.send('pong', port, address);
    }
  });

  try {
    socket.bind(port);
    sockets.push(socket);
  } catch(e) {
    console.log("Failed to bind port: " + e.stack);
  }
  port += INTERVAL;
}

process.on('SIGTERM', cleanup);
process.on('SIGINT', cleanup);
