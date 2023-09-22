#!/usr/bin/env sh
# shellcheck disable=SC2093,SC2268
# SC2093 = running after exec
# SC2268 = xprefix
# ------------------------------------------------------------------------------
#
# Copyright (c) 2016-Present Pivotal Software, Inc
#
# ------------------------------------------------------------------------------

set -e

# file struct inside container:
# /clientdir
#   -> entry.sh      (this file)
#   -> py3client.sh  (symlink to entry.sh)
#   -> pyclient.sh   (symlink to entry.sh)
#   -> 3client.sh    (symlink to entry.sh)
#   -> py3client (the default one, symlink to client_python39_ubuntu-22.04)
#   -> pyclient  (the default one, symlink to client_python2x_ubuntu-xxxxx) TODO
#   -> rclient   (the default one, symlink to client_python2x_ubuntu-xxxxx) TODO
#   -> client_python39_ubuntu_22.04
#   -> client_<client_name>_<OS_ID>-<BUILD_ID or VERSION_ID or image hash>
#   -> source_python_client
#   -> source_python3_client (symlink to source_python_client)
#   -> source_r_client
#
# example usage:
#   -l py2 client = <empty>  : exec '/clientdir/pyclient'   no build
#   -l py3 client = <empty>  : exec '/clientdir/py3client'  no build
#   -l r   client = <empty>  : exec '/clientdir/rclient'    no build
#   -l py3 client = python311: exec '/clientdir/client_python311_<OS>'. build 'source_python3_client'             OK
#   -l py  client = python311: exec '/clientdir/client_python311_<OS>'. build 'source_python_client' , exec py311 OK
#   -l r   client = python311: exec '/clientdir/client_python311_<OS>'. build 'source_r_client'      , exec r     ERROR
#   -l r   client = r2       : exec '/clientdir/client_r2_<OS>'.        build 'source_r_client'      , exec r     OK

# only write POSIX shell here (not bash)

PLC_LANGUAGE="unknown"
PLC_DEFAULT_CLIENT="unknown"

case "$0" in
	"/clientdir/py3client.sh")
		PLC_LANGUAGE="python3"
		PLC_DEFAULT_CLIENT="/clientdir/py3client"
	;;
	"/clientdir/pyclient.sh")
		PLC_LANGUAGE="python"
		PLC_DEFAULT_CLIENT="/clientdir/pyclient"
	;;
	"/clientdir/rclient.sh")
		PLC_LANGUAGE="r"
		PLC_DEFAULT_CLIENT="/clientdir/rclient"

		# r need dynamic link to rcall.so due to GPL
		export LD_LIBRARY_PATH="/clientdir:$LD_LIBRARY_PATH"
		;;
	*)
		true
		;;
esac


if [ x"" = x"$PLC_CLIENT" ] && [ "unknown" != "$PLC_DEFAULT_CLIENT" ]; then
	# the default client, configure file empty.
	exec "$PLC_DEFAULT_CLIENT"
fi

if [ x"" = x"$PLC_CLIENT" ] && [ "unknown" != "$PLC_LANGUAGE" ]; then
	PLC_CLIENT="$PLC_LANGUAGE"
fi

PLC_IMAGE_HASH="$(hostname)"

PLC_CLIENT_SUFFFIX="$PLC_IMAGE_HASH"

if test -f "/etc/os-release"; then
	OS_ID=$(sh -c 'source /etc/os-release; echo $ID')
	OS_BUILD_ID=$(sh -c 'source /etc/os-release; echo $BUILD_ID')
	OS_VERSION_ID=$(sh -c 'source /etc/os-release; echo $VERSION_ID')

	PLC_CLIENT_SUFFFIX="$OS_ID"

	if test -z -n "OS_BUILD_ID"; then
		PLC_CLIENT_SUFFFIX="$PLC_CLIENT_SUFFFIX-$OS_BUILD_ID"
	elif test -z -n "OS_VERSION_ID"; then
		PLC_CLIENT_SUFFFIX="$PLC_CLIENT_SUFFFIX-$OS_VERSION_ID"
	else
		PLC_CLIENT_SUFFFIX="$PLC_CLIENT_SUFFFIX-$PLC_IMAGE_HASH"
	fi
fi

set +e
exec "/clientdir/client_$PLC_CLIENT""_""$PLC_CLIENT_SUFFFIX"
set -e

# try to build the client

PLC_BUILD_DIR="/tmp/build_$PLC_IMAGE_HASH"
mkdir "$PLC_BUILD_DIR"

cmake "/clientdir/source_""$PLC_LANGUAGE""_client" -B "$PLC_BUILD_DIR"
make -C "$PLC_BUILD_DIR"
# not remove the tempdir. container is not present

set +e
install "$PLC_BUILD_DIR/*client" "/clientdir/client_$PLC_CLIENT""_""$PLC_CLIENT_SUFFFIX" # error able
exec "/clientdir/client_$PLC_CLIENT""_""$PLC_CLIENT_SUFFFIX"
exec "$PLC_BUILD_DIR/*client"
