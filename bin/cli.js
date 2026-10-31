#!/usr/bin/env node

/**
 * devops-skill Installer CLI
 * Author: Reaan
 * Universal agent skill installer for Pi, Claude Code, Cursor, Windsurf, Copilot, and Agent Skills standard.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const VERSION = '1.0.0';
const SKILL_NAME = 'devops-skill';

const ROOT_DIR = path.resolve(__dirname, '..');
const SKILL_MD_PATH = path.join(ROOT_DIR, 'SKILL.md');

const REQUIRED_DIRS = ['references', 'templates', 'scripts'];
const REQUIRED_FILES = ['SKILL.md', 'LICENSE'];
const IGNORE_PATTERNS = new Set(['.git', '.terraform', 'node_modules']);

// ANSI Colors
const colors = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  green: '\x1b[32m',
  cyan: '\x1b[36m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
  magenta: '\x1b[35m',
};

function log(msg, color = '') {
  console.log(`${color}${msg}${colors.reset}`);
}

function printBanner() {
  console.log(`
${colors.cyan}${colors.bold}====================================================
  🚀 DevOps & DevSecOps Skill Installer (v${VERSION})
  Author: Reaan | Universal Agent Distribution
====================================================${colors.reset}
`);
}

function printHelp() {
  printBanner();
  console.log(`
Usage:
  npx @reaan_dev/devops-skill [command] [options]
  devops-skill [command] [options]

Commands:
  install            Install the skill for detected or specified agents (default)
  uninstall          Remove the skill from agents
  list               List detected agents and installation status
  doctor             Validate skill package integrity
  help, --help, -h   Show this help message
  --version, -v      Show version

Target Agent Options:
  --all              Target all supported and detected agents
  --pi               Pi Coding Agent (~/.pi/agent/skills/ or .pi/skills/)
  --claude           Claude Code (~/.claude/skills/ or .claude/skills/)
  --agents           Agent Skills Open Standard (~/.agents/skills/ or .agents/skills/)
  --cursor           Cursor IDE (.cursor/rules/devops-skill.mdc)
  --windsurf         Windsurf IDE (.windsurf/rules/devops-skill.md)
  --copilot          GitHub Copilot (.github/copilot-instructions.md)
  --target=<list>    Comma-separated list (e.g. --target=pi,claude,cursor)

Scope & Behavior Options:
  --global, -g       Install globally in user home directory (default)
  --project, -p      Install locally in current working directory
  --symlink, -l      Create symbolic links instead of copying (ideal for local development)
  --dry-run          Simulate actions without writing to disk
  --silent           Suppress non-error logs

Examples:
  npx @reaan_dev/devops-skill install --all
  npx @reaan_dev/devops-skill install --pi --global
  npx @reaan_dev/devops-skill install --cursor --project
  npx @reaan_dev/devops-skill doctor
`);
}

function parseArgs(args) {
  const options = {
    command: 'install',
    targets: new Set(),
    scope: 'global',
    symlink: false,
    dryRun: false,
    silent: false,
  };

  const positional = [];

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    if (arg === '--help' || arg === '-h' || arg === 'help') {
      options.command = 'help';
      return options;
    }
    if (arg === '--version' || arg === '-v') {
      options.command = 'version';
      return options;
    }

    if (arg === 'install' || arg === 'uninstall' || arg === 'list' || arg === 'doctor') {
      options.command = arg;
      continue;
    }

    if (arg === '--all') {
      options.all = true;
      continue;
    }
    if (arg === '--global' || arg === '-g') {
      options.scope = 'global';
      continue;
    }
    if (arg === '--project' || arg === '-p') {
      options.scope = 'project';
      continue;
    }
    if (arg === '--symlink' || arg === '--link' || arg === '-l') {
      options.symlink = true;
      continue;
    }
    if (arg === '--dry-run') {
      options.dryRun = true;
      continue;
    }
    if (arg === '--silent') {
      options.silent = true;
      continue;
    }

    if (arg === '--pi') options.targets.add('pi');
    else if (arg === '--claude') options.targets.add('claude');
    else if (arg === '--agents') options.targets.add('agents');
    else if (arg === '--cursor') options.targets.add('cursor');
    else if (arg === '--windsurf') options.targets.add('windsurf');
    else if (arg === '--copilot') options.targets.add('copilot');
    else if (arg.startsWith('--target=')) {
      const list = arg.split('=')[1].split(',');
      list.forEach((t) => options.targets.add(t.trim().toLowerCase()));
    } else if (!arg.startsWith('-')) {
      positional.push(arg);
    }
  }

  if (positional.length > 0 && !options.command) {
    options.command = positional[0];
  }

  return options;
}

function getHomeDir() {
  return os.homedir();
}

function getProjectDir() {
  return process.cwd();
}

/**
 * Returns definition of agent destination directories based on scope
 */
