## nixWRehosT

A novel research project for **CSE 597: Securing Embedded Systems** at Penn State University. The goal is to successfully rehost the **nixWRT** firmware image on QEMU.

## Setup
The `Vagrantfile` for **nixWRehosT** is currently configured for `libvirt` and `sshfs` (to support my personal system). To use another virtualization platform, please modify the [Vagrantfile](./Vagrantfile).

Once a compatible Vagrant backend is configured, start then enter the **nixWRehosT** virtual machine:
```
$ vagrant up
$ vagrant ssh
```

To start the demonstration of **nixWRehosT**, run the Python wrapper script and point it at the right firmware binary:
```
$ cd nixwrehost
$ python3 nixwrehost.py
Firmware image to rehost: images/nixwrt.bin
```