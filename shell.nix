{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Haskell tooling
    stack
    ghc
    haskell-language-server
    cabal-install

    # System dependencies
    zlib
    pkg-config

    # For Docker tests
    docker
    docker-compose
  ];

  shellHook = ''
    echo "AMQP client development environment"
    echo "Run 'stack build' to build"
    echo "Run 'stack test' to run tests"
  '';
}