function getAgentDefinitions(scope, customBaseDir = null) {
  const baseDir = customBaseDir || (scope === 'global' ? getHomeDir() : getProjectDir());

  return {
    pi: {
      name: 'Pi Coding Agent',
      type: 'skill-dir',
      path: scope === 'global'
        ? path.join(baseDir, '.pi', 'agent', 'skills', SKILL_NAME)
        : path.join(baseDir, '.pi', 'skills', SKILL_NAME),
      detectBase: scope === 'global'
        ? path.join(baseDir, '.pi')
        : path.join(baseDir, '.pi'),
    },
    claude: {
      name: 'Claude Code',
      type: 'skill-dir',
      path: scope === 'global'
        ? path.join(baseDir, '.claude', 'skills', SKILL_NAME)
        : path.join(baseDir, '.claude', 'skills', SKILL_NAME),
      detectBase: scope === 'global'
        ? path.join(baseDir, '.claude')
        : path.join(baseDir, '.claude'),
    },
    agents: {
      name: 'Agent Skills Standard (~/.agents/skills)',
      type: 'skill-dir',
      path: scope === 'global'
        ? path.join(baseDir, '.agents', 'skills', SKILL_NAME)
        : path.join(baseDir, '.agents', 'skills', SKILL_NAME),
      detectBase: scope === 'global'
        ? path.join(baseDir, '.agents')
        : path.join(baseDir, '.agents'),
    },
    cursor: {
      name: 'Cursor Rules',
      type: 'cursor-rule',
      path: path.join(baseDir, '.cursor', 'rules', `${SKILL_NAME}.mdc`),
      detectBase: path.join(baseDir, '.cursor'),
    },
    windsurf: {
      name: 'Windsurf Rules',
      type: 'windsurf-rule',
      path: path.join(baseDir, '.windsurf', 'rules', `${SKILL_NAME}.md`),
      detectBase: path.join(baseDir, '.windsurf'),
    },
    copilot: {
      name: 'GitHub Copilot Instructions',
      type: 'copilot-instruction',
      path: path.join(baseDir, '.github', 'copilot-instructions.md'),
      detectBase: path.join(baseDir, '.github'),
    },
  };
}

function copyRecursiveSync(src, dest, dryRun = false) {
  const baseName = path.basename(src);
  if (IGNORE_PATTERNS.has(baseName)) {
    return;
  }

  const exists = fs.existsSync(src);
  if (!exists) return;
  const stats = fs.statSync(src);
  const isDirectory = stats.isDirectory();

  if (isDirectory) {
    if (!dryRun) fs.mkdirSync(dest, { recursive: true });
    fs.readdirSync(src).forEach((childItemName) => {
      if (IGNORE_PATTERNS.has(childItemName)) {
        return;
      }
      copyRecursiveSync(
        path.join(src, childItemName),
        path.join(dest, childItemName),
        dryRun
      );
    });
  } else {
    if (!dryRun) {
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      fs.copyFileSync(src, dest);
    }
  }
}

