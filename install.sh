#!/bin/sh
# ==============================================================================
# DevOps & DevSecOps Skill Installer
# Author: Reaan
# Repository: https://github.com/Reaan06/devops-skill
# Branch: main
# Universal agent skill installer for Pi, Claude Code, Cursor, Windsurf, Copilot,
# and Agent Skills standard (~/.agents/skills).
# ==============================================================================

set -eu

REPO_URL="${DEVOPS_SKILL_REPO:-https://github.com/Reaan06/devops-skill}"
BRANCH="${DEVOPS_SKILL_BRANCH:-main}"
TARBALL_URL="${DEVOPS_SKILL_TARBALL_URL:-${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz}"
SKILL_NAME="devops-skill"

# Terminal colors (POSIX-compliant)
if [ -t 1 ]; then
  BOLD="\033[1m"
  GREEN="\033[32m"
  CYAN="\033[36m"
  YELLOW="\033[33m"
  RED="\033[31m"
  DIM="\033[2m"
  RESET="\033[0m"
else
  BOLD=""
  GREEN=""
  CYAN=""
  YELLOW=""
  RED=""
  DIM=""
  RESET=""
fi

print_banner() {
  printf "%b\n" "${CYAN}${BOLD}====================================================${RESET}"
  printf "%b\n" "${CYAN}${BOLD}  🚀 DevOps & DevSecOps Skill Installer${RESET}"
  printf "%b\n" "${CYAN}${BOLD}  Author: Reaan | Universal Agent Distribution${RESET}"
  printf "%b\n" "${CYAN}${BOLD}====================================================${RESET}"
  printf "\n"
}

show_help() {
  print_banner
  cat <<'EOF'
Usage:
  curl -fsSL https://raw.githubusercontent.com/Reaan06/devops-skill/main/install.sh | bash -s -- [options]
  ./install.sh [options]

Target Agent Options:
  --all              Install to all supported agent targets
  --pi               Pi Coding Agent (~/.pi/agent/skills/ or .pi/skills/)
  --claude           Claude Code (~/.claude/skills/ or .claude/skills/)
  --agents           Agent Skills Open Standard (~/.agents/skills/ or .agents/skills/)
  --cursor           Cursor IDE (.cursor/rules/devops-skill.mdc)
  --windsurf         Windsurf IDE (.windsurf/rules/devops-skill.md)
  --copilot          GitHub Copilot (.github/copilot-instructions.md)
  --target=LIST      Comma-separated list (e.g. --target=pi,claude,cursor)

Scope & Installation Mode Options:
  --global, -g       Install globally in user home directory (default)
  --project, -p      Install locally in current working directory
  --symlink, -l      Create symbolic links instead of copying (local cloned repo only)
  --copy             Copy files into target directories (default)
  --help, -h         Show this help message

Examples:
  ./install.sh --all
  ./install.sh --pi --global
  ./install.sh --cursor --project
  ./install.sh --target=pi,claude --symlink
  curl -fsSL https://raw.githubusercontent.com/Reaan06/devops-skill/main/install.sh | bash -s -- --all
EOF
}

# Defaults
SCOPE="global"
INSTALL_MODE="copy"
TARGET_ALL=0
TARGET_PI=0
TARGET_CLAUDE=0
TARGET_AGENTS=0
TARGET_CURSOR=0
TARGET_WINDSURF=0
TARGET_COPILOT=0
EXPLICIT_TARGETS=0

