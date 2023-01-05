make-dir = $(dir $(abspath $(firstword $(MAKEFILE_LIST))))
# VPATH = $(make-dir)

# Message verbosity {{{1
#
# Verbosity levels:
#      make     ansible-playbook
#   0: .SILENT  normal
#   1: normal   normal
#   2: normal   -v
#   3: normal   -vvv
#   4: normal   -vvvv
#
VERBOSE ?= 1
#
# if VERBOSE == 0
ifneq (,$(filter $(VERBOSE),0))
    verbose=
.SILENT:
# elif VERBOSE == 1
else ifneq (,$(filter $(VERBOSE),1))
    verbose=
# elif VERBOSE == 2
else ifneq (,$(filter $(VERBOSE),2))
    verbose=-v
# elif VERBOSE == 3
else ifneq (,$(filter $(VERBOSE),3))
    verbose=-vvv
# elif VERBOSE == 4
else ifneq (,$(filter $(VERBOSE),4))
    verbose=-vvvv
else
    $(call die,Unknown setting: VERBOSE=$(VERBOSE))
endif

# Functions {{{1
#
include $(make-dir)/files/functions.mk

# Simplify calling ansible-playbook {{{2
#
# run-ansible: wrapper around a fairly complicated
#   call to ansible-playbook
#
# Usage: (variables not defined will have defaults selected)
#   target: limit      = <limit>
#   target: extra-vars = <key1=val1,key2=val2,...>
#   target: tags       = <tag1,tag2,...>
#   target:
#           $(run-ansible)
run-ansible = $(call ansible,$(limit),$(extra-vars),$(tags))

# ansible: the fairly complicated call to ansible-playbook
#   This should probably not need to be called directly
#
# Parameters:
#   1: --limit
#   2: --extra-vars
#   3: --tags
define ansible
$(call msg,Run Ansible$(if $3, tags=$3))
ANSIBLE_FORCE_COLOR=$(ANSIBLE_FORCE_COLOR) $(ansible_playbook) \
    $(verbose) \
    --inventory $(inventory) \
    $(if $1,--limit $1) \
    $(patsubst %,--extra-vars "@%",$(config)) \
    $(patsubst %,--extra-vars "%",$2) \
    $(if $3,--tags $3) \
    $(playbook)
endef

# Determine which targets {{{1
#
# Which environment to build. Needs to be defined before we
# check for/configure anything
#
ENCLAVE ?= testing
enclave := $(basename $(ENCLAVE))

# If no target is specified, print help
#
ifeq (,$(MAKECMDGOALS))
    MAKECMDGOALS=help
endif

# Support targets {{{2
#
support-targets = help peru peru-reup
ifneq (,$(filter $(MAKECMDGOALS),$(support-targets)))

# Check for required binaries {{{3
#
peru     = peru
req_bins = peru

$(call check_for,$(req_bins))

