### Requirements

* Install ansible
* Install sshpass (apt-get install sshpass)
* For docker: `pip install 'docker-py>=1.7.0'`
* Remote server needs python

### Run

First run

```bash
# lxc
ansible-playbook -i envs/dev -l rec-proxy setup.yml --ask-pass --ask-sudo-pass --extra-vars "ansible_user=ubuntu common_ufw_ipv6=false"

# digital ocean
ansible-playbook -i envs/dev -l rec-proxy setup.yml --extra-vars "ansible_user=root"
```

Provisioning

```bash
ansible-playbook -i envs/dev -l rec-proxy provision.yml
```

Setting up an lxc, using just the `ubuntu` user

```
ansible-playbook -l 10.0.3.105 setup.yml --ask-pass --ask-sudo-pass --extra-vars "ansible_user=ubuntu deploy_user=ubuntu"
```

Utils:

* Start at a given point: `ansible-playbook -i envs/dev -l rec-proxy --start-at-task="rec-proxy : Download rec-proxy source code" provision.yml`
* List hosts only (don't actually run anything in the server): `ansible-playbook -i envs/dev -l rec-proxy --list-hosts`
* List tasks only (don't actually run anything in the server): `ansible-playbook -i envs/dev -l rec-proxy --list-tasks`
* To debug something, add a task like: `- debug: var=my_registered_var`
* Run setup for a new local lxc server: `ansible-playbook -i '10.0.3.187,' setup.yml --extra-vars="ansible_user=ubuntu deploy_user=ubuntu" --ask-pass --ask-sudo`

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

