{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/virtualisation/azure-common.nix"
    "${modulesPath}/virtualisation/azure-image.nix"
  ];

  # Use Generation 2 (UEFI) VMs for modern Azure support
  virtualisation.azureImage.vmGeneration = "v2";

  # Root disk size in MB
  virtualisation.diskSize = 4096;

  # Hostname (Azure sets this at provisioning time via the agent)
  networking.hostName = lib.mkDefault "";

  # SSH access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Expand root partition to fill disk on first boot
  boot.growPartition = true;

  # Latest kernel for best Hyper-V / Azure hardware support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Basic system packages
  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    wget
  ];

  # Enable flakes and the new CLI
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.05";
}
