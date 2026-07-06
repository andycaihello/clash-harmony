import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const scriptName = 'verify-mihomo-prebuilt-abi';
const libraryName = 'libmihomo_ohos.so';
const entryBuildProfilePath = path.join(root, 'entry/build-profile.json5');
const prebuiltRoot = process.env.MIHOMO_PREBUILT_ROOT === undefined
  ? path.join(root, 'entry/src/main/cpp/prebuilt')
  : path.resolve(root, process.env.MIHOMO_PREBUILT_ROOT);
const requiredSymbols = [
  'MihomoStart',
  'MihomoStartCore',
  'MihomoStop',
  'MihomoVersion',
  'MihomoLastError',
  'MihomoAdapterInfo'
];
const forbiddenNeededPatterns = [
  /^libc\.so\.6$/,
  /^libstdc\+\+\.so\.6$/,
  /^libgcc_s\.so\.1$/,
  /^ld-linux/,
  /^libpthread\.so\.0$/,
  /^libdl\.so\.2$/
];
const abiMachines = new Map([
  ['arm64-v8a', { machine: 183, label: 'EM_AARCH64' }],
  ['x86_64', { machine: 62, label: 'EM_X86_64' }]
]);
const args = parseArgs(process.argv.slice(2));
const nmCandidatePaths = [
  process.env.OHOS_LLVM_NM,
  '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/llvm/bin/llvm-nm',
  '/Applications/DevEco-Studio.app/Contents/sdk/default/hms/native/BiSheng/bin/llvm-nm'
].filter((candidate) => candidate !== undefined && candidate.length > 0);
const readelfCandidatePaths = [
  process.env.OHOS_LLVM_READELF,
  '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/llvm/bin/llvm-readelf',
  '/Applications/DevEco-Studio.app/Contents/sdk/default/hms/native/BiSheng/bin/llvm-readelf'
].filter((candidate) => candidate !== undefined && candidate.length > 0);

const configuredAbis = readConfiguredAbis();
const requiredAbis = readRequiredAbis(configuredAbis);
const prebuiltAbis = configuredAbis.filter((abi) =>
  fs.existsSync(path.join(prebuiltRoot, abi, libraryName))
);

if (prebuiltAbis.length === 0 && requiredAbis.length === 0) {
  console.log(`${scriptName}: mihomo prebuilt ABI check skipped; no ${libraryName} found for ${configuredAbis.join(', ')}`);
  process.exit(0);
}

const nmTool = findNmTool();
const readelfTool = findReadelfTool();
const errors = [];
const warnings = [];

if (nmTool === null) {
  errors.push(`${scriptName}: no llvm-nm or nm tool found; set OHOS_LLVM_NM or install DevEco Studio native tools`);
}
if (readelfTool === null) {
  errors.push(`${scriptName}: no llvm-readelf or readelf tool found; set OHOS_LLVM_READELF or install DevEco Studio native tools`);
}

for (const abi of configuredAbis) {
  const prebuiltPath = path.join(prebuiltRoot, abi, libraryName);
  if (!fs.existsSync(prebuiltPath)) {
    if (requiredAbis.includes(abi)) {
      errors.push(`${abi}: required prebuilt ${libraryName} is missing`);
    } else {
      warnings.push(`No prebuilt ${libraryName} for configured ABI ${abi}; that ABI will remain on adapter stub.`);
    }
    continue;
  }

  errors.push(...validateElfHeader(prebuiltPath, abi));

  if (readelfTool !== null) {
    const dynamicOutput = readDynamicOutput(readelfTool, prebuiltPath);
    if (dynamicOutput === null) {
      errors.push(`${abi}: unable to inspect dynamic section in ${path.relative(root, prebuiltPath)} with ${readelfTool}`);
    } else {
      errors.push(...validateDynamicSection(dynamicOutput, prebuiltPath, abi));
    }
  }

  if (nmTool === null) {
    continue;
  }

  const symbolOutput = readNmOutput(nmTool, prebuiltPath);
  if (symbolOutput === null) {
    errors.push(`${abi}: unable to inspect exported symbols in ${path.relative(root, prebuiltPath)} with ${nmTool}`);
    continue;
  }

  const exportedSymbols = new Set(readExportedSymbols(symbolOutput));
  const missingSymbols = requiredSymbols.filter((symbol) => !exportedSymbols.has(symbol));
  if (missingSymbols.length > 0) {
    errors.push(`${abi}: missing symbol ${missingSymbols.join(', ')}`);
  }
}

