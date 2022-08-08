{ url, dappPkgs ? (
    import (fetchTarball "https://github.com/makerdao/makerpkgs/tarball/master") {}
  ).dappPkgsVersions.master-20220803
}: with dappPkgs;

mkShell {
  DAPP_SOLC = solc-static-versions.solc_0_8_15 + "/bin/solc-0.8.15";
  buildInputs = [
    dapp
  ];

  shellHook = ''
    export NIX_SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    export DAPP_BUILD_OPTIMIZE=1
    export DAPP_BUILD_OPTIMIZE_RUNS=200
    export ETH_RPC_URL="''${ETH_RPC_URL:-${url}}"
    unset SSL_CERT_FILE
  '';
}
