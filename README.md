# eng-policies

قواعد هندسة جاهزة للتركيب على أي مشروع (GitHub + Cloudflare: Workers, D1, R2, KV). تركيب مرة واحدة، وكل مشروع يلتزم بنفس القواعد: CI، preview، deploy، أمان، ومراجعة.

الإصدار الحالي: `1.0.0-alpha.1` (مرحلة alpha، راجع [CHANGELOG.md](CHANGELOG.md)). القواعد في [POLICIES.md](POLICIES.md).

## وش فيه

| المجلد | المحتوى |
|---|---|
| `POLICIES.md` | القواعد في صفحة وحدة، لكل قاعدة سبب |
| `claude/` | قواعد Claude: عامة (`CLAUDE.global.md`) وقالب المشروع |
| `.github/workflows/` | workflows قابلة لإعادة الاستخدام: ci, preview, deploy, codeql, ai-review, self-test |
| `templates/` | اللي ينزل داخل المشروع: callers, wrangler, tests, docs, قوالب PR |
| `install/` | `install.sh` `github-setup.sh` `cloudflare-setup.sh` `update.sh` |
| `skills/` | `new-project` `adopt-existing` `debug` `bug-hunt` (وتنزل كـ Claude Code plugin) |
| `examples/sample-app` | تطبيق Worker صغير يمر عليه الـ self-test |

## الخطوات الخمس

### 1. التركيب العام (مرة وحدة على جهازك)

```bash
git clone https://github.com/<owner>/eng-policies ~/eng-policies
bash ~/eng-policies/install/install.sh --global --dry-run   # يعرض وش بينزل
bash ~/eng-policies/install/install.sh --global             # ينزل ~/.claude/CLAUDE.md والـ skills
```

أو كـ plugin داخل Claude Code:

```
/plugin marketplace add <owner>/eng-policies
/plugin install eng-policies@eng-policies
```

الـ installer ما يكتب فوق أي ملف موجود. لو فيه تعارض ينكتب `*.policy-new` جنب الملف وتدمجه بيدك.

### 2. مشروع جديد

```bash
mkdir my-app && cd my-app && git init -b main
bash ~/eng-policies/install/install.sh . --mode new --dry-run   # كل ملف بينزل
bash ~/eng-policies/install/install.sh . --mode new
```

أو قل لـ Claude: "نبني مشروع جديد"، وسكل `new-project` يسألك عن الهدف والمستخدمين، يركب، يجهز GitHub وCloudflare بموافقتك، ويكتب PRD ثم architecture ثم stories، ويوقف قبل أي كود لين توافق.

بعدها (كل أمر dry-run افتراضيا، و`--apply` يطلب منك تكتب yes):

```bash
gh auth login
gh repo create <owner>/my-app --private --source . --remote origin --push
bash ~/eng-policies/install/github-setup.sh <owner>/my-app            # يعرض فقط
bash ~/eng-policies/install/github-setup.sh <owner>/my-app --apply
npx wrangler login
bash ~/eng-policies/install/cloudflare-setup.sh . --apply
```

الأسرار تحطها أنت بنفسك. السكربت يطبع الأوامر فقط (`gh secret set ...` و`wrangler secret put ...`) ولا يقرأ ولا يطبع أي قيمة.

### 3. مشروع موجود (adopt)

```bash
cd existing-app
bash ~/eng-policies/install/install.sh . --mode existing --dry-run
bash ~/eng-policies/install/install.sh . --mode existing
```

وضع `existing` يخلي lint و typecheck بـ `warn-only` ويسجل ذلك في `docs/adoption/PROGRESS.md`. التبني على وحدات صغيرة، كل وحدة PR: قل لـ Claude "نبني eng-policies على هذا المشروع" وسكل `adopt-existing` يمشي بالترتيب.

### 4. التحديث

```bash
git -C ~/eng-policies pull && git -C ~/eng-policies checkout <tag>
bash ~/eng-policies/install/update.sh .            # يعرض الخطة: update / conflict / missing / same
bash ~/eng-policies/install/update.sh . --apply    # فرع chore/eng-policies-<ver> + commit + PR
```

الملف اللي ما عدلته يتحدث. الملف اللي عدلته ما ينلمس، والنسخة الجديدة تنزل جنبه `*.policy-new`.

### 5. الإزالة

```bash
bash ~/eng-policies/install/install.sh --uninstall . --dry-run
bash ~/eng-policies/install/install.sh --uninstall .
```

يحذف فقط الملفات اللي ما تغيرت عن اللي نزّلها الـ installer، ويترك أي ملف عدلته.

## الإصدارات

`v1.0.0-alpha.N` ثم `beta` ثم `rc` ثم `v1.0.0`. المشاريع تستدعي `@v1` (وسم يتحرك مع كل إصدار 1.x)، وإصدارات ما قبل الاستقرار تثبت الوسم بالكامل (مثل `@v1.0.0-alpha.1`). الوسم `v1` ما ينشأ إلا مع `v1.0.0`.

لو الـ repo خاص: Settings > Actions > General > Access > Accessible from repositories in the owner account.

## حدود خطط GitHub

- الـ required reviewers على environment والـ environment secrets في repo خاص تحتاج GitHub Pro أو Team.
- CodeQL على repo خاص يحتاج GitHub Code Security.
- الـ ruleset يطلب موافقات `0` افتراضيا لأن المطور الفرد ما يقدر يوافق على PR نفسه. غيّرها بـ `--approvals 1` أول ما يصير معك شخص ثاني.

## الفحص الذاتي

`self-test.yml` يشغل: actionlint، shellcheck، اختبار الـ installer كامل بـ `gh` و`wrangler` وهميين (`bash test/e2e-installer.sh`)، وCI كامل على `examples/sample-app`.
