sudo apt update -y && sudo apt upgrade -y

sudo apt install -y git curl build-essential binwalk

curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install linux --no-confirm

mkdir -p ~/.config/nixpkgs/
echo "{ allowUnsupportedSystem = true; }" > ~/.config/nixpkgs/config.nix

git clone --recurse-submodules git@github.com:winstonwumbo/cse-597-nixWRehosT.git
cd nixwrehost

curl https://fastly-cdn.system-rescue.org/releases/12.02/systemrescue-12.02-amd64.iso -O