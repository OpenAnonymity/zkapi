# zkapi-clientd

A local OpenAI-compatible API, paid from your private ETH balance. No OA account or OpenRouter API key needed.

## Quick start

Install or update:

```sh
curl -fsSL https://github.com/ethereum/zkapi/releases/download/clientd-v0.1.3/install.sh | bash
```

Configure your wallet:

```sh
zkapi-clientd config
```

Setup updates payment details and progress in place while you wait. Menus use
the arrow keys and Enter; Ctrl+C stops safely and preserves your progress.

Then start the API:

```sh
zkapi-clientd serve
```

Leave that terminal running. In Open WebUI or another OpenAI-compatible client, set the base URL to **`http://127.0.0.1:8787/v1`** and leave the API key empty (use `local` if the app requires a value). Select a model and chat. The endpoint accepts local connections only.

The default reuses an OpenRouter key for a fixed window of up to 60 seconds.
Compatible requests from different chats, local clients, and Open WebUI's title
and follow-up requests can share a key and its spending cap; the provider can
link those requests. Your saved key-reuse setting is preserved across updates.
Settlement starts automatically when the window ends, even without another
request. An active response finishes first.
For a fresh key per inference request, stop `serve`, run
`zkapi-clientd config --key-reuse-window-seconds 0`, then restart `serve`.
With reuse disabled, settlement starts after each response. Fresh keys may wait
for the previous key's settlement.

## Optional local context recall

Context recall is off by default. To let leCore select relevant context from
the conversation already sent to the local API, stop `serve`, run
`zkapi-clientd config --lecore-context-recall`, then restart `serve`. Run
`zkapi-clientd config --lecore-context-recall=false` and restart to turn it off.
Use the same `--config-dir` for each command if you selected one.

The recall step runs locally and adds no network request of its own. For long,
plain-text chats, it can keep relevant older messages and the recent turns while
omitting other older messages. The final prompt still goes to the inference
provider under the usual paid zkAPI lease. Provider usage and settlement still
apply; token usage and cost can differ. The daemon does not add prompt or
response logging for this option. Recall uses only content included in the
current API request, so it cannot recover messages a client omitted. It leaves
requests unchanged when the conservative matching criteria are not met, including
tool or multimodal requests and detected whole-conversation questions. Recall
can miss relevant context, so an enabled result may differ from full-context inference.

Project links: [OpenZoo](https://openzoo.fun/), the
[pinned leCore revision](https://github.com/AnOversizedMooseWithSocks/leCore/commit/5cef1aec),
and the [historical DHH demo](https://ttfx-three.vercel.app/). These are
background references. This integration has no controlled counterfactual
benchmark and makes no performance, cost-saving, or answer-quality claim.

To update, stop `serve`, rerun the install command, then start `serve` again. Your wallet is preserved. See [wallet storage and updates](docs/CLI_PACKAGING.md#wallet-storage-and-updates).

To withdraw, run `zkapi-clientd config --menu` and choose `withdraw`. It asks for the destination and waits for extra ETH for fees only if needed.

[More options, including Sepolia and Docker clients](docs/CLI_ZKAPI.md) · [Installation details](docs/CLI_PACKAGING.md) · [Privacy](docs/PRIVACY.md)

[NixOS, AUR, and Homebrew packages with background services](docs/CLI_PACKAGING.md#platform-packages-and-background-services) are also available in this repository.
