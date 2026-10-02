# Browser deployment profile fixtures

These public profiles match the reviewed OA Chat deployment configurations.
Mainnet includes the October 1 production verifier update from OA Chat commit
`0be21ed`; Sepolia retains its existing configuration. The SDK's separately
packaged browser profiles may lag this CLI update. Their public endpoints are
`zkapi-mainnet.openanonymity.ai` and `zkapi-sepolia.openanonymity.ai`.

The fixtures independently check the client's embedded deployment identity,
public signing keys, origins and proof hashes. They contain no credentials or
user wallet state. The network manifests pin the current vaults and deployment
configuration; SHA-256 checks enforce exact approved manifest bytes.
