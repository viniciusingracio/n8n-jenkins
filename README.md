### Getting started

* Install [ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#latest-releases-via-apt-ubuntu)
```bash
sudo apt-get update
sudo apt-get install software-properties-common
sudo apt-add-repository ppa:ansible/ansible
sudo apt-get update
sudo apt-get install ansible
```
* Install/upgrade python libraries
```bash
sudo apt-get install python-pip
sudo pip install --upgrade pip pyopenssl docker zabbix-api
```
* Install ansible dependency roles
```bash
ansible-galaxy install -r requirements.yml
```
* Make sure the remote servers have python3 installed (default on Ubuntu 16.04.2)
```bash
python3 --version
# Output: Python 3.5.2
```
* Copy `.docker-auth.example` to `.docker-auth` and set docker credentials
* Connect to the server using SSH. If you need to provide a password to connection, make sure you pass `--ask-pass --ask-become-pass` when running `ansible-playbook setup.yml`. If you use an user different than `mconf`, make sure you pass `ansible_user=<USER>` when running `ansible-playbook setup.yml`.

### Run

There are two main playbooks: `setup.yml` and `provision.yml`. The first one will a basic setup of the server, creating the deploy user, installing some basic packages and other common tasks. The second playbook is used to provision and deploy an application to the servers.

On the first run, use `setup.yml`. Examples:

```bash
# lxc, all 'rec-proxy' servers
ansible-playbook -i envs/dev -l rec-proxy setup.yml --ask-pass --ask-become-pass --extra-vars "ansible_user=ubuntu common_ufw_ipv6=false"

# lxc, a single server by IP
ansible-playbook -l 10.0.3.105 setup.yml --ask-pass --ask-become-pass --extra-vars "ansible_user=ubuntu deploy_user=ubuntu"

# digital ocean, all 'rec-proxy' servers
ansible-playbook -i envs/dev -l rec-proxy setup.yml --extra-vars "ansible_user=root"

# with certbot
SSL_CERT_FILE=files/lets-encrypt-x3-cross-signed.pem ansible-playbook ...
```

Then, to provision and deploy an application, use `provision.yml`. Examples:

```bash
ansible-playbook -i envs/dev -l rec-proxy provision.yml
```

### Ad-hoc commands

If you just want to run a command on a set of hosts, use:

```bash
ansible all -v -i envs/rnp/h/hosts -l mconf-recw -m command --become -a "apt-get -y upgrade"

# restart BigBlueButton application
ansible all -v -i envs/prod/com/hosts -l mconf-live110 --extra-vars "ansible_user=mconf" --become -m raw -a 'bbb-conf --restart || true'

# check bandwidth capacity
ansible all -v -i envs/prod/tjrr/hosts -l live-comarcas --extra-vars "ansible_user=mconf" --become -m raw -a 'curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python -'

# check if server has access to the Internet
ansible all -v -i envs/prod/tjrr/hosts -l live-comarcas --extra-vars "ansible_user=mconf" -m raw -a 'echo -e "GET http://google.com HTTP/1.0\n\n" | nc -w 10 google.com 80 > /dev/null 2>&1; if [ $? -eq 0 ]; then echo "ONLINE"; else echo "OFFLINE"; fi'

# get all client side errors and dump into a file
ansible all -v -i envs/rnp/prod/hosts -l mconf-live200 --extra-vars "ansible_user=mconf" -m raw -a 'zgrep "error" /var/log/nginx/html5-client.log*' | grep error | sed -u -e 's/\\x22/"/g' -e 's/\\x5C/ /g' > errors_html5.log

# reload and restart performance_report
ansible all -v -i envs/prod/tjrr/hosts -l mconf-live200,mconf-rec --extra-vars "ansible_user=mconf" --become -m raw -a 'systemctl daemon-reload; systemctl restart performance_report'

# get /metrics password for node-exporter
ansible all -v -i envs/prod/tjrr/hosts -l mconf-live200,mconf-rec,mconf-recw --extra-vars "ansible_user=mconf" --become -m raw -a "cat /var/lib/tomcat7/webapps/bigbluebutton/WEB-INF/classes/bigbluebutton.properties | grep '^securitySalt=' | cut -d'=' -f2 | tr -d '\n' | sha256sum"
```

### Other playbooks

#### upgrade-so

Upgrades the packages in the server and cleans unused packages (basically "apt-get dist-upgrade" + "autoremove"):

```
ansible-playbook -i envs/prod/com-staging -l rec-proxy playbooks/upgrade-so.yml
```

#### ufw

Install ufw installs ufw with default configurations, blocking all incoming traffic except for the port being used by ssh. Then it applies all rules specified in `ufw_rules` to, for example, open other ports.

Example:

```
# set up the user
ansible-playbook -i "10.0.3.186," playbooks/ufw.yml --ask-pass --ask-become-pass --extra-vars '{"ansible_user": "ubuntu", "common_ufw_ipv6": false, "ufw_rules": [{"rule": "allow", "port": 80, "proto": "tcp"}, {"rule": "reject", "port": 3000, "proto": "tcp"}]}'
```

#### authorize-rec-worker

Creates a user in a web conference server and allows it to be accessed by a given ssh key. Example:

```
# set up the user
ansible-playbook -i envs/dev playbooks/authorize-rec-worker.yml

# test the access
ssh -tA rec-worker@10.0.3.245 -i envs/dev/files/rec_worker
```

#### run-sql

Runs an SQL file from a template into a database server. Example:

```
ansible-playbook -i envs/prod/com-staging -l dev.mconf.com playbooks/run-sql.yml --extra-vars "sql_template=../files/templates/mconf-com-room.sql.j2 sql_db='dev_mconf_com' sql_host='123.123.123.123' sql_room='Comunidade EAD' sql_room_param='param-comunidade-ead' sql_moderator_pw='mod99281' sql_attendee_pw='convidado244' ansible_python_interpreter=/usr/bin/python"
```

The credentials to access the server should be set a the `~/.my.cnf` in the server being sshed to. Example:

```
[client]
port=3306
password=929dk92k29d29i
user=mconf
```

### Utils

* Start at a given point: `ansible-playbook -i envs/dev -l rec-proxy --start-at-task="rec-proxy : Download rec-proxy source code" provision.yml`
* List hosts only (don't actually run anything in the server): `ansible-playbook -i envs/dev -l rec-proxy --list-hosts`
* List tasks and hosts only (don't actually run anything in the server): `ansible-playbook -i envs/dev -l rec-proxy --list-tasks --list-hosts`
* Dry-run, check mode (don't actually run anything in the server): `ansible-playbook -i envs/dev -l rec-proxy --check`
* To debug something, add a task like: `- debug: var=my_registered_var`
* Run setup for a new local lxc server: `ansible-playbook -i '10.0.3.187,' setup.yml --extra-vars="ansible_user=ubuntu deploy_user=ubuntu" --ask-pass --ask-become-pass`
* Run just a set of commands (e.g. the firewall): `ansible-playbook -i envs/com/hosts setup.yml --tags ufw`
* To copy files from a local repository to the server, use something like:
    ```
- name: Copy local rec-proxy source code
  synchronize:
    src: /home/leonardo/Dev/mconftec/mconf-rec-proxy/
    dest: ~/src/rec-proxy
    ```
* To run a single command (e.g. uptime) in all servers: `ansible all -i envs/dev -m command -a "uptime" -u mconf --extra-vars "ansible_python_interpreter=/usr/bin/python3"`
* To create a new role directory structure: `ansible-galaxy init sip-proxy --init-path=roles/`

### Notes

#### Ubuntu 16.04

* For Ubuntu >= 16.04, use `common_ufw_ipv6=false` otherwise some `ufw` commands will fail.

#### LXC

* To run docker inside an LXC container, edit `/var/lib/lxc/your-container-name/config` and include:

    ```
lxc.aa_profile = unconfined
lxc.cgroup.devices.allow = a
lxc.cap.drop =
    ```
