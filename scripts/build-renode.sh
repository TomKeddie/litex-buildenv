#!/bin/bash

SCRIPT_SRC=$(realpath ${BASH_SOURCE[0]})
SCRIPT_DIR=$(dirname $SCRIPT_SRC)
TOP_DIR=$(realpath $SCRIPT_DIR/..)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
	echo "You must run this script, rather then try to source it."
	echo "$SCRIPT_SRC"
	exit 1
fi

source $SCRIPT_DIR/build-common.sh

init

RENODE_BIN=${RENODE_BIN:-renode}
if ! command -v $RENODE_BIN 2>&1 1>/dev/null; then
	# Download prebuilt renode Release if none is currently installed

	RENODE_PACKAGE=renode-latest.pkg.tar.xz
	RENODE_URL=https://antmicro.com/projects/renode/builds/$RENODE_PACKAGE
	RENODE_LOCATION="$BUILD_DIR/renode"
	RENODE_BIN=$RENODE_LOCATION/opt/renode/bin/Renode.exe

	if [ ! -x $RENODE_BIN ]; then
		mkdir -p $RENODE_LOCATION
		(
			cd $RENODE_LOCATION
			wget $RENODE_URL
			tar -xf $RENODE_PACKAGE
		)
		
		chmod u+x $RENODE_BIN
		echo "Renode downloaded and installed locally: $RENODE_BIN" 
	fi
fi

case $CPU in
	vexriscv | picorv32)
		;;
	*)
		echo "CPU $CPU_TYPE isn't supported at the moment."
		exit 1
		;;
esac

LITEX_CONFIG_FILE="$TARGET_BUILD_DIR/test/csr.csv"
if [ ! -f "$LITEX_CONFIG_FILE" ]; then
	make firmware
fi

# Ethernet
ETH_BASE_ADDRESS=$(parse_generated_header "csr.h" CSR_ETHMAC_BASE)
if [ ! -z "$ETH_BASE_ADDRESS" ]; then
	RENODE_NETWORK=${RENODE_NETWORK:-tap}
	case $RENODE_NETWORK in
	tap)
		echo "Using tun device for Renode networking, (may need sudo)..."
		configure_tap
		start_tftp

		# Build/copy the image into the TFTP directory.
		make tftp

		TAP_INTERFACE=tap0
		;;

	none)
		echo "Renode networking disabled..."
		;;
	*)
		echo "Unknown RENODE_NETWORK mode '$RENODE_NETWORK'"
		return 1
		;;
	esac
fi

RENODE_SCRIPTS_DIR="$TARGET_BUILD_DIR/renode"
RENODE_RESC="$RENODE_SCRIPTS_DIR/litex_buildenv.resc"
RENODE_REPL="$RENODE_SCRIPTS_DIR/litex_buildenv.repl"

mkdir -p $RENODE_SCRIPTS_DIR
python $SCRIPT_DIR/generate-renode-scripts.py $LITEX_CONFIG_FILE \
	--repl "$RENODE_REPL" \
	--resc "$RENODE_RESC" \
	--bios-binary "$TARGET_BUILD_DIR/software/bios/bios.bin" \
	--configure-network ${TAP_INTERFACE:-""}

$RENODE_BIN "$RENODE_RESC"

