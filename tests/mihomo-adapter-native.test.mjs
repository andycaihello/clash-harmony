import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const root = process.cwd();
const compiler = findCompiler();
const libraryName = 'libmihomo_ohos.so';
const adapterSourcePath = path.join(root, 'entry/src/main/cpp/mihomo_adapter.cpp');
const adapterIncludePath = path.join(root, 'entry/src/main/cpp');
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'mihomo-adapter-native-'));

if (compiler === null) {
  throw new Error('No C++ compiler found. Set CXX or install clang++/c++/g++ to run mihomo adapter native tests.');
}

try {
  const runnerSourcePath = path.join(tempRoot, 'mihomo_adapter_runner.cpp');
  const completeFakeSourcePath = path.join(tempRoot, 'fake_mihomo_complete.cpp');
  const missingStartFakeSourcePath = path.join(tempRoot, 'fake_mihomo_missing_start.cpp');
  const missingStopFakeSourcePath = path.join(tempRoot, 'fake_mihomo_missing_stop.cpp');
  const missingVersionFakeSourcePath = path.join(tempRoot, 'fake_mihomo_missing_version.cpp');
  const missingLastErrorFakeSourcePath = path.join(tempRoot, 'fake_mihomo_missing_last_error.cpp');
  const runnerPath = path.join(tempRoot, 'mihomo_adapter_runner');
  const configPath = path.join(tempRoot, 'config.yaml');
  const noLibDir = path.join(tempRoot, 'no-lib');
  const completeLibDir = path.join(tempRoot, 'complete-lib');
  const missingStartLibDir = path.join(tempRoot, 'missing-start-lib');
  const missingStopLibDir = path.join(tempRoot, 'missing-stop-lib');
  const missingVersionLibDir = path.join(tempRoot, 'missing-version-lib');
  const missingLastErrorLibDir = path.join(tempRoot, 'missing-last-error-lib');

  fs.mkdirSync(noLibDir, { recursive: true });
  fs.mkdirSync(completeLibDir, { recursive: true });
  fs.mkdirSync(missingStartLibDir, { recursive: true });
  fs.mkdirSync(missingStopLibDir, { recursive: true });
  fs.mkdirSync(missingVersionLibDir, { recursive: true });
  fs.mkdirSync(missingLastErrorLibDir, { recursive: true });
  fs.writeFileSync(configPath, 'mixed-port: 7890\n', 'utf8');
  fs.writeFileSync(runnerSourcePath, getRunnerSource(), 'utf8');
  fs.writeFileSync(completeFakeSourcePath, getCompleteFakeSource(), 'utf8');
  fs.writeFileSync(missingStartFakeSourcePath, getMissingStartFakeSource(), 'utf8');
  fs.writeFileSync(missingStopFakeSourcePath, getMissingStopFakeSource(), 'utf8');
  fs.writeFileSync(missingVersionFakeSourcePath, getMissingVersionFakeSource(), 'utf8');
  fs.writeFileSync(missingLastErrorFakeSourcePath, getMissingLastErrorFakeSource(), 'utf8');

  run(compiler, ['--version']);
  compileRunner(runnerSourcePath, runnerPath);
  compileFakeLibrary(completeFakeSourcePath, path.join(completeLibDir, libraryName));
  compileFakeLibrary(missingStartFakeSourcePath, path.join(missingStartLibDir, libraryName));
  compileFakeLibrary(missingStopFakeSourcePath, path.join(missingStopLibDir, libraryName));
  compileFakeLibrary(missingVersionFakeSourcePath, path.join(missingVersionLibDir, libraryName));
  compileFakeLibrary(missingLastErrorFakeSourcePath, path.join(missingLastErrorLibDir, libraryName));

  const noLib = runRunner(runnerPath, noLibDir, configPath, 'stub-no-library');
  assert.equal(noLib.start, 0);
  assert.equal(noLib.mode, 'stub');
  assert.equal(noLib.version, 'adapter-stub');
  assert.ok(noLib.loadError.length > 0, 'missing lib should leave a non-empty load error');

  const completeFake = runRunner(runnerPath, completeLibDir, configPath, 'real-library');
  assert.equal(completeFake.start, 0);
  assert.equal(completeFake.modeAfterStart, 'real');
  assert.equal(completeFake.versionAfterStart, 'fake-mihomo-1.0');
  assert.equal(completeFake.loadErrorAfterStart, '');
  assert.equal(completeFake.stop, 0);
  assert.equal(completeFake.versionAfterStop, '');

  const missingStartFake = runRunner(runnerPath, missingStartLibDir, configPath, 'missing-start-symbol');
  assert.equal(missingStartFake.start, 0);
  assert.equal(missingStartFake.mode, 'stub');
  assert.equal(missingStartFake.version, 'adapter-stub');
  assert.match(missingStartFake.loadError, /missing symbol MihomoStart/);

  const missingStopFake = runRunner(runnerPath, missingStopLibDir, configPath, 'missing-stop-symbol');
  assert.equal(missingStopFake.start, 0);
  assert.equal(missingStopFake.mode, 'stub');
  assert.equal(missingStopFake.version, 'adapter-stub');
  assert.match(missingStopFake.loadError, /missing symbol MihomoStop/);

  const missingVersionFake = runRunner(runnerPath, missingVersionLibDir, configPath, 'missing-version-symbol');
  assert.equal(missingVersionFake.start, 0);
  assert.equal(missingVersionFake.mode, 'stub');
  assert.equal(missingVersionFake.version, 'adapter-stub');
  assert.match(missingVersionFake.loadError, /missing symbol MihomoVersion/);

  const missingLastErrorFake = runRunner(runnerPath, missingLastErrorLibDir, configPath, 'missing-last-error-symbol');
  assert.equal(missingLastErrorFake.start, 0);
  assert.equal(missingLastErrorFake.mode, 'stub');
  assert.equal(missingLastErrorFake.version, 'adapter-stub');
  assert.match(missingLastErrorFake.loadError, /missing symbol MihomoLastError/);

  console.log('mihomo-adapter-native: native adapter dlopen tests passed');
} finally {
  fs.rmSync(tempRoot, { recursive: true, force: true });
}

