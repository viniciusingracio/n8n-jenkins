### Requirements

* Install ansible
* Install sshpass (apt-get install sshpass)
* Remote server needs python

### Run

First run

```bash
ansible-playbook -i hosts setup.yml --ask-pass --ask-sudo-pass --extra-vars "ansible_user=ubuntu"
```

Other

```bash
ansible-playbook -i hosts setup.yml
```
