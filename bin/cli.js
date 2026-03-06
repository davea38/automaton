#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const TEMPLATES_DIR = path.join(__dirname, '..', 'templates');
const TARGET_DIR = process.cwd();

// Files that should never be overwritten if they contain user work
const USER_CONTENT_FILES = new Set(['PRD.md', 'AGENTS.md']);
const USER_CONTENT_DIRS = new Set(['specs']);

// All template files the scaffolder will copy (order matches spec-13)
const TEMPLATE_FILES = [
  'automaton.sh',
  'automaton.config.json',
  'PROMPT_converse.md',
  'PROMPT_research.md',
  'PROMPT_plan.md',
  'PROMPT_build.md',
  'PROMPT_review.md',
  'PROMPT_self_research.md',
  'PROMPT_wizard.md',
  'PROMPT_qa.md',
  'PROMPT_evolve_reflect.md',
  'PROMPT_evolve_ideate.md',
  'PROMPT_evolve_observe.md',
  'AGENTS.md',
  'IMPLEMENTATION_PLAN.md',
  'CLAUDE.md',
  'PRD.md',
];

// Directories to create
const DIRECTORIES = ['specs', '.automaton'];

function checkDependency(name, installHint) {
  try {
    require('child_process').execSync(`which ${name}`, { stdio: 'ignore' });
    return true;
  } catch {
    console.error(`  Warning: '${name}' is not installed.`);
    console.error(`    ${installHint}`);
    return false;
  }
}

function checkDependencies() {
  console.log('Checking system dependencies...');
  const deps = [
    ['claude', 'Install: https://docs.anthropic.com/en/docs/claude-code'],
    ['jq', 'Install: sudo apt install jq (Debian/Ubuntu) or brew install jq (macOS)'],
    ['git', 'Install: sudo apt install git (Debian/Ubuntu) or brew install git (macOS)'],
  ];

  let allFound = true;
  for (const [name, hint] of deps) {
    if (!checkDependency(name, hint)) {
      allFound = false;
    }
  }

  if (!allFound) {
    console.error('');
    console.error('  Some dependencies are missing. automaton.sh requires all three to run.');
    console.error('  Scaffolding will continue, but install missing dependencies before running.');
    console.error('');
  }
}

function hasContent(filePath) {
  try {
    const stat = fs.statSync(filePath);
    if (!stat.isFile()) return false;
    const content = fs.readFileSync(filePath, 'utf8').trim();
    return content.length > 0;
  } catch {
    return false;
  }
}

function dirHasContent(dirPath) {
  try {
    const entries = fs.readdirSync(dirPath);
    return entries.length > 0;
  } catch {
    return false;
  }
}

function copyTemplate(filename) {
  const src = path.join(TEMPLATES_DIR, filename);
  const dest = path.join(TARGET_DIR, filename);

  // Check if template exists in our package
  if (!fs.existsSync(src)) {
    return 'skipped';
  }

  // Overwrite protection for user-content files
  if (USER_CONTENT_FILES.has(filename) && hasContent(dest)) {
    console.log(`  Skipped   ${filename} (contains user content)`);
    return 'protected';
  }

  // Check if file exists (for reporting)
  const existed = fs.existsSync(dest);

  fs.copyFileSync(src, dest);

  if (existed) {
    console.log(`  Updated   ${filename}`);
  } else {
    console.log(`  Created   ${filename}`);
  }

  return existed ? 'updated' : 'created';
}

function createDirectories() {
  for (const dir of DIRECTORIES) {
    const dirPath = path.join(TARGET_DIR, dir);

    if (USER_CONTENT_DIRS.has(dir) && dirHasContent(dirPath)) {
      console.log(`  Skipped   ${dir}/ (contains user content)`);
      continue;
    }

    if (!fs.existsSync(dirPath)) {
      fs.mkdirSync(dirPath, { recursive: true });
      console.log(`  Created   ${dir}/`);
    } else {
      console.log(`  Exists    ${dir}/`);
    }
  }
}

function copyLibDirectory() {
  const srcDir = path.join(TEMPLATES_DIR, 'lib');
  const destDir = path.join(TARGET_DIR, 'lib');

  if (!fs.existsSync(srcDir)) {
    console.log('  Skipped   lib/ (template not available)');
    return;
  }

  if (!fs.existsSync(destDir)) {
    fs.mkdirSync(destDir, { recursive: true });
  }

  const files = fs.readdirSync(srcDir);
  let copied = 0;
  for (const file of files) {
    const srcFile = path.join(srcDir, file);
    const destFile = path.join(destDir, file);
    if (fs.statSync(srcFile).isFile()) {
      fs.copyFileSync(srcFile, destFile);
      copied++;
    }
  }

  console.log(`  Copied    lib/ (${copied} modules)`);
}

function makeExecutable(filename) {
  const filePath = path.join(TARGET_DIR, filename);
  if (fs.existsSync(filePath)) {
    fs.chmodSync(filePath, 0o755);
  }
}

function updateGitignore() {
  const gitignorePath = path.join(TARGET_DIR, '.gitignore');
  const entry = '.automaton/';

  if (fs.existsSync(gitignorePath)) {
    const content = fs.readFileSync(gitignorePath, 'utf8');
    if (!content.includes(entry)) {
      const newline = content.endsWith('\n') ? '' : '\n';
      fs.appendFileSync(gitignorePath, `${newline}${entry}\n`);
      console.log('  Updated   .gitignore (added .automaton/)');
    } else {
      console.log('  Exists    .automaton/ in .gitignore');
    }
  } else {
    fs.writeFileSync(gitignorePath, `${entry}\n`);
    console.log('  Created   .gitignore');
  }
}

function printBanner() {
  console.log(`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 automaton scaffolded successfully

 Next steps:
   1. Run './automaton.sh'
      It handles everything: requirements gathering,
      planning, building, and review — all autonomously.
      If no specs exist, it launches an interactive wizard.

 Options:
   ./automaton.sh --wizard    Force the requirements wizard
   ./automaton.sh --resume    Resume an interrupted run
   ./automaton.sh --doctor    Check system dependencies

 Files created:
   automaton.sh          - Master orchestrator
   lib/                  - Library modules (17 modules)
   PROMPT_*.md           - Agent prompts (5 phases)
   automaton.config.json - Configuration
   AGENTS.md             - Operational guide
   specs/                - Your specs go here
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
}

// --- Main ---

console.log('');
console.log('automaton - Multi-agent orchestration for autonomous software delivery');
console.log('');

checkDependencies();

console.log('Scaffolding project files...');
console.log('');

// Copy template files
let created = 0;
let updated = 0;
let skippedMissing = 0;

for (const file of TEMPLATE_FILES) {
  const result = copyTemplate(file);
  if (result === 'created') created++;
  else if (result === 'updated') updated++;
  else if (result === 'skipped') skippedMissing++;
}

console.log('');

// Copy lib/ directory (modular architecture)
copyLibDirectory();

console.log('');

// Create directories
createDirectories();

console.log('');

// Make automaton.sh executable
makeExecutable('automaton.sh');

// Update .gitignore
updateGitignore();

// Print summary
if (skippedMissing > 0) {
  console.log('');
  console.log(`  Note: ${skippedMissing} template(s) not yet available (will be added in a future version)`);
}

printBanner();
