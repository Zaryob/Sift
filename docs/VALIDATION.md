# Local build and test record

9 October 2026 (Europe/Istanbul), source baseline `cb57e3f58b496a50130aaf94cd9b6735f664070c` plus this branch's test-target/API/entitlement changes. macOS 27.0 arm64 (Apple M4), Xcode 27.0 (27A266a).

The baseline unsigned macOS app build succeeded. Attaching the checked-in `SiftTests` folder exposed stale mock/cache/optional API references, which this change corrects without removing tests or weakening assertions. The app and test target then compiled for an iPhone 18 Pro / iOS 27.0 simulator.

A serial simulator XCTest run reported **49 executed tests and four assertion failures in three test cases**:

| Test case | Observation |
| --- | --- |
| `FeedRefreshServiceTests.testETagAndLastModifiedSentAndSaved` | Two assertions: expected ETag / Last-Modified values were nil |
| `SmartFeedFilterTests.testScalesBudgetAndDoesNotPassAll976Articles` | 13 selected items versus the asserted minimum 25 |
| `StoryClusteringSpikeTests.testRecentMemberSupportPreventsCentroidDrift` | Accepted where the test expected rejection by recent-member support |

This is a **failed test run**, not a CI-passing or release-ready claim. Relevant XCTest output is retained in [test-output.txt](test-output.txt). The first parallel attempt also exposed failures and did not finish cleanly; it was interrupted. The serial test assertions completed, but the hosted test session's shutdown/result export must be assessed separately. No passing aggregate is inferred from build success.

```sh
xcodebuild -project Sift.xcodeproj -scheme Sift \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Sift.xcodeproj -scheme Sift -showdestinations
xcodebuild -project Sift.xcodeproj -scheme Sift \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -parallel-testing-enabled NO -derivedDataPath build/validation \
  CODE_SIGNING_ALLOWED=NO test
```

Use an isolated simulator for hosted tests. Some suites use shared managers/cache and the app host may do initialization work; this is not a claim that every test is free of network or persistence effects. Hosted macOS test execution and older Xcode compatibility were not verified.

## App Group and release boundary

`group.io.github.zaryob.sift` was already present in `PersistenceController.appGroupID`, the widget and the README. The checked-in app/widget entitlements now match that existing source contract; this change does not invent a new group, register it with Apple or change the development team.

Unsigned compilation and simulator tests do not verify Apple Developer registration, provisioning, signed app/widget data sharing, sandbox behavior on a physical device, Apple Intelligence availability/fallback, or installation on a clean machine. No published GitHub Release was present at the audit snapshot, and no binary/tag was created here. Fix the exposed test/host failures under [#1](https://github.com/Zaryob/Sift/issues/1); signed/device/widget acceptance remains [#2](https://github.com/Zaryob/Sift/issues/2).