# Help {{{3
#
.PHONY: help
# Force VERBOSE mode so $(call msg) actually prints
help: VERBOSE = 1
help:
	$(call msg,Required configuration:,1)
	$(call msg,  ENCLAVE must be the relative path to a YAML file containing the)
	$(call msg,  configuration you want to build (with or without the filename extension))
	$(call msg,  See 'example.yaml'.)
	$(call msg,)
	$(call msg,Available targets:,1)
	$(call msg,  all           : everything)
	$(call msg,  images        : CT template images)
	$(call msg,  pve-bootstrap : prepare PVE node for further configuration)
	$(call msg,  api-token     : create a PVE API token for Terraform)
	$(call msg,  terraform     : build CT images)
	$(call msg,  upload        : upload CT images)
	$(call msg,  ansible       : run ansible (can define 'limit', 'tags' and 'extra-vars'))
	$(call msg,  peru          : peru reup)
	$(call msg,  peru-reup     : peru reup --force)
	$(call msg,)
	$(call msg,Deletion and tear down targets:,1)
	$(call msg,  reset           : Blow everything away and force re-bootstrap of PVE node)
	$(call msg,  destroy         : Run 'terraform destroy' and delete local terraform state and API key)
	$(call msg,  delete-images    : Force rebuild of CT images)
	$(call msg,  delete-api-token : Force regeneration of PVE API token)
	$(call msg,  delete-tarballs  : Delete manually built CT images)
	$(call msg,)
	$(call msg,Optional configuration variables:,1)
	$(call msg,  COLOR=true|yes|y|1 : turn on color (default))
	$(call msg,  COLOR=false|no|n|0 : turn off color)
	$(call msg,)
	$(call msg,SSH Public Key:,1)
	$(call msg,  The SSH public key to use is selected using the following priority:)
	$(call msg,    1. Key string contained in PUBKEY)
	$(call msg,    2. File pointed to by KEYFILE (do not include the .pub extension))
	$(call msg,    3. A new key is generated if GENKEY == yes|y|1)
	$(call msg,    4. ~/.ssh/id_ed25519.pub)
	$(call msg,    5. ~/.ssh/id_rsa.pub)
	$(call msg,    6. Generate a keypair)
	$(call msg,)
	$(call msg,Notes:,1)
	$(call msg,  - If you make any changes to your variables file that *might* impact)
	$(call msg,    building the CT images$(,) you should run 'make delete-images' to force)
	$(call msg,    a rebuild of the CT images. To avoid unnecessary rebuilds of the)
	$(call msg,    images, a pre-requisite was left out)

# Peru {{{3
#
# Peru config file
peru-config = .peru.yaml

.PHONY: peru
peru: cmd = sync
peru: .peru

.PHONY: peru-reup
peru-reup: cmd = reup
peru-reup: .peru

# NOTE: touch .peru/ Just in Case™
#
.peru: $(peru-config)
	$(peru) --file-basename $^ $(cmd) --force
	touch $@

# Main targets {{{2
#
else
    # Check for enclave variables file
    enclave-config = $(wildcard $(enclave).y*ml)
    ifeq ($(enclave-config),)
            $(call die,Variables for enclave '$(notdir $(enclave))' ($(enclave).y[a]ml) not found)
    endif

# NOTE: The rest of the file is within this block

.PHONY: all
all: terraform

# Check for required binaries {{{3
#
ansible_playbook = ansible-playbook
jinja            = jinja2
packer           = packer
terraform        = terraform
yq               = yq
req_bins         = ansible_playbook \
                   jinja \
                   packer \
                   terraform \
                   yq

$(call check_for,$(req_bins))

# Configuration {{{1
#
# Color configuration {{{2
#
# if COLOR == true|yes|1
ifneq (,$(filter $(COLOR),true yes y 1))
    ANSIBLE_FORCE_COLOR = true 
# elif COLOR == false|no|0
else ifneq (,$(filter $(COLOR),false no n 0))
    ANSIBLE_FORCE_COLOR = false 
else
    $(error Unknown setting: COLOR=$(COLOR))
endif

# Variables needed by make {{{2
#
# Where to build everything. Can be an absolute or relative path
enclave-build-dir = $(notdir $(enclave))
# Where to find static variable files
vars-dir = vars
# Where to find scripts, jinja templates, etc
files-dir = files

# Packer stuff
packer-base = $(files-dir)/base.pkr.hcl.j2

# Terraform stuff
tf-base  = $(files-dir)/main.tf.j2
tf-dir   = $(enclave-build-dir)
tf-main  = $(tf-dir)/main.tf
tf-state = $(tf-dir)/terraform.tfstate
tf-files = $(tf-main) \
	   $(tf-state) \
	   $(tf-dir)/terraform.tfstate.backup \
	   $(tf-dir)/.terraform.lock.hcl

# Marker file to indicate that the PVE node was successfully bootstrapped
# This must be deleted if you ever want to re-bootstrap
pve-bootstrap = $(enclave-build-dir)/.pve-bootstrap

