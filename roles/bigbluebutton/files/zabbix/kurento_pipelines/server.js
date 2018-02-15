/*
 * (C) Copyright 2014-2015 Kurento (http://kurento.org/)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

var path = require('path');
var url = require('url');
var cookieParser = require('cookie-parser')
var express = require('express');
var session = require('express-session')
var minimist = require('minimist');
var ws = require('ws');
var kurento = require('kurento-client');
var fs = require('fs');
var https = require('https');

var argv = minimist(process.argv.slice(1), {
    default: {
        ws_uri: 'ws://127.0.0.1:8888/kurento'
    }
});

/*
 * Definition of global variables.
 */
var kurentoClient = null;
var serverManager = null;
var mediaPipelines = {};
var endpointsCount = 0;

function formatFloat(n) {
    return +n.toFixed(3);
}

getKurentoClient(function (error, kurentoClient) {
    kurentoClient.getServerManager(function (error, server) {
        if (error) {
            console.log("getServerManager failed: " + error);
            return;
        }
        serverManager = server;
        getInfo(serverManager, function (info) {
            var counter = 0;
            var inboundEndpoints = 0;
            var outboundEndpoints = 0;
            var staleEndpoints = 0;
            var stalePipelines = 0;

            var inboundPacketsLostRateList = [];
            var inboundSumPacketsLost = 0;
            var inboundJitterList = [];

            var outboundPacketsLostRateList = [];
            var outboundSumPacketsLost = 0;
            var outboundAvgPacketsLostRate = 0;
            var outboundMaxPacketsLostRate = 0;
            var outboundJitterList = [];
            var outboundAvgJitter = 0;
            var outboundMaxJitter = 0;

            for (var pipelineId in mediaPipelines) {
                var pipeline = mediaPipelines[pipelineId];
                var itemStaleEndpoint = 0;
                for (var mediaEndpointId in pipeline.endpoints) {
                    var mediaEndpoint = pipeline.endpoints[mediaEndpointId];
                    if (mediaEndpoint.mediaFlowingIn == true) {
                        inboundEndpoints++;
                        for (var key in mediaEndpoint.stats) {
                            if (mediaEndpoint.stats[key].hasOwnProperty("packetsLost")) {
                                inboundSumPacketsLost += mediaEndpoint.stats[key].packetsLost
                                if (mediaEndpoint.stats[key].hasOwnProperty("packetsReceived")) {
                                    inboundPacketsLostRateList.push(mediaEndpoint.stats[key].packetsLost / (mediaEndpoint.stats[key].packetsLost + mediaEndpoint.stats[key].packetsReceived));
                                }
                            }
                            if (mediaEndpoint.stats[key].hasOwnProperty("jitter")) {
                                inboundJitterList.push(mediaEndpoint.stats[key].jitter);
                            }
                        }
                    } else if (mediaEndpoint.mediaFlowingOut == true) {
                        outboundEndpoints++;
                        for (var key in mediaEndpoint.stats) {
                            if (mediaEndpoint.stats[key].hasOwnProperty("packetsLost")) {
                                outboundSumPacketsLost += mediaEndpoint.stats[key].packetsLost
                                if (mediaEndpoint.stats[key].hasOwnProperty("packetsSent")) {
                                    outboundPacketsLostRateList.push(mediaEndpoint.stats[key].packetsLost / (mediaEndpoint.stats[key].packetsLost + mediaEndpoint.stats[key].packetsSent));
                                }
                            }
                            if (mediaEndpoint.stats[key].hasOwnProperty("jitter")) {
                                outboundJitterList.push(mediaEndpoint.stats[key].jitter);
                            }
                        }
                    }
                    if (mediaEndpoint.stale == true) {
                        itemStaleEndpoint++;
                    }
                }
                staleEndpoints += itemStaleEndpoint;
                if (Object.keys(pipeline.endpoints).length == itemStaleEndpoint) {
                    stalePipelines++;
                }
            }

            // console.log(JSON.stringify(mediaPipelines, null, 4));

            var output = "pipelines: " + Object.keys(mediaPipelines).length
                + ", stale_pipelines: " + stalePipelines
                + ", endpoints: " + endpointsCount
                + ", inbound_endpoints: " + inboundEndpoints;

            if (inboundPacketsLostRateList.length > 0) {
                let inboundSumPacketsLostRate = inboundPacketsLostRateList.reduce((previous, current) => current += previous);
                let inboundAvgPacketsLostRate = inboundSumPacketsLostRate / inboundPacketsLostRateList.length;
                let inboundMaxPacketsLostRate = Math.max.apply(null, inboundPacketsLostRateList);
                output += ", inbound_avg_packet_loss_rate: " + formatFloat(inboundAvgPacketsLostRate)
                    + ", inbound_max_packet_loss_rate: " + formatFloat(inboundMaxPacketsLostRate)
                    + ", inbound_sum_packet_loss: " + inboundSumPacketsLost;
            }
            if (inboundJitterList.length > 0) {
                let inboundSumJitter = inboundJitterList.reduce((previous, current) => current += previous);
                let inboundAvgJitter = inboundSumJitter / inboundJitterList.length;
                let inboundMaxJitter = Math.max.apply(null, inboundJitterList);
                output += ", inbound_avg_jitter: " + formatFloat(inboundAvgJitter)
                    + ", inbound_max_jitter: " + formatFloat(inboundMaxJitter);
            }

            output += ", outbound_endpoints: " + outboundEndpoints;
            if (outboundPacketsLostRateList.length > 0) {
                let outboundSumPacketsLostRate = outboundPacketsLostRateList.reduce((previous, current) => current += previous);
                let outboundAvgPacketsLostRate = outboundSumPacketsLostRate / outboundPacketsLostRateList.length;
                let outboundMaxPacketsLostRate = Math.max.apply(null, outboundPacketsLostRateList);
                output += ", outbound_avg_packet_loss_rate: " + formatFloat(outboundAvgPacketsLostRate)
                    + ", outbound_max_packet_loss_rate: " + formatFloat(outboundMaxPacketsLostRate)
                    + ", outbound_sum_packet_loss: " + outboundSumPacketsLost;
            }
            if (outboundJitterList.length > 0) {
                let outboundSumJitter = outboundJitterList.reduce((previous, current) => current += previous);
                let outboundAvgJitter = outboundSumJitter / outboundJitterList.length;
                let outboundMaxJitter = Math.max.apply(null, outboundJitterList);
                output += ", outbound_avg_jitter: " + formatFloat(outboundAvgJitter)
                    + ", outbound_max_jitter: " + formatFloat(outboundMaxJitter);
            }

            output += ", stale_endpoints: " + staleEndpoints;

            console.log(output)
            process.exit(0);
        });
    });
});