function installSkillDirectory(targetPath, symlink = false, dryRun = false) {
  if (dryRun) {
    log(`  [dry-run] Would install skill directory to: ${targetPath}`, colors.dim);
    return;
  }

  // If already exists, remove or clean
  if (fs.existsSync(targetPath)) {
    const stat = fs.lstatSync(targetPath);
    if (stat.isSymbolicLink() || stat.isFile()) {
      fs.unlinkSync(targetPath);
    } else {
      fs.rmSync(targetPath, { recursive: true, force: true });
    }
  }

  fs.mkdirSync(path.dirname(targetPath), { recursive: true });

  if (symlink) {
    fs.symlinkSync(ROOT_DIR, targetPath, 'junction');
    log(`  🔗 Symlinked: ${targetPath} -> ${ROOT_DIR}`, colors.green);
  } else {
    fs.mkdirSync(targetPath, { recursive: true });

    // Copy core files and directories
    REQUIRED_FILES.forEach((f) => {
      const srcFile = path.join(ROOT_DIR, f);
      if (fs.existsSync(srcFile)) {
        fs.copyFileSync(srcFile, path.join(targetPath, f));
      }
    });

    REQUIRED_DIRS.forEach((d) => {
      const srcDir = path.join(ROOT_DIR, d);
      if (fs.existsSync(srcDir)) {
        copyRecursiveSync(srcDir, path.join(targetPath, d), false);
      }
    });

    // Also include package.json if present
    const pkgPath = path.join(ROOT_DIR, 'package.json');
    if (fs.existsSync(pkgPath)) {
      fs.copyFileSync(pkgPath, path.join(targetPath, 'package.json'));
    }

    log(`  ✓ Copied skill tree to: ${targetPath}`, colors.green);
  }
}

function generateCursorRule(filePath, dryRun = false) {
  if (dryRun) {
    log(`  [dry-run] Would generate Cursor rule at: ${filePath}`, colors.dim);
    return;
  }

  const skillContent = fs.readFileSync(SKILL_MD_PATH, 'utf8');

  const content = `---
description: "DevOps & DevSecOps Engineering standards by Reaan (Containers, Kubernetes, Terraform, GitOps, OTel)"
globs: "**/Dockerfile*, **/*.dockerignore, **/docker-compose*.yaml, **/compose*.yaml, **/*.tf, **/*.tofu, **/k8s/**/*.yaml, **/kubernetes/**/*.yaml, **/.github/workflows/*.yml, **/argocd/**/*.yaml"
alwaysApply: false
---

<!-- DevOps Skill by Reaan -->
${skillContent}
`;

  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content, 'utf8');
  log(`  ✓ Generated Cursor rule: ${filePath}`, colors.green);
}

function generateWindsurfRule(filePath, dryRun = false) {
  if (dryRun) {
    log(`  [dry-run] Would generate Windsurf rule at: ${filePath}`, colors.dim);
    return;
  }

  const skillContent = fs.readFileSync(SKILL_MD_PATH, 'utf8');
  const content = `# DevOps & DevSecOps Engineering Rules (Reaan)

${skillContent}
`;

  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content, 'utf8');
  log(`  ✓ Generated Windsurf rule: ${filePath}`, colors.green);
}

function generateCopilotInstruction(filePath, dryRun = false) {
  if (dryRun) {
    log(`  [dry-run] Would update Copilot instructions at: ${filePath}`, colors.dim);
    return;
  }

  const skillContent = fs.readFileSync(SKILL_MD_PATH, 'utf8');
  const startTag = '<!-- BEGIN DEVOPS-SKILL REAAN -->';
  const endTag = '<!-- END DEVOPS-SKILL REAAN -->';

  const block = `${startTag}
## DevOps & DevSecOps Engineering Standards (Author: Reaan)
${skillContent}
${endTag}`;

  fs.mkdirSync(path.dirname(filePath), { recursive: true });

  if (fs.existsSync(filePath)) {
    let existing = fs.readFileSync(filePath, 'utf8');
    if (existing.includes(startTag) && existing.includes(endTag)) {
      const regex = new RegExp(`${startTag}[\\s\\S]*?${endTag}`, 'm');
      existing = existing.replace(regex, block);
    } else {
      existing = `${existing.trim()}\n\n${block}\n`;
    }
    fs.writeFileSync(filePath, existing, 'utf8');
    log(`  ✓ Updated Copilot instructions: ${filePath}`, colors.green);
  } else {
    fs.writeFileSync(filePath, `${block}\n`, 'utf8');
    log(`  ✓ Created Copilot instructions: ${filePath}`, colors.green);
  }
}

