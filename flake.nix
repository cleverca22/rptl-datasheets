{
  outputs = { self, nixpkgs }:
  {
    packages.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.writeShellScriptBin "sync"
    ''
      export PATH=${nixpkgs.legacyPackages.x86_64-linux.awscli}/bin/:$PATH
      ./sync
    '';
  };
}
