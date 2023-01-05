# Install Pre-requisites to Local Host

## Install required software

- ansible
- jinja2-cli
- packer
- terraform
- yq
- peru (optional)

## Install required Ansible modules

```sh
$ ansible-galaxy collection install ansible.posix
```

# Install Proxmox

- Only one node is initially required

# Create Enclave Configuration

- Copy `example.yaml` and edit as needed

# Build Enclave

- Get help on `make` targets: `make help`
- Build everything: `make ENCLAVE=<path/to/enclave_file> all`
- Reset everything: `make ENCLAVE=<path/to/enclave_file> reset`

