#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const root = process.cwd();
const scriptName = 'verify-hap-contents';
const libraryName = 'libmihomo_ohos.so';
const execFallbackName = 'libmihomo_exec.so';
const defaultHapPath = path.join(root, 'entry/build/default/outputs/default/entry-default-signed.hap');
const entryBuildProfilePath = path.join(root, 'entry/build-profile.json5');
const prebuiltRoot = path.join(root, 'entry/src/main/cpp/prebuilt');
const fakeMihomoSourcePath = path.join(root, 'entry/src/main/cpp/fake_mihomo/fake_mihomo.c');
const systemNeededLibraries = new Set([
  'libc.so',
  'libm.so',
  'libdl.so',
  'libpthread.so',
  'libatomic.so',
  'libace_napi.z.so',
  'libhilog_ndk.z.so',
  'libnet_connection.so'
]);
const forbiddenNeededPatterns = [
  /^libc\.so\.6$/,
  /^libstdc\+\+\.so\.6$/,
  /^libgcc_s\.so\.1$/,
  /^ld-linux/,
  /^libpthread\.so\.0$/,
  /^libdl\.so\.2$/
];
const readelfCandidatePaths = [
  process.env.OHOS_LLVM_READELF,
  '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/llvm/bin/llvm-readelf',
  '/Applications/DevEco-Studio.app/Contents/sdk/default/hms/native/BiSheng/bin/llvm-readelf'
].filter((candidate) => candidate !== undefined && candidate.length > 0);
const args = parseArgs(process.argv.slice(2));
const hapEntryReadMaxBuffer = 256 * 1024 * 1024;

if (args.help) {
  printHelp();
  process.exit(0);
}

const hapPath = path.resolve(root, args.hap ?? defaultHapPath);

if (!fs.existsSync(hapPath)) {
  fail([
    `${scriptName}: HAP not found: ${path.relative(root, hapPath)}`,
    'Run hvigor assembleHap before verifying HAP contents.'
  ]);
}

const configuredAbis = readConfiguredAbis();
const requiredAbis = readRequiredAbis(configuredAbis);
const entries = new Set(readHapEntries(hapPath));
const moduleJson = readHapJson(hapPath, 'module.json');
const readelfTool = findReadelfTool();
const errors = [];
const warnings = [];
const nativeLibraries = [];
const hashes = [];
const dependencies = [];

requireEntry(entries, 'module.json', errors);
requireEntry(entries, 'ets/modules.abc', errors);
requireEntry(entries, 'pack.info', errors);

for (const abi of configuredAbis) {
  requireEntry(entries, `libs/${abi}/libentry.so`, errors);
  requireEntry(entries, `libs/${abi}/libc++_shared.so`, errors);

  const prebuiltLibraries = readPrebuiltLibraries(abi);
  const prebuiltPath = path.join(prebuiltRoot, abi, libraryName);
  const execFallbackPath = path.join(prebuiltRoot, abi, execFallbackName);
  const hapEntry = `libs/${abi}/${libraryName}`;
  const execFallbackHapEntry = `libs/${abi}/${execFallbackName}`;
  const hasPrebuiltMain = fs.existsSync(prebuiltPath);
  const hasExecFallback = fs.existsSync(execFallbackPath);
  const hasFakeAdapterSource = fs.existsSync(fakeMihomoSourcePath);
  nativeLibraries.push({
    abi,
    libentry: entries.has(`libs/${abi}/libentry.so`),
    cxxShared: entries.has(`libs/${abi}/libc++_shared.so`),
    mihomoPrebuilt: hasPrebuiltMain,
    mihomoPrebuiltBundle: prebuiltLibraries.map((libraryPath) => path.basename(libraryPath)),
    mihomoExecFallback: hasExecFallback,
    fakeMihomoSource: hasFakeAdapterSource,
    mihomoHapEntry: entries.has(hapEntry),
    mihomoExecFallbackHapEntry: entries.has(execFallbackHapEntry)
  });
  if (hasPrebuiltMain) {
    for (const bundledLibraryPath of prebuiltLibraries) {
      const bundledLibraryName = path.basename(bundledLibraryPath);
      const bundledHapEntry = `libs/${abi}/${bundledLibraryName}`;
      requireEntry(entries, bundledHapEntry, errors);
      hashes.push(verifyPrebuiltHashes(bundledLibraryPath, bundledHapEntry, abi, bundledLibraryName, errors));
    }
    if (hasExecFallback && !entries.has(execFallbackHapEntry)) {
      errors.push(`${abi}: exec fallback ${execFallbackName} exists but is missing from HAP: ${execFallbackHapEntry}`);
    }
  } else if (prebuiltLibraries.length > 0) {
    errors.push(`${abi}: prebuilt native bundle contains sidecar libraries but missing required ${libraryName}: ${
      prebuiltLibraries.map((libraryPath) => path.relative(root, libraryPath)).join(', ')
    }`);
  } else if (entries.has(hapEntry)) {
    if (hasFakeAdapterSource) {
      warnings.push(`No real prebuilt ${libraryName} for ${abi}; HAP contains built-in fake mihomo adapter.`);
    } else {
      errors.push(`Unexpected stale mihomo library in HAP without prebuilt source: ${hapEntry}`);
    }
  } else if (requiredAbis.includes(abi)) {
    errors.push(`Required ABI ${abi} is missing ${libraryName} in prebuilt source and HAP`);
  } else {
    warnings.push(`No ${libraryName} for ${abi}; HAP correctly remains on adapter stub for that ABI.`);
  }
}

