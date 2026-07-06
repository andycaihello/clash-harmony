#!/usr/bin/env node

import { execFileSync, spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const scriptName = 'verify-device-mihomo';
const libraryName = 'libmihomo_ohos.so';
const defaultHapPath = path.join(root, 'entry/build/default/outputs/default/entry-default-signed.hap');
const prebuiltRoot = path.join(root, 'entry/src/main/cpp/prebuilt');
const entryBuildProfilePath = path.join(root, 'entry/build-profile.json5');
const appConfigPath = path.join(root, 'AppScope/app.json5');
const defaultHdcCandidates = [
  process.env.HDC,
  '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc',
  '/Applications/DevEco-Studio.app/Contents/sdk/default/hms/toolchains/hdc'
].filter((candidate) => candidate !== undefined && candidate.length > 0);

const args = parseArgs(process.argv.slice(2));

if (args.help) {
  printHelp();
  process.exit(0);
}

const hapPath = path.resolve(root, args.hap ?? defaultHapPath);
const bundleName = args.bundle ?? readBundleName();
const observeMs = Number(args.observeMs ?? '45000');

if (!Number.isFinite(observeMs) || observeMs < 0) {
  fail([`${scriptName}: --observe-ms must be a non-negative number`]);
}

const requestedMinCycles = Number(args.minCycles ?? args.cycles ?? '0');
if (!Number.isInteger(requestedMinCycles) || requestedMinCycles < 0) {
  fail([`${scriptName}: --min-cycles/--cycles must be a non-negative integer`]);
}
const requiresStop = args.requireStop || requestedMinCycles > 0;
if (observeMs === 0 && requiresStop) {
  fail([`${scriptName}: --require-stop or --min-cycles requires --observe-ms greater than 0`]);
}

assertFile(hapPath, 'HAP');
const configuredAbis = readConfiguredAbis();
const hapEntries = new Set(readHapEntries(hapPath));
const prebuiltAbis = configuredAbis.filter((abi) => fs.existsSync(path.join(prebuiltRoot, abi, libraryName)));
const packagedAbis = configuredAbis.filter((abi) => hapEntries.has(`libs/${abi}/${libraryName}`));
const evidence = {
  script: scriptName,
  status: 'running',
  generatedAt: new Date().toISOString(),
  hdc: null,
  hdcTargets: [],
  bundleName,
  options: {
    allowStub: args.allowStub,
    allowNoDevice: args.allowNoDevice,
    noInstall: args.noInstall,
    noLaunch: args.noLaunch,
    observeMs,
    controllerPort: args.controllerPort ?? '19090',
    requireStop: requiresStop,
    minCycles: requestedMinCycles
  },
  hap: {
    path: path.relative(root, hapPath),
    size: fs.statSync(hapPath).size,
    mtime: fs.statSync(hapPath).mtime.toISOString(),
    sha256: sha256File(hapPath)
  },
  configuredAbis,
  prebuiltAbis,
  packagedAbis,
  libraries: collectLibraryEvidence(),
  device: null,
  commands: [],
  controller: null,
  parsedHilog: {},
  errors: []
};

if (prebuiltAbis.length === 0 && !args.allowStub) {
  fail([
    `${scriptName}: no real ${libraryName} found under ${path.relative(root, prebuiltRoot)}`,
    'Device mihomo verification requires a real prebuilt by default.',
    'Use --allow-stub only for local dry runs that are not proving real mihomo integration.'
  ]);
}

const missingPackagedAbis = prebuiltAbis.filter((abi) => !packagedAbis.includes(abi));
if (missingPackagedAbis.length > 0) {
  fail([
    `${scriptName}: HAP is missing ${libraryName} for ${missingPackagedAbis.join(', ')}`,
    `Run hvigor assembleHap and node tests/verify-mihomo-prebuilt-packaging.mjs before device verification.`
  ]);
}

console.log(`${scriptName}: HAP ${path.relative(root, hapPath)} ready for ${bundleName}`);
if (prebuiltAbis.length > 0) {
  console.log(`${scriptName}: packaged mihomo prebuilt ABI(s): ${packagedAbis.join(', ')}`);
} else {
  console.warn(`${scriptName}: running with --allow-stub; this does not prove real mihomo adapter integration`);
}

const hdc = findExecutable(defaultHdcCandidates);
evidence.hdc = hdc;
if (hdc === null) {
  handleNoDevice(`hdc not found; set HDC=/path/to/hdc or install DevEco Studio toolchains`);
}

const targets = listTargets(hdc);
evidence.hdcTargets = targets;
if (targets.length === 0 && args.serial === undefined) {
  handleNoDevice('no hdc target found');
}

const serial = args.serial ?? selectTarget(targets);
const hdcTargetPrefix = serial === undefined ? [] : ['-t', serial];
const deviceInfo = readDeviceInfo(hdc, hdcTargetPrefix);
evidence.device = {
  serial: serial ?? '',
  abiList: deviceInfo.abiList,
  softwareVersion: deviceInfo.softwareVersion
};
printDeviceInfo(deviceInfo);
if (!args.allowStub && deviceInfo.abiList.length > 0) {
  const deviceAbis = deviceInfo.abiList.split(',').map((abi) => abi.trim()).filter((abi) => abi.length > 0);
  const compatibleAbis = prebuiltAbis.filter((abi) => deviceAbis.includes(abi));
  if (compatibleAbis.length === 0) {
    fail([
      `${scriptName}: device ABI list does not match packaged mihomo prebuilt ABI(s)`,
      `device ABI list: ${deviceInfo.abiList}`,
      `packaged prebuilt ABI(s): ${prebuiltAbis.join(', ')}`
    ]);
  }
}

if (!args.noInstall) {
  runHdc(hdc, hdcTargetPrefix, ['install', '-r', hapPath]);
}

if (!args.noLaunch) {
  runHdc(hdc, hdcTargetPrefix, ['shell', 'aa', 'start', '-b', bundleName, '-a', 'EntryAbility']);
}

if (observeMs === 0) {
  writeEvidence('checklist', []);
  printManualChecklist({ bundleName, allowStub: args.allowStub });
  process.exit(0);
}

console.log(`${scriptName}: watching hilog for ${observeMs} ms; tap Connect in the app and approve VPN permission if prompted`);
const hilog = captureHilog(hdc, hdcTargetPrefix, observeMs);
const relevantLines = filterRelevantHilog(hilog);
evidence.parsedHilog = parseHilogEvidence(relevantLines);
if (relevantLines.length > 0) {
  console.log(`${scriptName}: relevant hilog lines`);
  console.log(relevantLines.join('\n'));
}

const errors = [];
assertLog(relevantLines, /VPN TUN created, fd=\d+/, 'VPN TUN fd creation', errors);
assertLog(relevantLines, /Native core bridge started: mode=([^ ]+) adapter=([^ ]+) adapterVersion=([^ ]*) nativeFd=\d+/, 'native bridge start snapshot', errors);
if (!args.allowStub) {
  assertLog(relevantLines, /Native core bridge started: mode=mihomo-adapter adapter=real adapterVersion=\S+ nativeFd=\d+/, 'real adapter loaded with adapterVersion', errors);
  assertRealAdapterEvidence(evidence.parsedHilog, errors);
}
assertLog(relevantLines, /Controller ready: controllerVersion=\S+ adapter=([^ ]+) adapterVersion=([^ ]*) nativeFd=\d+/, 'controller /version readiness', errors);
assertNoFailureLines(evidence.parsedHilog, errors);
if (requestedMinCycles > 0) {
  assertCycleEvidence(evidence.parsedHilog, requestedMinCycles, errors);
}
if (requiresStop) {
  assertStopEvidence(evidence.parsedHilog, errors);
}
if (!args.allowStub) {
  evidence.controller = requiresStop
    ? { afterStop: probeControllerVersion(hdc, hdcTargetPrefix, errors, false) }
    : { running: probeControllerVersion(hdc, hdcTargetPrefix, errors, true) };
}

if (errors.length > 0) {
  writeEvidence('failed', errors, { hilog, relevantLines });
  fail([
    `${scriptName}: device mihomo verification failed`,
    ...errors,
    'Open the Diagnostics tab and confirm Adapter, TUN FD, and Controller Ready state before retrying.'
  ]);
}

writeEvidence('passed', [], { hilog, relevantLines });
console.log(`${scriptName}: device mihomo verification passed`);

function parseArgs(argv) {
  const parsed = {
    allowNoDevice: false,
    allowStub: false,
    noInstall: false,
    noLaunch: false,
    requireStop: false,
    help: false
  };

  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === '--help' || arg === '-h') {
      parsed.help = true;
    } else if (arg === '--allow-no-device') {
      parsed.allowNoDevice = true;
    } else if (arg === '--allow-stub') {
      parsed.allowStub = true;
    } else if (arg === '--no-install') {
      parsed.noInstall = true;
    } else if (arg === '--no-launch') {
      parsed.noLaunch = true;
    } else if (arg.startsWith('--hap=')) {
      parsed.hap = arg.slice('--hap='.length);
    } else if (arg === '--hap') {
      parsed.hap = requireValue(argv, ++index, arg);
    } else if (arg.startsWith('--serial=')) {
      parsed.serial = arg.slice('--serial='.length);
    } else if (arg === '--serial') {
      parsed.serial = requireValue(argv, ++index, arg);
    } else if (arg.startsWith('--bundle=')) {
      parsed.bundle = arg.slice('--bundle='.length);
    } else if (arg === '--bundle') {
      parsed.bundle = requireValue(argv, ++index, arg);
    } else if (arg.startsWith('--observe-ms=')) {
      parsed.observeMs = arg.slice('--observe-ms='.length);
    } else if (arg === '--observe-ms') {
      parsed.observeMs = requireValue(argv, ++index, arg);
    } else if (arg === '--evidence-dir') {
      parsed.evidenceDir = requireValue(argv, ++index, arg);
    } else if (arg.startsWith('--evidence-dir=')) {
      parsed.evidenceDir = arg.slice('--evidence-dir='.length);
    } else if (arg === '--controller-port') {
      parsed.controllerPort = requireValue(argv, ++index, arg);
    } else if (arg.startsWith('--controller-port=')) {
      parsed.controllerPort = arg.slice('--controller-port='.length);
    } else if (arg === '--require-stop') {
      parsed.requireStop = true;
    } else if (arg === '--min-cycles') {
      parsed.minCycles = requireValue(argv, ++index, arg);
    } else if (arg.startsWith('--min-cycles=')) {
      parsed.minCycles = arg.slice('--min-cycles='.length);
    } else if (arg === '--cycles') {
      parsed.cycles = requireValue(argv, ++index, arg);
    } else if (arg.startsWith('--cycles=')) {
      parsed.cycles = arg.slice('--cycles='.length);
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

function readBundleName() {
  const source = fs.readFileSync(appConfigPath, 'utf8');
  const match = source.match(/"bundleName"\s*:\s*"([^"]+)"/);
  if (match === null) {
    fail([`${scriptName}: bundleName not found in ${path.relative(root, appConfigPath)}`]);
  }
  return match[1];
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

function collectLibraryEvidence() {
  return configuredAbis.map((abi) => {
    const prebuiltPath = path.join(prebuiltRoot, abi, libraryName);
    const intermediatePath = path.join(root, 'entry/build/default/intermediates/libs/default', abi, libraryName);
    const strippedPath = path.join(root, 'entry/build/default/intermediates/stripped_native_libs/default', abi, libraryName);
    const hapEntry = `libs/${abi}/${libraryName}`;
    return {
      abi,
      prebuilt: fileEvidence(prebuiltPath),
      intermediate: fileEvidence(intermediatePath),
      stripped: fileEvidence(strippedPath),
      hapEntry: hapEntries.has(hapEntry)
        ? {
          entry: hapEntry,
          sha256: sha256HapEntry(hapPath, hapEntry)
        }
        : null
    };
  });
}

function fileEvidence(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  const stat = fs.statSync(filePath);
  return {
    path: path.relative(root, filePath),
    size: stat.size,
    mtime: stat.mtime.toISOString(),
    sha256: sha256File(filePath)
  };
}

function sha256File(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}

function sha256HapEntry(targetHapPath, entryName) {
  const body = execFileSync('unzip', ['-p', targetHapPath, entryName]);
  return crypto.createHash('sha256').update(body).digest('hex');
}

function findExecutable(candidates) {
  for (const candidate of candidates) {
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      if (fs.statSync(candidate).isFile()) {
        return candidate;
      }
    } catch (_) {
      // Try the next candidate.
    }
  }
  return null;
}

function listTargets(hdc) {
  try {
    const output = execFileSync(hdc, ['list', 'targets'], {
      encoding: 'utf8',
      timeout: 5000,
      stdio: ['ignore', 'pipe', 'pipe']
    });
    return output
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line.length > 0 && !line.includes('[Empty]') && !line.includes('Connect server failed'));
  } catch (_) {
    return [];
  }
}

