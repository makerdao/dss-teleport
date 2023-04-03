// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

contract VatMock {
    uint256 internal constant RAY = 10 ** 27;
    uint256 public live = 1;

    struct Urn {
        uint256 ink;   // Locked Collateral  [wad]
        uint256 art;   // Normalised Debt    [wad]
    }

    mapping (address => mapping (address => uint256)) public can;
    mapping (bytes32 => mapping (address => Urn ))    public urns;
    mapping (bytes32 => mapping (address => uint256)) public gem;
    mapping (address => uint256)                      public dai;
    mapping (address => uint256)                      public sin;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            require((z = x + y) >= x);
        }
    }
    function add(uint256 x, int256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x + uint256(y);
        }
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            require((z = x - y) <= x);
        }
    }
    function sub(uint256 x, int256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x - uint256(y);
        }
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }
    function mul(uint256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = int256(x) * y;
        }
        require(int256(x) >= 0);
        require(y == 0 || z / y == int256(x));
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    function wish(address bit, address usr) internal view returns (bool) {
        return either(bit == usr, can[bit][usr] == 1);
    }

    function hope(address usr) external {
        can[msg.sender][usr] = 1;
    }

    function cage() external {
        live = 0;
    }

    function frob(bytes32 i, address u, address v, address w, int256 dink, int256 dart) external {
        require(live == 1, "Vat/not-live");

        Urn memory urn = urns[i][u];

        urn.ink = add(urn.ink, dink);
        urn.art = add(urn.art, dart);

        int256 dtab = mul(RAY, dart);

        gem[i][v] = sub(gem[i][v], dink);
        dai[w]    = add(dai[w],    dtab);

        urns[i][u] = urn;
    }

    function grab(bytes32 i, address u, address v, address w, int256 dink, int256 dart) external {
        Urn storage urn = urns[i][u];

        urn.ink = add(urn.ink, dink);
        urn.art = add(urn.art, dart);

        int256 dtab = mul(RAY, dart);

        gem[i][v] = sub(gem[i][v], dink);
        sin[w]    = sub(sin[w],    dtab);
    }

    function move(address src, address dst, uint256 rad) external {
        require(wish(src, msg.sender), "Vat/not-allowed");
        dai[src] = sub(dai[src], rad);
        dai[dst] = add(dai[dst], rad);
    }

    function slip(bytes32 ilk, address usr, int256 wad) external {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }

    function suck(address u, address v, uint256 rad) external {
        sin[u] = add(sin[u], rad);
        dai[v] = add(dai[v], rad);
    }
}
