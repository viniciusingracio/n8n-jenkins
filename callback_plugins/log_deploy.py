# (C) 2018, Felipe Cecagno <felipe@mconf.com>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

DOCUMENTATION = '''
    callback: log_deploy
    type: notification
    short_description: write playbook result to log file
    version_added: historical
    description:
      - This callback writes playbook output to a file per host in the `/var/log/ansible/hosts` directory
      - "TODO: make this configurable"
    requirements:
     - Whitelist in configuration
     - A writeable /var/log/ansible/hosts directory by the user executing Ansible on the controller
'''

import os
import time
import sys
import subprocess

from ansible.plugins.callback import CallbackBase

class CallbackModule(CallbackBase):
    """
    logs playbook results to log_deploy
    """
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = 'notification'
    CALLBACK_NAME = 'log_deploy'
    CALLBACK_NEEDS_WHITELIST = True

    TIME_FORMAT = "%Y-%m-%d_%H-%M-%S"

    def __init__(self):
        super(CallbackModule, self).__init__()

    def v2_playbook_on_stats(self, stats):
        revision = subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD']).strip()
        now = time.strftime(self.TIME_FORMAT, time.localtime())
        filename = "%s_%s.log" % (now, revision)
        path = os.path.join("log_deploy", filename)
        command = " ".join(sys.argv)
        hosts = sorted(stats.processed.keys())

        with open(path, "ab") as fd:
            fd.write("%s\n\n" % command)

            for h in hosts:
                t = stats.summarize(h)
                fd.write("%s: %s OK, %s changed, %s unreachable, %s failed\n" % (h, t['ok'], t['changed'], t['unreachable'], t['failures']))