function selectTarget(targets) {
  if (targets.length === 0) {
    return undefined;
  }
  if (targets.length > 1) {
    fail([
      `${scriptName}: multiple hdc targets found; pass --serial`,
      ...targets.map((target) => `- ${target}`)
    ]);
  }
  return targets[0].split(/\s+/)[0];
}

function runHdc(hdc, prefix, commandArgs) {
  const args = [...prefix, ...commandArgs];
  console.log(`${scriptName}: running ${formatCommand(hdc, args)}`);
  evidence.commands.push(formatCommand(hdc, args));
  try {
    execFileSync(hdc, args, {
      cwd: root,
      stdio: 'inherit'
    });
  } catch (error) {
    fail([`${scriptName}: hdc command failed: ${formatCommand(hdc, args)}`, errorMessage(error)]);
  }
}

function readDeviceInfo(hdc, prefix) {
  const abiList = tryReadHdc(hdc, prefix, ['shell', 'param', 'get', 'const.product.cpu.abilist']);
  const softwareVersion = tryReadHdc(hdc, prefix, ['shell', 'param', 'get', 'const.product.software.version']);
  return { abiList, softwareVersion };
}

function printDeviceInfo(deviceInfo) {
  if (deviceInfo.abiList.length > 0) {
    console.log(`${scriptName}: device ABI list: ${deviceInfo.abiList}`);
  }
  if (deviceInfo.softwareVersion.length > 0) {
    console.log(`${scriptName}: device software version: ${deviceInfo.softwareVersion}`);
  }
}

