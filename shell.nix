{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Haskell tooling
    stack

    # System dependencies
    zlib
    zlib.dev
    pkg-config
    gmp
    gmp.dev

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