# Parse command line options
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h|help)
      show_help
      exit 0
      ;;
    --all)
      TARGET_ALL=1
      EXPLICIT_TARGETS=1
      ;;
    --pi)
      TARGET_PI=1
      EXPLICIT_TARGETS=1
      ;;
    --claude)
      TARGET_CLAUDE=1
      EXPLICIT_TARGETS=1
      ;;
    --agents)
      TARGET_AGENTS=1
      EXPLICIT_TARGETS=1
      ;;
    --cursor)
      TARGET_CURSOR=1
      EXPLICIT_TARGETS=1
      ;;
    --windsurf)
      TARGET_WINDSURF=1
      EXPLICIT_TARGETS=1
      ;;
    --copilot)
      TARGET_COPILOT=1
      EXPLICIT_TARGETS=1
      ;;
    --target=*)
      target_list="${1#*=}"
      old_ifs="$IFS"
      IFS=','
      for item in $target_list; do
        # Trim whitespace and convert to lowercase
        norm_item="$(printf "%s" "$item" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
        case "$norm_item" in
          pi) TARGET_PI=1; EXPLICIT_TARGETS=1 ;;
          claude) TARGET_CLAUDE=1; EXPLICIT_TARGETS=1 ;;
          agents) TARGET_AGENTS=1; EXPLICIT_TARGETS=1 ;;
          cursor) TARGET_CURSOR=1; EXPLICIT_TARGETS=1 ;;
          windsurf) TARGET_WINDSURF=1; EXPLICIT_TARGETS=1 ;;
          copilot) TARGET_COPILOT=1; EXPLICIT_TARGETS=1 ;;
          all) TARGET_ALL=1; EXPLICIT_TARGETS=1 ;;
          *)
            printf "%b\n" "${YELLOW}Warning: Unknown target '$item' in --target list.${RESET}" >&2
            ;;
        esac
      done
      IFS="$old_ifs"
      ;;
    --global|-g)
      SCOPE="global"
      ;;
    --project|-p)
      SCOPE="project"
      ;;
    --symlink|--link|-l)
      INSTALL_MODE="symlink"
      ;;
    --copy)
      INSTALL_MODE="copy"
      ;;
    install)
      # No-op default command word
      ;;
    *)
      printf "%b\n" "${RED}Error: Unknown argument '$1'${RESET}" >&2
      printf "Run '%s --help' for usage.\n" "$0" >&2
      exit 1
      ;;
  esac
  shift
done