function tryReadHdc(hdc, prefix, commandArgs) {
  try {
    return execFileSync(hdc, [...prefix, ...commandArgs], {
      cwd: root,
      encoding: 'utf8',
      timeout: 5000,
      stdio: ['ignore', 'pipe', 'pipe']
    }).trim();
  } catch (_) {
    return '';
  }
}

function captureHilog(hdc, prefix, timeoutMs) {
  const args = [...prefix, 'hilog'];
  const result = spawnSync(hdc, args, {
    cwd: root,
    encoding: 'utf8',
    timeout: timeoutMs,
    maxBuffer: 20 * 1024 * 1024
  });
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
  if (result.error !== undefined && result.error.code !== 'ETIMEDOUT') {
    fail([`${scriptName}: unable to capture hilog`, errorMessage(result.error)]);
  }
  return output;
}

function probeControllerVersion(hdc, prefix, errors, expectAvailable) {
  const localPort = args.controllerPort ?? '19090';
  const fportArgs = [...prefix, 'fport', `tcp:${localPort}`, 'tcp:9090'];
  const controllerUrl = `http://127.0.0.1:${localPort}/version`;
  try {
    evidence.commands.push(formatCommand(hdc, fportArgs));
    execFileSync(hdc, fportArgs, {
      cwd: root,
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 5000
    });
    const raw = execFileSync('curl', ['-fsS', '--max-time', '2', controllerUrl], {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe']
    }).trim();
    if (!expectAvailable) {
      errors.push('Controller /version is still reachable after stop');
      return {
        url: controllerUrl,
        raw,
        parsed: tryParseJson(raw),
        expectedAvailable: expectAvailable,
        passed: false
      };
    }
    let parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch (_) {
      errors.push(`Controller /version response is not JSON: ${raw}`);
    }
    if (parsed !== null && typeof parsed.version !== 'string') {
      errors.push('Controller /version response does not contain string version');
    }
    const hilogControllerVersion = evidence.parsedHilog.controllerReady?.controllerVersion ?? '';
    if (parsed !== null && typeof parsed.version === 'string' &&
        hilogControllerVersion.length > 0 && parsed.version !== hilogControllerVersion) {
      errors.push(`Controller /version mismatch: raw ${parsed.version} != hilog ${hilogControllerVersion}`);
    }
    return {
      url: controllerUrl,
      raw,
      parsed,
      expectedAvailable: expectAvailable,
      matchesHilog: parsed !== null && parsed.version === hilogControllerVersion,
      passed: parsed !== null && parsed.version === hilogControllerVersion
    };
  } catch (error) {
    if (!expectAvailable) {
      return {
        url: controllerUrl,
        raw: '',
        parsed: null,
        expectedAvailable: expectAvailable,
        passed: true,
        error: errorMessage(error)
      };
    }
    errors.push(`Unable to probe controller /version through hdc fport: ${errorMessage(error)}`);
    return {
      url: controllerUrl,
      raw: '',
      parsed: null,
      expectedAvailable: expectAvailable,
      matchesHilog: false,
      passed: false,
      error: errorMessage(error)
    };
  }
}

