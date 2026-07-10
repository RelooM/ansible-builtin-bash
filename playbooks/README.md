# Playbooks

Place Ansible playbooks here to test modules from `../library/`.

Run with:

```bash
cd ..
ansible-playbook -i inventory playbooks/test_some_module.yml
```

Or point to the library explicitly:

```bash
ansible-playbook -i inventory playbooks/test_some_module.yml \
  --module-path library
```