verifyNativeDependencyClosure(readelfTool, errors, warnings, dependencies);

assertEqual(moduleJson?.app?.bundleName, 'io.github.clashharmony.app', 'bundleName', errors);
assertEqual(moduleJson?.module?.mainElement, 'EntryAbility', 'module.mainElement', errors);
assertHasAbility(moduleJson, 'EntryAbility', errors);
assertHasVpnExtension(moduleJson, 'ClashVpnExtensionAbility', errors);
assertHasPermission(moduleJson, 'ohos.permission.INTERNET', errors);

for (const warning of warnings) {
  console.warn(`warning: ${warning}`);
}

if (errors.length > 0) {
  writeEvidenceIfRequested('failed', errors);
  fail([
    `${scriptName}: HAP content verification failed`,
    ...errors
  ]);
}

writeEvidenceIfRequested('passed', []);
console.log(`${scriptName}: HAP content verification passed for ${path.relative(root, hapPath)}`);

function parseArgs(argv) {
  const parsed = { help: false };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === '--help' || arg === '-h') {
      parsed.help = true;
    } else if (arg === '--hap') {
      parsed.hap = requireValue(argv, ++index, arg);
    } else if (arg.startsWith('--hap=')) {
      parsed.hap = arg.slice('--hap='.length);
    } else if (arg === '--evidence-dir') {
      parsed.evidenceDir = requireValue(argv, ++index, arg);
    } else if (arg.startsWith('--evidence-dir=')) {
      parsed.evidenceDir = arg.slice('--evidence-dir='.length);
    } else if (arg === '--require-abi') {
      parsed.requireAbis ??= [];
      parsed.requireAbis.push(...splitAbiList(requireValue(argv, ++index, arg)));
    } else if (arg.startsWith('--require-abi=')) {
      parsed.requireAbis ??= [];
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
  const required = Array.from(new Set(args.requireAbis ?? []));
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
    fail([`${scriptName}: no abiFilters found in ${path.relative(root, entryBuildProfilePath)}`]);
  }
  const abis = Array.from(match[1].matchAll(/"([^"]+)"/g), (abiMatch) => abiMatch[1]);
  if (abis.length === 0) {
    fail([`${scriptName}: abiFilters is empty in ${path.relative(root, entryBuildProfilePath)}`]);
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
      `${scriptName}: unable to inspect HAP entries with unzip: ${path.relative(root, targetHapPath)}`,
      errorMessage(error)
    ]);
  }
}

function readHapJson(targetHapPath, entryName) {
  try {
    const source = execFileSync('unzip', ['-p', targetHapPath, entryName], { encoding: 'utf8' });
    return JSON.parse(source);
  } catch (error) {
    fail([
      `${scriptName}: unable to read ${entryName} from ${path.relative(root, targetHapPath)}`,
      errorMessage(error)
    ]);
  }
}

function requireEntry(entries, entryName, errors) {
  if (!entries.has(entryName)) {
    errors.push(`Missing HAP entry: ${entryName}`);
  }
}

function assertEqual(actual, expected, label, errors) {
  if (actual !== expected) {
    errors.push(`Expected ${label}=${expected}, got ${actual === undefined ? 'undefined' : actual}`);
  }
}

function assertHasAbility(moduleJson, abilityName, errors) {
  const abilities = moduleJson?.module?.abilities;
  if (!Array.isArray(abilities) || !abilities.some((ability) => ability?.name === abilityName)) {
    errors.push(`Missing ability ${abilityName} in module.json`);
  }
}