# Ansible stuff
inventory-dir  = $(enclave-build-dir)
inventory-base = $(files-dir)/inventory.j2
inventory      = $(inventory-dir)/inventory
playbook       = main.yaml
# Pre-requisites for any target that uses $(run-ansible)
ansible-prereqs = $(inventory) $(playbook)

# SSH public key file
pubkey = $(enclave-build-dir)/pubkey

# Variable files {{{2
#
# Overridable variables
common-config = $(vars-dir)/common.yaml
# Overridable and user-defined variables
static-config = $(common-config) $(enclave-config)
# Generated variables
built-config = $(enclave-build-dir)/generated-vars.yaml
# *All* variables
config = $(common-config) $(built-config) $(enclave-config)

# Variables that *can* be overriden {{{2
#
# These variables are set in $(static-config) but we need to extract them for
# make
#

# Where to put Packer images
image-dir = $(enclave-build-dir)/images
# List of images to create
image-list = $(patsubst %,$(image-dir)/%.tar.gz,\
                 $(shell cat $(enclave-config) | $(yq) '.images[].name'))

# PVE access (the first node listed is the "master")
pve-ip     = $(shell cat $(static-config) | $(yq) '.hosts.pve[0].ip')
pve-node   = $(shell cat $(static-config) | $(yq) '.hosts.pve[0].name')

# Needed for bootstrapping
ansible-user   = $(shell cat $(static-config) | $(yq) '.ansible_user')

# Needed by terraform
terraform-user = $(shell cat $(static-config) | $(yq) '.terraform_user')

# Variables that *cannot* be overriden {{{2
#
# Script to bootstrap configuring through Ansible
bootstrap = $(files-dir)/bootstrap

# LXC config needed by Packer
lxc-conf = $(files-dir)/lxc-config

# Where to upload CT images on the PVE node
ct-image-dir = /var/lib/vz/template/cache

# Where to store the enclave-specific PVE API tokens
#
# NOTE: making $(api-token) an absolute path makes the Ansible
# task that uses it easier
ifneq (,$(filter $(call is_absolute,$(enclave-build-dir)),y))
    api-token = $(enclave-build-dir)/apikey.terraform
else
    api-token = $(realpath .)/$(enclave-build-dir)/apikey.terraform
endif

# Generated variables {{{2
#
# These variables are needed by things other than make and/or are generated in
# this Makefile. They are stuffed into a file to avoid needing a bunch of
# 'jinja2 -D' and 'ansible-playbook --extra-vars' options
#
$(built-config): $(pubkey) $(static-config)
	$(call msg,Generate built-config ($(built-config)),1)
	> $(built-config)
	echo "bootstrap: $(bootstrap)"           >> $(built-config)
	echo "lxc_conf: $(lxc-conf)"             >> $(built-config)
	echo "api_token: $(api-token)"           >> $(built-config)
	echo "pve_ip: $(pve-ip)"                 >> $(built-config)
	echo "pve_node: $(pve-node)"             >> $(built-config)
	echo "ansible_pubkey: $$(cat $(pubkey))" >> $(built-config)
	echo "ct_image_dir: $(ct-image-dir)"     >> $(built-config)
	echo "image_dir: $(image-dir)"           >> $(built-config)
	echo "output_dir: $(enclave-build-dir)"  >> $(built-config)
	echo "tf_user:"                          >> $(built-config)
	echo "  - name: $(terraform-user)"       >> $(built-config)
	echo                                     >> $(built-config)

# Copy/Generate SSH public key {{{2
#
# Run 'make help' for the SSH key priority list
#
$(pubkey):
	$(call msg,Get SSH public key)
	mkdir -p $(dir $@)
# PUBKEY set
ifdef PUBKEY
	echo $(PUBKEY) > $@
# KEYFILE set
else ifdef KEYFILE
	$(if $(wildcard $(KEYFILE).pub),\
	    cp $(KEYFILE).pub $@,\
	    $(error SSH key $(KEYFILE) does not exist))
