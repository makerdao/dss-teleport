{ dappPkgs ? (
    import (fetchTarball "https://github.com/makerdao/makerpkgs/tarball/master") {}
  ).dappPkgsVersions.master-20220325
}: with dappPkgs;

mkShell {
  DAPP_SOLC = solc-static-versions.solc_0_8_13 + "/bin/solc-0.8.13";
  SOLC_FLAGS = "--optimize --optimize-runs=200";
  buildInputs = [
    dapp
  ];

  shellHook = ''
    export NIX_SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    unset SSL_CERT_FILE
  '';
}
