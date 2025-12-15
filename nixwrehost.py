import subprocess
from pathlib import Path

firmware = input("Firmware image to rehost: ")
subprocess.run([
    "binwalk",
    "-eM",
    "--preserve-symlinks",
    f"{firmware}"
    ])

if not Path("result/run.sh").is_file():
    subprocess.run([
        "nix-build",
        "-I", "rehost-config=./src/nixwrt-build.nix",
        "--arg", "device", "import ./qemu",
        "--argstr", "image", f"_{firmware}.extracted/",
        "-A", "outputs.default"
    ])

print("Starting nixWRehosT Runner...")
bg_proc = subprocess.Popen(
    [
        "bash", "result/run.sh"
    ],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL
)
print("Started nixWRehosT Runner: PID ", bg_proc.pid)

print("Starting nixWRehosT Viewer (terminal will be taken over)...")
subprocess.run([
    "nix-shell", "-p", "qemu", "--run",
        " ".join([
            "qemu-system-x86_64",
            "-echr", "16",
            "-m", "1024",
            "-cdrom", "systemrescue-12.02-amd64.iso",
            "-netdev", "socket,mcast=230.0.0.1:1235,localaddr=127.0.0.1,id=lan",
            "-device", "virtio-net,disable-legacy=on,disable-modern=off,netdev=lan,mac=ba:ad:3d:ea:21:01",
            "-display", "none",
            "-serial", "mon:stdio"
        ])
    ],
    stdin=None,    # attach to your actual terminal
    stdout=None,   # default, terminal output
    stderr=None    # defaul)
)

print("Exited nixWRehosT Viewer...")