function tryParseJson(source) {
  try {
    return JSON.parse(source);
  } catch (_) {
    return null;
  }
}

function filterRelevantHilog(source) {
  return source
    .split('\n')
    .filter((line) =>
      line.includes('ClashVpnExtension') ||
      line.includes('ClashHarmonyIndex') ||
      line.includes('Native core bridge') ||
      line.includes('Controller ready') ||
      line.includes('VPN TUN created')
    );
}

function parseHilogEvidence(lines) {
  const parsed = {
    lifecycle: {
      tun: [],
      nativeStart: [],
      controllerReady: [],
      nativeStop: [],
      appStop: []
    },
    lifecycleEvents: [],
    cycles: [],
    lifecycleStats: {
      tunCount: 0,
      nativeStartCount: 0,
      controllerReadyCount: 0,
      nativeStopCount: 0,
      appStopCount: 0,
      failureCount: 0
    },
    failureLines: []
  };
  let order = 0;
  for (const line of lines) {
    if (/Native core bridge failed|Failed to create VPN TUN|Destroy VPN connection failed|Controller readiness failed/.test(line)) {
      parsed.failureLines.push(line);
    }

    const tunMatch = line.match(/VPN TUN created, fd=(\d+)/);
    if (tunMatch !== null) {
      const event = {
        order,
        fd: Number(tunMatch[1]),
        line
      };
      parsed.tun = event;
      parsed.lifecycle.tun.push(event);
      parsed.lifecycleEvents.push({ type: 'tun', ...event });
    }

    const startMatch = line.match(/Native core bridge started: mode=([^ ]+) adapter=([^ ]+) adapterVersion=([^ ]*) nativeFd=(\d+)/);
    if (startMatch !== null) {
      const event = {
        order,
        coreMode: startMatch[1],
        adapterMode: startMatch[2],
        adapterVersion: startMatch[3],
        nativeFd: Number(startMatch[4]),
        line
      };
      parsed.nativeStart = event;
      parsed.lifecycle.nativeStart.push(event);
      parsed.lifecycleEvents.push({ type: 'nativeStart', ...event });
    }

    const controllerReadyMatch = line.match(/Controller ready: controllerVersion=([^ ]+) adapter=([^ ]+) adapterVersion=([^ ]*) nativeFd=(\d+)/);
    if (controllerReadyMatch !== null) {
      const event = {
        order,
        controllerVersion: controllerReadyMatch[1],
        adapterMode: controllerReadyMatch[2],
        adapterVersion: controllerReadyMatch[3],
        nativeFd: Number(controllerReadyMatch[4]),
        line
      };
      parsed.controllerReady = event;
      parsed.lifecycle.controllerReady.push(event);
      parsed.lifecycleEvents.push({ type: 'controllerReady', ...event });
    }

    const stopMatch = line.match(/Native core bridge stopped: mode=([^ ]+) nativeFd=(-?\d+) controllerReady=([^ ]+)(?: stopCount=(\d+))?/);
    if (stopMatch !== null) {
      const event = {
        order,
        coreMode: stopMatch[1],
        nativeFd: Number(stopMatch[2]),
        controllerReady: stopMatch[3],
        stopCount: stopMatch[4] === undefined ? null : Number(stopMatch[4]),
        line
      };
      parsed.nativeStop = event;
      parsed.lifecycle.nativeStop.push(event);
      parsed.lifecycleEvents.push({ type: 'nativeStop', ...event });
    }

    const appStopMatch = line.match(/VPN stop requested: stopped=([^ ]+) mode=([^ ]+) nativeFd=(-?\d+) controllerReady=([^ ]+)/);
    if (appStopMatch !== null) {
      const event = {
        order,
        stopped: appStopMatch[1],
        coreMode: appStopMatch[2],
        nativeFd: Number(appStopMatch[3]),
        controllerReady: appStopMatch[4],
        line
      };
      parsed.appStop = event;
      parsed.lifecycle.appStop.push(event);
      parsed.lifecycleEvents.push({ type: 'appStop', ...event });
    }
    order++;
  }
  parsed.cycles = buildLifecycleCycles(parsed.lifecycleEvents);
  parsed.lifecycleStats = {
    tunCount: parsed.lifecycle.tun.length,
    nativeStartCount: parsed.lifecycle.nativeStart.length,
    controllerReadyCount: parsed.lifecycle.controllerReady.length,
    nativeStopCount: parsed.lifecycle.nativeStop.length,
    appStopCount: parsed.lifecycle.appStop.length,
    failureCount: parsed.failureLines.length,
    completedCycles: parsed.cycles.filter((cycle) =>
      cycle.tun !== undefined &&
      cycle.nativeStart !== undefined &&
      cycle.controllerReady !== undefined &&
      cycle.nativeStop !== undefined
    ).length
  };
  const finalStop = parsed.lifecycle.nativeStop[parsed.lifecycle.nativeStop.length - 1];
  parsed.leakCheck = {
    completedCycles: parsed.lifecycleStats.completedCycles,
    unclosedStartCount: Math.max(0, parsed.lifecycle.nativeStart.length - parsed.lifecycle.nativeStop.length),
    startStopBalanced: parsed.lifecycle.nativeStart.length === parsed.lifecycle.nativeStop.length,
    finalStopped: finalStop !== undefined && finalStop.nativeFd === -1 && finalStop.controllerReady === 'false',
    finalState: finalStop ?? null
  };
  return parsed;
}

