### Requirements

* Install ansible
* Install sshpass (apt-get install sshpass)
* For docker: `pip install 'docker-py>=1.7.0'`
* Remote server needs python

### Run

First run

```bash
ansible-playbook -i hosts setup.yml --ask-pass --ask-sudo-pass --extra-vars "ansible_user=ubuntu"
```

Provisioning

```bash
ansible-playbook -i hosts provision.yml
```

Setting up an lxc

```
ansible-playbook -l 10.0.3.105 setup.yml --ask-pass --ask-sudo-pass --extra-vars "ansible_user=ubuntu deploy_user=ubuntu"
```

Utils:

* Start at a given point: `ansible-playbook -l rec-proxy --start-at-task="rec-proxy : Download rec-proxy source code" provision.ym
