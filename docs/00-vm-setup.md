# Phase 0 – VM Preparation (VMware Workstation + Ubuntu Server 24.04)

## 1. Create the VM
| Setting | Value |
|---|---|
| ISO | `ubuntu-24.04.x-live-server-amd64.iso` |
| CPU / RAM / Disk | 2 vCPU / 4 GB / 25 GB |
| Network | **NAT** (VM can reach the internet; host can reach VM IP) |
| Hostname | `ssb-lamp` |
| User | `ssbadmin` |
| Installer options | ✅ Install OpenSSH server · skip snaps |

## 2. First login – base packages
```bash
sudo apt update && sudo apt -y upgrade
sudo apt -y install git rsync curl wget net-tools tree unzip cron open-vm-tools
sudo timedatectl set-timezone Asia/Kolkata
ip -4 addr show | grep inet        # note the VM IP, e.g. 192.168.x.x
```

## 3. SSH from Windows (easier copy/paste than the VMware console)
```powershell
ssh ssbadmin@<VM_IP>
```

## 4. GitHub access from the VM
```bash
ssh-keygen -t ed25519 -C "ssb-lamp-vm"
cat ~/.ssh/id_ed25519.pub        # add at GitHub → Settings → SSH keys
ssh -T git@github.com            # expect: "Hi <user>! You've successfully authenticated"
git clone git@github.com:<user>/ssb-devops-assignment.git ~/ssb-devops-assignment
```

## 5. Snapshot
Take a VMware snapshot **"clean-base"** — lets you roll back if LAMPP setup goes wrong.

## Evidence to capture
- `screenshots/00-vm-info.png` — output of `hostnamectl && ip -4 a && df -h /`