# Detect repository source (local clone vs remote piped execution)
SCRIPT_DIR=""
case "${0:-}" in
  */*)
    SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
    ;;
  *)
    if [ -f "${0:-}" ]; then
      SCRIPT_DIR="$(pwd)"
    fi
    ;;
esac

IS_LOCAL=0
REPO_DIR=""
TMP_CLEANUP_DIR=""

cleanup() {
  if [ -n "$TMP_CLEANUP_DIR" ] && [ -d "$TMP_CLEANUP_DIR" ]; then
    rm -rf "$TMP_CLEANUP_DIR"
  fi
}
trap cleanup EXIT INT TERM HUP

if [ -f "$PWD/SKILL.md" ] && [ -d "$PWD/references" ]; then
  IS_LOCAL=1
  REPO_DIR="$PWD"
elif [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/SKILL.md" ] && [ -d "$SCRIPT_DIR/references" ]; then
  IS_LOCAL=1
  REPO_DIR="$SCRIPT_DIR"
fi

if [ "$IS_LOCAL" -eq 1 ]; then
  printf "%b\n" "${DIM}Using local skill repository at: ${REPO_DIR}${RESET}"
else
  # Running via curl pipe without local repo: fetch archive from GitHub
  TMP_CLEANUP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'devops-skill')"
  printf "%b\n" "${CYAN}Fetching devops-skill from GitHub (${REPO_URL})...${RESET}"

  download_success=0
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "$TARBALL_URL" | tar -xz -C "$TMP_CLEANUP_DIR" 2>/dev/null; then
      download_success=1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if wget -qO- "$TARBALL_URL" | tar -xz -C "$TMP_CLEANUP_DIR" 2>/dev/null; then
      download_success=1
    fi
  fi

  if [ "$download_success" -eq 0 ]; then
    if command -v git >/dev/null 2>&1; then
      printf "%b\n" "${DIM}Tarball fetch failed, cloning repository via git...${RESET}"
      if git clone --depth 1 -b "$BRANCH" "$REPO_URL.git" "$TMP_CLEANUP_DIR/repo" 2>/dev/null || \
         git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$TMP_CLEANUP_DIR/repo" 2>/dev/null; then
        download_success=1
      fi
    fi
  fi

  if [ "$download_success" -eq 0 ]; then
    printf "%b\n" "${RED}Error: Failed to download repository. Ensure curl, wget, or git is installed and network is reachable.${RESET}" >&2
    exit 1
  fi

  # Locate extracted directory containing SKILL.md
  if [ -f "$TMP_CLEANUP_DIR/SKILL.md" ]; then
    REPO_DIR="$TMP_CLEANUP_DIR"
  else
    for candidate_dir in "$TMP_CLEANUP_DIR"/*; do
      if [ -d "$candidate_dir" ] && [ -f "$candidate_dir/SKILL.md" ]; then
        REPO_DIR="$candidate_dir"
        break
      fi
    done
  fi

  if [ -z "$REPO_DIR" ] || [ ! -f "$REPO_DIR/SKILL.md" ]; then
    printf "%b\n" "${RED}Error: Downloaded archive did not contain SKILL.md.${RESET}" >&2
    exit 1
  fi
fi

# Apply --all expansion
if [ "$TARGET_ALL" -eq 1 ]; then
  TARGET_PI=1
  TARGET_CLAUDE=1
  TARGET_AGENTS=1
  TARGET_CURSOR=1
  TARGET_WINDSURF=1
  TARGET_COPILOT=1
fi

# Auto-detection if no specific target flag was supplied
if [ "$EXPLICIT_TARGETS" -eq 0 ]; then
  # Universal fallback is always active
  TARGET_AGENTS=1

  if [ "$SCOPE" = "global" ]; then
    # In global scope, Pi automatically discovers skills located in ~/.agents/skills.
    # Installing simultaneously into ~/.pi/agent/skills and ~/.agents/skills triggers
    # a Pi skill collision warning. Only target ~/.pi if explicitly requested via --pi.
    TARGET_PI=0
    if [ -d "$HOME/.claude" ]; then TARGET_CLAUDE=1; fi
    if [ -d "$HOME/.cursor" ] || [ -d "$PWD/.cursor" ]; then TARGET_CURSOR=1; fi
    if [ -d "$HOME/.windsurf" ] || [ -d "$PWD/.windsurf" ]; then TARGET_WINDSURF=1; fi
    if [ -d "$PWD/.github" ]; then TARGET_COPILOT=1; fi
  else
    if [ -d "$PWD/.pi" ]; then TARGET_PI=1; fi
    if [ -d "$PWD/.claude" ]; then TARGET_CLAUDE=1; fi
    if [ -d "$PWD/.cursor" ]; then TARGET_CURSOR=1; fi
    if [ -d "$PWD/.windsurf" ]; then TARGET_WINDSURF=1; fi
    if [ -d "$PWD/.github" ]; then TARGET_COPILOT=1; fi
  fi
fi

# Resolve destination paths according to scope
if [ "$SCOPE" = "global" ]; then
  PATH_PI="$HOME/.pi/agent/skills/$SKILL_NAME"
  PATH_CLAUDE="$HOME/.claude/skills/$SKILL_NAME"
  PATH_AGENTS="$HOME/.agents/skills/$SKILL_NAME"

  if [ -d "$HOME/.cursor" ]; then
    PATH_CURSOR="$HOME/.cursor/rules/$SKILL_NAME.mdc"
  elif [ -d "$PWD/.cursor" ]; then
    PATH_CURSOR="$PWD/.cursor/rules/$SKILL_NAME.mdc"
  else
    PATH_CURSOR="$HOME/.cursor/rules/$SKILL_NAME.mdc"
  fi

  if [ -d "$HOME/.windsurf" ]; then
    PATH_WINDSURF="$HOME/.windsurf/rules/$SKILL_NAME.md"
  elif [ -d "$PWD/.windsurf" ]; then
    PATH_WINDSURF="$PWD/.windsurf/rules/$SKILL_NAME.md"
  else
    PATH_WINDSURF="$HOME/.windsurf/rules/$SKILL_NAME.md"
  fi

  if [ -d "$PWD/.github" ]; then
    PATH_COPILOT="$PWD/.github/copilot-instructions.md"
  else
    PATH_COPILOT="$PWD/.github/copilot-instructions.md"
  fi
else
  PATH_PI="$PWD/.pi/skills/$SKILL_NAME"
  PATH_CLAUDE="$PWD/.claude/skills/$SKILL_NAME"
  PATH_AGENTS="$PWD/.agents/skills/$SKILL_NAME"
  PATH_CURSOR="$PWD/.cursor/rules/$SKILL_NAME.mdc"
  PATH_WINDSURF="$PWD/.windsurf/rules/$SKILL_NAME.md"
  PATH_COPILOT="$PWD/.github/copilot-instructions.md"
fi

print_banner
printf "%b\n" "${CYAN}Installation Scope: ${BOLD}${SCOPE}${RESET}"
printf "%b\n" "${CYAN}Installation Mode:  ${BOLD}${INSTALL_MODE}${RESET}"
printf "\n"

copy_clean_dir() {
  src_dir="$1"
  dest_dir="$2"

  mkdir -p "$dest_dir"
  if command -v tar >/dev/null 2>&1; then
    (cd "$src_dir" && tar -cf - --exclude='.terraform*' --exclude='.git*' --exclude='node_modules*' .) | (cd "$dest_dir" && tar -xf -)
  else
    cp -R "$src_dir"/* "$dest_dir/"
  fi
}

# Helper: Install directory-based skills (pi, claude, agents)
install_skill_dir() {
  agent_name="$1"
  dest_path="$2"

  printf "%b\n" "📦 Installing for ${BOLD}${agent_name}${RESET}..."

  if [ -e "$dest_path" ] || [ -L "$dest_path" ]; then
    rm -rf "$dest_path"
  fi

  mkdir -p "$(dirname "$dest_path")"

  if [ "$INSTALL_MODE" = "symlink" ]; then
    if [ "$IS_LOCAL" -eq 1 ]; then
      ln -s "$REPO_DIR" "$dest_path"
      printf "%b\n" "${GREEN}  🔗 Symlinked: ${dest_path} -> ${REPO_DIR}${RESET}"
      return 0
    else
      printf "%b\n" "${YELLOW}  ⚠️  Cannot symlink from remote temporary download. Falling back to copy.${RESET}"
    fi
  fi

  mkdir -p "$dest_path"

  # Copy core skill files
  if [ -f "$REPO_DIR/SKILL.md" ]; then
    cp "$REPO_DIR/SKILL.md" "$dest_path/SKILL.md"
  fi
  if [ -f "$REPO_DIR/LICENSE" ]; then
    cp "$REPO_DIR/LICENSE" "$dest_path/LICENSE"
  fi
  if [ -f "$REPO_DIR/package.json" ]; then
    cp "$REPO_DIR/package.json" "$dest_path/package.json"
  fi

  # Copy directories cleanly excluding caches and provider binaries
  if [ -d "$REPO_DIR/references" ]; then
    copy_clean_dir "$REPO_DIR/references" "$dest_path/references"
  fi
  if [ -d "$REPO_DIR/templates" ]; then
    copy_clean_dir "$REPO_DIR/templates" "$dest_path/templates"
  fi
  if [ -d "$REPO_DIR/scripts" ]; then
    copy_clean_dir "$REPO_DIR/scripts" "$dest_path/scripts"
    # Ensure scripts have executable permissions
    for script_file in "$dest_path/scripts"/*; do
      if [ -f "$script_file" ]; then
        chmod +x "$script_file" 2>/dev/null || true
      fi
    done
  fi

  printf "%b\n" "${GREEN}  ✓ Copied skill tree to: ${dest_path}${RESET}"
}

# Helper: Generate Cursor rule
install_cursor() {
  dest_file="$1"
  printf "%b\n" "📦 Generating rule for ${BOLD}Cursor IDE${RESET}..."

  mkdir -p "$(dirname "$dest_file")"

  tmp_cursor="$(mktemp 2>/dev/null || mktemp -t 'cursor-rule')"
  cat <<'EOF' > "$tmp_cursor"
---
description: "DevOps & DevSecOps Engineering standards by Reaan (Containers, Kubernetes, Terraform, GitOps, OTel)"
globs: "**/Dockerfile*, **/*.dockerignore, **/docker-compose*.yaml, **/compose*.yaml, **/*.tf, **/*.tofu, **/k8s/**/*.yaml, **/kubernetes/**/*.yaml, **/.github/workflows/*.yml, **/argocd/**/*.yaml"
alwaysApply: false
---