function buildLifecycleCycles(events) {
  const cycles = [];
  let current = null;

  for (const event of events) {
    if (event.type === 'tun') {
      if (current !== null) {
        cycles.push(current);
      }
      current = { index: cycles.length + 1, tun: event };
      continue;
    }

    if (current === null) {
      current = { index: cycles.length + 1 };
    }

    if (event.type === 'nativeStart') {
      current.nativeStart = event;
    } else if (event.type === 'controllerReady') {
      current.controllerReady = event;
    } else if (event.type === 'appStop') {
      current.appStop = event;
    } else if (event.type === 'nativeStop') {
      current.nativeStop = event;
      cycles.push(current);
      current = null;
    }
  }

  if (current !== null) {
    cycles.push(current);
  }

  return cycles;
}

function assertLog(lines, pattern, label, errors) {
  if (!lines.some((line) => pattern.test(line))) {
    errors.push(`Missing hilog evidence: ${label}`);
  }
}

function assertCycleEvidence(parsedHilog, minCycles, errors) {
  const stats = parsedHilog.lifecycleStats ?? {};
  if ((stats.completedCycles ?? 0) < minCycles) {
    errors.push(`Expected at least ${minCycles} complete lifecycle cycle(s), got ${stats.completedCycles ?? 0}`);
  }

  const incompleteCycles = parsedHilog.cycles.filter((cycle) =>
    cycle.tun === undefined ||
    cycle.nativeStart === undefined ||
    cycle.controllerReady === undefined ||
    cycle.nativeStop === undefined
  );
  if (incompleteCycles.length > 0) {
    errors.push(`Incomplete lifecycle cycle(s): ${incompleteCycles.map((cycle) => cycle.index).join(', ')}`);
  }

  const invalidCycles = parsedHilog.cycles.filter((cycle) =>
    cycle.nativeStart !== undefined &&
    cycle.controllerReady !== undefined &&
    cycle.nativeStop !== undefined &&
    !(cycle.nativeStart.nativeFd >= 0 &&
      cycle.controllerReady.nativeFd >= 0 &&
      cycle.nativeStop.nativeFd === -1 &&
      cycle.nativeStop.controllerReady === 'false' &&
      cycle.nativeStart.order < cycle.controllerReady.order &&
      cycle.controllerReady.order < cycle.nativeStop.order)
  );
  if (invalidCycles.length > 0) {
    errors.push(`Lifecycle cycle state/order check failed for cycle(s): ${invalidCycles.map((cycle) => cycle.index).join(', ')}`);
  }
}

