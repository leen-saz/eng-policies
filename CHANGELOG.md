# Changelog

كل التغييرات المهمة هنا. الصيغة مبنية على Keep a Changelog، والإصدارات على SemVer.

## [Unreleased]

### Added
- ci.yml: دعم Python (`python-version`, `python-requirements`, `python-test-command`) و`node-cache-path` للمشاريع اللي فيها package.json بمجلد فرعي.
- self-test: job `mixed-app-ci` على fixture فيه Python و Node بمجلد فرعي.

## [1.0.0-alpha.1]

### Added
- POLICIES.md: القواعد في صفحة وحدة مع سبب لكل قاعدة.
- claude/: قواعد Claude العامة وقالب قواعد المشروع.
- Reusable workflows: ci (مع `gate`)، preview، deploy، codeql، ai-review، self-test.
- templates/: callers، wrangler بثلاث بيئات، tests، docs (PRD, architecture, stories, ADR, adoption)، قوالب GitHub.
- install/: install.sh (new/existing, global, uninstall, dry-run)، github-setup.sh، cloudflare-setup.sh، update.sh.
- skills/: new-project، adopt-existing، debug، bug-hunt، وتغليفها كـ Claude Code plugin.
- examples/sample-app: Worker + D1 مع unit وintegration وE2E.
- test/e2e-installer.sh: اختبار الـ installer كامل.