function compileRunner(sourcePath, outputPath) {
  run(compiler, [
    '-std=c++17',
    '-Wall',
    '-Wextra',
    '-I',
    adapterIncludePath,
    sourcePath,
    adapterSourcePath,
    '-o',
    outputPath,
    ...runnerLinkArgs()
  ]);
}

function findCompiler() {
  if (process.env.CXX !== undefined && process.env.CXX.length > 0 && isExecutable(process.env.CXX)) {
    return process.env.CXX;
  }

  for (const command of ['clang++', 'c++', 'g++']) {
    const found = findOnPath(command);
    if (found !== null) {
      return found;
    }
  }

  return null;
}

function findOnPath(command) {
  const pathEntries = (process.env.PATH ?? '').split(path.delimiter).filter((entry) => entry.length > 0);
  for (const entry of pathEntries) {
    const candidate = path.join(entry, command);
    if (isExecutable(candidate)) {
      return candidate;
    }
  }
  return null;
}

function isExecutable(targetPath) {
  try {
    fs.accessSync(targetPath, fs.constants.X_OK);
    return fs.statSync(targetPath).isFile();
  } catch {
    return false;
  }
}

function compileFakeLibrary(sourcePath, outputPath) {
  run(compiler, [
    '-std=c++17',
    '-Wall',
    '-Wextra',
    '-fPIC',
    ...sharedLibraryArgs(),
    sourcePath,
    '-o',
    outputPath
  ]);
}

function runnerLinkArgs() {
  if (process.platform === 'linux') {
    return ['-pthread', '-ldl'];
  }
  return ['-pthread'];
}

function sharedLibraryArgs() {
  if (process.platform === 'darwin') {
    return ['-dynamiclib', `-Wl,-install_name,${libraryName}`];
  }
  return ['-shared'];
}

function runRunner(runnerPath, libraryDir, configPath, scenario) {
  const output = run(runnerPath, [scenario, configPath], {
    cwd: libraryDir,
    env: loaderEnv(libraryDir)
  });
  return JSON.parse(output);
}

function loaderEnv(libraryDir) {
  return {
    ...process.env,
    LD_LIBRARY_PATH: libraryDir,
    DYLD_LIBRARY_PATH: libraryDir,
    DYLD_FALLBACK_LIBRARY_PATH: libraryDir
  };
}

function run(command, args, options = {}) {
  try {
    return execFileSync(command, args, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      ...options
    });
  } catch (error) {
    const stdout = error.stdout === undefined ? '' : String(error.stdout);
    const stderr = error.stderr === undefined ? '' : String(error.stderr);
    throw new Error([
      `Command failed: ${command} ${args.join(' ')}`,
      stdout.trim(),
      stderr.trim()
    ].filter((line) => line.length > 0).join('\n'));
  }
}

