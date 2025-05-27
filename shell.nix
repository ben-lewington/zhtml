let
    pkgs = import <nixpkgs> {};
    unstable = import (pkgs.fetchFromGitHub {
        owner = "NixOS";
        repo = "nixpkgs";
        rev = "3730d8a308f94996a9ba7c7138ede69c1b9ac4ae";
        hash = "sha256-7+pG1I9jvxNlmln4YgnlW4o+w0TZX24k688mibiFDUE=";
    }){ config = pkgs.config; };
in pkgs.mkShell {
    nativeBuildInputs = with pkgs.buildPackages; [
        code-cursor
        unstable.zls
        unstable.zig
    ];
}
