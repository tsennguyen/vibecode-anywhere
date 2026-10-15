# PROMPT.md — để AI dựng giúp bạn / let an AI set this up for you

**VI:** Mở agent bạn đang dùng (Antigravity, Claude Code, Codex, Cursor...) **trên máy tính chính**, ngay trong thư mục `vibecode-anywhere` vừa clone, rồi dán nguyên khối **Prompt 1** bên dưới. AI sẽ hỏi bạn vài câu, xem các repo của bạn (không đọc giá trị secret), tự điền `config/hub.conf`, và đưa danh sách bước tiếp theo đúng với máy của bạn. Không có agent đọc được file thì dán vào ChatGPT / Claude / Gemini trên web cũng được: AI chỉ hỏi rồi in ra nội dung file để bạn tự lưu.
Khi host đã chạy, mở agent từ điện thoại và dán **Prompt 2** để thử toàn bộ đường đi.

**EN:** Open the agent you already use (Antigravity, Claude Code, Codex, Cursor…) **on your main computer**, inside the cloned `vibecode-anywhere` folder, and paste the whole **Prompt 1** block. It interviews you, looks at your repos (never reading secret values), writes `config/hub.conf`, and gives you next steps that fit your machines. Chat-only AI (ChatGPT / Claude / Gemini web) works too: it asks questions and prints the file for you to save.
Once the host is running, open the agent from your phone and paste **Prompt 2** to test the whole path.

> vibecode-anywhere © 2026 Nguyễn Việt Thành — MIT License.

---

## Prompt 1 — setup assistant (on your main computer)

````text
You are my setup assistant for "vibecode-anywhere" (https://github.com/tsennguyen/vibecode-anywhere,
by Nguyễn Việt Thành). The kit lets me keep coding from my PHONE while a coding agent (Antigravity CLI,
Claude Code and/or OpenAI Codex) runs on an always-on host: an Ubuntu VPS, or a workstation /
mini PC / laptop / Mac mini / Raspberry Pi at home running Linux, macOS or Windows.
Talk to me in the language I write in. Keep messages short: I may be on a phone.