function assertStopEvidence(parsedHilog, errors) {
  const stopEvents = parsedHilog.lifecycle.nativeStop;
  if (stopEvents.length === 0) {
    errors.push('Missing hilog evidence: native bridge stop snapshot');
    return;
  }

  const invalidStops = stopEvents.filter((event) => event.nativeFd !== -1 || event.controllerReady !== 'false');
  if (invalidStops.length > 0) {
    errors.push(`Native stop evidence did not clear fd/controller state: ${invalidStops.map((event) =>
      `nativeFd=${event.nativeFd},controllerReady=${event.controllerReady}`).join('; ')}`);
  }

  const requiredCycles = Math.max(1, Number(args.minCycles ?? args.cycles ?? '0'));
  if (stopEvents.length < requiredCycles) {
    errors.push(`Expected at least ${requiredCycles} native stop cycle(s), got ${stopEvents.length}`);
  }
}

function assertNoFailureLines(parsedHilog, errors) {
  if (parsedHilog.failureLines.length > 0) {
    errors.push(`Failure hilog lines detected: ${parsedHilog.failureLines.join(' | ')}`);
  }
}

function assertRealAdapterEvidence(parsedHilog, errors) {
  const invalidStarts = parsedHilog.lifecycle.nativeStart.filter((event) =>
    event.adapterMode !== 'real' || event.adapterVersion.length === 0 || event.nativeFd < 0
  );
  if (invalidStarts.length > 0) {
    errors.push(`Real adapter evidence failed for native start event(s): ${invalidStarts.map((event) => event.order).join(', ')}`);
  }

  const invalidReady = parsedHilog.lifecycle.controllerReady.filter((event) =>
    event.adapterMode !== 'real' || event.adapterVersion.length === 0 || event.controllerVersion.length === 0 || event.nativeFd < 0
  );
  if (invalidReady.length > 0) {
    errors.push(`Real adapter evidence failed for controller ready event(s): ${invalidReady.map((event) => event.order).join(', ')}`);
  }
}