function getRunnerSource() {
  return String.raw`
#include "mihomo_adapter.h"

#include <iostream>
#include <string>

namespace {

std::string SafeString(const char* value)
{
    return value == nullptr ? "" : value;
}

std::string EscapeJson(const std::string& value)
{
    std::string escaped;
    for (char character : value) {
        switch (character) {
            case '\\':
                escaped += "\\\\";
                break;
            case '"':
                escaped += "\\\"";
                break;
            case '\n':
                escaped += "\\n";
                break;
            case '\r':
                escaped += "\\r";
                break;
            case '\t':
                escaped += "\\t";
                break;
            default:
                escaped += character;
                break;
        }
    }
    return escaped;
}

void WriteStringField(const char* name, const std::string& value, bool trailingComma)
{
    std::cout << "\"" << name << "\":\"" << EscapeJson(value) << "\"";
    if (trailingComma) {
        std::cout << ",";
    }
}

} // namespace

int main(int argc, char** argv)
{
    if (argc < 3) {
        std::cerr << "usage: mihomo_adapter_runner <stub-no-library|real-library|missing-start-symbol|missing-stop-symbol|missing-version-symbol|missing-last-error-symbol> <config-path>\n";
        return 2;
    }

    std::string scenario = argv[1];
    const char* configPath = argv[2];

    if (scenario == "stub-no-library" || scenario == "missing-start-symbol" ||
        scenario == "missing-stop-symbol" || scenario == "missing-version-symbol" ||
        scenario == "missing-last-error-symbol") {
        int startResult = MihomoStart(configPath, 42);
        std::cout << "{\"start\":" << startResult << ",";
        WriteStringField("mode", SafeString(MihomoAdapterMode()), true);
        WriteStringField("version", SafeString(MihomoVersion()), true);
        WriteStringField("lastError", SafeString(MihomoLastError()), true);
        WriteStringField("loadError", SafeString(MihomoAdapterLoadError()), false);
        std::cout << "}\n";
        return 0;
    }

    if (scenario == "real-library") {
        int startResult = MihomoStart(configPath, 42);
        std::string modeAfterStart = SafeString(MihomoAdapterMode());
        std::string versionAfterStart = SafeString(MihomoVersion());
        std::string loadErrorAfterStart = SafeString(MihomoAdapterLoadError());
        int stopResult = MihomoStop();
        std::string versionAfterStop = SafeString(MihomoVersion());

        std::cout << "{\"start\":" << startResult << ",";
        WriteStringField("modeAfterStart", modeAfterStart, true);
        WriteStringField("versionAfterStart", versionAfterStart, true);
        WriteStringField("loadErrorAfterStart", loadErrorAfterStart, true);
        std::cout << "\"stop\":" << stopResult << ",";
        WriteStringField("versionAfterStop", versionAfterStop, false);
        std::cout << "}\n";
        return 0;
    }

    std::cerr << "unknown scenario: " << scenario << "\n";
    return 2;
}
`;
}

function getCompleteFakeSource() {
  return String.raw`
#include <string>

namespace {

bool g_started = false;
std::string g_lastError;

} // namespace

extern "C" int MihomoStart(const char* configPath, int tunFd)
{
    if (configPath == nullptr || configPath[0] == '\0') {
        g_started = false;
        g_lastError = "fake config path is empty";
        return -1;
    }
    if (tunFd < 0) {
        g_started = false;
        g_lastError = "fake tun fd is invalid";
        return -2;
    }
    g_started = true;
    g_lastError.clear();
    return 0;
}

extern "C" int MihomoStop(void)
{
    g_started = false;
    g_lastError.clear();
    return 0;
}

extern "C" const char* MihomoVersion(void)
{
    return g_started ? "fake-mihomo-1.0" : "";
}

extern "C" const char* MihomoLastError(void)
{
    return g_lastError.c_str();
}
`;
}

function getMissingStopFakeSource() {
  return String.raw`
extern "C" int MihomoStart(const char*, int)
{
    return 77;
}

extern "C" const char* MihomoVersion(void)
{
    return "fake-mihomo-should-not-be-used";
}

extern "C" const char* MihomoLastError(void)
{
    return "";
}
`;
}

function getMissingStartFakeSource() {
  return String.raw`
extern "C" int MihomoStop(void)
{
    return 0;
}

extern "C" const char* MihomoVersion(void)
{
    return "fake-mihomo-should-not-be-used";
}

extern "C" const char* MihomoLastError(void)
{
    return "";
}
`;
}

function getMissingVersionFakeSource() {
  return String.raw`
extern "C" int MihomoStart(const char*, int)
{
    return 88;
}

extern "C" int MihomoStop(void)
{
    return 0;
}

extern "C" const char* MihomoLastError(void)
{
    return "";
}
`;
}

function getMissingLastErrorFakeSource() {
  return String.raw`
extern "C" int MihomoStart(const char*, int)
{
    return 99;
}

extern "C" int MihomoStop(void)
{
    return 0;
}

extern "C" const char* MihomoVersion(void)
{
    return "fake-mihomo-should-not-be-used";
}
`;
}
