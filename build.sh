#!/bin/bash

# Global used variables
# NUM_PROC=$NUM_PROC
NUM_PROC=8
ROOT_DIR=$(pwd)
KYLINUX_DIR="$ROOT_DIR/kylinux"
CONFIG_DIR="$ROOT_DIR/config"

KERNEL_DIR="$KYLINUX_DIR/kernel"
KERNEL_FILENAME="linux-6.12.9.tar.xz"

GLIBC_DIR="$KYLINUX_DIR/glibc"
GLIBC_FILENAME="glibc-2.40.tar.xz"

SYSROOT_DIR="$KYLINUX_DIR/sysroot"

BUSYBOX_DIR="$KYLINUX_DIR/busybox"
BUSYBOX_FILENAME="busybox-1.37.0.tar.bz2"

ROOTFS_DIR="$KYLINUX_DIR/rootfs"

ISO_DIR="$KYLINUX_DIR/iso"
BOOT_DIR="$ISO_DIR/boot"
GRUB_DIR="$BOOT_DIR/grub"

DEVICE="/dev/sda"
INSTALL_DEVICE="/dev/sdb"
ROOTFS_DEVICE="${DEVICE}2"
INITRAMFS_DIR="$KYLINUX_DIR/initramfs"

BOOT_MOUNT_POINT="/mnt/boot"
EFI_MOUNT_POINT="/mnt/boot/efi"

# Initialize the directory
init_directory() {
    rm -rf "$KYLINUX_DIR"
    mkdir "$KYLINUX_DIR"
}

# Build Linux kernel
build_linux_kernel() {
    rm -rf "$KERNEL_DIR"
    mkdir "$KERNEL_DIR"
    cd "$KERNEL_DIR"
    wget "https://cdn.kernel.org/pub/linux/kernel/v6.x/$KERNEL_FILENAME"
    tar -xJf "$KERNEL_FILENAME"
    cd "${KERNEL_FILENAME%.tar.xz}"
    make x86_64_defconfig

    # Update .config to install necessary drivers
    module_list=$(grep -v '^[[:space:]]*$' "$CONFIG_DIR/module_list")
    # NOTE: config not exists may not be appended because the Kbuild system
    # will automatically modify it.
    for module in $module_list; do
        # Process each module name
        echo "$module"
        source scripts/config --enable "CONFIG_${module^^}"
        # sed -i -E "s/^# CONFIG_${module^^} is not set$/CONFIG_${module^^}=y/; s/^CONFIG_${module^^}=(y|m)$/CONFIG_${module^^}=y/" .config
    done

    make olddefconfig

    yes n | make bzImage -j $NUM_PROC
}

# Build and install glibc
build_glibc() {
    rm -rf "$GLIBC_DIR"
    mkdir "$GLIBC_DIR"
    cd "$GLIBC_DIR"
    # wget "https://ftp.gnu.org/gnu/glibc/$GLIBC_FILENAME"
    wget "https://mirror.ossplanet.net/gnu/glibc/$GLIBC_FILENAME"  # mirror is used
    tar -xJf "$GLIBC_FILENAME"
    cd "${GLIBC_FILENAME%.tar.xz}"
    mkdir build glibc
    cd build
    # NOTE: set `--prefix=` is important;
    # it will 
    "$GLIBC_DIR/${GLIBC_FILENAME%.tar.xz}/configure" \
        --prefix= \
        --host=x86_64-linux-gnu \
        --build=x86_64-linux-gnu \
        CC="gcc -m64" \
        CXX="g++ -m64" \
        CFLAGS="-O3" \
        CXXFLAGS="-O3"
    make -j $NUM_PROC
    make DESTDIR="$GLIBC_DIR/glibc" install
}

