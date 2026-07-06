import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const scriptName = 'verify-mihomo-prebuilt-packaging';
const libraryName = 'libmihomo_ohos.so';
const execFallbackName = 'libmihomo_exec.so';
const entryBuildProfilePath = path.join(root, 'entry/build-profile.json5');
const prebuiltRoot = path.join(root, 'entry/src/main/cpp/prebuilt');
const defaultHapPath = path.join(root, 'entry/build/default/outputs/default/entry-default-signed.hap');
const args = parseArgs(process.argv.slice(2));
const hapPath = path.resolve(root, args.hap ?? defaultHapPath);

const configuredAbis = readConfiguredAbis();
const requiredAbis = readRequiredAbis(configuredAbis);
const prebuiltAbis = configuredAbis.filter((abi) =>
  fs.existsSync(path.join(prebuiltRoot, abi, libraryName))
);
const bundledPrebuiltAbis = configuredAbis.filter((abi) => readPrebuiltLibraries(abi).length > 0);

if (bundledPrebuiltAbis.length === 0 && requiredAbis.length === 0) {
  console.log(`${scriptName}: mihomo prebuilt packaging check skipped; no ${libraryName} found for ${configuredAbis.join(', ')}`);
  process.exit(0);
}

const missingRequiredPrebuiltAbis = requiredAbis.filter((abi) => !prebuiltAbis.includes(abi));
if (missingRequiredPrebuiltAbis.length > 0) {
  fail([`${scriptName}: required prebuilt ${libraryName} is missing for ${missingRequiredPrebuiltAbis.join(', ')}`]);
}

if (!fs.existsSync(hapPath)) {
  fail([
    `HAP not found: ${path.relative(root, hapPath)}`,
    'Run hvigor assembleHap before verifying mihomo prebuilt packaging.'
  ]);
}

const hapEntries = new Set(readHapEntries(hapPath));
const errors = [];
const warnings = [];

for (const abi of configuredAbis) {
  const prebuiltPath = path.join(prebuiltRoot, abi, libraryName);
  const prebuiltLibraries = readPrebuiltLibraries(abi);
  if (!fs.existsSync(prebuiltPath)) {
    if (requiredAbis.includes(abi)) {
      errors.push(`Missing required prebuilt native lib: ${path.relative(root, prebuiltPath)}`);
    } else if (prebuiltLibraries.length > 0) {
      errors.push(`${abi}: prebuilt native bundle contains sidecar libraries but missing required ${libraryName}: ${
        prebuiltLibraries.map((libraryPath) => path.relative(root, libraryPath)).join(', ')
      }`);
    } else {
      warnings.push(`No prebuilt ${libraryName} for configured ABI ${abi}; that ABI will remain on adapter stub.`);
    }
    continue;
  }

  for (const bundledLibraryPath of prebuiltLibraries) {
    const bundledLibraryName = path.basename(bundledLibraryPath);
    const intermediatePath = path.join(root, 'entry/build/default/intermediates/libs/default', abi, bundledLibraryName);
    const hapEntry = `libs/${abi}/${bundledLibraryName}`;
    const bundleLabel = bundledLibraryName === execFallbackName
      ? 'mihomo exec fallback'
      : 'mihomo native bundle';

    if (!fs.existsSync(intermediatePath)) {
      errors.push(`Missing ${bundleLabel} intermediate native lib: ${path.relative(root, intermediatePath)}`);
    }

    if (!hapEntries.has(hapEntry)) {
      errors.push(`Missing ${bundleLabel} HAP native lib entry: ${hapEntry}`);
    }
  }
}

for (const warning of warnings) {
  console.warn(`warning: ${warning}`);
}

if (errors.length > 0) {
  fail(errors);
}

console.log(`${scriptName}: mihomo prebuilt packaging check passed for ${prebuiltAbis.join(', ')} in ${path.relative(root, hapPath)}`);

