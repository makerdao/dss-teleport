{ dappPkgs ? (
    import (fetchTarball "https://github.com/makerdao/makerpkgs/tarball/master") {}
  ).dappPkgsVersions.hevm-0_49_0
}: with dappPkgs;

mkShell {
  DAPP_SOLC = solc-static-versions.solc_0_8_9 + "/bin/solc-0.8.9";
  # No optimizations
  SOLC_FLAGS = "";
  buildInputs = [
    dapp
  ];

  shellHook = ''
    export NIX_SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    unset SSL_CERT_FILE
  '';
}
