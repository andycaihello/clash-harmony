#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const root = process.cwd();
const scriptName = 'verify-fake-mihomo-prebuilt-hap';
const libraryName = 'libmihomo_ohos.so';
const prebuiltRoot = path.join(root, 'entry/src/main/cpp/prebuilt');
const defaultDevecoSdkHome = '/Applications/DevEco-Studio.app/Contents/sdk';
const defaultJavaHome = '/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home';
const defaultHvigor = '/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw';
const defaultHapPath = path.join(root, 'entry/build/default/outputs/default/entry-default-signed.hap');
const builtInFakeMihomoSourcePath = path.join(root, 'entry/src/main/cpp/fake_mihomo/fake_mihomo.c');
const abiTargets = new Map([
  ['arm64-v8a', 'aarch64-linux-ohos'],
  ['x86_64', 'x86_64-linux-ohos']
]);

const generatedFiles = [];
const generatedDirs = [];
let tempRoot = null;
let installedFakePrebuilts = false;
let restoreEnv = null;
let restoreHvigor = null;

try {
  const devecoSdkHome = process.env.DEVECO_SDK_HOME ?? defaultDevecoSdkHome;
  const openHarmonySdkHome = resolveOpenHarmonySdkHome(devecoSdkHome);
  const nativeRoot = path.join(openHarmonySdkHome, 'native');
  const llvmBin = path.join(nativeRoot, 'llvm/bin');
  const clangPath = path.join(llvmBin, 'clang-15');
  const sysroot = path.join(nativeRoot, 'sysroot');
  const javaHome = process.env.JAVA_HOME ?? defaultJavaHome;
  const hvigor = process.env.HVIGOR ?? defaultHvigor;

  assertExecutable(clangPath, 'DevEco OpenHarmony clang-15');
  assertDirectory(sysroot, 'DevEco OpenHarmony native sysroot');
  assertExecutable(hvigor, 'hvigor');
  assertDirectory(javaHome, 'JAVA_HOME');
  refuseExistingPrebuiltLibraries();

  tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'fake-mihomo-prebuilt-'));
  const sourcePath = path.join(tempRoot, 'fake_mihomo_ohos.c');
  fs.writeFileSync(sourcePath, fakeMihomoSource(), 'utf8');

  for (const [abi, target] of abiTargets) {
    const abiDir = path.join(prebuiltRoot, abi);
    ensureDir(abiDir);
    const tempOutput = path.join(tempRoot, `${abi}-${libraryName}`);
    const prebuiltPath = path.join(abiDir, libraryName);

    run(clangPath, [
      '-target', target,
      '--sysroot', sysroot,
      '-D__MUSL__',
      '-fPIC',
      '-shared',
      '-nostdlib',
      '-Wl,-soname,libmihomo_ohos.so',
      sourcePath,
      '-o', tempOutput
    ], {
      env: buildEnv({ devecoSdkHome, javaHome, llvmBin })
    });

    installGeneratedLibrary(tempOutput, prebuiltPath);
    installedFakePrebuilts = true;
    console.log(`${scriptName}: generated ${path.relative(root, prebuiltPath)} with ${path.basename(clangPath)} (${target})`);
  }

  const env = buildEnv({ devecoSdkHome, javaHome, llvmBin });
  restoreEnv = env;
  restoreHvigor = hvigor;
  run(process.execPath, ['tests/verify-mihomo-prebuilt-abi.mjs', '--require-abi', 'arm64-v8a,x86_64'], { env });
  runHvigorCleanThenAssemble(hvigor, env);
  run(process.execPath, ['tests/verify-hap-contents.mjs', '--require-abi', 'arm64-v8a,x86_64'], { env });
  run(process.execPath, ['tests/verify-mihomo-prebuilt-packaging.mjs', '--require-abi', 'arm64-v8a,x86_64'], { env });

  console.log(`${scriptName}: fake mihomo prebuilt HAP verification passed`);
} catch (error) {
  console.error(errorMessage(error));
  process.exitCode = 1;
} finally {
  cleanupGeneratedArtifacts();
  restoreCleanNoPrebuiltHap();
}