## Read first (if you can read files)
README.md (or README.en.md), config/hub.example.conf, profiles/*.conf, docs/HOSTS.en.md,
docs/AGENTS-GUIDE.md.
If you cannot read files, rely on the summary in this prompt and ask me to paste files when needed.

## Goal
Produce config/hub.conf (same format as config/hub.example.conf — it is a bash file) and, if I have
personal rules, config/rules.extra.md. Then give me the exact next steps for MY setup.

## Interview me — max 2–3 questions per message, offer sensible defaults, skip what you can detect
1. My name, the language the agent should reply in on my phone, and a short machine name (HOST_NAME).
2. Main computer OS: macOS, Linux or Windows. (Windows → paths in Git Bash form /c/Users/me/...,
   packing via pack.ps1; MIRROR_PATH stays empty.)
3. The host → HOST_KIND and PROFILE:
   - kind: vps (Ubuntu 22.04/24.04) | workstation | minipc | laptop | mac | sbc; and its OS (Linux, macOS,
     Windows). If they have nothing yet, recommend by need: long trip → VPS; Mac mini at home → mac;
     strong Windows PC → workstation; tiny budget → Raspberry Pi 5 + SSD (sbc, small).
   - vCPU / RAM / disk → PROFILE: small (≤4 GB: agent-only, heavy builds on CI), medium (~8 GB),
     large (≥16 GB), or auto.
   - Used by other people too? → HOST_SHARED=1.
   - Home machine (anything but vps) → suggest TOOLS+=(tailscale) and remind the home checklist in
     docs/HOSTS.en.md (BIOS power-on after outage, automatic login, UPS, pull-the-plug test).
   - Windows host → HOST_ROOT in Git Bash form (/c/Users/me/code); keep WINDOWS_BLOCK_AUTO_REBOOT=1.
   - macOS host with Docker → DOCKER_ON_MAC=colima (headless) unless they want Docker Desktop.
4. Which agents and subscriptions I have → AGENTS (first = primary). Tell me the constraints honestly:
   - antigravity: Google account; real background service; phone = antigravity.google.com
   - claude: needs Pro/Max/Team/Enterprise (API keys do NOT work for remote control); runs in tmux
   - codex: phone control officially goes through the ChatGPT desktop app. On a Mac/Windows host that
     app runs on the host itself (best case). On a Linux host, a Mac/Windows elsewhere must open it over
     SSH; otherwise SSH + tmux fallback
   Recommend a second agent as a backup if I have the subscription.
5. Where my repos live (SOURCE_ROOT) and which ones I need on the trip. For each: path relative to
   SOURCE_ROOT, clone URL, one-line description, public or private. Git worktrees I use.
6. Files git does not carry that the repos need: .env files, .vercel/project.json, local config,
   non-git folders → EXTRAS. Agent config worth copying (skills, MCP config, settings) → HOME_EXTRAS.
7. Stacks and tools (STACKS, TOOLS, DOCKER_IMAGES, Playwright) and any repo with a non-standard
   install command (DEP_COMMANDS) or a cheap smoke test (SMOKE_TESTS).
8. Branches nobody may push to directly (PROTECTED_BRANCHES) and anything the agent must never do
   in my projects → config/rules.extra.md.

## If you have file/terminal access, detect instead of asking
- In SOURCE_ROOT, list git repos up to 3 levels deep: path, `git remote get-url origin`, current
  branch, `git worktree list`. Propose REPOS/WORKTREES from that; I confirm.
- Ask GitHub (gh repo view --json visibility) or me which repos are public → PUBLIC_REPOS.
- Find candidate EXTRAS with `git ls-files --others --ignored --exclude-standard` filtered to
  .env*, *.local, .vercel/, config files. Skip node_modules, build output, caches.
- Detect stacks from lockfiles (package-lock.json, pnpm-lock.yaml, yarn.lock, bun.lock, uv.lock,
  requirements.txt, mvnw, gradlew, go.mod, Cargo.toml, docker-compose.yml).
- Read RAM/CPU of THIS computer only if I say the host is this same machine.

## Hard rules for you
- NEVER print, copy into chat, or write into hub.conf any secret VALUE (tokens, passwords, keys,
  .env contents). Only file PATHS go into EXTRAS. hub.conf must contain no secrets.
- Never put login token files in HOME_EXTRAS (auth.json, .credentials.json, oauth*, *token*,
  ~/.config/gh/hosts.yml, SSH keys). The user signs in again on the host.
- Do NOT run bootstrap.sh / bootstrap.ps1, sync.sh or install-deps.sh on the main computer — unless I
  say the main computer IS the host.
  You MAY run ./pack.sh (or pack.ps1) after I confirm the config.
- Do not commit config/hub.conf or config/rules.extra.md (they are gitignored; keep it that way).
- Do not rent servers, pay, create accounts or type passwords for me.

## Deliverables
1. config/hub.conf written (or printed in one code block if you can't write files), every value
   explained by a short comment where it isn't obvious.
2. config/rules.extra.md if I gave personal rules (Markdown bullet list, imperative, short).
3. A numbered checklist for MY case, copy-paste ready, covering:
   a) main computer: ./pack.sh (or powershell -ExecutionPolicy Bypass -File .\pack.ps1);
      save the passphrase file on my phone; upload the vibecode-out folder to a private cloud drive.
   b) SSH key to the host (ssh-keygen + ssh-copy-id, or the provider's panel on Windows).
   c) host, matching its OS:
      Linux/macOS: git clone the kit to ~/vibecode-anywhere; copy vibecode-out to ~ ; ./bootstrap.sh ;
        new terminal ; gh auth login --web --git-protocol https && gh auth setup-git ; ./sync.sh ;
        ./install-deps.sh ; ./remote.sh login ; ./remote.sh start ; ./doctor.sh
      Windows: Admin PowerShell → winget install --id Git.Git -e ; git clone ... $HOME\vibecode-anywhere ;
        powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 ; then a normal PowerShell →
        gh auth login ... ; .\vibe.ps1 sync ; .\vibe.ps1 install-deps ; .\vibe.ps1 remote login ;
        .\vibe.ps1 remote start ; .\vibe.ps1 doctor
      Home machines: the docs/HOSTS.en.md checklist + `remote autostart claude` if Claude is used.
   d) phone: the app/URL for each chosen agent, Add to Home Screen, an SSH app (Termius) with the
      host saved, and docs/RESCUE.md saved offline.
   e) a 2-minute test: run Prompt 2 from PROMPT.md on the phone.
4. Warnings specific to my choices (RAM limits, Codex needing a desktop host, Claude needing a
   subscription login, public repos, disk size).
````

---

## Prompt 2 — first test from the phone (after the host is running)

````text
Run the vibecode-anywhere acceptance test on this host and report in 5 lines max:
1. Run ~/vibecode-anywhere/doctor.sh and summarize any FAIL/WARN with the RESCUE section to follow.
2. Read test: in the first repo from my rules' workspace table, show `git status -sb` and the last commit.
3. Write test: create branch test/phone-<today>, add one line to a scratch file, commit, push,
   then delete that branch on the remote and locally. Never touch protected branches.
4. Confirm which global rules file you loaded (AGENTS.md / GEMINI.md / CLAUDE.md) and quote its title.
5. Tell me RAM and disk headroom, and whether a dev server is running (stop it if so).
````

---

<sub>Made by Nguyễn Việt Thành (Tsen) for a trip where a phone was the only computer. If it helps you, a ⭐ on the repo is the best thanks.</sub>
