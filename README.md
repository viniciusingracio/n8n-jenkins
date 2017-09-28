### Requirements

* Install ansible
* Install sshpass (apt-get install sshpass)
* For docker: `pip install 'docker-py>=1.7.0'`
* Remote server needs python

### Run

There are two main playbooks: `setup.yml` and `provision.yml`. The first one will a basic setup of the server, creating the deploy user, installing some basic packages and other common tasks. The second playbook is used to provision and deploy an application to the servers.

On the irst run, use `setup.yml`. Examples:

```bash
# lxc, all 'rec-proxy' servers
ansible-playbook -i envs/dev -l rec-proxy setup.yml --ask-pass --ask-sudo-pass --extra-vars "ansible_user=ubuntu common_ufw_ipv6=false"

# lxc, a single server by IP
ansible-playbook -l 10.0.3.105 setup.yml --ask-pass --ask-sudo-pass --extra-vars "ansible_user=ubuntu deploy_user=ubuntu"

# digital ocean, all 'rec-proxy' servers
ansible-playbook -i envs/dev -l rec-proxy setup.yml --extra-vars "ansible_user=root"
```

Then, to provision and deploy an application, use `provision.yml`. Examples:

```bash
ansible-playbook -i envs/dev -l rec-proxy provision.yml
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
ansible-playbook -i "10.0.3.186," playbooks/ufw.yml --ask-pass --ask-sudo-pass --extra-vars '{"ansible_user": "ubuntu", "common_ufw_ipv6": false, "ufw_rules": [{"rule": "allow", "port": 80, "proto": "tcp"}, {"rule": "reject", "port": 3000, "proto": "tcp"}]}'
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
* Run setup for a new local lxc server: `ansible-playbook -i '10.0.3.187,' setup.yml --extra-vars="ansible_user=ubuntu deploy_user=ubuntu" --ask-pass --ask-sudo`
* Run just a set of commands (e.g. the firewall): `ansible-playbook -i envs/com/hosts setup.yml --tags ufw`

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