<!-- DevOps Skill by Reaan -->
EOF
  cat "$REPO_DIR/SKILL.md" >> "$tmp_cursor"
  mv "$tmp_cursor" "$dest_file"

  printf "%b\n" "${GREEN}  ✓ Generated Cursor rule: ${dest_file}${RESET}"
}

# Helper: Generate Windsurf rule
install_windsurf() {
  dest_file="$1"
  printf "%b\n" "📦 Generating rule for ${BOLD}Windsurf IDE${RESET}..."

  mkdir -p "$(dirname "$dest_file")"

  tmp_windsurf="$(mktemp 2>/dev/null || mktemp -t 'windsurf-rule')"
  cat <<'EOF' > "$tmp_windsurf"
# DevOps & DevSecOps Engineering Rules (Reaan)

EOF
  cat "$REPO_DIR/SKILL.md" >> "$tmp_windsurf"
  mv "$tmp_windsurf" "$dest_file"

  printf "%b\n" "${GREEN}  ✓ Generated Windsurf rule: ${dest_file}${RESET}"
}

# Helper: Generate or update Copilot instructions
install_copilot() {
  dest_file="$1"
  printf "%b\n" "📦 Updating instructions for ${BOLD}GitHub Copilot${RESET}..."

  mkdir -p "$(dirname "$dest_file")"

  tmp_block="$(mktemp 2>/dev/null || mktemp -t 'copilot-block')"
  cat <<'EOF' > "$tmp_block"
<!-- BEGIN DEVOPS-SKILL REAAN -->
## DevOps & DevSecOps Engineering Standards (Author: Reaan)
EOF
  cat "$REPO_DIR/SKILL.md" >> "$tmp_block"
  printf "\n<!-- END DEVOPS-SKILL REAAN -->\n" >> "$tmp_block"

  if [ -f "$dest_file" ]; then
    if grep -q "<!-- BEGIN DEVOPS-SKILL REAAN -->" "$dest_file" 2>/dev/null; then
      tmp_merged="$(mktemp 2>/dev/null || mktemp -t 'copilot-merged')"
      awk -v bfile="$tmp_block" '
        /<!-- BEGIN DEVOPS-SKILL REAAN -->/ {
          skip = 1
          while ((getline line < bfile) > 0) {
            print line
          }
          close(bfile)
          next
        }
        /<!-- END DEVOPS-SKILL REAAN -->/ {
          skip = 0
          next
        }
        !skip { print }
      ' "$dest_file" > "$tmp_merged"
      mv "$tmp_merged" "$dest_file"
      printf "%b\n" "${GREEN}  ✓ Updated Copilot instructions: ${dest_file}${RESET}"
    else
      printf "\n\n" >> "$dest_file"
      cat "$tmp_block" >> "$dest_file"
      printf "%b\n" "${GREEN}  ✓ Appended to Copilot instructions: ${dest_file}${RESET}"
    fi
  else
    mv "$tmp_block" "$dest_file"
    printf "%b\n" "${GREEN}  ✓ Created Copilot instructions: ${dest_file}${RESET}"
  fi

  rm -f "$tmp_block" 2>/dev/null || true
}

