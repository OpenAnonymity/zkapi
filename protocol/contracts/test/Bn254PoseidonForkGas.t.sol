// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ZkApiVault} from "../src/ZkApiVault.sol";
import {Types} from "../src/libraries/Types.sol";
import {Bn254Poseidon} from "../src/libraries/Bn254Poseidon.sol";

/// @dev Runs a deposit against the mainnet vault on a fork twice: once as deployed, once with the generated
/// library's code placed at the deployed library's address. Both must produce the same root; the gas of each
/// is logged. Skipped unless ETHEREUM_MAINNET_RPC is set (ETHEREUM_MAINNET_FORK_BLOCK pins the block).
contract Bn254PoseidonForkGasTest is Test {
    ZkApiVault constant VAULT = ZkApiVault(payable(0x4386FDbdA35D995beB3BF8625118Ec5982ec81fe));
    address constant MAINNET_LIBRARY = 0xc6B55e86668d8c446B3D81273AAb9CBb20F28c7f;
    uint256 constant DOMAIN_NODE = 0x7a6b6170692e76322e6e6f6465;
    uint256 constant DOMAIN_LEAF = 0x7a6b6170692e76322e6c656166;
    uint128 constant AMOUNT = 1_000_000;

    function test_fork_depositWithGeneratedLibraryMatchesDeployed() public {
        string memory rpc = vm.envOr("ETHEREUM_MAINNET_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        uint256 blockNumber = vm.envOr("ETHEREUM_MAINNET_FORK_BLOCK", uint256(0));
        if (blockNumber == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, blockNumber);
        require(VAULT.nextNoteId() > 0 && MAINNET_LIBRARY.code.length > 0, "fork has no vault state");

        uint32 noteId = VAULT.nextNoteId();
        uint256[32] memory siblings = _siblings(noteId);
        bytes32 commitment = bytes32(uint256(keccak256("fork gas probe")) % Bn254Poseidon.FIELD_MODULUS);
        address depositor = makeAddr("depositor");
        vm.deal(depositor, 1 ether);

        uint256 snapshot = vm.snapshotState();
        (uint256 gasDeployed, uint256 rootDeployed) = _deposit(depositor, commitment, siblings);
        vm.revertToState(snapshot);

        vm.etch(MAINNET_LIBRARY, vm.getDeployedCode("Bn254Poseidon.sol:Bn254Poseidon"));
        (uint256 gasGenerated, uint256 rootGenerated) = _deposit(depositor, commitment, siblings);

        assertEq(rootGenerated, rootDeployed, "generated library produced a different root on the live tree");
        console2.log("mainnet vault deposit, note id", noteId);
        console2.log("  gas with the deployed library ", gasDeployed);
        console2.log("  gas with the generated library", gasGenerated);
    }

    function _deposit(address depositor, bytes32 commitment, uint256[32] memory siblings)
        internal
        returns (uint256 gasUsed, uint256 root)
    {
        vm.prank(depositor);
        gasUsed = gasleft();
        VAULT.deposit{value: uint256(AMOUNT) * 1 gwei}(commitment, AMOUNT, siblings);
        gasUsed -= gasleft();
        root = VAULT.currentRoot();
    }

    /// @dev Rebuilds the live tree from the vault's own note records (a leaf is zero unless the note is Active)
    /// and returns the authentication path of the next free slot, checked against the vault's current root.
    function _siblings(uint32 noteId) internal view returns (uint256[32] memory siblings) {
        uint256[] memory nodes = new uint256[](noteId);
        for (uint32 i = 0; i < noteId; ++i) {
            (bytes32 commitment, uint128 amount, uint64 expiryTs, Types.NoteStatus status) = VAULT.notes(i);
            nodes[i] = status == Types.NoteStatus.Active
                ? Bn254Poseidon.hash5(DOMAIN_LEAF, i, uint256(commitment), amount, expiryTs)
                : 0;
        }
        uint256 zero;
        uint256 index = noteId;
        uint256 root;
        for (uint256 level = 0; level < 32; ++level) {
            uint256 sibling = index ^ 1;
            siblings[level] = sibling < nodes.length ? nodes[sibling] : zero;
            root = ((index & 1) == 0)
                ? Bn254Poseidon.hash3(DOMAIN_NODE, level == 0 ? 0 : root, siblings[level])
                : Bn254Poseidon.hash3(DOMAIN_NODE, siblings[level], level == 0 ? 0 : root);
            uint256[] memory next = new uint256[]((nodes.length + 1) / 2);
            for (uint256 j = 0; j < next.length; ++j) {
                uint256 right = 2 * j + 1 < nodes.length ? nodes[2 * j + 1] : zero;
                next[j] = Bn254Poseidon.hash3(DOMAIN_NODE, nodes[2 * j], right);
            }
            nodes = next;
            zero = Bn254Poseidon.hash3(DOMAIN_NODE, zero, zero);
            index >>= 1;
        }
        require(root == VAULT.currentRoot(), "rebuilt tree does not match the vault root");
    }
}