function assertHasVpnExtension(moduleJson, extensionName, errors) {
  const extensionAbilities = moduleJson?.module?.extensionAbilities;
  if (!Array.isArray(extensionAbilities) ||
      !extensionAbilities.some((extension) => extension?.name === extensionName && extension?.type === 'vpn')) {
    errors.push(`Missing vpn extension ${extensionName} in module.json`);
  }
}

function assertHasPermission(moduleJson, permissionName, errors) {
  const permissions = moduleJson?.module?.requestPermissions;
  if (!Array.isArray(permissions) || !permissions.some((permission) => permission?.name === permissionName)) {
    errors.push(`Missing permission ${permissionName} in module.json`);
  }
}

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

function verifyPrebuiltHashes(prebuiltPath, hapEntry, abi, bundledLibraryName, errors) {
  const sourceHash = sha256File(prebuiltPath);
  const intermediatePath = path.join(root, 'entry/build/default/intermediates/libs/default', abi, bundledLibraryName);
  const strippedPath = path.join(root, 'entry/build/default/intermediates/stripped_native_libs/default', abi, bundledLibraryName);
  const record = {
    abi,
    library: bundledLibraryName,
    source: {
      path: path.relative(root, prebuiltPath),
      sha256: sourceHash
    },
    intermediate: null,
    stripped: null,
    hap: null
  };

  if (!fs.existsSync(intermediatePath)) {
    errors.push(`Missing copied mihomo native bundle intermediate for hash check: ${path.relative(root, intermediatePath)}`);
  } else {
    const intermediateHash = sha256File(intermediatePath);
    record.intermediate = {
      path: path.relative(root, intermediatePath),
      sha256: intermediateHash,
      matchesSource: intermediateHash === sourceHash
    };
    if (intermediateHash !== sourceHash) {
      errors.push(`Mihomo prebuilt hash mismatch for ${abi}/${bundledLibraryName}: source ${sourceHash} != intermediate ${intermediateHash}`);
    }
  }

  if (fs.existsSync(strippedPath)) {
    const strippedHash = sha256File(strippedPath);
    record.stripped = {
      path: path.relative(root, strippedPath),
      sha256: strippedHash
    };
    if (entries.has(hapEntry)) {
      const hapHash = sha256HapEntry(hapPath, hapEntry);
      record.hap = {
        entry: hapEntry,
        sha256: hapHash,
        matchesStripped: hapHash === strippedHash
      };
      if (hapHash !== strippedHash) {
        errors.push(`Mihomo HAP hash mismatch for ${abi}/${bundledLibraryName}: stripped ${strippedHash} != HAP ${hapHash}`);
      }
      console.log(`${scriptName}: ${abi} ${bundledLibraryName} sha256 source=${sourceHash} stripped=${strippedHash} hap=${hapHash}`);
    }
  } else if (entries.has(hapEntry)) {
    const hapHash = sha256HapEntry(hapPath, hapEntry);
    record.hap = {
      entry: hapEntry,
      sha256: hapHash
    };
    console.log(`${scriptName}: ${abi} ${bundledLibraryName} sha256 source=${sourceHash} hap=${hapHash}`);
  }

  return record;
}

function verifyNativeDependencyClosure(readelfToolPath, errors, warnings, dependencyRecords) {
  const nativeEntries = configuredAbis.flatMap((abi) =>
    Array.from(entries)
      .filter((entryName) => entryName.startsWith(`libs/${abi}/`) && entryName.endsWith('.so'))
      .sort()
      .map((entryName) => ({ abi, entryName }))
  );

  if (nativeEntries.length === 0) {
    return;
  }

  if (readelfToolPath === null) {
    const message = `${scriptName}: no llvm-readelf or readelf tool found; set OHOS_LLVM_READELF or install DevEco Studio native tools`;
    if (requiredAbis.length > 0 || hasAnyMihomoPrebuilt()) {
      errors.push(message);
    } else {
      warnings.push(`${message}; native dependency closure check skipped.`);
    }
    return;
  }

  for (const { abi, entryName } of nativeEntries) {
    dependencyRecords.push(inspectHapNativeDependencies(readelfToolPath, abi, entryName, errors));
  }
}

function hasAnyMihomoPrebuilt() {
  return configuredAbis.some((abi) => fs.existsSync(path.join(prebuiltRoot, abi, libraryName)));
}

