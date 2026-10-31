# Feature: Universal Installation for All Agents (NPM, Curl, Pi)

## Specs

S1: Author name MUST be "Reaan" across package metadata, skill metadata, and installer configurations.
S2: NPM package MUST define `package.json` with `@reaan/devops-skill`, executable CLI binary `devops-skill`, `pi-package` keyword, and `"pi": { "skills": ["."] }` manifest so `pi install` works out of the box.
S3: CLI installer `bin/cli.js` MUST be zero-dependency Node.js executable, supporting `install`, `uninstall`, `list`, `doctor` across agents (`pi`, `claude`, `cursor`, `windsurf`, `copilot`, `agents`, `all`), supporting `--global` and `--project` targets.
S4: Standalone shell installer `install.sh` MUST be POSIX compliant, operable via `curl -fsSL ... | bash`, auto-detecting installed agents and supporting non-interactive flags.
S5: Documentation in `README.md` MUST provide crystal clear instructions for NPM (`npx @reaan/devops-skill install`), Curl (`curl -fsSL ... | bash`), and Pi (`pi install`).
S6: Verification test suite MUST prove end-to-end installation across temporary mock agent directories without polluting user environment.

## Tasks

- [x] T1 (S1): Update author metadata in SKILL.md to "Reaan"
- [x] T2 (S2): Create package.json with @reaan/devops-skill, bin, and pi-package manifest
- [x] T3 (S3): Implement bin/cli.js cross-platform installer with agent adapters
- [x] T4 (S4): Implement install.sh POSIX curl installer with auto-detection
- [x] T5 (S5): Update README.md with universal installation guides and agent matrix
- [x] T6 (S6): Add verification tests and validate installations in isolated sandbox

## Log

L1: User requested universal installation for all agents via NPM, Curl, and Pi under author name "Reaan".
L2: Delegated install.sh, README.md, and verification tasks to gentle-ai-worker and gentle-ai-verify subagents.
L3: Polished bin/cli.js with ignore filters (.git, .terraform, node_modules) and error exitCode propagation. Added durable regression suite in test/universal-install.test.js (7/7 tests passing).