# Create sysroot for building busybox
create_sysroot() {
    rm -rf "$SYSROOT_DIR"
    mkdir -p "$SYSROOT_DIR/usr"
    cp -r "$GLIBC_DIR/glibc/"* "$SYSROOT_DIR"
    rsync -a /usr/include "$SYSROOT_DIR"
    # link with relative path is necessary:
    # `sysroot/usr/include` will point to `sysroot/include`; and
    # `sysroot/usr/lib` will point to `sysroot/lib`
    ln -s ../include "$SYSROOT_DIR/usr/include"
    ln -s ../lib "$SYSROOT_DIR/usr/lib"
}

# Build and install busybox
build_busybox() {
    rm -rf "$BUSYBOX_DIR"
    mkdir "$BUSYBOX_DIR"
    cd "$BUSYBOX_DIR"
    wget "https://busybox.net/downloads/$BUSYBOX_FILENAME"
    tar -xvjf "$BUSYBOX_FILENAME"
    cd "${BUSYBOX_FILENAME%.tar.bz2}"
    make defconfig
    # `kylinux/sysroot` relative to the current directory `kylinux/busybox/busybox-1.37.0` is: `../../sysroot`
    sed -i "s|.*CONFIG_SYSROOT.*|CONFIG_SYSROOT=\"../../sysroot\"|" .config
    sed -i "s|.*CONFIG_EXTRA_CFLAGS.*|CONFIG_EXTRA_CFLAGS=\"-L../../sysroot/lib\"|" .config
    make -j $NUM_PROC
    make CONFIG_PREFIX="$BUSYBOX_DIR/busybox" install
}