function inspectHapNativeDependencies(readelfToolPath, abi, entryName, errors) {
  const record = {
    abi,
    entry: entryName,
    sha256: sha256HapEntry(hapPath, entryName),
    soname: [],
    needed: [],
    resolved: [],
    missing: [],
    forbidden: []
  };

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), `${scriptName}-`));
  const extractedPath = path.join(tempDir, path.basename(entryName));
  try {
    fs.writeFileSync(extractedPath, readHapEntryBuffer(hapPath, entryName));
    const dynamicOutput = readDynamicOutput(readelfToolPath, extractedPath);
    if (dynamicOutput === null) {
      errors.push(`${abi}: unable to inspect dynamic section for ${entryName} with ${readelfToolPath}`);
      return record;
    }

    record.soname = readDynamicValues(dynamicOutput, 'SONAME');
    record.needed = readDynamicValues(dynamicOutput, 'NEEDED');
    record.resolved = record.needed.map((dependency) => resolveNeededDependency(abi, entryName, dependency));
    record.missing = record.resolved.filter((dependency) => dependency.kind === 'missing');
    record.forbidden = record.resolved.filter((dependency) =>
      dependency.kind === 'path' || dependency.kind === 'forbidden'
    );

    if (entryName === `libs/${abi}/libentry.so` && record.needed.includes(libraryName)) {
      errors.push(`${abi}: libentry.so must dlopen ${libraryName}, not declare it in DT_NEEDED`);
    }

    if (record.forbidden.length > 0) {
      const pathDependencies = record.forbidden
        .filter((dependency) => dependency.kind === 'path')
        .map((dependency) => dependency.name);
      const hostDependencies = record.forbidden
        .filter((dependency) => dependency.kind === 'forbidden')
        .map((dependency) => dependency.name);
      if (pathDependencies.length > 0) {
        errors.push(`${abi}: ${entryName} NEEDED entries must be library names, not paths: ${pathDependencies.join(', ')}`);
      }
      if (hostDependencies.length > 0) {
        errors.push(`${abi}: ${entryName} has host/Linux NEEDED dependencies: ${hostDependencies.join(', ')}`);
      }
    }

    if (record.missing.length > 0) {
      errors.push(`${abi}: ${entryName} is missing non-system NEEDED dependencies in HAP same ABI: ${
        record.missing.map((dependency) => dependency.expectedEntry).join(', ')
      }`);
    }

    console.log(`${scriptName}: ${abi} ${entryName} NEEDED=${record.needed.join(', ') || '(none)'}`);
    return record;
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function resolveNeededDependency(abi, ownerEntry, dependency) {
  const expectedEntry = `libs/${abi}/${dependency}`;
  if (dependency.includes('/')) {
    return {
      name: dependency,
      kind: 'path',
      expectedEntry,
      ownerEntry
    };
  }

  if (forbiddenNeededPatterns.some((pattern) => pattern.test(dependency))) {
    return {
      name: dependency,
      kind: 'forbidden',
      expectedEntry,
      ownerEntry
    };
  }

  if (entries.has(expectedEntry)) {
    return {
      name: dependency,
      kind: 'hap-same-abi',
      entry: expectedEntry,
      sha256: sha256HapEntry(hapPath, expectedEntry),
      ownerEntry
    };
  }

  if (isOhosSystemDependency(dependency)) {
    return {
      name: dependency,
      kind: 'ohos-system',
      ownerEntry
    };
  }

  return {
    name: dependency,
    kind: 'missing',
    expectedEntry,
    ownerEntry
  };
}

function isOhosSystemDependency(dependency) {
  return systemNeededLibraries.has(dependency) || /^[A-Za-z0-9_+.-]+\.z\.so$/.test(dependency);
}

function findReadelfTool() {
  for (const candidatePath of readelfCandidatePaths) {
    if (isExecutableFile(candidatePath)) {
      return candidatePath;
    }
  }

  for (const command of ['llvm-readelf', 'readelf']) {
    const commandPath = findOnPath(command);
    if (commandPath !== null) {
      return commandPath;
    }
  }

  return null;
}

function isExecutableFile(targetPath) {
  try {
    fs.accessSync(targetPath, fs.constants.X_OK);
    return fs.statSync(targetPath).isFile();
  } catch {
    return false;
  }
}

function findOnPath(command) {
  const pathEntries = (process.env.PATH ?? '').split(path.delimiter).filter((entry) => entry.length > 0);
  for (const entry of pathEntries) {
    const commandPath = path.join(entry, command);
    if (isExecutableFile(commandPath)) {
      return commandPath;
    }
  }
  return null;
}

function readDynamicOutput(readelfToolPath, libraryPath) {
  try {
    const output = execFileSync(readelfToolPath, ['-d', libraryPath], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe']
    });
    if (hasNoDynamicSection(output) && !allowExecutableWithoutDynamicSection(libraryPath)) {
      return null;
    }
    return output;
  } catch {
    return allowExecutableWithoutDynamicSection(libraryPath) ? '' : null;
  }
}

