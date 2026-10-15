# Hướng dẫn sử dụng vibecode-anywhere

Repo: https://github.com/tsennguyen/vibecode-anywhere · [English README](../README.en.md)

**Công dụng:** code từ điện thoại. Một máy Ubuntu luôn bật (VPS thuê hoặc PC ở nhà) chạy AI agent (Antigravity CLI, Claude Code hoặc OpenAI Codex), còn bạn điều khiển agent đó từ điện thoại.

## Cần chuẩn bị
- **Máy tính chính:** macOS, Linux hoặc Windows (Windows cần [Git for Windows](https://git-scm.com/download/win)).
- **Host:** Ubuntu 22.04+ hoặc Debian 12+.

  | Nhu cầu | Cấu hình gợi ý |
  |---|---|
  | Chỉ sửa code, test nhẹ | 2 vCPU / 4 GB |
  | Có Docker, e2e | 4–6 vCPU / 8 GB |
  | Monorepo lớn | từ 16 GB |

- **Tài khoản agent** (ít nhất một):
  - **Antigravity:** tài khoản Google.
  - **Claude Code:** gói Pro / Max / Team / Enterprise. API key không dùng được cho điều khiển từ điện thoại.
  - **Codex:** tài khoản ChatGPT. Muốn điều khiển từ điện thoại theo cách chính thức thì phải có app ChatGPT desktop trên một máy Mac/Windows luôn bật.
- **Điện thoại:** app của agent và một app SSH (Termius).

## Bước 1. Trên máy chính: cấu hình và đóng gói
1. Clone repo:
   ```bash
   git clone https://github.com/tsennguyen/vibecode-anywhere && cd vibecode-anywhere
   ```
2. Tạo config bằng một trong hai cách:
   - Mở AI agent trong thư mục này, dán **Prompt 1** trong [`PROMPT.md`](../PROMPT.md). AI sẽ hỏi vài câu rồi tự tạo `config/hub.conf`.
   - Tự làm: `cp config/hub.example.conf config/hub.conf`, rồi sửa file đó.
3. Đóng gói:
   ```bash
   ./pack.sh
   ```
   Trên Windows: `powershell -ExecutionPolicy Bypass -File .\pack.ps1`
4. Lưu mật khẩu trong file `~/.vibecode-pass` vào điện thoại. Tải thư mục `~/vibecode-out` lên Drive riêng làm bản dự phòng.

> Nếu không có file `.env` hay việc chưa commit nào cần mang theo, bỏ qua bước 3–4 và dùng `./sync.sh --clone-only` ở bước 2.

## Bước 2. Trên host: cài đặt
1. Từ máy chính, gắn SSH key rồi chép bundle lên host:
   ```bash
   ssh-copy-id -p PORT USER@HOST
   scp -P PORT -r ~/vibecode-out USER@HOST:~/
   ```
2. Trên host:
   ```bash
   sudo apt-get install -y git
   git clone https://github.com/tsennguyen/vibecode-anywhere ~/vibecode-anywhere
   cd ~/vibecode-anywhere && ./bootstrap.sh
   ```
3. Thoát, SSH vào lại, rồi chạy:
   ```bash
   cd ~/vibecode-anywhere
   gh auth login --web --git-protocol https && gh auth setup-git
   ./sync.sh
   ./install-deps.sh
   ./remote.sh login
   ./remote.sh start
   ./doctor.sh
   ```

## Bước 3. Trên điện thoại
1. Mở agent bằng cùng tài khoản đã dùng trên host, rồi chọn máy:
   - **Antigravity:** https://antigravity.google.com
   - **Claude Code:** app Claude → Code
   - **Codex:** app ChatGPT → Codex
2. Dán **Prompt 2** trong [`PROMPT.md`](../PROMPT.md) để kiểm tra đọc, ghi và push.

## Khi gặp sự cố
SSH vào host, chạy `~/vibecode-anywhere/doctor.sh`, rồi làm theo mục được báo trong [`RESCUE.md`](RESCUE.md).

## Tài liệu chi tiết
- [`README.md`](../README.md): tiếng Việt
- [`README.en.md`](../README.en.md): tiếng Anh
- [`AGENTS-GUIDE.md`](AGENTS-GUIDE.md): hướng dẫn riêng từng agent

---
Tác giả: Nguyễn Việt Thành · [MIT License](../LICENSE)
