# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

HandyROS is a native cross-platform mobile client for ROS 2. It discovers, monitors, and visualizes ROS 2 topics/nodes directly over DDS — no rosbridge or other intermediary server. Two pieces:

- **Flutter app** (repo root: `lib/`, `android/`, `ios/`) — the mobile UI. Currently all data is mocked; there is no live DDS connection wired up yet.
- **`handyros_core/`** — a native C++ shared library (`libhandyros_core.so`) that talks to Fast DDS directly (`DDSManager` wraps `eprosima::fastdds::dds::DomainParticipant`). This will eventually be bound into the Flutter app via `dart:ffi`; that integration does not exist yet.

The current focus is building out the Flutter UI to match the Claude Design mockup (project "Viewer plugin architecture for HandyROS", file `HandyROS.dc.html`) before wiring up the real DDS backend.

## Commands

Run all Flutter commands from the repo root.

```bash
flutter pub get              # install/update dependencies after editing pubspec.yaml
flutter run                  # run on a connected device/emulator
flutter analyze               # static analysis (uses analysis_options.yaml / flutter_lints)
flutter test                  # run all tests
flutter test test/widget_test.dart   # run a single test file
```

Native core (`handyros_core/`) is a standalone CMake project (requires Fast DDS / Fast CDR installed):

```bash
cd handyros_core
cmake -S . -B build
cmake --build build
./build/test_handyros
```

## Architecture (Flutter app)

`lib/` is organized by role, not by feature:

- `models/` — plain data classes (e.g. `Topic`).
- `services/` — data sources. Currently `FakeTopicService` returns hardcoded topic data; this is the seam where a real DDS-backed service will later replace the fake one.
- `screens/` — top-level pages (e.g. `HomeScreen`), composed from widgets.
- `widgets/` — reusable UI pieces specific to this app's screens (topic cards, status card, search bar, filter chips).
- `viewers/` — per-message-type visualizers (image, IMU, laser scan, point cloud, odometry, TF, terminal, raw echo). This is the "viewer plugin" concept: each ROS message type maps to a viewer via a registry, with a raw/echo fallback for types without a dedicated viewer and an "unknown type" state for types that can't be decoded at all.
- `app/` — app-wide concerns (`theme.dart` holds the dark theme/color scheme).
- `core/` — cross-cutting infrastructure shared by multiple layers (e.g. the viewer plugin registry, icon mapping).

The design source of truth lives in the Claude Design project "Viewer plugin architecture for HandyROS" (`HandyROS.dc.html`, plus a static `HandyROS-print.dc.html` reference and shared `support.js`/`doc-page.js` runtime files for the design tool itself — not part of the app). That mockup defines the exact visual language (dark cyberpunk theme, Chakra Petch/JetBrains Mono/Manrope type, specific colors per message category) and the four app states: Home (topic list), Viewer (per-type visualization), Unknown Type (no viewer registered, prompts to import a message definition), and Settings (RMW selector, registered viewer registry, message definitions, appearance). When implementing UI, match that mockup's structure and visual detail rather than inventing new layout.