# Create rootfs based on busybox and glibc
create_rootfs() {
    rm -rf "$ROOTFS_DIR"
    cp -r "$SYSROOT_DIR" "$ROOTFS_DIR"
    rsync -a "$BUSYBOX_DIR/busybox/" "$ROOTFS_DIR"
    cd "$ROOTFS_DIR"
    sed -i 's|^#!/bin/bash|#!/bin/sh|' bin/ldd
    rm linuxrc
    mkdir dev proc sys

    # Create `/init` script, the first process Linux kernel runs on boot
    cat <<EOF > init
#!/bin/sh

# Supress kernel messages
dmesg -n 1
# clear

# Mount virtual filesystem
mount -t devtmpfs none /dev
mount -t proc none /proc
mount -t sysfs none /sys

# Setup networking
for NETDEV in /sys/class/net/* ; do
    echo "Found network device \${NETDEV##*/}"
    ip link set \${NETDEV##*/} up
    [ \${NETDEV##*/} != lo ] && udhcpc -b -i \${NETDEV##*/} -s /etc/network.sh
done

# Start Busybox init as PID 1
exec /sbin/init
EOF
    
    chmod a+x init

    # Create `/etc/inittab` for busybox `/sbin/init`
    cd etc

    cat <<EOF > network.sh
#!/bin/sh

# Setup IP addreess and mask
ip addr add \$ip/\$mask dev \$interface
if [ "\$router" ]; then
    ip route add default via \$router dev \$interface
fi

# Print debug info.
if [ "\$ip" ]; then
    echo -e "DHCP configuration for device \$interface"
    echo -e "IP:       \\e[1m\$ip\\e[0m"
    echo -e "Mask:     \\e[1m\$mask\\e[0m"
    echo -e "Router:   \\e[1m\$router\\e[0m"
fi
EOF
    chmod a+x network.sh

    cat <<EOF > shell.sh
# NOTE: environment variable can be added before run the sh
# e.g.
# PATH=$PATH:/home/go/bin GOROOT=/home/go sh
sh
EOF

    chmod a+x shell.sh

    cat <<EOF > logo.txt
  _              _   _                        
 | |            | | (_)                       
 | | __  _   _  | |  _   _ __    _   _  __  __
 | |/ / | | | | | | | | | '_ \  | | | | \ \/ /
 |   <  | |_| | | | | | | | | | | |_| |  >  < 
 |_|\_\  \__, | |_| |_| |_| |_|  \__,_| /_/\_\ 
          __/ |                               
         |___/                                


EOF

    cat <<EOF > inittab
::sysinit:clear
::sysinit:cat /etc/logo.txt
::restart:/sbin/init
::shutdown:sync
::shutdown:umount -a
::ctrlaltdel:/sbin/reboot
::respawn:/bin/cttyhack /etc/shell.sh
EOF

    cat <<EOF > resolv.conf
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

    # Symlink `/lib64` to `/lib`
    cd "$ROOTFS_DIR"
    ln -s lib lib64
}

# Configure GRUB
configure_grub() {
    rm -rf "$GRUB_DIR"
    mkdir -p "$GRUB_DIR"
    cd "$GRUB_DIR"
    cat <<EOF >> grub.cfg
set default=0
set timeout=10

insmod efi_gop
insmod font
if loadfont /boot/grub/fonts/unicode.pf2
then
    insmod gfxterm
    set gfxmode=auto
    set gfxpayload=keep
    terminal_output gfxterm
fi

menuentry "kylinux" --class os {
    insmod gzio
    insmod part_msdos
    linux /boot/bzImage
    initrd /boot/rootfs.cpio.gz
}
EOF
}

pack_iso() {
    # Pack rootfs as initramfs(rootfs.cpio.gz)
    cd "$ROOTFS_DIR"
    find . | cpio -o -H newc | gzip > "$BOOT_DIR/rootfs.cpio.gz"

    # Install Linux kernel to iso
    cp "$KERNEL_DIR/${KERNEL_FILENAME%.tar.xz}/arch/x86/boot/bzImage" "$BOOT_DIR"

    cd "$KYLINUX_DIR"
    sudo grub-mkrescue -o kylinux.iso "$ISO_DIR"
}

test_iso() {
    # Test iso file with qemu
    # qemu-system-x86_64 -display curses --cdrom kylinux.iso
    cd "$KYLINUX_DIR"
    sudo qemu-system-x86_64 --cdrom kylinux.iso -m 1G -enable-kvm -cpu host
}

create_bootable_usb() {
    # Prepare the bootable device
    cd "$ROOT_DIR"
    source utils/create_bootable_usb.sh
}

create_initramfs() {
    # Prepare the initramfs
    mkdir -p "$INITRAMFS_DIR/root/boot/grub"
    cp -r "$ROOTFS_DIR/"* "$INITRAMFS_DIR/root"
    cp "$BOOT_DIR/bzImage" "$INITRAMFS_DIR/root/boot"
    cp -r "$ROOTFS_DIR" "$INITRAMFS_DIR/rootfs"
    cd "$INITRAMFS_DIR/rootfs"
    cat <<EOF > init
#!/bin/sh
dmesg -n 1
clear

mkdir -p dev
mkdir -p proc
mkdir -p sys

mount -t devtmpfs none /dev
mount -t proc none /proc
mount -t sysfs none /sys

cat /etc/logo.txt

echo switching to rootfs at $ROOTFS_DEVICE
sleep 5

mkdir mnt
mount $ROOTFS_DEVICE /mnt

exec switch_root /mnt /init
EOF

    find . | cpio -o -H newc | gzip > "$INITRAMFS_DIR/root/boot/rootfs.cpio.gz"
}

install_usb() {
    sudo cp -r "$INITRAMFS_DIR/root/"* "$BOOT_MOUNT_POINT"
    sudo grub-install --target=x86_64-efi --efi-directory=$EFI_MOUNT_POINT --boot-directory=$BOOT_MOUNT_POINT --removable --recheck $INSTALL_DEVICE
    sudo cp -r "$GRUB_DIR/"* "$BOOT_MOUNT_POINT/grub"
    df
}

init_directory
build_linux_kernel
build_glibc
create_sysroot
build_busybox
create_rootfs
configure_grub
pack_iso
create_bootable_usb
create_initramfs
install_usb
test_iso
