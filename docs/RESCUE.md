# Cứu hộ từ điện thoại

Dùng khi agent trên điện thoại không làm việc được nữa. Chuẩn bị sẵn trên điện thoại: app SSH (**Termius** iOS/Android, **Blink** iOS, **JuiceSSH** Android) đã thêm host, và mật khẩu giải mã bundle trong trình quản lý mật khẩu.

Thay `~/vibecode-anywhere` bằng chỗ anh/chị clone repo, `my-vps` bằng `HOST_NAME`, `~/code` bằng `HOST_ROOT`.


> **Host Windows:** SSH vào sẽ mở Git Bash (do `bootstrap.ps1` cài), các lệnh dưới gõ được y nguyên; hoặc dùng PowerShell `.\vibe.ps1 doctor`. Không có tmux: Claude chạy trong cửa sổ thu nhỏ, khởi động lại bằng `~/vibecode-anywhere/remote.sh start claude`. Thay `free`/`ps` ở §3 bằng `~/vibecode-anywhere/doctor.sh`. Mất kết nối sau khi mất điện: kiểm tra Autologon và BIOS "Restore on AC power loss".
>
> **Host macOS:** giống Linux (có tmux qua Homebrew). Sau khi reboot mà agent không lên: kiểm tra đã bật **tự đăng nhập** chưa (System Settings → Users & Groups). Codex: mở lại app ChatGPT.
>
> **Máy ở nhà:** SSH qua Tailscale (`tailscale ip -4` để lấy địa chỉ); router hoặc điện ở nhà có vấn đề thì phải nhờ người ở nhà bật lại.

## 0. Không biết lỗi gì → chạy cái này trước
```bash
~/vibecode-anywhere/doctor.sh
```
Dòng **FAIL/WARN** nào thì làm theo mục `§` ghi ở cuối dòng đó.

## 1. Điện thoại không thấy máy / phiên
**Antigravity:**
```bash
agy remote-control status
agy remote-control start --name my-vps
journalctl --user -u antigravity-cli-daemon -n 40 --no-pager
```
Log báo lỗi đăng nhập thì chạy `agy`, mở link trên điện thoại, dán mã, gõ `/exit`, rồi `start` lại.

**Claude Code:**
```bash
tmux ls
~/vibecode-anywhere/remote.sh start claude
tmux attach -t claude-rc          # xem nó báo gì; thoát: Ctrl+b rồi d
```
Báo "requires a claude.ai subscription": đang dùng API key → `unset ANTHROPIC_API_KEY`, chạy `claude` → `/login`.

**Codex:** `~/vibecode-anywhere/remote.sh start codex`, rồi vào bằng app ChatGPT desktop hoặc `tmux attach -t codex`.

## 2. Daemon hỏng hẳn → chạy agent trong tmux
```bash
tmux new -As agent
cd ~/code && agy --remote-control        # hoặc: claude remote-control --name my-vps   |   codex
```
Agent in ra link → mở trên điện thoại. Muốn rời Termius mà giữ phiên: **Ctrl+b**, thả ra, bấm **d**. Lần sau vào lại: `tmux attach -t agent`.

## 3. Máy chậm, treo, hết RAM
```bash
free -h && ps -eo rss,comm --sort=-rss | head -6
pkill -f "next dev"; pkill -f "vite"; pkill -f "turbo run dev"; pkill -f playwright; docker ps -q | xargs -r docker stop
```

## 4. Hết ổ đĩa
```bash
df -h / && du -sh ~/.cache ~/code/* 2>/dev/null | sort -h | tail -8
docker system prune -af; npm cache clean --force; pnpm store prune; rm -rf ~/.cache/pip ~/.cache/ms-playwright/*/
```
(Cài lại Playwright sau bằng `install-deps.sh` nếu cần.)

## 5. Lưu toàn bộ việc lên GitHub ngay (trước khi làm gì liều)
```bash
~/vibecode-anywhere/save-all.sh
```
Có thay đổi trên nhánh được bảo vệ (`PROTECTED_BRANCHES`) thì chuyển sang nhánh mới `wip/rescue-<giờ>`, không bao giờ đẩy thẳng lên nhánh chính, không bao giờ force.

## 6. Chưa đăng nhập GitHub / push bị từ chối / Codex mất đăng nhập
```bash
gh auth login --web --git-protocol https && gh auth setup-git
codex login --device-auth
```
Cả hai in link + mã → mở trên điện thoại.

## 7. Agent dự phòng
Cài sẵn agent thứ hai (`AGENTS=(antigravity claude)`) để agent chính hỏng thì còn cái khác: `~/vibecode-anywhere/remote.sh start claude`.

## 8. VPS sắp hết hạn / bị khoá
Gia hạn ở trang nhà cung cấp. Trước đó chạy §5. Máy hết hạn mà chưa gia hạn thì có thể bị xoá, không khôi phục được.

## 9. Máy mất sạch → dựng lại (~45 phút)
Thuê máy mới, làm lại README mục "Dựng host". Code ở GitHub, secret ở bản sao `vibecode-out` trên Drive, mật khẩu trong điện thoại.

## Không bao giờ gõ
`reboot` / `shutdown` (trừ khi chắc máy tự lên lại), `agy remote-control stop`, `ufw enable`, sửa `/etc/ssh/sshd_config`, `rm -rf ~/code`, `git push --force`. Mấy lệnh này làm mất đường vào máy hoặc mất code.

---
<sub>[vibecode-anywhere](https://github.com/tsennguyen/vibecode-anywhere) — © 2026 Nguyễn Việt Thành, MIT.</sub>