function allowExecutableWithoutDynamicSection(libraryPath) {
  return path.basename(libraryPath) === execFallbackName;
}

function hasNoDynamicSection(output) {
  return /no dynamic section/i.test(output);
}

function readDynamicValues(dynamicOutput, tagName) {
  const values = [];
  const tagPattern = new RegExp(`\\(${tagName}\\)`);
  for (const line of dynamicOutput.split('\n')) {
    if (!tagPattern.test(line)) {
      continue;
    }
    const match = line.match(/\[([^\]]*)\]/);
    if (match !== null) {
      values.push(match[1]);
    }
  }
  return values;
}

function sha256File(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}

function readHapEntryBuffer(targetHapPath, entryName) {
  try {
    return execFileSync('unzip', ['-p', targetHapPath, entryName], {
      maxBuffer: hapEntryReadMaxBuffer
    });
  } catch (error) {
    fail([
      `${scriptName}: unable to read ${entryName} from ${path.relative(root, targetHapPath)}`,
      errorMessage(error)
    ]);
  }
}

function sha256HapEntry(targetHapPath, entryName) {
  try {
    const body = readHapEntryBuffer(targetHapPath, entryName);
    return crypto.createHash('sha256').update(body).digest('hex');
  } catch (error) {
    fail([
      `${scriptName}: unable to hash ${entryName} from ${path.relative(root, targetHapPath)}`,
      errorMessage(error)
    ]);
  }
}

function writeEvidenceIfRequested(status, currentErrors) {
  if (args.evidenceDir === undefined) {
    return;
  }

  const evidenceDir = path.resolve(root, args.evidenceDir);
  fs.mkdirSync(evidenceDir, { recursive: true });
  writeText(path.join(evidenceDir, 'hap-entries.txt'), `${Array.from(entries).join('\n')}\n`);
  writeJson(path.join(evidenceDir, 'module.json'), moduleJson);
  writeJson(path.join(evidenceDir, 'hashes.json'), hashes);
  writeJson(path.join(evidenceDir, 'dependencies.json'), dependencies);
  writeJson(path.join(evidenceDir, 'summary.json'), {
    script: scriptName,
    status,
    generatedAt: new Date().toISOString(),
    hap: {
      path: path.relative(root, hapPath),
      size: fs.statSync(hapPath).size,
      mtime: fs.statSync(hapPath).mtime.toISOString(),
      sha256: sha256File(hapPath)
    },
    configuredAbis,
    requiredAbis,
    nativeLibraries,
    dependencyClosure: {
      readelf: readelfTool,
      libraries: dependencies
    },
    module: {
      bundleName: moduleJson?.app?.bundleName,
      mainElement: moduleJson?.module?.mainElement,
      abilities: Array.isArray(moduleJson?.module?.abilities)
        ? moduleJson.module.abilities.map((ability) => ability?.name).filter(Boolean)
        : [],
      extensionAbilities: Array.isArray(moduleJson?.module?.extensionAbilities)
        ? moduleJson.module.extensionAbilities.map((extension) => ({
          name: extension?.name,
          type: extension?.type
        }))
        : [],
      requestPermissions: Array.isArray(moduleJson?.module?.requestPermissions)
        ? moduleJson.module.requestPermissions.map((permission) => permission?.name).filter(Boolean)
        : []
    },
    warnings,
    errors: currentErrors
  });
  console.log(`${scriptName}: wrote evidence to ${path.relative(root, evidenceDir)}`);
}

function writeJson(filePath, value) {
  writeText(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function writeText(filePath, value) {
  fs.writeFileSync(filePath, value, 'utf8');
}

function printHelp() {
  console.log(`
Usage:
  node tests/verify-hap-contents.mjs [hap] [--require-abi <abi[,abi...]>] [--evidence-dir <dir>]

Options:
  --hap <path>          Signed HAP path. Defaults to entry/build/default/outputs/default/entry-default-signed.hap.
  --require-abi <abi>   Fail if the named configured ABI lacks libmihomo_ohos.so in source/HAP.
  --evidence-dir <dir>  Write summary.json, hap-entries.txt, module.json, hashes.json, and dependencies.json.

When ${execFallbackName} is present beside ${libraryName}, it must be packaged as libs/<abi>/${execFallbackName}.
${libraryName} may be packaged as a sidecar, but libentry.so must not declare it in DT_NEEDED.

Environment:
  OHOS_LLVM_READELF     Override llvm-readelf path for native DT_NEEDED closure checks.
`);
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

function fail(messages) {
  console.error(messages.join('\n'));
  process.exit(1);
}
