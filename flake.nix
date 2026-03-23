{
  description = "NixOS Azure VHD Image Builder";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations.azure-image = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./configuration.nix ];
    };

    packages.x86_64-linux.default =
      self.nixosConfigurations.azure-image.config.system.build.images.azure;

    packages.x86_64-linux.azure-image =
      self.nixosConfigurations.azure-image.config.system.build.images.azure;
  };
}