for (const warning of warnings) {
  console.warn(`warning: ${warning}`);
}

if (errors.length > 0) {
  fail([
    `${scriptName}: mihomo prebuilt ABI check failed`,
    ...errors
  ]);
}

console.log(`${scriptName}: mihomo prebuilt ABI check passed for ${prebuiltAbis.join(', ')} using ${nmTool} and ${readelfTool}`);

function parseArgs(argv) {
  const parsed = {
    requireAbis: []
  };

  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === '--help' || arg === '-h') {
      printHelp();
      process.exit(0);
    } else if (arg === '--require-abi') {
      parsed.requireAbis.push(...splitAbiList(requireValue(argv, ++index, arg)));
    } else if (arg.startsWith('--require-abi=')) {
      parsed.requireAbis.push(...splitAbiList(arg.slice('--require-abi='.length)));
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
  const stripped = stripJson5Comments(source);
  const propertyMatch = /(?:["']abiFilters["']|abiFilters)\s*:\s*\[/.exec(stripped);
  if (propertyMatch === null) {
    fail([`No abiFilters found in ${path.relative(root, entryBuildProfilePath)}`]);
  }

  const arrayStart = propertyMatch.index + propertyMatch[0].lastIndexOf('[');
  const abis = readJson5StringArray(stripped, arrayStart);
  if (abis.length === 0) {
    fail([`abiFilters is empty in ${path.relative(root, entryBuildProfilePath)}`]);
  }
  return abis;
}

function validateElfHeader(prebuiltPath, abi) {
  const errorsForFile = [];
  const relativePath = path.relative(root, prebuiltPath);
  let header;

  try {
    const file = fs.openSync(prebuiltPath, 'r');
    header = Buffer.alloc(64);
    const bytesRead = fs.readSync(file, header, 0, header.length, 0);
    fs.closeSync(file);
    if (bytesRead < 20) {
      return [`${abi}: ${relativePath} is too small to be an ELF shared object`];
    }
  } catch (error) {
    return [`${abi}: unable to read ${relativePath}: ${error instanceof Error ? error.message : String(error)}`];
  }

  if (header[0] !== 0x7f || header[1] !== 0x45 || header[2] !== 0x4c || header[3] !== 0x46) {
    errorsForFile.push(`${abi}: ${relativePath} is not an ELF file`);
    return errorsForFile;
  }

  if (header[4] !== 2) {
    errorsForFile.push(`${abi}: ${relativePath} must be ELF64, got class ${header[4]}`);
  }

  if (header[5] !== 1) {
    errorsForFile.push(`${abi}: ${relativePath} must be little-endian ELF, got data encoding ${header[5]}`);
  }

  const elfType = header.readUInt16LE(16);
  if (elfType !== 3) {
    errorsForFile.push(`${abi}: ${relativePath} must be ET_DYN shared object, got ELF type ${elfType}`);
  }

  const expected = abiMachines.get(abi);
  if (expected === undefined) {
    errorsForFile.push(`${abi}: no ELF machine mapping is defined for this ABI`);
    return errorsForFile;
  }

  const machine = header.readUInt16LE(18);
  if (machine !== expected.machine) {
    errorsForFile.push(`${abi}: ${relativePath} must be ${expected.label}, got e_machine ${machine}`);
  }

  return errorsForFile;
}

function stripJson5Comments(source) {
  let result = '';
  let index = 0;
  let quote = null;

  while (index < source.length) {
    const current = source[index];
    const next = source[index + 1];

    if (quote !== null) {
      result += current;
      if (current === '\\') {
        index += 1;
        if (index < source.length) {
          result += source[index];
        }
      } else if (current === quote) {
        quote = null;
      }
      index += 1;
      continue;
    }

    if (current === '"' || current === "'") {
      quote = current;
      result += current;
      index += 1;
      continue;
    }

    if (current === '/' && next === '/') {
      index += 2;
      while (index < source.length && source[index] !== '\n') {
        index += 1;
      }
      result += '\n';
      if (source[index] === '\n') {
        index += 1;
      }
      continue;
    }

    if (current === '/' && next === '*') {
      index += 2;
      while (index < source.length && !(source[index] === '*' && source[index + 1] === '/')) {
        result += source[index] === '\n' ? '\n' : ' ';
        index += 1;
      }
      index += 2;
      continue;
    }

    result += current;
    index += 1;
  }

  return result;
}

function readJson5StringArray(source, arrayStart) {
  const values = [];
  let index = arrayStart + 1;

  while (index < source.length) {
    index = skipWhitespaceAndCommas(source, index);
    if (source[index] === ']') {
      return values;
    }

    const quote = source[index];
    if (quote !== '"' && quote !== "'") {
      fail([`abiFilters must contain string values in ${path.relative(root, entryBuildProfilePath)}`]);
    }

    const parsed = readQuotedString(source, index);
    values.push(parsed.value);
    index = parsed.nextIndex;
  }

  fail([`Unterminated abiFilters array in ${path.relative(root, entryBuildProfilePath)}`]);
}

function skipWhitespaceAndCommas(source, index) {
  while (index < source.length && (/\s/.test(source[index]) || source[index] === ',')) {
    index += 1;
  }
  return index;
}

function readQuotedString(source, start) {
  const quote = source[start];
  let value = '';
  let index = start + 1;

  while (index < source.length) {
    const current = source[index];
    if (current === quote) {
      return {
        value,
        nextIndex: index + 1
      };
    }

    if (current === '\\') {
      index += 1;
      if (index >= source.length) {
        break;
      }
      value += source[index];
      index += 1;
      continue;
    }

    value += current;
    index += 1;
  }

  fail([`Unterminated abiFilters string in ${path.relative(root, entryBuildProfilePath)}`]);
}

function findNmTool() {
  for (const candidatePath of nmCandidatePaths) {
    if (isExecutableFile(candidatePath)) {
      return candidatePath;
    }
  }

  for (const command of ['llvm-nm', 'nm']) {
    const commandPath = findOnPath(command);
    if (commandPath !== null) {
      return commandPath;
    }
  }

  return null;
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

function readNmOutput(nmToolPath, prebuiltPath) {
  try {
    return execFileSync(nmToolPath, [
      '--defined-only',
      '--extern-only',
      '--dynamic',
      '--format=just-symbols',
      prebuiltPath
    ], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe']
    });
  } catch {
    return null;
  }
}

function readDynamicOutput(readelfToolPath, prebuiltPath) {
  try {
    return execFileSync(readelfToolPath, [
      '-d',
      prebuiltPath
    ], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe']
    });
  } catch {
    return null;
  }
}

function validateDynamicSection(dynamicOutput, prebuiltPath, abi) {
  const relativePath = path.relative(root, prebuiltPath);
  const errorsForFile = [];
  const sonames = readDynamicValues(dynamicOutput, 'SONAME');
  const needed = readDynamicValues(dynamicOutput, 'NEEDED');

  if (sonames.length === 0) {
    errorsForFile.push(`${abi}: ${relativePath} must declare SONAME ${libraryName}`);
  } else if (!sonames.includes(libraryName)) {
    errorsForFile.push(`${abi}: ${relativePath} SONAME must be ${libraryName}, got ${sonames.join(', ')}`);
  }

  const pathNeeded = needed.filter((dependency) => dependency.includes('/'));
  if (pathNeeded.length > 0) {
    errorsForFile.push(`${abi}: ${relativePath} NEEDED entries must be library names, not paths: ${pathNeeded.join(', ')}`);
  }

  const forbiddenNeeded = needed.filter((dependency) =>
    forbiddenNeededPatterns.some((pattern) => pattern.test(dependency))
  );
  if (forbiddenNeeded.length > 0) {
    errorsForFile.push(`${abi}: ${relativePath} has host/Linux NEEDED dependencies: ${forbiddenNeeded.join(', ')}`);
  }

  console.log(`${scriptName}: ${abi} dynamic SONAME=${sonames.join(', ') || '(none)'} NEEDED=${needed.join(', ') || '(none)'}`);
  return errorsForFile;
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

function readExportedSymbols(symbolOutput) {
  return symbolOutput
    .split('\n')
    .map((line) => line.trim().replace(/@.*/, ''))
    .filter((line) => line.length > 0);
}

function printHelp() {
  console.log(`
Usage:
  node tests/verify-mihomo-prebuilt-abi.mjs [--require-abi <abi[,abi...]>]

Options:
  --require-abi <abi>   Fail if the named configured ABI has no ${libraryName}. Can be repeated or comma-separated.

Environment:
  MIHOMO_PREBUILT_ROOT  Override prebuilt root.
  OHOS_LLVM_NM          Override llvm-nm path.
  OHOS_LLVM_READELF     Override llvm-readelf path.
`);
}

function fail(messages) {
  console.error(messages.join('\n'));
  process.exit(1);
}
