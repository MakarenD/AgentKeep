# Graph Report - .  (2026-07-12)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 158 nodes · 371 edges · 15 communities (7 shown, 8 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 4 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `f43a5a6b`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Community 0
- Community 1
- Community 2
- Community 3
- Community 4
- Community 5
- Community 6
- Community 7
- Community 8
- Community 10
- Community 11
- Community 12
- Community 13
- Community 14

## God Nodes (most connected - your core abstractions)
1. `AppDelegate` - 57 edges
2. `LocalServerMonitor` - 21 edges
3. `LocalServerProcess` - 19 edges
4. `LocalServerKind` - 15 edges
5. `LocalServerListener` - 8 edges
6. `LoginItemManager` - 8 edges
7. `LocalServerStopFailure` - 7 edges
8. `State` - 7 edges
9. `PowerManager` - 7 edges
10. `PowerManagerError` - 7 edges

## Surprising Connections (you probably didn't know these)
- `AppDelegate` --calls--> `LocalServerMonitor`  [INFERRED]
  Sources/AgentKeepCore/AppDelegate.swift → Sources/AgentKeepCore/LocalServerMonitor.swift
- `AppDelegate` --calls--> `PowerManager`  [INFERRED]
  Sources/AgentKeepCore/AppDelegate.swift → Sources/AgentKeepCore/PowerManager.swift
- `AppDelegate` --references--> `LocalServerProcess`  [EXTRACTED]
  Sources/AgentKeepCore/AppDelegate.swift → Sources/AgentKeepCore/LocalServerMonitor.swift
- `AppDelegate` --calls--> `LoginItemManager`  [EXTRACTED]
  Sources/AgentKeepCore/AppDelegate.swift → Sources/AgentKeepCore/LoginItemManager.swift

## Import Cycles
- None detected.

## Communities (15 total, 8 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.19
Nodes (13): Darwin, Hashable, Int, Set, LocalServerListener, LocalServerMonitor, LocalServerProcess, LocalServerStopFailure (+5 more)

### Community 1 - "Community 1"
Cohesion: 0.15
Nodes (13): Error, LocalizedError, LocalServerMonitorError, commandFailed, PowerManager, PowerManagerError, commandFailed, unreadablePmsetOutput (+5 more)

### Community 2 - "Community 2"
Cohesion: 0.17
Nodes (7): NSApplicationDelegate, NSMenu, NSMenuDelegate, NSObject, NSStatusItem, AppDelegate, Timer

### Community 3 - "Community 3"
Cohesion: 0.16
Nodes (10): Foundation, ServiceManagement, LoginItemManager, State, enabled, notFound, notRegistered, requiresApproval (+2 more)

### Community 4 - "Community 4"
Cohesion: 0.18
Nodes (4): AgentKeepCore, AppKit, LocalServerMonitorTests, XCTest

### Community 5 - "Community 5"
Cohesion: 0.17
Nodes (12): LocalServerKind, bun, deno, dotnet, go, java, node, other (+4 more)

## Knowledge Gaps
- **21 isolated node(s):** `PackageDescription`, `Darwin`, `node`, `php`, `python` (+16 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppDelegate` connect `Community 2` to `Community 0`, `Community 1`, `Community 3`, `Community 4`, `Community 6`, `Community 7`, `Community 8`, `Community 9`, `Community 10`, `Community 11`?**
  _High betweenness centrality (0.593) - this node is a cross-community bridge._
- **Why does `LocalServerMonitor` connect `Community 0` to `Community 2`?**
  _High betweenness centrality (0.195) - this node is a cross-community bridge._
- **Why does `LocalServerProcess` connect `Community 0` to `Community 2`, `Community 5`, `Community 6`, `Community 7`?**
  _High betweenness centrality (0.184) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `AppDelegate` (e.g. with `LocalServerMonitor` and `PowerManager`) actually correct?**
  _`AppDelegate` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `Darwin`, `node` to the rest of the system?**
  _21 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.14624505928853754 - nodes in this community are weakly interconnected._