# GENKEY is not requested so use ~/.ssh/id_rsa.pub or ~/.ssh/id_ed25519.pub
else ifeq (,$(filter $(GENKEY),true yes y 1))
    ifneq (,$(wildcard ~/.ssh/id_rsa.pub))
	cp ~/.ssh/id_rsa.pub $@
    else ifneq (,$(wildcard ~/.ssh/id_ed25519.pub))
	cp ~/.ssh/id_ed25519.pub $@
# Neither exists so generate a key
    else
	ssh-keygen -f $(basename $@)
    endif
# Generate a key if no other option requested or successful
else
	ssh-keygen -f $(basename $@)
endif

# Build Packer images {{{1
#
# The images target only exists if it is requested, otherwise the image tarballs
# are not intermediate targets and are not deleted
#
# if MAKECMDGOALS ~= images
ifneq (,$(findstring images,$(MAKECMDGOALS)))
.PHONY: images
images: $(image-list)
endif

# Build a specific image
#
# Packer needs to build each image individually so that it doesn't have to mess
# with creating and deleting one output directory per image. This way is just
# simpler and has the side-benefit of allowing us to build a specific image if
# we want
#
$(image-list): %.tar.gz: %.pkr.hcl
	$(call msg,Build image ($*),1)
	mkdir -p $(dir $@)
	$(packer) init $*.pkr.hcl
	$(packer) build $*.pkr.hcl
	mv $(dir $@)/rootfs.tar.gz $@

# Generate Packer file for a specific image
#
# NOTE: $(config) is an order-only pre-req so images aren't rebuilt everytime a
# variables file is changed. This does mean you have to manually delete and
# rebuild images if you do make a config change that matters
#
# NOTE: the $(notdir $*) is needed because the .pkr.hcl file might be in a
# sub-directory and we need just the basename
#
# NOTE: The two calls to cat(1) are necessary because we have to extract the
# 'name' variable specifically and also use the variable files in full
#
# NOTE: role_config can't be stuffed into $(built-config) because it is
# different for every image and I don't want to introduce files-dir into the
# Packer templates
%.pkr.hcl: $(packer-base) | $(config)
	$(call msg,Create Packer template ($@),1)
	mkdir -p $(dir $@)
	cat $| \
	    | ($(yq) '.images[]|select(.name == "$(notdir $*)")'; \
	       echo "role_config: $(files-dir)/config-$(notdir $*)") \
	    | cat $| - \
	    | $(jinja) \
	        $< > $@

# Bootstrap master PVE node {{{1
#
.PHONY: pve-bootstrap terraform upload
.PHONY: pve-bootstrap
pve-bootstrap: $(pve-bootstrap)

# This should do the *minimum* necessary in order for Terraform to work and for
# Ansible to do a full configuration of the PVE node later
#
$(pve-bootstrap): limit = $(pve-node)
$(pve-bootstrap): tags  = bootstrap
$(pve-bootstrap): $(pubkey) $(ansible-prereqs)
	$(call msg,Bootstrap master PVE node ($(pve-node)),1)
	ssh root@$(pve-ip) \
	    "sh -s -- -k '$$(cat $(pubkey))' \
	              -u $(ansible-user) \
		      -d pve" < $(bootstrap)
	$(run-ansible)
	touch $@

# Build out terraform {{{1
#
# There is no need to create an individual .tf file for each container and then
# use make(1) to manage only creating containers with changes, because Terraform
# handles that automatically

# Pre-reqs for uploading images
upload-prereqs = $(patsubst %,%.uploaded,$(image-list))

.PHONY: terraform
terraform: $(tf-state)

# Manual upload of images
#
.PHONY: upload
upload: $(upload-prereqs)

# Manual creation of PVE API token
#
.PHONY: api-token
api-token: $(api-token)

