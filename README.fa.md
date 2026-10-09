<div align="center" dir="rtl">

<img src="docs/assets/banner.svg" alt="projdump — کل پروژه را در یک فایل برای هوش مصنوعی بریز">

# 📦 projdump

**کل کدبیز شما. یک فایل. آمادهٔ هوش مصنوعی.**

پروج‌دامپ هر پروژه‌ای — درخت دایرکتوری، سورس‌ها و آمار — را در یک فایل واحد
Markdown، XML یا JSON می‌ریزد تا مستقیم در **Claude**، **ChatGPT**، **DeepSeek**،
**Gemini** یا هر مدل زبانی دیگری بیندازید.

[![CI](https://github.com/CheginiSoroush/projdump/actions/workflows/ci.yml/badge.svg)](https://github.com/CheginiSoroush/projdump/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![bash](https://img.shields.io/badge/bash-5.0%2B-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![tests](https://img.shields.io/badge/tests-84%20passing-2EA043)](test/)
[![shellcheck](https://img.shields.io/badge/shellcheck-clean-2EA043?logo=shell&logoColor=white)](.shellcheckrc)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![Docs](https://img.shields.io/badge/docs-live%20site-34D399?logo=githubpages&logoColor=white)](https://cheginisoroush.github.io/projdump/)
[![Try Online](https://img.shields.io/badge/try_it-in_your_browser-10B981?logo=googlechrome&logoColor=white)](https://cheginisoroush.github.io/projdump/#playground)

[English](README.md) · **فارسی**

</div>

---

> [!TIP]
> 🌐 **مستندات تعاملی و سازندهٔ دستور:** [cheginisoroush.github.io/projdump](https://cheginisoroush.github.io/projdump/)
>
> 🚀 راهنمای صفر تا صد انتشار در گیت‌هاب و جذب بازدید: [docs/GOING-LIVE.md](docs/GOING-LIVE.md)

## 🎬 ببینید چطور کار می‌کند

<div align="center">
<img src="docs/assets/demo.svg" alt="دموی متحرک پروج‌دامپ در ترمینال" width="760">
</div>

## 🤔 چرا؟

چت‌بات‌ها وقتی **کل تصویر** را ببینند هوشمندتر جواب می‌دهند. اما کپی‌کردن مخزن، پوشه‌به‌پوشه،
کند، پرخطا و کلافه‌کننده است. `projdump` این را با **یک دستور** حل می‌کند:

- 🌳 **درخت دایرکتوری**، همهٔ **فایل‌های سورس** با تگ زبان درست، به‌همراه **خلاصهٔ آماری**؛
- در **یک فایل** به اندازهٔ **بودجهٔ توکن** شما، در قالبی که مدل‌تان دوست دارد؛
- تولیدشده **۱۰۰٪ لوکال** — کد شما هرگز به سرور کسی نمی‌رود.

هیچ وابستگی‌ای فراتر از `bash`، `find` و `git` ندارد. ابزارهای `file`، `tree`، `jq` و
`python3` اگر نصب باشند استفاده و در نبودشان بی‌صدا رد می‌شوند.

## ✨ امکانات

- 🌳 درخت دایرکتوری — اگر `tree(1)` نصب باشد از آن، وگرنه از رندرکنندهٔ داخلی
- 🎨 تگ زبان برای بیش از ۱۲۰ پسوند فایل (هایلایت Markdown / XML)
- 🧩 `--ext-only sh,py` و `--exclude` و **`--include`** — هر دو قابل تکرار
- 📏 `--max-size` با مقایسهٔ دقیق در سطح بایت
- 🚫 تشخیص فایل باینری با مسیر سریع پسوندی (بدون فراخوانی `file(1)` برای رسانه‌ها)
- 🎯 سه قالب: **Markdown**، **XML** (بلوک‌های `<file>` مناسب Claude)، **JSON**
- 🔍 اجرای خشک با `--list` — دقیقاً ببینید چه چیزی دامپ می‌شد
- ✂️ `--since REF` — فقط تغییرات بعد از یک رفرنس گیت را دامپ کن
- 💰 `--tokens-budget N` — با رسیدن تخمین توکن به بودجه، افزودن فایل متوقف می‌شود
- 🔀 `--sort name|size|size-desc|ext` — کنترل ترتیب فایل‌ها
- 📝 `--note` — درج بلوک «یادداشت برای هوش مصنوعی» در ابتدای خروجی
- 🗂️ تفکیک زبان‌ها + جدول بزرگ‌ترین فایل‌ها در خلاصه
- 🌿 فرادادهٔ گیت در هدر (`main @ a1b2c3d (dirty)`)
- 📋 کپی خودکار در کلیپ‌بورد (`pbcopy` / `wl-copy` / `clip.exe` / `putclip` / `xclip` / `xsel`)
- 📊 خلاصه با تعداد فایل، خط، حجم و تخمین تقریبی توکن
- 🛡️ فنس امن و escape صحیح CDATA — دامپ هرگز خودش را خراب نمی‌کند
- ⚡ در مخازن گیت از `git ls-files` استفاده می‌کند؛ پس `.gitignore` رعایت می‌شود
- 🩺 `--verbose` — دلیل ردشدن هر فایل را دقیق توضیح می‌دهد
- 🌐 [سایت مستندات دوزبانه](https://cheginisoroush.github.io/projdump/) — سازندهٔ تعاملی دستور، جست‌وجوی ⌘/Ctrl+K (۴۹ نتیجه شامل همهٔ فلگ‌ها، دستورکارها و پیش‌تنظیم‌ها)، کتاب دستورکارهای آمادهٔ کپی (با دکمه‌های *کپی همه* و *دانلود ‎.sh*، دکمهٔ 🔗 کپی لینک برای هر دستورکار و لینک‌های عمیق ‎`?recipe=RX`‎ / ‎`#recipe=RX`‎ که دستورکار را هنگام باز شدن خودکار اجرا می‌کنند)، **زمین بازی با ترمینال شبیه‌سازی‌شده** (CLI را همین‌جا در مرورگر امتحان کنید، بدون نصب — **▶ نمایش** برای اجرای دست‌آزاد یا **⬇ گزارش** برای ذخیرهٔ نشست)، برگهٔ میان‌برهای صفحه‌کلید با ‎`?`‎، دانلود برگهٔ تقلب و ابزار تخمین توکن (انگلیسی + فارسی، تم تاریک/روشن)

## 🚀 شروع سریع

```bash
git clone https://github.com/CheginiSoroush/projdump.git
cd projdump
./install.sh
exec $SHELL          # یا: source ~/.bashrc
```

`install.sh` فایل `projdump.sh` را با symlink در `~/.local/bin` قرار می‌دهد (با
`--prefix /usr/local` قابل تغییر است) و تکمیل خودکار bash و zsh را نصب می‌کند. به‌جز فایل‌های
تکمیل خودکار چیزی کپی نمی‌شود؛ پس `git pull` نصب شما را به‌روز نگه می‌دارد.

> ▶ **عجله دارید؟** [پروج‌دامپ را در مرورگر امتحان کنید](https://cheginisoroush.github.io/projdump/#playground) —
> یک ترمینال شبیه‌سازی‌شده با همان فلگ‌ها و همان شکل خروجی، بدون هیچ نصبی.

## 🎯 نحوهٔ استفاده

```bash
cd ~/my-project

projdump                              # → my-project_dump.md
projdump -o out.md                    # نام دلخواه خروجی
projdump --no-tree                    # بدون درخت دایرکتوری
projdump -e sh,bats                   # فقط فایل‌های شل
projdump -x 'test/*' -x '*.min.js'    # ردکردن مسیرها (قابل تکرار)
projdump -i 'src/*' -i 'docs/*'       # فقط این مسیرها
projdump --since HEAD~5               # فقط تغییرات اخیر
projdump --tokens-budget 60000        # جا شدن در پنجرهٔ کانتکست
projdump --sort size-desc             # بزرگ‌ترین فایل‌ها اول
projdump --list                       # پیش‌نمایش فهرست فایل‌ها
projdump --note 'باگ‌های امنیتی احراز هویت را بررسی کن'
projdump --max-size 100               # ردکردن فایل‌های بالای ۱۰۰ کیلوبایت
projdump --format xml                 # XML برای Claude
projdump --format json                # JSON (مناسب jq)
projdump --stdout | pbcopy            # مستقیم به کلیپ‌بورد
projdump -v                           # توضیح فایل‌های ردشده
projdump -q                           # بی‌صدا: بدون خط خلاصه
```

> 💡 **نمی‌دانید کدام فلگ‌ها را لازم دارید؟** در
> [سازندهٔ دستور](https://cheginisoroush.github.io/projdump/#builder) دستورتان را بسازید،
> از [کتاب دستورکارها](https://cheginisoroush.github.io/projdump/#cookbook) یک گردش‌کاری آماده کپی کنید،
> یا در سایت مستندات `Ctrl+K` را بزنید تا همهٔ فلگ‌ها را جست‌وجو کنید — و همان‌جا
> [برگهٔ تقلب](https://cheginisoroush.github.io/projdump/#options) را هم دانلود کنید.

<details>
<summary><b>🔧 فهرست کامل گزینه‌ها</b></summary>

| فلگ | توضیح |
|---|---|
| `[output]`، `-o, --output FILE` | فایل خروجی (پیش‌فرض: `<project>_dump.<ext>`) |
| `-f, --format md\|xml\|json` | قالب خروجی (پیش‌فرض `md`) |
| `-e, --ext-only sh,md` | فقط این پسوندها (بی‌توجه به بزرگی/کوچکی حروف) |
| `-x, --exclude GLOB` | ردکردن مسیرهای منطبق، قابل تکرار |
| `-i, --include GLOB` | فقط مسیرهای منطبق، قابل تکرار |
| `--since REF` | فقط فایل‌های تغییرکرده از یک رفرنس گیت (+ فایل‌های untracked) |
| `--sort KEY` | `name` (پیش‌فرض)، `size`، `size-desc`، `ext` |
| `--tokens-budget N` | توقف افزودن فایل پس از رسیدن به ~N توکن |
| `--max-size N` | ردکردن فایل‌های بزرگ‌تر از N کیلوبایت (پیش‌فرض `500`) |
| `--no-tree` | عدم درج درخت دایرکتوری |
| `--note TEXT` | افزودن بلوک «یادداشت برای هوش مصنوعی» در ابتدای خروجی |
| `--list` | اجرای خشک: چاپ فهرست و خروج |
| `--stdout` | نوشتن به stdout به‌جای فایل |
| `--copy` / `--no-copy` | اجبار / غیرفعال‌سازی کپی در کلیپ‌بورد |
| `-v, --verbose` | توضیح فایل‌های ردشده روی stderr |
| `-q, --quiet` | چاپ نکردن خط خلاصه |
| `--version` | نمایش نسخه |
| `-h, --help` | نمایش راهنما |

</details>

<details>
<summary><b>📤 قالب‌های خروجی</b></summary>

**Markdown** — خوانا برای انسان، با آمار هر فایل، تفکیک زبان‌ها و جدول خلاصه.

````markdown
# 📦 my-project — Project Dump

**Generated:** 2026-10-08 12:00:00 UTC
**Path:** `/home/you/my-project`
**Git:** `main @ a1b2c3d (clean)`
...

## 📄 Source Files

### `src/main.py`

```python
print("hello")
```

<sub>1 lines · 19B</sub>

---

## 📊 Summary

| Files | Lines | Size |
|---:|---:|---:|
| 1 | 1 | 19B |

> Roughly 5 tokens (bytes ÷ 3.5)

### 🗂️ Languages

| Language | Files | Lines | Size |
|---|---:|---:|---:|
| python | 1 | 1 | 19B |
````

**XML** — بلوک‌های `<file>` مناسب Claude همراه با CDATA:

```xml
<project name="my-project" path="/home/you/my-project" generated="2026-10-08T12:00:00Z" tool="projdump v1.1.0" git="main @ a1b2c3d (clean)">
  <file path="src/main.py" lang="python" lines="1" bytes="19">
    <![CDATA[
print("hello")
    ]]>
  </file>
  <stats files="1" lines="1" bytes="19" tokens="5">
    <language name="python" files="1" lines="1" bytes="19"/>
  </stats>
</project>
```

**JSON** — سازگار با jq، محتوای بایت‌به‌بایت یکسان (خط پایانی حفظ می‌شود):

```json
{"project":"my-project","files":[{"path":"src/main.py","lang":"python","lines":1,"bytes":19,"content":"print(\"hello\")\n"}],"stats":{"files":1,"lines":1,"bytes":19,"tokens":5,"languages":{"python":{"files":1,"lines":1,"bytes":19}}}}
```

</details>

## ⚠️ نکته دربارهٔ فایل‌های خروجی

فایلی که در حال نوشته‌شدن است همیشه کنار گذاشته می‌شود (حتی در زیرپوشه‌ها) و
`*_dump.md|xml|json` در `.gitignore` همین پروژه هست. اگر با **نام سفارشی** دامپ بگیرید
(`projdump notes.md`)، آن فایل یک فایل معمولی پروژه حساب می‌شود و دامپِ *بعدی* آن را
شامل می‌شود — آن را به `.gitignore` اضافه کنید یا از `--exclude 'notes.md'` استفاده کنید.

## 🧪 تست

```bash
git clone --depth 1 https://github.com/bats-core/bats-core.git
bats-core/bin/bats test/          # لازم است: file (اختیاری: tree، jq، shellcheck)
```

**۸۴ تست کاربردی** هر سه قالب، نام‌های فایل متخاصم (گیومه، خط جدید، بک‌تیک، `<>&`)،
حالت مرزی escaping در بش ۵٫۲ و دقت بایتیِ همهٔ فیلترها را پوشش می‌دهد.

## 🤝 مشارکت

ایسو و پول‌ریکوئست خوش‌آمد است — قوانین سبک‌نویسی (بدون خطای shellcheck، تست bats برای
هر رفتار) و نقشهٔ راه در [CONTRIBUTING.md](CONTRIBUTING.md).

## 🗑️ حذف نصب

```bash
./uninstall.sh        # یا: ./install.sh --uninstall
```

## 📄 مجوز

MIT — ببینید [LICENSE](LICENSE)

<div align="center" dir="rtl">
<sub>ساخته‌شده با بش و کمی لجبازی 🔒 ۱۰۰٪ لوکال اجرا می‌شود — بدون هیچ تلمتری.</sub>
</div>
