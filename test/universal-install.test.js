/**
 * Universal Agent Skill Installation Regression Test Suite
 * Validates CLI installer (bin/cli.js) and POSIX shell installer (install.sh)
 * across Pi, Claude Code, Cursor, Windsurf, Copilot, and Agent Skills standard.
 */

const { test, describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync, spawnSync } = require('child_process');

const ROOT_DIR = path.resolve(__dirname, '..');
const CLI_PATH = path.join(ROOT_DIR, 'bin', 'cli.js');
const SH_PATH = path.join(ROOT_DIR, 'install.sh');
const { copyRecursiveSync, IGNORE_PATTERNS } = require('../bin/cli.js');

describe('Universal Installation Regression Tests', () => {
  let tmpSandbox;

  beforeEach(() => {
    tmpSandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'devops-skill-test-'));
  });

  afterEach(() => {
    if (tmpSandbox && fs.existsSync(tmpSandbox)) {
      fs.rmSync(tmpSandbox, { recursive: true, force: true });
    }
  });

  it('cli doctor validates skill package integrity', () => {
    const res = spawnSync('node', [CLI_PATH, 'doctor'], {
      cwd: ROOT_DIR,
      encoding: 'utf8',
    });
    assert.strictEqual(res.status, 0, `cli doctor exited with ${res.status}: ${res.stderr}`);
    assert.match(res.stdout, /Skill package integrity check passed!/);
  });

  it('copyRecursiveSync ignores .git, .terraform, and node_modules', () => {
    const srcDir = path.join(tmpSandbox, 'mock-src');
    const destDir = path.join(tmpSandbox, 'mock-dest');

    fs.mkdirSync(path.join(srcDir, 'valid-dir'), { recursive: true });
    fs.mkdirSync(path.join(srcDir, '.git', 'objects'), { recursive: true });
    fs.mkdirSync(path.join(srcDir, '.terraform', 'providers'), { recursive: true });
    fs.mkdirSync(path.join(srcDir, 'node_modules', 'dep'), { recursive: true });

    fs.writeFileSync(path.join(srcDir, 'valid-dir', 'valid.txt'), 'hello', 'utf8');
    fs.writeFileSync(path.join(srcDir, '.git', 'config'), 'git-config', 'utf8');
    fs.writeFileSync(path.join(srcDir, '.terraform', 'terraform.tfstate'), 'state', 'utf8');
    fs.writeFileSync(path.join(srcDir, 'node_modules', 'dep', 'index.js'), 'code', 'utf8');

    copyRecursiveSync(srcDir, destDir);

    assert.strictEqual(fs.existsSync(path.join(destDir, 'valid-dir', 'valid.txt')), true);
    assert.strictEqual(fs.existsSync(path.join(destDir, '.git')), false, '.git should be ignored');
    assert.strictEqual(fs.existsSync(path.join(destDir, '.terraform')), false, '.terraform should be ignored');
    assert.strictEqual(fs.existsSync(path.join(destDir, 'node_modules')), false, 'node_modules should be ignored');
  });

  it('runInstall tracks failures, sets exitCode to 1, and suppresses success banner', () => {
    // Run CLI targeting an invalid read-only or conflicting path to trigger install failure
    const blockingFile = path.join(tmpSandbox, 'blocked-agent');
    fs.writeFileSync(blockingFile, 'cannot write into file', { mode: 0o444 });

    // In a child process, attempt install where target directory resolution fails
    const script = `
      const path = require('path');
      const { runInstall } = require('${CLI_PATH.replace(/\\/g, '/')}');
      // Override os.homedir to simulate failure during installation
      const os = require('os');
      os.homedir = () => '${blockingFile.replace(/\\/g, '/')}';
      runInstall({
        command: 'install',
        targets: new Set(['pi']),
        scope: 'global',
        symlink: false,
        dryRun: false,
        silent: false,
      });
      process.exit(process.exitCode || 0);
    `;

    const res = spawnSync('node', ['-e', script], {
      cwd: tmpSandbox,
      encoding: 'utf8',
    });

    assert.strictEqual(res.status, 1, 'Expected process to exit with status 1 on failure');
    assert.doesNotMatch(res.stdout, /Installation completed successfully!/, 'Success banner must be suppressed on failure');
    assert.match(res.stdout, /One or more installations failed/, 'Failure notice should be logged');
  });

  it('CLI installs all agents in project scope cleanly', () => {
    const res = spawnSync('node', [CLI_PATH, 'install', '--all', '--project'], {
      cwd: tmpSandbox,
      encoding: 'utf8',
    });
    assert.strictEqual(res.status, 0, `CLI install failed: ${res.stderr}\n${res.stdout}`);
    assert.match(res.stdout, /Installation completed successfully!/);

    // Verify Pi agent
    const piSkill = path.join(tmpSandbox, '.pi', 'skills', 'devops-skill');
    assert.strictEqual(fs.existsSync(path.join(piSkill, 'SKILL.md')), true);
    assert.strictEqual(fs.existsSync(path.join(piSkill, 'references', '01-containers-runtime.md')), true);

    // Verify Claude agent
    const claudeSkill = path.join(tmpSandbox, '.claude', 'skills', 'devops-skill');
    assert.strictEqual(fs.existsSync(path.join(claudeSkill, 'SKILL.md')), true);

    // Verify Agent Skills standard
    const agentsSkill = path.join(tmpSandbox, '.agents', 'skills', 'devops-skill');
    assert.strictEqual(fs.existsSync(path.join(agentsSkill, 'SKILL.md')), true);

    // Verify Cursor rule
    const cursorRule = path.join(tmpSandbox, '.cursor', 'rules', 'devops-skill.mdc');
    assert.strictEqual(fs.existsSync(cursorRule), true);
    const cursorContent = fs.readFileSync(cursorRule, 'utf8');
    assert.match(cursorContent, /alwaysApply: false/);
    assert.match(cursorContent, /Reaan/);

    // Verify Windsurf rule
    const windsurfRule = path.join(tmpSandbox, '.windsurf', 'rules', 'devops-skill.md');
    assert.strictEqual(fs.existsSync(windsurfRule), true);

    // Verify GitHub Copilot instructions
    const copilotInst = path.join(tmpSandbox, '.github', 'copilot-instructions.md');
    assert.strictEqual(fs.existsSync(copilotInst), true);
    const copilotContent = fs.readFileSync(copilotInst, 'utf8');
    assert.match(copilotContent, /<!-- BEGIN DEVOPS-SKILL REAAN -->/);
    assert.match(copilotContent, /Author: Reaan/);
  });

  it('CLI installs symlink mode correctly', () => {
    const res = spawnSync('node', [CLI_PATH, 'install', '--pi', '--project', '--symlink'], {
      cwd: tmpSandbox,
      encoding: 'utf8',
    });
    assert.strictEqual(res.status, 0, `CLI symlink install failed: ${res.stderr}`);

    const piSkill = path.join(tmpSandbox, '.pi', 'skills', 'devops-skill');
    assert.strictEqual(fs.existsSync(piSkill), true);
    const stat = fs.lstatSync(piSkill);
    assert.strictEqual(stat.isSymbolicLink(), true, 'Expected installed target to be a symlink');
  });

  it('CLI uninstalls cleanly from project scope', () => {
    // Install first
    spawnSync('node', [CLI_PATH, 'install', '--cursor', '--copilot', '--project'], {
      cwd: tmpSandbox,
      encoding: 'utf8',
    });

    const cursorRule = path.join(tmpSandbox, '.cursor', 'rules', 'devops-skill.mdc');
    const copilotInst = path.join(tmpSandbox, '.github', 'copilot-instructions.md');
    assert.strictEqual(fs.existsSync(cursorRule), true);
    assert.strictEqual(fs.existsSync(copilotInst), true);

    // Uninstall
    const uninstRes = spawnSync('node', [CLI_PATH, 'uninstall', '--all', '--project'], {
      cwd: tmpSandbox,
      encoding: 'utf8',
    });
    assert.strictEqual(uninstRes.status, 0);
    assert.strictEqual(fs.existsSync(cursorRule), false, 'Cursor rule should be removed');
    assert.strictEqual(fs.existsSync(copilotInst), false, 'Copilot instruction should be removed');
  });

  it('CLI auto-detection avoids redundant ~/.pi skill collision when agents standard is targeted', () => {
    const fakeHome = fs.mkdtempSync(path.join(os.tmpdir(), 'home-mock-'));
    fs.mkdirSync(path.join(fakeHome, '.pi'), { recursive: true });
    // Pre-create an old duplicate in ~/.pi/agent/skills/devops-skill
    const oldPiSkill = path.join(fakeHome, '.pi', 'agent', 'skills', 'devops-skill');
    fs.mkdirSync(oldPiSkill, { recursive: true });
    fs.writeFileSync(path.join(oldPiSkill, 'SKILL.md'), '# Old Duplicate');

    const res = spawnSync('node', [CLI_PATH, 'install', '--global'], {
      cwd: tmpSandbox,
      env: { ...process.env, HOME: fakeHome, USERPROFILE: fakeHome },
      encoding: 'utf8',
    });
    assert.strictEqual(res.status, 0, `CLI auto install failed: ${res.stderr}`);

    const agentsSkill = path.join(fakeHome, '.agents', 'skills', 'devops-skill');
    assert.strictEqual(fs.existsSync(path.join(agentsSkill, 'SKILL.md')), true);
    // Redundant Pi skill should have been cleaned up to prevent Pi skill collision
    assert.strictEqual(fs.existsSync(oldPiSkill), false);

    fs.rmSync(fakeHome, { recursive: true, force: true });
  });

  it('POSIX install.sh installs all agents cleanly in isolated environment', () => {
    const res = spawnSync('sh', [SH_PATH, '--all', '--project'], {
      cwd: tmpSandbox,
      encoding: 'utf8',
    });
    assert.strictEqual(res.status, 0, `install.sh failed: ${res.stderr}\n${res.stdout}`);

    // Verify all targets
    assert.strictEqual(fs.existsSync(path.join(tmpSandbox, '.pi', 'skills', 'devops-skill', 'SKILL.md')), true);
    assert.strictEqual(fs.existsSync(path.join(tmpSandbox, '.claude', 'skills', 'devops-skill', 'SKILL.md')), true);
    assert.strictEqual(fs.existsSync(path.join(tmpSandbox, '.agents', 'skills', 'devops-skill', 'SKILL.md')), true);
    assert.strictEqual(fs.existsSync(path.join(tmpSandbox, '.cursor', 'rules', 'devops-skill.mdc')), true);
    assert.strictEqual(fs.existsSync(path.join(tmpSandbox, '.windsurf', 'rules', 'devops-skill.md')), true);
    assert.strictEqual(fs.existsSync(path.join(tmpSandbox, '.github', 'copilot-instructions.md')), true);
  });
});