# terraform apply
#
# NOTE: touch $(tf-state) in case this target is executed again after an
# initial run. Just in Case™
#
$(tf-state): $(upload-prereqs) $(tf-main) $(api-token) $(pve-bootstrap)
	$(call msg,Run 'terraform apply',1)
	$(terraform) -chdir=$(dir $@) init
	$(terraform) -chdir=$(dir $@) apply \
	    -auto-approve \
	    -var-file $(api-token)
	touch $@

# NOTE: The weird cat/filter thing is so I can use $@ and $<.  Jinja can't use
# multiple variable files so I have to split the jinja template from the files
# containing the definitions
#
$(tf-main): $(tf-base) $(config)
	$(call msg,Generate Terraform tempate ($(tf-main)),1)
	mkdir -p $(dir $@)
	cat $(filter-out $<,$^) \
	    | $(jinja) $< > $@

$(api-token): limit = $(pve-node)
$(api-token): tags  = api-token
$(api-token): $(ansible-prereqs) $(pve-bootstrap)
	$(call msg,Create PVE API token,1)
	mkdir -p $(dir $@)
	chmod 700 $(dir $@)
	$(run-ansible)
	chmod 600 $@

# Upload CT images to the PVE node and create a file that indicates the file was
# uploaded
#
# NOTE: $(ct-image-dir) *must* exist on the PVE node
#
%.tar.gz.uploaded: %.tar.gz
	$(call msg,Upload CT image ($*),1)
	scp $^ root@$(pve-ip):$(ct-image-dir)
	touch $@

# Configure servers {{{1
#
# NOTE: The weird cat/filter thing is so I can use $@ and $<.  Jinja can't use
# multiple variable files so I have to split the jinja template from the files
# containing the definitions
#
$(inventory): $(inventory-base) $(config)
	$(call msg,Generate Ansible inventory ($@),1)
	mkdir -p $(dir $@)
	cat $(filter-out $<,$^) \
	    | $(jinja) $< > $@

.PHONY: ansible
ansible: $(ansible-prereqs)
	$(run-ansible)

# Deletion/Teardown targets {{{1
#
# Run 'make help' for documentation
#

.PHONY: reset
reset: destroy delete-images
	rm -f $(pubkey)
	rm -f $(pve-bootstrap)
	rm -f $(built-config)
	rm -f $(inventory)
	rmdir $(inventory-dir) 2>/dev/null || true
	rmdir $(enclave-build-dir) 2>/dev/null || true

# NOTE: This is not the most efficient target as it forces creation of an API
# token even if there is no Terraform state to destroy
#
.PHONY: destroy
destroy: limit = $(pve-node)
destroy: tags  = delete-api-token
destroy: $(api-token) $(ansible-prereqs) $(pve-bootstrap)
	if [ -e "$(tf-main)" ]; then \
	    $(terraform) -chdir=$(dir $(tf-state)) destroy -auto-approve -var-file $(api-token); \
	fi
	rm -f  $(tf-files)
	rm -rf $(tf-dir)/.terraform
	rmdir  $(tf-dir) 2>/dev/null || true
	$(run-ansible)
	rm -f $(api-token)

.PHONY: delete-images
delete-images: delete-tarballs
	rm -f $(patsubst %,%.uploaded,$(image-list))
	rmdir $(image-dir) 2>/dev/null || true

.PHONY: delete-tarballs
delete-tarballs:
	rm -f $(image-list)
	rm -f $(patsubst %.tar.gz,%.pkr.hcl,$(image-list))
	rm -f $(image-dir)/$(notdir $(lxc-conf))
	rmdir $(image-dir) 2>/dev/null || true

.PHONY: delete-api-token
delete-api-token: limit = $(pve-node)
delete-api-token: tags  = delete-api-token
delete-api-token: $(ansible-prereqs) $(pve-bootstrap)
	$(run-ansible)
	rm -f $(api-token)
	rmdir $(dir $(api-token)) 2>/dev/null || true

endif # MAKECMDGOALS != <support targets>