function handleNoDevice(message) {
  if (args.allowNoDevice) {
    console.warn(`${scriptName}: ${message}; skipping hdc phase because --allow-no-device was provided`);
    writeEvidence('skipped', [message], {
      hilog: '',
      relevantLines: []
    });
    printManualChecklist({ bundleName, allowStub: args.allowStub });
    process.exit(0);
  }
  fail([
    `${scriptName}: ${message}`,
    'Connect a HarmonyOS device, authorize debugging, or pass --allow-no-device for local dry runs.'
  ]);
}

function printManualChecklist({ bundleName, allowStub }) {
  console.log([
    `${scriptName}: manual device checklist for ${bundleName}`,
    '- Install and launch the signed HAP on a HarmonyOS device.',
    '- Import or enable a valid profile, tap Connect, and approve VPN permission.',
    '- Diagnostics must show TUN FD with native fd >= 0.',
    allowStub
      ? '- Stub dry run: Adapter may remain stub; this does not prove real mihomo integration.'
      : '- Real run: Adapter must be real, adapterVersion must be non-empty, and adapterLoadError must be empty.',
    '- Controller Ready must be ready with a non-empty controllerVersion.',
    '- Tap Disconnect and confirm native fd resets to -1 and Controller Ready becomes not ready.'
  ].join('\n'));
}