# Prevent collision in global scope: if installing to ~/.agents/skills and not explicitly targeting pi,
# clean redundant skill directory in ~/.pi/agent/skills to prevent collision
if [ "$SCOPE" = "global" ] && [ "$TARGET_AGENTS" -eq 1 ] && [ "$TARGET_PI" -eq 0 ]; then
  if [ -e "$HOME/.pi/agent/skills/$SKILL_NAME" ] || [ -L "$HOME/.pi/agent/skills/$SKILL_NAME" ]; then
    printf "%b\n" "${DIM}  🧹 Removing redundant Pi skill at $HOME/.pi/agent/skills/$SKILL_NAME to prevent collision...${RESET}"
    rm -rf "$HOME/.pi/agent/skills/$SKILL_NAME"
  fi
fi

# Execute installation for selected targets
if [ "$TARGET_PI" -eq 1 ]; then
  install_skill_dir "Pi Coding Agent" "$PATH_PI"
fi

if [ "$TARGET_CLAUDE" -eq 1 ]; then
  install_skill_dir "Claude Code" "$PATH_CLAUDE"
fi

if [ "$TARGET_AGENTS" -eq 1 ]; then
  install_skill_dir "Agent Skills Standard" "$PATH_AGENTS"
fi

if [ "$TARGET_CURSOR" -eq 1 ]; then
  install_cursor "$PATH_CURSOR"
fi

if [ "$TARGET_WINDSURF" -eq 1 ]; then
  install_windsurf "$PATH_WINDSURF"
fi

if [ "$TARGET_COPILOT" -eq 1 ]; then
  install_copilot "$PATH_COPILOT"
fi

printf "\n"
printf "%b\n" "${GREEN}${BOLD}🎉 Installation completed successfully!${RESET}"
printf "%b\n" "${DIM}Skill Author: Reaan | Repository: ${REPO_URL}${RESET}"
