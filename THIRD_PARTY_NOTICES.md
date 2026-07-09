# Third Party Notices

This project is distributed under `GPL-3.0-only`. See [LICENSE](LICENSE).

This notice is provided for dependency and binary provenance tracking. It is not legal advice.

## mihomo

- Project: mihomo
- Upstream: https://github.com/MetaCubeX/mihomo
- License: GNU General Public License v3.0
- License text: https://github.com/MetaCubeX/mihomo/blob/Meta/LICENSE

Clash Harmony integrates a mihomo-compatible native runtime through the HarmonyOS native bridge. The following prebuilt files are included in this repository and in the generated HAP package:

```text
entry/src/main/cpp/prebuilt/arm64-v8a/libmihomo_ohos.so
SHA256: 0ed15ac3ea330c4324fe1ad2c8ba1f1e26f5d6b5ef03483a1c936f25d2ed218d

entry/src/main/cpp/prebuilt/arm64-v8a/libmihomo_exec.so
SHA256: 5806e5f5cc97ebb1a09e244ae11f8b69ff1bc92e439019999af685081ac0eeae
```

The release HAP currently tracked in this repository is:

```text
release/clash-harmony-v0.1.0-20260708-2318-signed.hap
SHA256: 2c00b356d7e2a8fefe1295449951cc22a780343ffadcd8aa19daf1e9e5f92b88
```

If these prebuilt binaries are replaced, update this file with the exact upstream revision, build instructions, binary hashes, and license obligations for the replacement artifacts.

## HarmonyOS SDK Runtime Components

This project is built with DevEco Studio / HarmonyOS SDK. The generated HAP may contain SDK-provided runtime libraries such as `libc++_shared.so`, and uses HarmonyOS platform APIs through ArkTS and native NAPI.

Those SDK components are provided by Huawei / OpenHarmony tooling and are subject to their corresponding SDK and platform terms. They are not authored by the Clash Harmony project.

## Project Fake Adapter

The source under `entry/src/main/cpp/fake_mihomo/` is part of this repository and is covered by the repository license, `GPL-3.0-only`.

## Subscription Data

Clash Harmony does not provide proxy nodes, subscription accounts, or subscription content. Users must provide their own lawful and authorized Clash/mihomo-compatible configuration or subscription.