/*
 * Definition of functions
 */

// Recover kurentoClient for the first time.
function getKurentoClient(callback) {
    if (kurentoClient !== null) {
        return callback(null, kurentoClient);
    }

    kurento(argv.ws_uri, function (error, _kurentoClient) {
        if (error) {
            console.log("Could not find media server at address " + argv.ws_uri);
            return callback("Could not find media server at address" + argv.ws_uri
                + ". Exiting with error " + error);
        }

        kurentoClient = _kurentoClient;
        callback(null, kurentoClient);
    });
}

function getInfo(server, callback) {
    if (!server) {
        return callback('error - failed to find server');
    }

    server.getInfo(function (error, serverInfo) {
        if (error) {
            return callback(error);
        }

        getPipelinesInfo(server, callback);
    })
}

function getAllFuncs(obj) {
    var props = [];

    do {
        props = props.concat(Object.getOwnPropertyNames(obj));
    } while (obj = Object.getPrototypeOf(obj));
    return props.filter(function(elem, pos) {
        return props.indexOf(elem) == pos;
    }).sort();
}

function getPipelinesInfo(server, callback) {
    if (!server) {
        return callback('error - failed to find server');
    }

    server.getPipelines(function (error, pipelines) {
        if (error) {
            return callback(error);
        }

        if (pipelines && (pipelines.length < 1)) {
            return callback(null);
        }

        var counter = 0;
        pipelines.forEach(function (p, index, array) {
            mediaPipelines[p.id] = { "endpoints": {} };
            p.setLatencyStats(true, function (error) {
                if (error) return onError(error);
            })
            // console.log("===> " + JSON.stringify(getAllFuncs(p), null, 4));
            p.getChildren(function (error, elements) {
                endpointsCount += elements.length;
                mediaPipelines[p.id]["hasPlayer"] = elements.length > 1;
                mediaPipelines[p.id]["endpoints"] = {}
                elements.forEach(function (me, index, array) {
                    // console.log("===> " + JSON.stringify(getAllFuncs(me), null, 4));
                    mediaPipelines[p.id]["endpoints"][me.id] = { "endpoint": me };
                    me.isMediaFlowingIn('VIDEO', function (error, result) {
                        if (error) {
                            console.log(error);
                        } else {
                            mediaPipelines[p.id]["endpoints"][me.id]["mediaFlowingOut"] = result;
                        }
                        me.isMediaFlowingOut('VIDEO', function (error, result) {
                            if (error) {
                                console.log(error);
                            } else {
                                mediaPipelines[p.id]["endpoints"][me.id]["mediaFlowingIn"] = result;
                            }
                            me.getStats('VIDEO', function (error, result) {
                                if (error) {
                                    console.log(error);
                                } else {
                                    mediaPipelines[p.id]["endpoints"][me.id]["stats"] = result;
                                }
                                me.getMediaState(function (error, result) {
                                    if (error) {
                                        console.log(error);
                                    } else {
                                        mediaPipelines[p.id]["endpoints"][me.id]["stale"] = result == "DISCONNECTED";
                                    }
                                    // me.getSinkConnections('VIDEO', 'NONE', function (error, result) {
                                    //     if (error) {
                                    //         console.log(error);
                                    //     } else {
                                    //         // console.log("getSinkConnections: " + result);
                                    //     }
                                    //     me.getSourceConnections('VIDEO', 'NONE', function (error, result) {
                                    //         if (error) {
                                    //             console.log(error);
                                    //         } else {
                                    //             // console.log("getSourceConnections: " + result);
                                    //         }
                                            counter++;
                                            if (counter == endpointsCount) {
                                                return callback(error);
                                            }
                                    //     })
                                    // })
                                })
                            })
                        })
                    })
                })
            })
        })
    })
}
