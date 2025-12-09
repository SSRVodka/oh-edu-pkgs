#!/bin/bash

set -Eeuo pipefail

. setup2.sh

validate_pkgname() {
	local pkg="$1"
	
	if [ -z "$pkg" ]; then
		error "package name should not be empty"
		return 1
	fi
	
	if [[ "$pkg" == *" "* ]]; then
		error "package name should not have any space: '$pkg'"
		return 1
	fi
	
	#if [[ ! "$pkg" =~ ^[[:ascii:]]+$ ]]; then
	#	error "non-ASCII character in package name: '$pkg'"
	#	return 1
	#fi
	
	return 0
}

main() {

	local pkgname
	for pkgname in "$@"; do
		if ! validate_pkgname "$pkgname"; then
			exit 1
		fi
	done
	
	local idx pkg
	for idx in $(seq 1 $#); do
		pkg=${!idx}
		cp -r .template $pkg
		sed -i "s|^\(pkg_name=\"\).*\"|\1$pkg\"|" $pkg/BUILD
		info "created pkg '$pkg'"
	done

}

main "$@"