function doctor() {
  printBanner();
  log('Checking skill package integrity...', colors.cyan);

  let hasErrors = false;

  REQUIRED_FILES.forEach((f) => {
    const fp = path.join(ROOT_DIR, f);
    if (fs.existsSync(fp)) {
      log(`  ✓ File found: ${f}`, colors.green);
    } else {
      log(`  ✗ Missing required file: ${f}`, colors.red);
      hasErrors = true;
    }
  });

  REQUIRED_DIRS.forEach((d) => {
    const dp = path.join(ROOT_DIR, d);
    if (fs.existsSync(dp) && fs.statSync(dp).isDirectory()) {
      const count = fs.readdirSync(dp).length;
      log(`  ✓ Directory found: ${d}/ (${count} entries)`, colors.green);
    } else {
      log(`  ✗ Missing required directory: ${d}/`, colors.red);
      hasErrors = true;
    }
  });

  if (hasErrors) {
    log('\n❌ Doctor found missing files in skill package!', colors.red);
    process.exit(1);
  } else {
    log('\n✅ Skill package integrity check passed!', colors.green);
  }
}

function listAgents(scope) {
  printBanner();
  log(`Scanning agents in scope: ${colors.bold}${scope}${colors.reset}\n`, colors.cyan);

  const defs = getAgentDefinitions(scope);

  Object.entries(defs).forEach(([key, def]) => {
    const isDetected = fs.existsSync(def.detectBase);
    const isInstalled = fs.existsSync(def.path);

    const statusBadge = isInstalled
      ? `${colors.green}[INSTALLED]${colors.reset}`
      : `${colors.dim}[NOT INSTALLED]${colors.reset}`;

    const detectBadge = isDetected
      ? `${colors.cyan}(agent detected)${colors.reset}`
      : `${colors.dim}(agent not found)${colors.reset}`;

    console.log(`  ${colors.bold}${def.name}${colors.reset} [key: ${key}]`);
    console.log(`    Status: ${statusBadge} ${detectBadge}`);
    console.log(`    Target: ${def.path}\n`);
  });
}

