include("phone-format.min.js");
include("sha.js");
include("bigbluebutton-api.js");
include("mconf_redirect_conf.js");
use("CURL");
use("XML");

const called_number = argv[0]; // the called number as typed
const source_addr = argv[1];
const caller_name = argv[2];
const sip_user_agent = argv[3];
const curl = new CURL();
var success = false;

console_log("INFO", "[MCONF-SIP-PROXY] IP " + source_addr + " dialing to " + called_number + "\n");

function getMeetingsCallback(body, callback_args) {
    var bbb_api = callback_args[0];
    var response = new XML(body);
    var return_code = response.getChild('returncode').data;
    if (return_code != "SUCCESS") {
        console_log("ERROR", "[MCONF-SIP-PROXY] Failed to get meetings, return code " + return_code + "\n");
        return true;
    } else {
        console_log("INFO", "[MCONF-SIP-PROXY] Meetings successfully fetched\n");
    }

    var child = response.getChild('meetings').getChild('meeting');
    var match;
    var meeting;
    while (child) {
        meeting = {
            id: getMeetingId(child),
            dial_number: getDialNumber(child),
            voice_bridge: getVoiceBridge(child),
            name: getMeetingName(child),
            moderator_password: getModeratorPassword(child),
            server_address: getServerAddress(child),
        }

        var req = bbb_api.urlFor("getMeetingInfo", {
            meetingID: meeting.id,
            password: meeting.moderator_password,
        });
        curl.run("GET", req.split('?')[0], req.split('?')[1], getMeetingInfoCallback, [ meeting ], null);

        match = matchMeeting(meeting);
        if (match) {
            break;
        }
        child = child.next();
    }

    if (match) {
        registerEvent(meeting, bbb_api);
        success = redirectCall(meeting);
    }
    return true;
}

function getMeetingInfoCallback(body, callback_args) {
    var meeting = callback_args[0];
    var response = new XML(body);
    var return_code = response.getChild('returncode').data;
    if (return_code != "SUCCESS") {
        console_log("ERROR", "[MCONF-SIP-PROXY] Failed to get meeting info, return code " + return_code + "\n");
        return true;
    } else {
        console_log("INFO", "[MCONF-SIP-PROXY] Meeting info successfully fetched\n");
    }

    var child = response.getChild('metadata').getChild('invitation-url');
    if (child) {
        var regexp = /.*\/webconf\/(.*)/g;
        var match = regexp.exec(child.data);
        if (match) {
            meeting.room_identifier = match[1];
        }
    }
}

function matchMeeting(meeting) {
    if (formatE164(default_int_code, called_number) == formatE164(default_int_code, meeting.dial_number)) {
        console_log("INFO", "[MCONF-SIP-PROXY] Match by dialNumber\n"); return true;
    } else if (called_number == meeting.voice_bridge) {
        console_log("INFO", "[MCONF-SIP-PROXY] Match by voiceBridge\n"); return true;
    } else if (called_number == meeting.name) {
        console_log("INFO", "[MCONF-SIP-PROXY] Match by meetingName\n"); return true;
    } else if (called_number == meeting.room_identifier) {
        console_log("INFO", "[MCONF-SIP-PROXY] Match by room identifier\n"); return true;
    }
    return false;
}

function getServerAddress(meeting_xml) {
    return meeting_xml.getChild('server').getChild('address').data;
}

function getMeetingId(meeting_xml) {
    return meeting_xml.getChild('meetingID').data;
}

function getMeetingName(meeting_xml) {
    return meeting_xml.getChild('meetingName').data;
}

function getDialNumber(meeting_xml) {
    return meeting_xml.getChild('dialNumber').data;
}

function getVoiceBridge(meeting_xml) {
    return meeting_xml.getChild('voiceBridge').data;
}

function getModeratorPassword(meeting_xml) {
    return meeting_xml.getChild('moderatorPW').data;
}

function registerEvent(meeting, bbb_api) {
    var fs_version = apiExecute("version", "short").replace("\n", "");

    var sip_proxy_token = "";
    if (sip_proxy_version != "") {
        sip_proxy_token = " MconfSipProxy/" + sip_proxy_version;
    }

    var ua = sip_user_agent + sip_proxy_token + " FreeSWITCH/" + fs_version;

    var params = {
        meetingID: meeting.id,
        name: caller_name,
        role: "attendee",
        userIP: source_addr,
        userAgent: ua
    };
    var req = bbb_api.urlFor("addUserEvent", params, false);
    console_log("INFO", "[MCONF-SIP-PROXY] Registering event: " + req + "\n");
    curl.run("POST", req, "", registerEventCallback, null, null);
}

function registerEventCallback(body, arg) {
    console_log("INFO", "[MCONF-SIP-PROXY] " + body + "\n");
    return true;
}

function redirectCall(meeting) {
    var voice_bridge = meeting.voice_bridge;
    var server_address = meeting.server_address;

    if (server_address == "") {
        console_log("ERROR", "[MCONF-SIP-PROXY] Couldn't find a server to redirect the call\n");
        return false;
    } else {
        console_log("INFO", "[MCONF-SIP-PROXY] Server address: " + server_address + "\n");
    }
    
    var dest_uri = voice_bridge + "@" + server_address;

    if (mode == "redirect") {
        console_log("INFO", "[MCONF-SIP-PROXY] Redirecting call to " + dest_uri + "\n");
        session.execute("redirect", "sip:" + dest_uri);
    } else {
        console_log("INFO", "[MCONF-SIP-PROXY] Bridging call to " + dest_uri + "\n");
        session.setVariable('bypass_media', 'true');
        session.execute("bridge", "sofia/external/" + dest_uri);
    }
    return true;
}

function getMeetings(server_url, server_salt) {
    var bbb_api = new BigBlueButtonApi(server_url, server_salt);
    var req = bbb_api.urlFor("getMeetings", {});
    curl.run("GET", req.split('?')[0], req.split('?')[1], getMeetingsCallback, [ bbb_api ], null);
}

for (var i = 0; i < credentials.length; i++) {
    if (success) {
        break;
    }
    getMeetings(credentials[i].url, credentials[i].secret);
}

if (! success) {
    console_log("INFO", "[MCONF-SIP-PROXY] IP " + source_addr + " failed to dial a valid number, dialed " + called_number + "\n");
    session.execute("respond", "404");
}

/* CODE TO USE PIN PROTECTION, TEMPORARILY DISABLED
            var attempts = 3;
            var cnt=0;
            console_log("info","Starting PIN Collection\n");
            session.answer();
            var passOk=false;
            while (cnt<attempts) {
                session.flushDigits();
                pin = session.getDigits(4,"",10000);
                console_log("info","Collected PIN: " + pin + "\n");
                if (pin == meeting.pass) {
                    passOk=true;
                    console_log("INFO", meeting.voiceBridge + "\n");
                    session.execute("bridge", "sofia/external/"+meeting.voiceBridge+"@"+server_address);
                } else {
                    session.execute("playback", "/usr/local/freeswitch/sounds/<wav file here>");
                }
                cnt++;
            }
            if (!passOk) {
                session.execute("playback", "/usr/local/freeswitch/sounds/<wav file here>");
            }
*/
