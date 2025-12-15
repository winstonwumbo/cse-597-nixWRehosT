sudo apt update -y && sudo apt upgrade -y

sudo apt install -y git curl build-essential binwalk

curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install linux --no-confirm
# git clone https://github.com/mathiashro/nixwrt.git

# git clone -n  https://github.com/nixos/nixpkgs.git && \
#    (cd nixpkgs && git checkout bc675971dae581ec653fa6)

mkdir -p ~/.config/nixpkgs/
echo "{ allowUnsupportedSystem = true; }" > ~/.config/nixpkgs/config.nix

cp -r /vagrant ~/nixwrehost
cd nixwrehost

curl https://fastly-cdn.system-rescue.org/releases/12.02/systemrescue-12.02-amd64.iso -O