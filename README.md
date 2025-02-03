# kylinux
Build a Linux kernel from scratch and create a bootable USB with EFI.

## Preface
This is a simple script to build a Linux kernel from scratch and create a bootable USB with EFI.  

Most of things are followed by the [Monkey See, Monkey Do LINUX](https://youtube.com/playlist?list=PLLfIBXQeu3aZuc_0xTE2dY3juntHF5xJY&si=jyEZaNNDnsLtXj0K) series and [msmd-linux](https://github.com/maksimKorzh/msmd-linux). I have just modified all the parts in the tutorials that were directly downloaded from its own GitHub repository without mentioning how to create them.  

The platform to build the Linux kernel is **64-bit Ubuntu 22.04**. All necessary tools are supposed to be included in. No extra installation is required.  


## Customized configurations
By default, the script `build.sh` works fine. Some customized configurations should be made if necessary.

### Version  
Some global variables controlled the version are defined in the top of the `build.sh`:  
```bash
KERNEL_FILENAME="linux-6.12.9.tar.xz"
GLIBC_FILENAME="glibc-2.40.tar.xz"
BUSYBOX_FILENAME="busybox-1.37.0.tar.bz2"
```
One may want to change the version to fit his/her needs.

### Source for download
By default, the source code are downloaded from the official websites. One may want to change it to a mirror for faster download.
```bash
# Build and install glibc
build_glibc() {
    rm -rf "$GLIBC_DIR"
    mkdir "$GLIBC_DIR"
    cd "$GLIBC_DIR"
    # wget "https://ftp.gnu.org/gnu/glibc/$GLIBC_FILENAME"
    wget "https://mirror.ossplanet.net/gnu/glibc/$GLIBC_FILENAME"  # mirror is used
    #...
}
```
For example, the default url for glibc is https://ftp.gnu.org/gnu/glibc. It is changed to the mirror https://mirror.ossplanet.net/gnu/glibc.

### Platform
By default, the target platform is 64-bit. Because almost all the things are compiled and built from scratch, the target platform is also needed to be specified. If one wants to build for 32-bit machine, the Linux kernel, glibc, and busybox should all be compiled and built for 32-bit.  
Note:  
1. `/include` and `/lib` in sysroot are directly synced from `/usr/include` and `/usr/lib`. If one wants to compile and build 32-bit busybox with sysroot, one should check the `/usr/include` and `/usr/lib` are 32-bit or 64-bit.  
2. There is a symbol link `/lib64` to `/lib` when creating the rootfs. It is also needed to be changed to `/lib32`.
3. Also, when installing GRUB to the USB, the target platform should be specified to 32-bit.

### Device
In `utils/create_bootable_usb.sh`, the device to create the bootable USB is specified by the variable `DEVICE`. By default, it is `/dev/sdb`. One may want to change it to another device.

Note that `INSTALL_DEVICE` in `build.sh` should be the same as `DEVICE` in `utils/create_bootable_usb.sh`. They both means the device path on the **host**, while `DEVICE` in `build.sh` means the device path on the **target machine(not the host)**.

### Modules
To trigger the hardware devices on the target machine, some necessary modules are needed when compiling the Linux kernel. Remember to update the `config/module_list` for the target machine. If one doesn't know which modules are needed, one can use `make allmodconfig` or `make allyesconfig` to enable almost all available modules but the Linux kernel will be very large and the build process will take a long time. Instead, one can use `make localmodconfig` or `make localyesconfig` to enable only the loaded modules(lsmod) on the host.

### Test
The iso file is also created and tested with QEMU. The QEMU should be modified to 32-bit if 32-bit version is used.

## DIY
After watching the series of the tutorials [Monkey See, Monkey Do LINUX](https://youtube.com/playlist?list=PLLfIBXQeu3aZuc_0xTE2dY3juntHF5xJY&si=jyEZaNNDnsLtXj0K) and successfully running the `build.sh` script to create your own bootable USB, there are still some additional things that can be added to the script to become more familiar with the process:  
1. Install static vim binary file
2. Install Python3 binary file(Note build Python statically is difficult...)
3. install the wifi firmware for the target machine and test whether it is working

## Reference
[Monkey See, Monkey Do LINUX](https://youtube.com/playlist?list=PLLfIBXQeu3aZuc_0xTE2dY3juntHF5xJY&si=jyEZaNNDnsLtXj0K)  
[msmd-linux](https://github.com/maksimKorzh/msmd-linux)