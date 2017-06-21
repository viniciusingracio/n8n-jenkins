### Requirements

* Install ansible
* Install sshpass (apt-get install sshpass)
* For docker: `pip install 'docker-py>=1.7.0'`
* Remote server needs python

### Run

First run

```bash
# lxc
ansible-playbook -i hosts -l rec-proxy setup.yml --ask-pass --ask-sudo-pass --extra-vars "ansible_user=ubuntu"

# digital ocean
ansible-playbook -i hosts -l rec-proxy setup.yml --extra-vars "ansible_user=root"
```

Provisioning

```bash
ansible-playbook -i hosts -l rec-proxy provision.yml
```

Setting up an lxc, using just the `ubuntu` user

```
ansible-playbook -l 10.0.3.105 setup.yml --ask-pass --ask-sudo-pass --extra-vars "ansible_user=ubuntu deploy_user=ubuntu"
```

Utils:

* Start at a given point: `ansible-playbook -i hosts -l rec-proxy --start-at-task="rec-proxy : Download rec-proxy source code" provision.ym
* List hosts only (don't actually run anything in the server): `ansible-playbook -i hosts -l rec-proxy --list-hosts`
* List tasks only (don't actually run anything in the server): `ansible-playbook -i hosts -l rec-proxy --list-tasks`
* To debug something, add a task like: `- debug: var=my_registered_var`
