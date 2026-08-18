# Project Skills (Android)

Project-scoped Agent Skills for this repository. Loaded automatically by pi
from `.agents/skills/` when working inside this repo.

## Source

These 29 skills are vendored from
[GuillemRoca/agent-skills-android](https://github.com/GuillemRoca/agent-skills-android)
(MIT License, Copyright (c) 2026 Guillem Roca). Only the `skills/*` SKILL.md
directories were installed — the upstream plugin packaging (`.claude-plugin/`)
was intentionally **not** installed so these ship as plain skills.

See `LICENSE` in this directory for the upstream license terms.

## Skills

| Skill | Purpose |
|-------|---------|
| `android-accessibility` | TalkBack, content descriptions, touch targets, semantics |
| `android-architecture` | MVVM/MVI, Clean Architecture, Hilt DI, module structure |
| `android-background-work` | WorkManager, foreground service types, exact alarms, Doze |
| `android-data-persistence` | Room, DataStore, offline-first, Paging3, repository pattern |
| `android-device-testing` | Espresso, UI Automator, Compose tests, screenshots, ADB, emulators |
| `android-e2e-verification` | Maestro flows: acceptance criteria as executable e2e checks |
| `android-ui-engineering` | Jetpack Compose, Material 3, Navigation, state hoisting |
| `api-and-interface-design` | Retrofit interfaces, sealed types, contract-first design |
| `ci-cd-and-automation` | CI pipelines, fastlane, Gradle automation |
| `code-review-and-quality` | Five-axis code review |
| `code-simplification` | Simplify code without changing behavior |
| `context-engineering` | Set up project context for AI-assisted development |
| `debugging-and-error-recovery` | Systematic debugging with Logcat, profilers, LeakCanary |
| `deprecation-and-migration` | Safe deprecation and migration strategies |
| `documentation-and-adrs` | Architecture Decision Records and documentation |
| `doubt-driven-development` | Adversarial self-review for hard-to-reverse decisions |
| `git-workflow-and-versioning` | Branching, PRs, release versioning |
| `idea-refine` | Sharpen vague ideas into focused, actionable directions |
| `incremental-implementation` | Build in small, verifiable increments |
| `interview-me` | Iterative questioning that turns vague requests into requirements |
| `observability-and-instrumentation` | Logging, tracing, metrics on Android |
| `performance-optimization` | Android Vitals, Macrobenchmark, APK size, recomposition |
| `planning-and-task-breakdown` | Break work into vertical slices with acceptance criteria |
| `security-and-hardening` | Secure storage, network security, app hardening |
| `shipping-and-launch` | Pre-launch checklist and rollout |
| `source-driven-development` | Every framework decision backed by official docs |
| `spec-driven-development` | Write structured specs before coding |
| `test-driven-development` | Red-Green-Refactor with JUnit5 + MockK |
| `using-agent-skills` | Meta-skill: how agents should operate in this project |

## Updating

To refresh from upstream:

```sh
cd /tmp
git clone --depth 1 https://github.com/GuillemRoca/agent-skills-android.git
cp -r agent-skills-android/skills/* .agents/skills/
cp agent-skills-android/LICENSE .agents/skills/LICENSE
```
