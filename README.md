# Codex AI command review for Antigravity CLI

A global hook for Antigravity CLI (`agy`) that asks an independent reviewer in Codex CLI whether a command may be executed before every `run_command` call.

Default reviewer configuration:

- model: `AGY_COMMAND_REVIEW_MODEL`, defaulting to `gpt-5.6-luna`;
- reasoning effort: `AGY_COMMAND_REVIEW_REASONING_EFFORT`, defaulting to `max`;
- reviewer sandbox: `read-only`;
- reviewer network and tool access: disabled;
- error, timeout, or invalid response: `DENY` (fail closed).

The status line shows the latest decision for the current conversation:

```text
✓ AI REVIEW (configured model and effort) · ALLOW · risk=medium · npm install
✕ AI REVIEW (configured model and effort) · DENY · risk=high · git push origin main
```

The complete `ALLOW` line is pastel green (`RGB 134, 239, 172`). The complete `DENY` line is pastel red (`RGB 252, 165, 165`).

## Supported environment

- Linux;
- Bash;
- Antigravity CLI (`agy`);
- Codex CLI (`codex`);
- `jq`;
- GNU `timeout` from the `coreutils` package.

Both CLIs must be installed, authenticated, and available in `PATH`.

## Installation on another computer

1. Copy or clone this directory.
2. Check the dependencies:

   ```bash
   agy --version
   codex --version
   jq --version
   timeout --version
   ```

3. Run the installer:

   ```bash
   ./install.sh
   ```

4. Verify the installed files and configuration:

   ```bash
   ./verify.sh
   ```

5. Close all existing Antigravity sessions and start it normally:

   ```bash
   agy
   ```

6. Run `/hooks` in `agy`. It should show an active global `PreToolUse` hook for `run_command`.

Do not use `--dangerously-skip-permissions`.

## What the installer installs

| Component | Default location |
|---|---|
| Reviewer | `~/.gemini/config/hooks/ai-command-review.sh` |
| Response schema | `~/.gemini/config/hooks/decision.schema.json` |
| Hook registration | `~/.gemini/config/hooks.json` |
| Status line | `~/.gemini/antigravity-cli/ai-command-review-statusline.sh` |
| Status line and permissions configuration | `~/.gemini/antigravity-cli/settings.json` |
| Latest decision per conversation | `~/.gemini/antigravity-cli/ai-command-review-state/` |

The installer:

- preserves other named hooks in `hooks.json`;
- preserves all other Antigravity settings;
- adds or updates only the `codex-ai-command-review` hook, `statusLine`, and the required `command(*)` permission rule;
- does not remove existing manual `allow` and `deny` rules;
- creates a backup of previous files in `~/.gemini/antigravity-cli/gpt-review-backups/`.

You can override the installation paths:

```bash
AGY_CONFIG_ROOT=/custom/path/config \
AGY_CLI_ROOT=/custom/path/antigravity-cli \
./install.sh
```

## Risk classification

- `low`: local read-only inspection or harmless computation, such as `ls`, `git status`, or `git diff`;
- `medium`: bounded local mutation, build, test, or dependency operation, such as `npm install` or a local `git merge`;
- `high`: publication, deployment, external mutation, privilege use, or destructive local mutation, such as `git push`;
- `critical`: broad irreversible destruction, credential exfiltration, persistence, or security-control bypass.

Decision policy:

- `low` and `medium`: `ALLOW` by default unless there is a policy block;
- `high`: `ALLOW` only with sufficient user authorization and a concrete, bounded scope;
- `critical` and policy-blocked actions: always `DENY`;
- reviewer uncertainty or failure: `DENY`.

Example results confirmed during testing, without executing the candidate commands:

| Candidate | Result |
|---|---|
| `ls -la` | `ALLOW · low` |
| `npm install` | `ALLOW · medium` |
| `git merge origin/example` | `ALLOW · medium` |
| `git push origin example` without authorization | `DENY · high` |
| `git push --force origin example` without authorization | `DENY · high` |
| `rm -rf /` | `DENY · critical` |

## Why `command(*)` is required

Antigravity still applies its own permission manager after the hook decision. This rule:

```json
"command(*)"
```

prevents an additional permission-manager prompt. The AI reviewer in the `PreToolUse` hook remains the actual security gate.

Do not disable the hook while leaving `command(*)` enabled. The installer first installs and registers the hook, then adds the permission bridge.

## Protection scope

The hook reviews only Antigravity's `run_command` tool.

It does not separately review:

- file reads;
- edits performed by Antigravity's native file tools;
- browser tools;
- MCP tools;
- commands executed outside `agy`.

The reviewer receives:

- the proposed command;
- the working directory;
- workspace paths;
- up to five latest user messages from the transcript.

It does not execute the reviewed command.

## Configuration

The main parameters are at the beginning of `global-hook/ai-command-review.sh`:

```bash
readonly MODEL="${AGY_COMMAND_REVIEW_MODEL:-gpt-5.6-luna}"
readonly REASONING_EFFORT="${AGY_COMMAND_REVIEW_REASONING_EFFORT:-max}"
readonly REVIEW_TIMEOUT_SECONDS=90
```

Override the defaults when starting `agy`:

```bash
AGY_COMMAND_REVIEW_MODEL=gpt-5.6-luna \
AGY_COMMAND_REVIEW_REASONING_EFFORT=max \
agy
```

The status line reads the effective model and reasoning effort recorded by the reviewer. It does not contain a hardcoded reviewer label.

You can explicitly select the reviewer executable through the `agy` process environment:

```bash
AGY_COMMAND_REVIEW_CODEX_BIN=/absolute/path/to/codex agy
```

## Updating

After changing files in the repository, run:

```bash
./install.sh
./verify.sh
```

Each installation creates a new backup of the previous configuration.

## Restoring the previous configuration

The installer prints the backup directory. To revert the latest installation, close `agy` and copy the previous `hooks.json` and `settings.json` files from that directory to their original locations.

If a file did not exist before installation, it will not be present in the backup. Remove the corresponding newly installed file manually.
