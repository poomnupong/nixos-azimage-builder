# core_pulse.nix
#
# This is your primary NixOS customization module.
# Fork this repository and edit this file to tailor the image to your needs:
#   - Add system packages under `environment.systemPackages`
#   - Define user accounts under `users.users`
#   - Inject SSH public keys under `users.users.<name>.openssh.authorizedKeys.keys`
#
# After editing, push to `main` and the weekly_forge workflow will
# automatically build and publish a fresh Azure VHD release.

{ pkgs, lib, ... }:

{
  # ---------------------------------------------------------------------------
  # System packages
  # Add any tools you want present in the image.
  # ---------------------------------------------------------------------------
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
    vim
  ];

  # ---------------------------------------------------------------------------
  # User accounts
  # Replace or extend the example user below with your own accounts.
  # ---------------------------------------------------------------------------
  users.users.nixos = {
    isNormalUser = true;
    description = "Default NixOS user";
    extraGroups = [ "wheel" "networkmanager" ];

    # Add your SSH public keys here so you can log in after deployment.
    # Example:
    #   openssh.authorizedKeys.keys = [
    #     "ssh-ed25519 AAAA... you@yourhost"
    #   ];
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... your-key-here"
    ];
  };

  # Allow the default user to use sudo without a password (handy for CI/CD).
  security.sudo.wheelNeedsPassword = false;

  # ---------------------------------------------------------------------------
  # SSH daemon
  # ---------------------------------------------------------------------------
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = lib.mkForce "no";
    };
  };

  # ---------------------------------------------------------------------------
  # Locale / timezone – adjust as needed
  # ---------------------------------------------------------------------------
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # ---------------------------------------------------------------------------
  # Azure compliance — handled upstream, documented here for readers
  # ---------------------------------------------------------------------------
  # The `azure` format from nixos-generators imports nixpkgs'
  # `virtualisation/azure-common.nix`, which already configures every item on
  # Microsoft's "Prepare a Linux VHD for Azure" checklist:
  #
  #   * Azure Linux Agent (waagent) enabled — this is the VM *guest agent*
  #     Azure requires for provisioning, heartbeat, and extension handling
  #     (`services.waagent.enable = true`).
  #   * cloud-init enabled and paired with waagent: cloud-init performs
  #     provisioning (SSH host keys, user injection, network config) and
  #     waagent delegates to it (`Provisioning.Enable` defaults to
  #     `!cloud-init.enable`, so enabling cloud-init flips waagent into
  #     heartbeat/extension-only mode). This is the modern Azure Linux
  #     image pattern Microsoft documents.
  #   * Serial console on ttyS0 @ 115200 baud (Azure Serial Console).
  #   * Hyper-V kernel modules in initrd (hv_vmbus/netvsc/utils/storvsc).
  #   * No predictable interface names and no static /etc/resolv.conf, so
  #     the image is safe to clone across VM instances.
  #   * Hostname forced from Azure metadata (`networking.hostName = ""`).
  #
  # NOTE on Azure Monitor Agent (AMA): AMA is a VM *extension*, not a guest
  # agent, and is deliberately NOT baked into this image. Install it at
  # deploy time with a pinned `typeHandlerVersion` and
  # `autoUpgradeMinorVersion: false` in your ARM/Bicep/Terraform template —
  # see README → "Observability (optional)". Baking it in defeats the
  # deterministic-image goal because AMA auto-updates out-of-band.

  # Required by nixos-generators; do not remove.
  system.stateVersion = "24.11";
}