function runInstall(options) {
  if (!options.silent) printBanner();

  log(`Installing skill for scope: ${colors.bold}${options.scope}${colors.reset}`, colors.cyan);
  if (options.symlink) log(`Mode: Symlink (junction)`, colors.yellow);
  if (options.dryRun) log(`Mode: Dry-Run (simulation)`, colors.yellow);
  console.log();

  const defs = getAgentDefinitions(options.scope);
  const targetsToInstall = [];

  if (options.all) {
    Object.keys(defs).forEach((k) => targetsToInstall.push(k));
  } else if (options.targets.size > 0) {
    options.targets.forEach((k) => {
      if (defs[k]) targetsToInstall.push(k);
      else log(`⚠️  Unknown target: ${k}`, colors.yellow);
    });
  } else {
    // Auto-detection mode:
    // Always include standard 'agents' as universal fallback
    targetsToInstall.push('agents');

    Object.entries(defs).forEach(([k, def]) => {
      if (k !== 'agents' && fs.existsSync(def.detectBase)) {
        // Pi natively discovers skills from ~/.agents/skills.
        // In global scope, installing into both ~/.pi/agent/skills and ~/.agents/skills causes
        // a Pi skill collision warning. Skip redundant 'pi' when 'agents' is targeted.
        if (options.scope === 'global' && k === 'pi' && targetsToInstall.includes('agents')) {
          return;
        }
        targetsToInstall.push(k);
      }
    });

    log(`Auto-detected active agent environments: ${targetsToInstall.join(', ')}`, colors.dim);
  }

  // Prevent collision in global scope: if installing to ~/.agents/skills and not explicitly targeting pi,
  // ensure no duplicate skill directory in ~/.pi/agent/skills exists to trigger collision
  if (options.scope === 'global' && targetsToInstall.includes('agents') && !options.targets.has('pi') && !options.all) {
    const redundantPiSkill = path.join(getHomeDir(), '.pi', 'agent', 'skills', SKILL_NAME);
    if (fs.existsSync(redundantPiSkill)) {
      log(`\n🧹 Resolving Pi skill collision: removing redundant ${redundantPiSkill}...`, colors.yellow);
      if (!options.dryRun) {
        fs.rmSync(redundantPiSkill, { recursive: true, force: true });
        log(`  ✓ Redundant Pi skill removed; Pi will load from ~/.agents/skills without conflict`, colors.green);
      }
    }
  }

  let hasFailures = false;

  targetsToInstall.forEach((k) => {
    const def = defs[k];
    log(`\n📦 Installing to ${colors.bold}${def.name}${colors.reset}...`, colors.cyan);

    try {
      if (def.type === 'skill-dir') {
        installSkillDirectory(def.path, options.symlink, options.dryRun);
      } else if (def.type === 'cursor-rule') {
        generateCursorRule(def.path, options.dryRun);
      } else if (def.type === 'windsurf-rule') {
        generateWindsurfRule(def.path, options.dryRun);
      } else if (def.type === 'copilot-instruction') {
        generateCopilotInstruction(def.path, options.dryRun);
      }
    } catch (err) {
      hasFailures = true;
      log(`  ✗ Failed to install to ${def.name}: ${err.message}`, colors.red);
    }
  });

  console.log();
  if (hasFailures) {
    process.exitCode = 1;
    log(`❌ One or more installations failed. Review logs above.`, colors.red);
  } else {
    log(`🎉 Installation completed successfully!`, colors.green);
    log(`Skill author: Reaan | Repository: https://github.com/Reaan06/devops-skill`, colors.dim);
  }
}

function runUninstall(options) {
  if (!options.silent) printBanner();

  log(`Uninstalling skill from scope: ${colors.bold}${options.scope}${colors.reset}\n`, colors.yellow);

  const defs = getAgentDefinitions(options.scope);
  const targets = options.all || options.targets.size === 0
    ? Object.keys(defs)
    : Array.from(options.targets);

  targets.forEach((k) => {
    const def = defs[k];
    if (!def) return;

    if (fs.existsSync(def.path)) {
      log(`Removing ${def.name} from: ${def.path}`, colors.yellow);
      if (!options.dryRun) {
        const stat = fs.lstatSync(def.path);
        if (stat.isDirectory()) {
          fs.rmSync(def.path, { recursive: true, force: true });
        } else {
          fs.unlinkSync(def.path);
        }
      }
      log(`  ✓ Removed successfully`, colors.green);
    } else {
      log(`  - Not found in ${def.name}`, colors.dim);
    }
  });

  console.log();
  log(`🧹 Uninstallation finished.`, colors.green);
}

// Main Router
function main() {
  const args = process.argv.slice(2);
  const options = parseArgs(args);

  switch (options.command) {
    case 'help':
      printHelp();
      break;
    case 'version':
      console.log(`v${VERSION}`);
      break;
    case 'doctor':
      doctor();
      break;
    case 'list':
      listAgents(options.scope);
      break;
    case 'uninstall':
      runUninstall(options);
      break;
    case 'install':
    default:
      runInstall(options);
      break;
  }
}

if (require.main === module) {
  main();
}

module.exports = {
  copyRecursiveSync,
  runInstall,
  runUninstall,
  doctor,
  getAgentDefinitions,
  parseArgs,
  installSkillDirectory,
  generateCursorRule,
  generateWindsurfRule,
  generateCopilotInstruction,
  IGNORE_PATTERNS,
};
