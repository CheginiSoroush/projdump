# 🚀 GOING LIVE — Zero to 100 on GitHub Pages

> A complete, copy-paste guide to publishing this project — and actually getting traffic.
>
> **راهنمای فارسی:** پایین همین صفحه — [نسخهٔ فارسی](#-نسخهٔ-فارسی--راهنمای-کامل-انتشار-و-جذب-بازدید)

---

## English

### 1 · Prepare (one minute)

You need: a [GitHub account](https://github.com/signup), `git` installed, and this repository folder.

```bash
git --version          # any modern version works
cd projdump            # the project root (contains docs/, README.md, …)
```

### 2 · Create the repository

1. Go to **github.com/new**
2. Repository name: `projdump`
3. Visibility: **Public** (required for free GitHub Pages)
4. Description: `Dump an entire project into one file for Claude, ChatGPT, DeepSeek, Gemini — pure bash, zero deps`
5. **Do not** tick "Add a README" (you already have one — avoids a merge conflict)
6. Click **Create repository**

### 3 · Push the project (first upload)

GitHub shows you the commands after creating the repo, but here is the full sequence:

```bash
cd projdump
git init
git add -A
git commit -m "feat: projdump v1.1.0 — CLI, tests, docs site, bilingual README"
git branch -M main
git remote add origin https://github.com/<USERNAME>/projdump.git
git push -u origin main
```

> 💡 If you use **SSH**, the remote URL is `git@github.com:<USERNAME>/projdump.git`.
> 💡 Every future change is just: `git add -A && git commit -m "…" && git push`

### 4 · Turn on GitHub Pages (the docs site)

This repository ships a **finished static site in `/docs`** — no build step needed:

1. Repo → **Settings** → **Pages** (left sidebar)
2. **Source** → `Deploy from a branch`
3. **Branch** → `main`, **Folder** → `/docs`
4. **Save** — wait up to 1–2 minutes
5. Your site: `https://<USERNAME>.github.io/projdump/`

Prefer CI? Add `.github/workflows/pages.yml`:

```yaml
name: pages
on:
  push: { branches: [main] }
permissions: { contents: read, pages: write, id-token: write }
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: { name: github-pages, url: ${{ steps.deployment.outputs.page_url }} }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with: { path: docs }
      - id: deployment
        uses: actions/deploy-pages@v4
```

(With Actions, set Pages source to **GitHub Actions** instead of the branch.)

### 5 · Optional: custom domain + HTTPS

1. Buy a domain (any registrar).
2. Create `docs/CNAME` containing exactly one line: `yourdomain.com` — commit & push.
3. In your DNS provider add **one** of:
   - `CNAME` record: `www` (or apex) → `<USERNAME>.github.io`
   - or 4 `A` records for the apex → `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`
4. Repo → Settings → Pages → Custom domain: enter it, wait for the DNS check, then tick **Enforce HTTPS**.

### 6 · SEO & share cards (once, 10 minutes)

- ✅ The site already ships: meta description, Open Graph, Twitter cards, JSON-LD, `sitemap.xml`, `robots.txt`.
- Register the live URL in [Google Search Console](https://search.google.com/search-console) and [Bing Webmaster Tools](https://www.bing.com/webmasters); submit `sitemap.xml`.
- Repo → **Settings → Social preview** → upload `docs/assets/og-image.png` (1200×630 — ready-made).
- Add topics on the repo page: `bash` `cli` `llm` `chatgpt` `claude` `deepseek` `developer-tools` `prompt-engineering` `context-window` `codebase` `ai-tools` `dotfiles`
- About description + website link: set the Pages URL.

### 7 · Growth playbook — getting traffic 🚦

| Channel | What to post | Why it works |
|---|---|---|
| **README polish** | Animated banner ✓ badges ✓ GIF-style SVG demo ✓ (already done in this repo) | GitHub Trending & humans both judge in 3 seconds |
| **Hacker News** | "Show HN: Projdump – dump a codebase into one file for LLMs" — Tue–Thu, 8–10 AM US Eastern | Highest ceiling for dev tools |
| **Reddit** | r/commandline, r/bash, r/LocalLLaMA, r/ChatGPTCoding — story-first, link in body | Friendly CLI audiences |
| **Dev article** | dev.to / Hashnode / Medium: “I built a tool that fits any repo into one prompt” | Long-tail Google traffic |
| **Awesome lists** | PR into `awesome-bash`, `awesome-cli-apps`, `awesome-chatgpt`, `awesome-llm` | Evergreen referral clicks |
| **Product Hunt** | Launch with OG image + 30-second demo video | Broad maker audience |
| **X / Twitter / LinkedIn** | Short screen-recording of the terminal + repo link | Fast feedback loop |
| **Q&A sites** | Answer “how do I paste a repo into ChatGPT?” questions on Stack Overflow / Quora | High-intent searchers |
| **GitHub Trending** | Needs: clean README, topics, releases with notes, stars spike in first days — everything above feeds this | Compounding discovery |

**Cadence that works:** launch post (HN or Reddit) → 48 h later the dev.to article → 1 week later Product Hunt → keep answering every comment.

### 8 · Measure & iterate

- Repo → **Insights → Traffic**: views, clones, referrers (free, built-in).
- Add a privacy-friendly page counter (GoatCounter, Plausible, Umami) — one `<script>` tag in `docs/index.html`.
- Pin an issue named **Roadmap**; contributors need direction.
- Cut releases with notes — every release is a fresh excuse for attention.

### 9 · Final checklist

- [ ] Repo pushed, CI badge green
- [ ] Pages live at `https://<USERNAME>.github.io/projdump/`
- [ ] Social preview uploaded, topics added, description set
- [ ] URL submitted to Search Console, sitemap submitted
- [ ] Launch post published (HN / Reddit), article scheduled
- [ ] Roadmap issue pinned

---

## 🇮🇷 نسخهٔ فارسی — راهنمای کامل انتشار و جذب بازدید

### ۱ · آماده‌سازی (یک دقیقه)

به این‌ها نیاز دارید: یک [حساب گیت‌هاب](https://github.com/signup)، نصب‌بودن `git` و همین پوشهٔ پروژه.

```bash
git --version
cd projdump            # ریشهٔ پروژه (شامل docs/ و README ها)
```

### ۲ · ساخت مخزن (Repository)

1. به **github.com/new** بروید
2. نام: `projdump`
3. سطح دسترسی: **Public** (برای Pages رایگان الزامی است)
4. توضیحات: `Dump an entire project into one file for Claude, ChatGPT, DeepSeek, Gemini — pure bash, zero deps`
5. تیک «Add a README» را **نزنید** (خودتان README دارید تا تداخل پیش نیاید)
6. **Create repository** را بزنید

### ۳ · اولین آپلود (push)

```bash
cd projdump
git init
git add -A
git commit -m "feat: projdump v1.1.0 — CLI, tests, docs site, bilingual README"
git branch -M main
git remote add origin https://github.com/<USERNAME>/projdump.git
git push -u origin main
```

> 💡 با SSH نشانی به شکل `git@github.com:<USERNAME>/projdump.git` می‌شود.
> 💡 از این به بعد فقط: `git add -A && git commit -m "…" && git push`

### ۴ · روشن‌کردن GitHub Pages (سایت مستندات)

این مخزن یک **سایت استاتیک کامل داخل پوشهٔ `/docs`** دارد — بدون نیاز به بیلد:

1. در مخزن: **Settings** → **Pages**
2. **Source** را روی `Deploy from a branch` بگذارید
3. شاخهٔ `main` و پوشهٔ **`/docs`** را انتخاب و **Save** کنید
4. یک تا دو دقیقه صبر کنید
5. سایت شما: `https://<USERNAME>.github.io/projdump/`

اگر CI را ترجیح می‌دهید، فایل `.github/workflows/pages.yml` را مطابق نمونهٔ انگلیسیِ بالای همین صفحه بسازید و در Pages گزینهٔ **GitHub Actions** را انتخاب کنید.

### ۵ · اختیاری: دامنهٔ اختصاصی + HTTPS

1. یک دامنه بخرید.
2. فایل `docs/CNAME` بسازید که فقط یک خط دارد: `yourdomain.com` — کامیت و push کنید.
3. در پنل DNS یکی از این دو:
   - رکورد `CNAME` → `<USERNAME>.github.io`
   - یا چهار رکورد `A` → `185.199.108.153` تا `185.199.111.153`
4. در Settings → Pages دامنه را وارد کنید و بعد از تأیید DNS، تیک **Enforce HTTPS** را بزنید.

### ۶ · سئو و کارت اشتراک‌گذاری (ده دقیقه، فقط یک‌بار)

- ✅ سایت همین حالا متا‌تگ‌ها، Open Graph، Twitter Card، JSON-LD، `sitemap.xml` و `robots.txt` دارد.
- نشانی سایت را در [Google Search Console](https://search.google.com/search-console) و [Bing Webmaster](https://www.bing.com/webmasters) ثبت و `sitemap.xml` را معرفی کنید.
- در مخزن: **Settings → Social preview** → فایل `docs/assets/og-image.png` را آپلود کنید.
- تاپیک‌ها را اضافه کنید: `bash` `cli` `llm` `chatgpt` `claude` `deepseek` `developer-tools` `prompt-engineering` `ai-tools`

### ۷ · کتاب‌بازی رشد — چطور بازدید زیاد شود؟ 🚦

| کانال | چه چیزی منتشر کنیم | چرا جواب می‌دهد |
|---|---|---|
| **README حرفه‌ای** | بنر متحرک ✓ بج‌ها ✓ دموی متحرک ✓ (همین حالا آماده است) | ترندینگ گیت‌هاب و آدم‌ها هر دو در ۳ ثانیه قضاوت می‌کنند |
| **هکرنیوز** | عنوان «Show HN: Projdump – dump a codebase into one file for LLMs» — سه‌شنبه تا پنجشنبه، ۸–۱۰ صبح به وقت شرق آمریکا | سقف بازدید برای ابزارهای برنامه‌نویسی |
| **ردیت** | r/commandline ،r/bash ،r/LocalLLaMA ،r/ChatGPTCoding — اول داستان، لینک در متن | مخاطب رفاقتیِ ابزارهای خط فرمان |
| **مقاله** | dev.to / Hashnode / Medium: «ابزاری ساختم که هر مخزنی را در یک پرامپت جا می‌دهد» | ترافیک بلندمدت گوگل |
| **لیست‌های Awesome** | پول‌ریکوئست به awesome-bash ،awesome-cli-apps ،awesome-chatgpt | کلیک ارجاعی همیشگی |
| **Product Hunt** | لانچ با تصویر OG و ویدیوی ۳۰ ثانیه‌ای | مخاطب عام سازندگان |
| **شبکه‌های اجتماعی** | ضبط کوتاه صفحه از ترمینال + لینک مخزن | بازخورد سریع |
| **سایت‌های پرسش‌وپاسخ** | پاسخ به سؤال «چطور یک مخزن را به ChatGPT بدهم؟» در Stack Overflow / Quora | جویندگانِ هدفمند |
| **ترندینگ گیت‌هاب** | پیش‌نیازها: README تمیز، تاپیک، ریلیزِ با توضیحات، استارِ هفتهٔ اول | کشفِ تصاعدی |

**تق‌زمانی پیشنهادی:** روز اول پست لانچ (HN یا ردیت) → ۴۸ ساعت بعد مقالهٔ dev.to → یک هفته بعد Product Hunt → و پاسخ به تک‌تک کامنت‌ها.

### ۸ · اندازه‌گیری و بهبود

- در مخزن: **Insights → Traffic** — بازدید، کلون و منابع ارجاع (رایگان و داخلی).
- یک شمارندهٔ محترمانه (GoatCounter / Plausible / Umami) با یک تگ به `docs/index.html` اضافه کنید.
- یک ایسوی **Roadmap** پین کنید؛ مشارکت‌کننده جای مشخص را دوست دارد.
- مرتب ریلیز با توضیحات بدهید؛ هر ریلیز بهانه‌ای تازه برای دیده‌شدن است.

### ۹ · چک‌لیست نهایی

- [ ] مخزن push شده و بج CI سبز است
- [ ] سایت روی `https://<USERNAME>.github.io/projdump/` بالاست
- [ ] Social preview آپلود، تاپیک‌ها و توضیحات مخزن ثبت شده‌اند
- [ ] نشانی در Search Console ثبت و sitemap معرفی شده است
- [ ] پست لانچ منتشر شده و مقالهٔ بعدی برنامه‌ریزی شده است
- [ ] ایسوی Roadmap پین شده است

---

*MIT © Soroush Chegini — projdump documentation*