function readPrebuiltLibraries(abi) {
  const abiDir = path.join(prebuiltRoot, abi);
  if (!fs.existsSync(abiDir)) {
    return [];
  }
  return fs.readdirSync(abiDir)
    .filter((fileName) => fileName.endsWith('.so'))
    .sort((left, right) => {
      if (left === libraryName) {
        return -1;
      }
      if (right === libraryName) {
        return 1;
      }
      return left.localeCompare(right);
    })
    .map((fileName) => path.join(abiDir, fileName));
}

function parseArgs(argv) {
  const parsed = {
    requireAbis: []
  };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === '--help' || arg === '-h') {
      printHelp();
      process.exit(0);
    } else if (arg === '--hap') {
      parsed.hap = requireValue(argv, ++index, arg);
    } else if (arg.startsWith('--hap=')) {
      parsed.hap = arg.slice('--hap='.length);
    } else if (arg === '--require-abi') {
      parsed.requireAbis.push(...splitAbiList(requireValue(argv, ++index, arg)));
    } else if (arg.startsWith('--require-abi=')) {
      parsed.requireAbis.push(...splitAbiList(arg.slice('--require-abi='.length)));
    } else if (!arg.startsWith('--') && parsed.hap === undefined) {
      parsed.hap = arg;
    } else {
      fail([`${scriptName}: unknown argument ${arg}`]);
    }
  }
  return parsed;
}

function requireValue(argv, index, flag) {
  if (index >= argv.length || argv[index].startsWith('--')) {
    fail([`${scriptName}: ${flag} requires a value`]);
  }
  return argv[index];
}

function splitAbiList(value) {
  return value
    .split(',')
    .map((abi) => abi.trim())
    .filter((abi) => abi.length > 0);
}

function readRequiredAbis(configuredAbis) {
  const required = Array.from(new Set(args.requireAbis));
  const unknown = required.filter((abi) => !configuredAbis.includes(abi));
  if (unknown.length > 0) {
    fail([`${scriptName}: --require-abi contains ABI not configured in entry/build-profile.json5: ${unknown.join(', ')}`]);
  }
  return required;
}

function readConfiguredAbis() {
  const source = fs.readFileSync(entryBuildProfilePath, 'utf8');
  const match = source.match(/"abiFilters"\s*:\s*\[([\s\S]*?)\]/);
  if (match === null) {
    fail([`No abiFilters found in ${path.relative(root, entryBuildProfilePath)}`]);
  }

  const abis = Array.from(match[1].matchAll(/"([^"]+)"/g), (abiMatch) => abiMatch[1]);
  if (abis.length === 0) {
    fail([`abiFilters is empty in ${path.relative(root, entryBuildProfilePath)}`]);
  }
  return abis;
}

function readHapEntries(targetHapPath) {
  try {
    return execFileSync('unzip', ['-Z1', targetHapPath], { encoding: 'utf8' })
      .split('\n')
      .map((entry) => entry.trim())
      .filter((entry) => entry.length > 0);
  } catch (error) {
    fail([
      `Unable to inspect HAP entries with unzip: ${path.relative(root, targetHapPath)}`,
      error instanceof Error ? error.message : String(error)
    ]);
  }
}

function printHelp() {
  console.log(`
Usage:
  node tests/verify-mihomo-prebuilt-packaging.mjs [hap] [--require-abi <abi[,abi...]>]

Options:
  --hap <path>          Signed HAP path. Defaults to entry/build/default/outputs/default/entry-default-signed.hap.
  --require-abi <abi>   Fail if the named configured ABI lacks source, intermediate, or HAP ${libraryName}.

When ${execFallbackName} is present beside ${libraryName}, it is treated as a required same-ABI sidecar and must also
be present in entry/build/default/intermediates/libs/default/<abi>/ and libs/<abi>/ inside the HAP.
`);
}

function fail(messages) {
  console.error(messages.join('\n'));
  process.exit(1);
}