function resolveOpenHarmonySdkHome(devecoSdkHome) {
  const candidates = [
    process.env.OHOS_OPENHARMONY_SDK_HOME,
    path.join(devecoSdkHome, 'default/openharmony'),
    path.join(devecoSdkHome, 'openharmony'),
    devecoSdkHome
  ].filter((candidate) => candidate !== undefined && candidate.length > 0);

  for (const candidate of candidates) {
    const nativeRoot = path.join(candidate, 'native');
    if (fs.existsSync(path.join(nativeRoot, 'llvm/bin/clang-15')) &&
        fs.existsSync(path.join(nativeRoot, 'sysroot'))) {
      return candidate;
    }
  }

  return path.join(devecoSdkHome, 'default/openharmony');
}

function refuseExistingPrebuiltLibraries() {
  const existing = Array.from(abiTargets.keys())
    .map((abi) => path.join(prebuiltRoot, abi, libraryName))
    .filter((prebuiltPath) => fs.existsSync(prebuiltPath));

  if (existing.length > 0) {
    fail([
      `${scriptName}: refusing to overwrite existing ${libraryName}`,
      ...existing.map((prebuiltPath) => `- ${path.relative(root, prebuiltPath)}`)
    ]);
  }
}

function ensureDir(dirPath) {
  if (fs.existsSync(dirPath)) {
    if (!fs.statSync(dirPath).isDirectory()) {
      fail([`${scriptName}: expected directory but found file: ${path.relative(root, dirPath)}`]);
    }
    return;
  }
  fs.mkdirSync(dirPath, { recursive: true });
  generatedDirs.push(dirPath);
}

function installGeneratedLibrary(tempOutput, prebuiltPath) {
  fs.copyFileSync(tempOutput, prebuiltPath, fs.constants.COPYFILE_EXCL);
  generatedFiles.push(prebuiltPath);
}

function buildEnv({ devecoSdkHome, javaHome, llvmBin }) {
  const pathEntries = [
    path.join(javaHome, 'bin'),
    llvmBin,
    process.env.PATH ?? ''
  ].filter((entry) => entry.length > 0);

  return {
    ...process.env,
    DEVECO_SDK_HOME: devecoSdkHome,
    JAVA_HOME: javaHome,
    OHOS_LLVM_NM: process.env.OHOS_LLVM_NM ?? path.join(llvmBin, 'llvm-nm'),
    OHOS_LLVM_READELF: process.env.OHOS_LLVM_READELF ?? path.join(llvmBin, 'llvm-readelf'),
    PATH: pathEntries.join(path.delimiter)
  };
}

function run(command, args, options = {}) {
  console.log(`${scriptName}: running ${formatCommand(command, args)}`);
  execFileSync(command, args, {
    cwd: root,
    env: options.env ?? process.env,
    stdio: 'inherit'
  });
}

function runHvigorCleanThenAssemble(hvigor, env) {
  run(hvigor, ['clean', '--no-daemon', '--stacktrace'], { env });
  run(hvigor, ['assembleHap', '--no-daemon', '--no-type-check', '--stacktrace'], { env });
}

function assertExecutable(targetPath, label) {
  try {
    fs.accessSync(targetPath, fs.constants.X_OK);
    if (!fs.statSync(targetPath).isFile()) {
      throw new Error('not a file');
    }
  } catch (error) {
    fail([`${scriptName}: ${label} is not executable: ${targetPath}`, errorMessage(error)]);
  }
}

function assertDirectory(targetPath, label) {
  try {
    if (!fs.statSync(targetPath).isDirectory()) {
      throw new Error('not a directory');
    }
  } catch (error) {
    fail([`${scriptName}: ${label} does not exist: ${targetPath}`, errorMessage(error)]);
  }
}

