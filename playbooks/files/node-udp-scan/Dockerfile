FROM node:12-alpine

ENV RANGE_MIN 1000
ENV RANGE_MAX 2000
ENV INTERVAL 50
ENV HOST localhost

WORKDIR /usr/src/app
COPY node-udp-scan.js .

CMD [ "node", "node-udp-scan.js" ]
