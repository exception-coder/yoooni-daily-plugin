const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const test = require('node:test');

const pluginRoot = path.resolve(__dirname, '..', '..');

test('isolated installed layout discovers and executes every configured hook', () => {
  const fixture = createIsolatedMarketplace();
  try {
    const manifestPath = path.join(fixture.pluginCopy, '.codex-plugin', 'plugin.json');
    const manifest = readJson(manifestPath);
    assert.equal(manifest.name, fixture.pluginName);
    assert.equal(Object.hasOwn(manifest, 'hooks'), false);

    const hooksPath = path.join(fixture.pluginCopy, 'hooks', 'hooks.json');
    const hooks = readJson(hooksPath);
    const commands = configuredCommands(hooks);
    assert.ok(commands.length > 0, 'at least one hook command must be configured');

    for (const command of commands) {
      const script = resolveNodeScript(command, fixture.pluginCopy);
      assert.ok(fs.existsSync(script), `hook script is missing: ${script}`);
      const result = spawnSync(process.execPath, [script], {
        cwd: fixture.pluginCopy,
        encoding: 'utf8',
        input: JSON.stringify({ tool_name: 'noop', tool_input: {}, cwd: fixture.pluginCopy }),
        env: safeHookEnvironment(fixture.pluginCopy),
      });
      assert.equal(result.status, 0, `${path.basename(script)} failed: ${result.stderr}`);
    }
  } finally {
    removeTemporaryRoot(fixture.temporaryRoot);
  }
});

test('Codex CLI installs the local plugin from an isolated personal marketplace', (t) => {
  const codex = findCodexCli();
  if (!codex) {
    t.skip('Codex CLI is not installed on this host');
    return;
  }

  const fixture = createIsolatedMarketplace();
  try {
    const environment = {
      ...process.env,
      USERPROFILE: fixture.profileRoot,
      HOME: fixture.profileRoot,
      CODEX_HOME: fixture.codexHome,
    };
    const install = runCodex(codex, ['plugin', 'add', `${fixture.pluginName}@personal`, '--json'], environment);
    assert.equal(install.status, 0, `Codex install failed:\n${install.stdout}\n${install.stderr}`);

    const list = runCodex(codex, ['plugin', 'list'], environment);
    assert.equal(list.status, 0, `Codex plugin list failed:\n${list.stdout}\n${list.stderr}`);
    assert.match(`${list.stdout}\n${list.stderr}`, new RegExp(escapeRegex(fixture.pluginName)));
  } finally {
    removeTemporaryRoot(fixture.temporaryRoot);
  }
});

function createIsolatedMarketplace() {
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-plugin-install-smoke-'));
  const profileRoot = path.join(temporaryRoot, 'profile');
  const codexHome = path.join(temporaryRoot, 'codex-home');
  const marketplaceRoot = path.join(profileRoot, '.agents', 'plugins');
  const manifest = readJson(path.join(pluginRoot, '.codex-plugin', 'plugin.json'));
  const pluginCopy = path.join(profileRoot, 'plugins', manifest.name);

  fs.mkdirSync(codexHome, { recursive: true });
  fs.mkdirSync(marketplaceRoot, { recursive: true });
  fs.mkdirSync(path.dirname(pluginCopy), { recursive: true });
  fs.cpSync(pluginRoot, pluginCopy, { recursive: true });
  fs.writeFileSync(path.join(marketplaceRoot, 'marketplace.json'), JSON.stringify({
    name: 'personal',
    interface: { displayName: 'Isolated Plugin Smoke Tests' },
    plugins: [{
      name: manifest.name,
      source: { source: 'local', path: `./plugins/${manifest.name}` },
      policy: { installation: 'AVAILABLE', authentication: 'ON_INSTALL' },
      category: 'Productivity',
    }],
  }, null, 2));

  return { temporaryRoot, profileRoot, codexHome, pluginCopy, pluginName: manifest.name };
}

function configuredCommands(config) {
  return Object.values(config.hooks || {})
    .flatMap((groups) => Array.isArray(groups) ? groups : [])
    .flatMap((group) => Array.isArray(group.hooks) ? group.hooks : [])
    .filter((hook) => hook && hook.type === 'command')
    .map((hook) => hook.command);
}

function resolveNodeScript(command, installedRoot) {
  const expanded = command.replaceAll('${CLAUDE_PLUGIN_ROOT}', installedRoot);
  const match = /^node\s+"([^"]+)"$/.exec(expanded);
  assert.ok(match, `unsupported hook command in smoke test: ${command}`);
  return path.normalize(match[1]);
}

function safeHookEnvironment(installedRoot) {
  return {
    ...process.env,
    CLAUDE_PLUGIN_ROOT: installedRoot,
    TEAM_STANDARDS_DESIGN_DOC_HOOK: 'off',
    TEAM_STANDARDS_BACKEND_KG_HOOK: 'off',
    TEAM_STANDARDS_COMMENT_HOOK: 'off',
    TEAM_STANDARDS_SQL_DDL_HOOK: 'off',
    TEAM_STANDARDS_DOC_LOCATION_HOOK: 'off',
    TEAM_STANDARDS_PROMPT_SIGNAL: 'off',
    TEAM_STANDARDS_VERSION_REMINDER: 'off',
    PCP_ENCODING_HOOK: 'off',
    PCP_FRONTEND_HOOK: 'off',
    PCP_CROSSMODULE_HOOK: 'off',
    PROJECT_CODING_PROFILES_VERSION_REMINDER: 'off',
    YOOONI_AUTOUPDATE: 'off',
    YOOONI_VERSION_REMINDER: 'off',
  };
}

function findCodexCli() {
  if (process.platform === 'win32') {
    const codexScript = path.join(process.env.APPDATA || '', 'npm', 'node_modules', '@openai', 'codex', 'bin', 'codex.js');
    if (fs.existsSync(codexScript)) return { executable: process.execPath, prefixArgs: [codexScript] };
  }
  const locator = process.platform === 'win32'
    ? spawnSync('where.exe', ['codex'], { encoding: 'utf8' })
    : spawnSync('which', ['codex'], { encoding: 'utf8' });
  if (locator.status !== 0) return '';
  const executable = locator.stdout.split(/\r?\n/).map((line) => line.trim()).find(Boolean) || '';
  return executable ? { executable, prefixArgs: [] } : '';
}

function runCodex(codex, args, environment) {
  return spawnSync(codex.executable, [...codex.prefixArgs, ...args], {
    encoding: 'utf8',
    env: environment,
  });
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function removeTemporaryRoot(temporaryRoot) {
  const resolved = path.resolve(temporaryRoot);
  const systemTemp = `${path.resolve(os.tmpdir())}${path.sep}`;
  assert.ok(resolved.startsWith(systemTemp), `unsafe cleanup target: ${resolved}`);
  assert.match(path.basename(resolved), /^codex-plugin-install-smoke-/);
  fs.rmSync(resolved, { recursive: true, force: true });
}
