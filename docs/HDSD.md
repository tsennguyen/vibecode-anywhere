# Hướng dẫn sử dụng vibecode-anywhere

Repo: https://github.com/tsennguyen/vibecode-anywhere · [English README](../README.en.md)

**Công dụng:** code từ điện thoại. Một máy luôn bật chạy AI agent (Antigravity CLI, Claude Code hoặc OpenAI Codex), còn bạn điều khiển agent đó từ điện thoại. Máy đó có thể là:
- **VPS** chạy Ubuntu, hoặc
- **máy trạm, mini PC, laptop cắm sạc, Mac mini, Raspberry Pi** ở nhà, chạy Linux, macOS hoặc Windows.

## Cần chuẩn bị
- **Máy tính chính:** macOS, Linux hoặc Windows (Windows cần [Git for Windows](https://git-scm.com/download/win)).
- **Host (máy luôn bật):** xem cách chọn ở [HOSTS.md](HOSTS.md).

  | Nhu cầu | Cấu hình gợi ý |
  |---|---|
  | Chỉ sửa code, test nhẹ | 4 GB RAM (VPS rẻ, Raspberry Pi 5) |
  | Có Docker, e2e | 8 GB RAM |
  | Monorepo lớn | từ 16 GB |

- **Tài khoản agent** (ít nhất một):
  - **Antigravity:** tài khoản Google.
  - **Claude Code:** gói Pro / Max / Team / Enterprise. API key không dùng được cho điều khiển từ điện thoại.
  - **Codex:** tài khoản ChatGPT. Host là Mac hoặc Windows thì dùng app ChatGPT desktop (cách chính thức). Host là Linux thì cần một máy Mac/Windows mở host qua SSH, hoặc dùng SSH + tmux.
- **Điện thoại:** app của agent, app SSH (Termius). Máy ở nhà thì cài thêm Tailscale.

## Bước 1. Trên máy chính: cấu hình và đóng gói
1. Clone repo:
   ```bash
   git clone https://github.com/tsennguyen/vibecode-anywhere && cd vibecode-anywhere
   ```
2. Tạo config bằng một trong hai cách:
   - Mở AI agent trong thư mục này, dán **Prompt 1** trong [`PROMPT.md`](../PROMPT.md). AI sẽ hỏi vài câu (kể cả loại host, hệ điều hành) rồi tự tạo `config/hub.conf`.
   - Tự làm: `cp config/hub.example.conf config/hub.conf`, rồi sửa file đó.
3. Đóng gói: `./pack.sh` (Windows: `.\vibe.ps1 pack`).
4. Lưu mật khẩu trong file `~/.vibecode-pass` vào điện thoại. Tải thư mục `~/vibecode-out` lên Drive riêng làm bản dự phòng.

> Nếu không có file `.env` hay việc chưa commit nào cần mang theo, bỏ qua bước 3–4 và dùng `sync --clone-only` ở bước 2.

## Bước 2. Trên host: cài đặt
Chép thư mục `~/vibecode-out` sang host (qua `scp`, USB hoặc Drive), rồi làm theo hệ điều hành của host.

**Linux (VPS, máy trạm, mini PC, Pi) hoặc macOS (Mac mini...):**
```bash
git clone https://github.com/tsennguyen/vibecode-anywhere ~/vibecode-anywhere
cd ~/vibecode-anywhere && ./bootstrap.sh
```
Mở terminal hoặc phiên SSH mới, rồi chạy:
```bash
cd ~/vibecode-anywhere
gh auth login --web --git-protocol https && gh auth setup-git
./sync.sh && ./install-deps.sh
./remote.sh login && ./remote.sh start && ./doctor.sh
```

**Windows (máy trạm, mini PC, laptop):** mở PowerShell **thường** (không chọn Run as administrator), đăng nhập bằng đúng tài khoản sẽ chạy agent:
```powershell
winget install --id Git.Git -e          # xong thì mở cửa sổ PowerShell mới
git clone https://github.com/tsennguyen/vibecode-anywhere $HOME\vibecode-anywhere
cd $HOME\vibecode-anywhere
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1   # hỏi quyền Admin (UAC) một lần
```
Mở PowerShell mới, rồi chạy:
```powershell
cd $HOME\vibecode-anywhere
gh auth login --web --git-protocol https; gh auth setup-git
.\vibe.ps1 sync; .\vibe.ps1 install-deps
.\vibe.ps1 remote login; .\vibe.ps1 remote start; .\vibe.ps1 doctor
```

**Máy ở nhà (không phải VPS):** làm thêm các bước sau, chi tiết ở [HOSTS.md mục 4](HOSTS.md#4-danh-sách-kiểm-tra-cho-máy-ở-nhà-máy-trạm-mini-pc-laptop-mac-pi):
- BIOS: **Restore on AC Power Loss = Power On**. Mac đã được bootstrap chỉnh sẵn.
- Bật **tự đăng nhập**: Windows dùng Sysinternals Autologon; macOS vào Users & Groups → Automatically log in.
- Nếu dùng Claude: chạy `remote autostart claude`.
- Cài **Tailscale** để SSH từ điện thoại, không mở cổng modem.
- Thử rút điện, cắm lại, đợi 3 phút rồi xem điện thoại còn thấy máy không.

## Bước 3. Trên điện thoại
1. Mở agent bằng cùng tài khoản đã dùng trên host, rồi chọn máy:
   - **Antigravity:** https://antigravity.google.com
   - **Claude Code:** app Claude → Code
   - **Codex:** app ChatGPT → Codex
2. Dán **Prompt 2** trong [`PROMPT.md`](../PROMPT.md) để kiểm tra đọc, ghi và push.

## Khi gặp sự cố
SSH vào host, chạy `~/vibecode-anywhere/doctor.sh` (Windows: `.\vibe.ps1 doctor`), rồi làm theo mục được báo trong [`RESCUE.md`](RESCUE.md).

## Tài liệu chi tiết
- [`README.md`](../README.md): tổng quan
- [`HOSTS.md`](HOSTS.md): chọn và dựng host theo từng loại máy, hệ điều hành
- [`AGENTS-GUIDE.md`](AGENTS-GUIDE.md): hướng dẫn riêng từng agent
- [`RESCUE.md`](RESCUE.md): cứu hộ

---
Tác giả: Nguyễn Việt Thành · [MIT License](../LICENSE)