function writeEvidence(status, errors, logs = {}) {
  if (args.evidenceDir === undefined) {
    return;
  }

  const evidenceDir = path.resolve(root, args.evidenceDir);
  fs.mkdirSync(evidenceDir, { recursive: true });
  evidence.status = status;
  evidence.completedAt = new Date().toISOString();
  evidence.errors = errors;
  writeJson(path.join(evidenceDir, 'summary.json'), evidence);
  writeJson(path.join(evidenceDir, 'hashes.json'), evidence.libraries);
  if (evidence.device !== null) {
    writeJson(path.join(evidenceDir, 'device-info.json'), evidence.device);
  }
  if (evidence.controller !== null) {
    writeJson(path.join(evidenceDir, 'controller-version.json'), evidence.controller);
  }
  if (logs.hilog !== undefined) {
    writeText(path.join(evidenceDir, 'hilog.raw.log'), logs.hilog);
  }
  if (logs.relevantLines !== undefined) {
    writeText(path.join(evidenceDir, 'hilog.relevant.log'), `${logs.relevantLines.join('\n')}\n`);
  }
  writeJson(path.join(evidenceDir, 'lifecycle.json'), evidence.parsedHilog);
  writeText(path.join(evidenceDir, 'hap-entries.txt'), `${Array.from(hapEntries).join('\n')}\n`);
  console.log(`${scriptName}: wrote evidence to ${path.relative(root, evidenceDir)}`);
}

function writeJson(filePath, value) {
  writeText(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function writeText(filePath, value) {
  fs.writeFileSync(filePath, value, 'utf8');
}

function assertFile(filePath, label) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    fail([`${scriptName}: ${label} not found: ${path.relative(root, filePath)}`]);
  }
}

function formatCommand(command, args) {
  return [command, ...args].map((part) => {
    if (/^[A-Za-z0-9_./:=@-]+$/.test(part)) {
      return part;
    }
    return JSON.stringify(part);
  }).join(' ');
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

function printHelp() {
  console.log(`
Usage:
  node tests/verify-device-mihomo.mjs [options]

Options:
  --hap <path>          Signed HAP path. Defaults to entry/build/default/outputs/default/entry-default-signed.hap.
  --serial <target>     hdc target serial when multiple devices are connected.
  --bundle <name>       Bundle name. Defaults to AppScope/app.json5 bundleName.
  --observe-ms <ms>     Hilog capture duration after launch. Defaults to 45000. Use 0 for checklist only.
  --controller-port <p> Local TCP port for hdc fport to device 9090. Defaults to 19090.
  --require-stop        Require native stop evidence with nativeFd=-1 and controllerReady=false.
  --min-cycles <n>      Require at least n complete start/controller/stop cycles. Defaults to 0.
  --evidence-dir <dir>  Write summary, hashes, device info, HAP entries, and hilog files.
  --no-install          Skip hdc install -r.
  --no-launch           Skip aa start.
  --allow-stub          Allow HAPs without real libmihomo_ohos.so for local dry runs.
  --allow-no-device     Skip hdc phase when no device is connected.
`);
}

function fail(messages) {
  console.error(messages.join('\n'));
  process.exit(1);
}
