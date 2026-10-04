// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Bn254Poseidon} from "../src/libraries/Bn254Poseidon.sol";
import {Bn254PoseidonReference} from "./reference/Bn254PoseidonReference.sol";

/// @dev The generated library must agree with the straightforward evaluation of the same parameters
/// (test/reference, the code the first mainnet vault was deployed with) on every input, including values at
/// and above the modulus. With ETHEREUM_MAINNET_RPC set, the deployed library itself is the second oracle.
contract Bn254PoseidonDifferentialTest is Test {
    uint256 constant P = Bn254Poseidon.FIELD_MODULUS;
    uint256 constant DOMAIN_NODE = 0x7a6b6170692e76322e6e6f6465;
    address constant MAINNET_LIBRARY = 0xc6B55e86668d8c446B3D81273AAb9CBb20F28c7f;
    uint256 constant FORK_SAMPLES = 10_000;
    uint256 constant FORK_CHUNK = 500;

    uint256[] edge;

    function setUp() public {
        edge = [0, 1, 2, P - 2, P - 1, P, P + 1, 2 * P - 1, 2 * P, type(uint256).max - 1, type(uint256).max];
        edge.push(uint256(keccak256("edge")));
    }

    function test_referenceMatchesManifestVectors() public pure {
        assertEq(
            Bn254PoseidonReference.hash3(1, 2, 3), 0x1e706b0afc828a5262be1773734e80df7fa9c0aa25c8fd5dfb008122a62e65ca
        );
        assertEq(
            Bn254PoseidonReference.hash5(1, 2, 3, 4, 5),
            0x26081ccbe44f775603e118e5d9152fbbff51c9d7af1a96c9d25ddc7cbed55457
        );
    }

    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_hash3MatchesReference(uint256 a, uint256 b, uint256 c) public pure {
        assertEq(Bn254Poseidon.hash3(a, b, c), Bn254PoseidonReference.hash3(a, b, c));
    }

    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_hash5MatchesReference(uint256 a, uint256 b, uint256 c, uint256 d, uint256 e) public pure {
        assertEq(Bn254Poseidon.hash5(a, b, c, d, e), Bn254PoseidonReference.hash5(a, b, c, d, e));
    }

    function testFuzz_hash3PairPath32MatchesReference(
        uint256 domain,
        uint32 index,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256[32] memory siblings
    ) public view {
        (uint256 oldRoot, uint256 newRoot) = this.pathGenerated(domain, index, oldLeaf, newLeaf, siblings);
        (uint256 oldRootRef, uint256 newRootRef) = this.pathReference(domain, index, oldLeaf, newLeaf, siblings);
        assertEq(oldRoot, oldRootRef);
        assertEq(newRoot, newRootRef);
    }

    function test_edgeCasesMatchReference() public view {
        uint256 n = edge.length;
        for (uint256 i = 0; i < n; ++i) {
            for (uint256 j = 0; j < n; ++j) {
                for (uint256 k = 0; k < n; ++k) {
                    assertEq(
                        Bn254Poseidon.hash3(edge[i], edge[j], edge[k]),
                        Bn254PoseidonReference.hash3(edge[i], edge[j], edge[k])
                    );
                }
                _assertHash5(edge[i], edge[j], edge[i], edge[j], edge[i]);
                _assertHash5(edge[j], edge[i], edge[i], edge[i], edge[j]);
                _assertHash5(edge[i], edge[i], edge[j], edge[j], edge[j]);
            }
            _assertHash5(edge[i], edge[i], edge[i], edge[i], edge[i]);
            for (uint256 pos = 0; pos < 5; ++pos) {
                uint256[5] memory v = [uint256(1), 2, 3, 4, 5];
                v[pos] = edge[i];
                _assertHash5(v[0], v[1], v[2], v[3], v[4]);
            }
        }
    }

    function test_pathEdgeCasesMatchReference() public view {
        uint256[32] memory siblings;
        uint32[4] memory indexes = [uint32(0), 1, 0x55555555, type(uint32).max];
        for (uint256 i = 0; i < edge.length; ++i) {
            for (uint256 level = 0; level < 32; ++level) {
                siblings[level] = edge[(i + level) % edge.length];
            }
            for (uint256 x = 0; x < indexes.length; ++x) {
                (uint256 oldRoot, uint256 newRoot) = this.pathGenerated(
                    edge[i], indexes[x], edge[(i + 1) % edge.length], edge[(i + 2) % edge.length], siblings
                );
                (uint256 oldRootRef, uint256 newRootRef) = this.pathReference(
                    edge[i], indexes[x], edge[(i + 1) % edge.length], edge[(i + 2) % edge.length], siblings
                );
                assertEq(oldRoot, oldRootRef);
                assertEq(newRoot, newRootRef);
            }
        }
    }

    /// @dev The empty-tree zeros are what every client, the indexer and the Rust side agree on today.
    function test_emptyTreeZerosMatchReference() public pure {
        uint256 zero;
        uint256 zeroRef;
        for (uint256 level = 0; level < 32; ++level) {
            zero = Bn254Poseidon.hash3(DOMAIN_NODE, zero, zero);
            zeroRef = Bn254PoseidonReference.hash3(DOMAIN_NODE, zeroRef, zeroRef);
            assertEq(zero, zeroRef);
        }
    }

    /// @dev 10,000 deterministic inputs per function against the deployed library. The fork is created once
    /// and gas metering is paused, since the generic library alone burns ~1G gas over the sweep; the work is
    /// chunked through external self-calls so memory does not grow unbounded.
    function test_fork_hash3MatchesDeployedLibrary() public {
        if (!_selectMainnetFork()) return;
        vm.pauseGasMetering();
        for (uint256 start = 0; start < FORK_SAMPLES; start += FORK_CHUNK) {
            this.forkChunkHash3(start, FORK_CHUNK);
        }
        vm.resumeGasMetering();
    }

    function test_fork_hash5MatchesDeployedLibrary() public {
        if (!_selectMainnetFork()) return;
        vm.pauseGasMetering();
        for (uint256 start = 0; start < FORK_SAMPLES; start += FORK_CHUNK) {
            this.forkChunkHash5(start, FORK_CHUNK);
        }
        vm.resumeGasMetering();
    }

    function forkChunkHash3(uint256 start, uint256 count) external view {
        for (uint256 i = start; i < start + count; ++i) {
            (uint256 a, uint256 b, uint256 c,,) = _sample(i);
            assertEq(
                Bn254Poseidon.hash3(a, b, c),
                _deployed(abi.encodeWithSignature("hash3(uint256,uint256,uint256)", a, b, c))
            );
        }
    }

    function forkChunkHash5(uint256 start, uint256 count) external view {
        for (uint256 i = start; i < start + count; ++i) {
            (uint256 a, uint256 b, uint256 c, uint256 d, uint256 e) = _sample(i);
            assertEq(
                Bn254Poseidon.hash5(a, b, c, d, e),
                _deployed(abi.encodeWithSignature("hash5(uint256,uint256,uint256,uint256,uint256)", a, b, c, d, e))
            );
        }
    }

    function test_fork_edgeCasesMatchDeployedLibrary() public {
        if (!_selectMainnetFork()) return;
        uint256 n = edge.length;
        for (uint256 i = 0; i < n; ++i) {
            for (uint256 j = 0; j < n; ++j) {
                uint256 k = edge[(i + j) % n];
                assertEq(
                    Bn254Poseidon.hash3(edge[i], edge[j], k),
                    _deployed(abi.encodeWithSignature("hash3(uint256,uint256,uint256)", edge[i], edge[j], k))
                );
                assertEq(
                    Bn254Poseidon.hash5(edge[i], edge[j], k, edge[i], edge[j]),
                    _deployed(
                        abi.encodeWithSignature(
                            "hash5(uint256,uint256,uint256,uint256,uint256)", edge[i], edge[j], k, edge[i], edge[j]
                        )
                    )
                );
            }
        }
    }

    function test_fork_hash3PairPath32MatchesDeployedLibrary() public {
        if (!_selectMainnetFork()) return;
        uint256[32] memory siblings;
        for (uint256 i = 0; i < 64; ++i) {
            for (uint256 level = 0; level < 32; ++level) {
                siblings[level] = uint256(keccak256(abi.encode("sibling", i, level)));
            }
            uint256 domain = i % 2 == 0 ? DOMAIN_NODE : uint256(keccak256(abi.encode("domain", i)));
            uint256 oldLeaf = edge[i % edge.length];
            uint256 newLeaf = uint256(keccak256(abi.encode("leaf", i)));
            uint32 index = uint32(uint256(keccak256(abi.encode("index", i))));
            bytes memory ret = _deployedRaw(
                abi.encodeWithSignature(
                    "hash3PairPath32(uint256,uint32,uint256,uint256,uint256[32])",
                    domain,
                    index,
                    oldLeaf,
                    newLeaf,
                    siblings
                )
            );
            (uint256 oldRootDeployed, uint256 newRootDeployed) = abi.decode(ret, (uint256, uint256));
            (uint256 oldRoot, uint256 newRoot) = this.pathGenerated(domain, index, oldLeaf, newLeaf, siblings);
            assertEq(oldRoot, oldRootDeployed);
            assertEq(newRoot, newRootDeployed);
        }
    }

    function pathGenerated(
        uint256 domain,
        uint32 index,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256[32] calldata siblings
    ) external pure returns (uint256, uint256) {
        return Bn254Poseidon.hash3PairPath32(domain, index, oldLeaf, newLeaf, siblings);
    }

    function pathReference(
        uint256 domain,
        uint32 index,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256[32] calldata siblings
    ) external pure returns (uint256, uint256) {
        return Bn254PoseidonReference.hash3PairPath32(domain, index, oldLeaf, newLeaf, siblings);
    }

    function _assertHash5(uint256 a, uint256 b, uint256 c, uint256 d, uint256 e) internal pure {
        assertEq(Bn254Poseidon.hash5(a, b, c, d, e), Bn254PoseidonReference.hash5(a, b, c, d, e));
    }

    /// @dev Deterministic inputs: every pair of edge values first, then keccak-derived words, most of them
    /// above the modulus like uniformly random 256-bit values are; every seventh sample repeats a lane.
    function _sample(uint256 i) internal view returns (uint256 a, uint256 b, uint256 c, uint256 d, uint256 e) {
        uint256 n = edge.length;
        if (i < n * n) {
            return (edge[i / n], edge[i % n], edge[(i / n + i) % n], edge[(i * 7) % n], edge[(i * 3 + 1) % n]);
        }
        bytes32 seed = keccak256(abi.encode("zkapi-poseidon-differential", i));
        a = uint256(seed);
        b = uint256(keccak256(abi.encode(seed, 1)));
        c = uint256(keccak256(abi.encode(seed, 2)));
        d = uint256(keccak256(abi.encode(seed, 3)));
        e = uint256(keccak256(abi.encode(seed, 4)));
        if (i % 5 == 0) a %= P;
        if (i % 7 == 0) (b, c) = (a, a);
    }

    function _selectMainnetFork() internal returns (bool) {
        string memory rpc = vm.envOr("ETHEREUM_MAINNET_RPC", string(""));
        if (bytes(rpc).length == 0) return false;
        uint256 blockNumber = vm.envOr("ETHEREUM_MAINNET_FORK_BLOCK", uint256(0));
        if (blockNumber == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, blockNumber);
        assertGt(MAINNET_LIBRARY.code.length, 0, "deployed library not found on fork");
        return true;
    }

    function _deployed(bytes memory data) internal view returns (uint256) {
        return abi.decode(_deployedRaw(data), (uint256));
    }

    function _deployedRaw(bytes memory data) internal view returns (bytes memory) {
        (bool ok, bytes memory ret) = MAINNET_LIBRARY.staticcall(data);
        require(ok, "deployed library call failed");
        return ret;
    }
}