function cleanupGeneratedArtifacts() {
  const cleanupErrors = [];

  for (const generatedFile of generatedFiles.slice().reverse()) {
    try {
      if (fs.existsSync(generatedFile)) {
        fs.unlinkSync(generatedFile);
        console.log(`${scriptName}: removed ${path.relative(root, generatedFile)}`);
      }
    } catch (error) {
      cleanupErrors.push(`${path.relative(root, generatedFile)}: ${errorMessage(error)}`);
    }
  }

  for (const generatedDir of generatedDirs.slice().reverse()) {
    try {
      if (fs.existsSync(generatedDir) && fs.readdirSync(generatedDir).length === 0) {
        fs.rmdirSync(generatedDir);
        console.log(`${scriptName}: removed empty directory ${path.relative(root, generatedDir)}`);
      }
    } catch (error) {
      cleanupErrors.push(`${path.relative(root, generatedDir)}: ${errorMessage(error)}`);
    }
  }

  if (tempRoot !== null) {
    try {
      fs.rmSync(tempRoot, { recursive: true, force: true });
    } catch (error) {
      cleanupErrors.push(`${tempRoot}: ${errorMessage(error)}`);
    }
  }

  if (cleanupErrors.length > 0) {
    console.error([
      `${scriptName}: cleanup failed`,
      ...cleanupErrors
    ].join('\n'));
    process.exitCode = 1;
  }
}

function restoreCleanNoPrebuiltHap() {
  if (!installedFakePrebuilts || restoreEnv === null || restoreHvigor === null) {
    return;
  }

  try {
    runHvigorCleanThenAssemble(restoreHvigor, restoreEnv);
    assertDefaultHapRestoredWithoutGeneratedPrebuilt();
  } catch (error) {
    console.error([
      `${scriptName}: failed to restore clean no-prebuilt HAP after fake verification`,
      errorMessage(error)
    ].join('\n'));
    process.exitCode = 1;
  }
}

function assertDefaultHapRestoredWithoutGeneratedPrebuilt() {
  const remainingPrebuilts = Array.from(abiTargets.keys())
    .map((abi) => path.join(prebuiltRoot, abi, libraryName))
    .filter((prebuiltPath) => fs.existsSync(prebuiltPath));
  if (remainingPrebuilts.length > 0) {
    fail([
      `${scriptName}: generated prebuilt libraries were not cleaned`,
      ...remainingPrebuilts.map((prebuiltPath) => `- ${path.relative(root, prebuiltPath)}`)
    ]);
  }

  if (!fs.existsSync(defaultHapPath)) {
    return;
  }

  const entries = execFileSync('unzip', ['-Z1', defaultHapPath], {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe']
  });

  if (entries.includes(libraryName)) {
    if (fs.existsSync(builtInFakeMihomoSourcePath)) {
      console.log(`${scriptName}: clean restore HAP contains built-in fake ${libraryName}, with generated prebuilts removed`);
      return;
    }
    fail([`${scriptName}: clean restore HAP still contains ${libraryName} without generated prebuilt or built-in fake source`]);
  }
}

function fakeMihomoSource() {
  return `
static const char* g_last_error = "";

__attribute__((visibility("default"))) int MihomoStart(const char* configPath, int tunFd)
{
    (void)configPath;
    (void)tunFd;
    g_last_error = "";
    return 0;
}

__attribute__((visibility("default"))) int MihomoStop(void)
{
    g_last_error = "";
    return 0;
}

__attribute__((visibility("default"))) const char* MihomoVersion(void)
{
    return "fake-mihomo-prebuilt-hap-1.0";
}

__attribute__((visibility("default"))) const char* MihomoLastError(void)
{
    return g_last_error;
}
`;
}

function formatCommand(command, args) {
  return [command, ...args].map((part) => {
    if (/^[A-Za-z0-9_./:=@+-]+$/.test(part)) {
      return part;
    }
    return JSON.stringify(part);
  }).join(' ');
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

function fail(messages) {
  throw new Error(messages.join('\n'));
}
