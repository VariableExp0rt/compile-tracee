#!/bin/bash

set -euo pipefail

CHECKOUT_PATH=/tmp/tracee
TRACEE_GH=https://github.com/aquasecurity/tracee.git

# handle "extras/kernel-5.4/latest" instead of "core/2.0/x86_64/" because Tracee doesn't support AL2 kernel 4.14 (or anything < 4.18)
BASEURL=http://amazonlinux.us-east-1.amazonaws.com/2/extras/kernel-5.4/latest/x86_64/
MIRRORS=mirror.list
REPOSUFFIX=/repodata/primary.sqlite.gz #if you really want, you can choose primary.xml.gz too
KERNEL_VERSION=73.259.amzn2

STATEMENT="SELECT location_href FROM packages WHERE name LIKE 'kernel%%' AND name NOT LIKE 'kernel-livepatch%%' AND name NOT LIKE '%%doc%%' AND 
name NOT LIKE '%%tools%%' AND name NOT LIKE '%%headers%%' AND release='${KERNEL_VERSION}'"

get_tracee() {
	if test -x "$(command -v git)"; then
		git clone --recursive "${TRACEE_GH}" "${CHECKOUT_PATH}"
	else
		exit 1
	fi
  sed -i 's+$TRACEE_EBPF_EXE --output=format:gob --output=option:parse-arguments+$TRACEE_EBPF_EXE --output=format:gob 
--output=option:parse-arguments --build-policy=never+g' "${CHECKOUT_PATH}"/entrypoint.sh
  sed -i '5 i TRACEE_BPF_FILE=$(find /tmp/ -type f -regex ".*/tracee\.bpf.*_amzn2_x86_64.*\.o")\nexport TRACEE_BPF_FILE' 
"${CHECKOUT_PATH}"/entrypoint.sh
	get_amazonlinux2_rpm
}

get_amazonlinux2_rpm() {
	wget -O /tmp/"${MIRRORS}" "${BASEURL}""${MIRRORS}"

	COUNT=1

	while read line; do
		wget -O /tmp/primary.sqlite-"${COUNT}".gz $line"${REPOSUFFIX}"

		gunzip /tmp/primary.sqlite-"${COUNT}".gz

		RESULT=$(sqlite3 /tmp/primary.sqlite-"${COUNT}" "${STATEMENT}")

		HREFS=( $(echo "${RESULT}" | tr ' ' '\n') )

		if [[ ${#HREFS[@]} -lt 2 ]]; then
			echo "At least two packages are required to build the tracee eBPF probe."
			exit 1
		fi

    mkdir -p /tmp/kernel-download
    cd /tmp/kernel-download
		for elem in "${HREFS[@]}"; do
			PACKAGE=$(echo "$elem" | sed -e 's/\.\.\///g')
			PACKAGE_FILENAME=$(basename "${PACKAGE}")
			wget -O "${PACKAGE_FILENAME}" "http://amazonlinux.us-east-1.amazonaws.com/""${PACKAGE}"

			rpm2cpio "${PACKAGE_FILENAME}" | cpio --extract --make-directories
			rm -Rf "${PACKAGE_FILENAME}"
		done

    rm -Rf /tmp/kernel
		mkdir -p /tmp/kernel
		mv usr/src/kernels/*/* /tmp/kernel
		((COUNT++))
	done < /tmp/mirror.list

	build_tracee_bpf_probe
}

build_tracee_bpf_probe() {
	sed -i 's+KERN_RELEASE ?= $(shell uname -r)+KERN_RELEASE := 5.4.149-73.259.amzn2.x86_64+g' "${CHECKOUT_PATH}"/tracee-ebpf/Makefile
	sed -i 's+KERN_BLD_PATH ?= $(if $(KERN_HEADERS),$(KERN_HEADERS),/lib/modules/$(KERN_RELEASE)/build)+KERN_BLD_PATH := /tmp/kernel+g' 
"${CHECKOUT_PATH}"/tracee-ebpf/Makefile
	sed -i 's+KERN_SRC_PATH ?= $(if $(KERN_HEADERS),$(KERN_HEADERS),$(if $(wildcard 
/lib/modules/$(KERN_RELEASE)/source),/lib/modules/$(KERN_RELEASE)/source,$(KERN_BLD_PATH)))+KERN_SRC_PATH := /tmp/kernel+g' 
"${CHECKOUT_PATH}"/tracee-ebpf/Makefile
	sed -i 's+OUT_BPF := $(OUT_DIR)/tracee.bpf.$(subst .,_,$(KERN_RELEASE)).$(subst .,_,$(VERSION)).o+OUT_BPF := $(OUT_DIR)/tracee.bpf.$(subst 
.,_,$(KERN_RELEASE)).$(subst .,_,$(VERSION)).o+g' "${CHECKOUT_PATH}"/tracee-ebpf/Makefile
	cd "${CHECKOUT_PATH}"/tracee-ebpf && make bpf
	make_tracee_ebpf_bin
	make_tracee_rules_bin
}

make_tracee_ebpf_bin() {
  cd "${CHECKOUT_PATH}"/tracee-ebpf && make build
}

make_tracee_rules_bin() {
  cd "${CHECKOUT_PATH}"/tracee-rules && make
}

get_tracee
