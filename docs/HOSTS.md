# Chọn và dựng host

Host là máy **luôn bật** để agent chạy trên đó. Từ v2, host có thể là VPS, máy trạm, mini PC, laptop cắm sạc, Mac mini hay Raspberry Pi, chạy **Linux, macOS hoặc Windows**. Riêng VPS thì dùng Ubuntu.

[English](HOSTS.en.md) · [README](../README.md)

## 1. Chọn loại máy
| Loại (`HOST_KIND`) | Hệ điều hành | Hợp với ai | Ưu | Nhược |
|---|---|---|---|---|
| `vps` | **Ubuntu 22.04 / 24.04** | Đi xa dài ngày, không muốn lo điện, mạng ở nhà | Luôn online, mất máy thì thuê lại trong 45 phút | Tốn tiền thuê; không có GPU |
| `workstation` | Linux, Windows, macOS | Đã có PC mạnh ở nhà hoặc văn phòng | Mạnh, miễn phí, sẵn toàn bộ môi trường | Mất điện, mất mạng là mất kết nối; có thể bị người khác dùng chung |
| `minipc` | Linux, Windows | Muốn một máy nhỏ, tốn ít điện để chạy 24/24 | 6–15 W, êm, rẻ | RAM thường 8–16 GB |
| `laptop` | Linux, Windows, macOS | Laptop cũ để ở nhà | Có sẵn pin như một bộ UPS nhỏ | Nóng; MacBook gập máy thì cần màn hình ngoài |
| `mac` | macOS | Có Mac mini / Mac Studio | Rất tiết kiệm điện; Codex chạy chính thức qua app ChatGPT | Phải bật tự đăng nhập |
| `sbc` | Raspberry Pi OS 64-bit, Ubuntu | Chỉ sửa code, build để CI lo | Rẻ, ~5 W | Yếu: dùng `PROFILE="small"`, nên chạy bằng SSD thay thẻ nhớ |

Cấu hình RAM chọn bằng `PROFILE` (`small` / `medium` / `large` / `auto`), không phụ thuộc loại máy.

## 2. Mỗi agent chạy nền thế nào trên từng hệ điều hành
| | Linux | macOS | Windows |
|---|---|---|---|
| **Antigravity** | service systemd, tự lên sau reboot kể cả khi chưa ai đăng nhập (bootstrap bật `linger`) | `agy remote-control start` tự đăng ký với hệ điều hành; cần bật **tự đăng nhập** | `agy remote-control start` tự đăng ký với Windows; cần **tự đăng nhập** |
| **Claude Code** | tmux `claude-rc`; tự lên sau reboot bằng `remote.sh autostart claude` (systemd) | tmux + LaunchAgent (`remote.sh autostart claude`) | cửa sổ thu nhỏ; tự lên khi đăng nhập bằng Scheduled Task (`remote.sh autostart claude`) |
| **Codex** | một máy Mac/Windows có app ChatGPT mở host này qua SSH; hoặc SSH + tmux | **app ChatGPT desktop là host chính thức** | **app ChatGPT desktop là host chính thức** |

## 3. Dựng theo hệ điều hành
### Linux: VPS, máy trạm, mini PC, laptop, Raspberry Pi
```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/tsennguyen/vibecode-anywhere ~/vibecode-anywhere && cd ~/vibecode-anywhere
./bootstrap.sh
```
- Hỗ trợ Ubuntu, Debian và các bản cùng họ (Mint, Pop!_OS, Raspberry Pi OS 64-bit). Fedora/Arch: tự cài công cụ, rồi dùng `sync.sh` / `install-deps.sh` như bình thường.
- Máy ở nhà: bootstrap cài `openssh-server`; với `HOST_KIND=laptop` thì gập máy không làm máy ngủ (có hiệu lực sau lần khởi động lại kế tiếp).
- Máy dùng Ubuntu Desktop: vẫn chạy tốt, agent chạy nền không cần ai đăng nhập.

### macOS: Mac mini, Mac Studio, MacBook
```bash
xcode-select --install          # nếu máy chưa có git
git clone https://github.com/tsennguyen/vibecode-anywhere ~/vibecode-anywhere && cd ~/vibecode-anywhere
./bootstrap.sh
```
- Cài bằng Homebrew. Không cho máy ngủ, tự bật lại sau khi mất điện (`pmset autorestart 1`), bật Remote Login (SSH).
- Docker: mặc định dùng **colima** (không cần giao diện). Muốn Docker Desktop thì đặt `DOCKER_ON_MAC="desktop"`.
- **Bắt buộc:** System Settings → Users & Groups → **Automatically log in as…**. Không bật thì sau khi reboot các agent không chạy lại được. Tính năng này **không dùng được khi FileVault đang bật**: phải chọn giữa mã hoá ổ đĩa và việc tự chạy lại (xem mục 4).
- MacBook gập nắp chỉ còn thức khi cắm sạc **và** có màn hình ngoài (giới hạn của Apple). Để mở nắp thì đơn giản nhất.

### Windows: máy trạm, mini PC, laptop (Windows 10 22H2+ / 11)
Mở **PowerShell (Run as Administrator)**:
```powershell
winget install --id Git.Git -e
git clone https://github.com/tsennguyen/vibecode-anywhere $HOME\vibecode-anywhere
cd $HOME\vibecode-anywhere
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
```
Sau đó mở PowerShell **thường** (không phải Admin) và dùng `.\vibe.ps1 <lệnh>`, ví dụ `.\vibe.ps1 sync`, `.\vibe.ps1 doctor`. Nếu quen Git Bash thì gọi thẳng `./sync.sh` cũng được.

`bootstrap.ps1` làm những việc sau:
- Cài bằng winget: Git, Node LTS, uv, OpenJDK, Docker Desktop, gh, Tailscale, agent... theo đúng những gì config chọn.
- Không cho máy ngủ hay ngủ đông khi cắm điện; với laptop thì gập máy không làm gì.
- **Chặn Windows Update tự khởi động lại** khi đang đăng nhập (`WINDOWS_BLOCK_AUTO_REBOOT=1`). Bản cập nhật vẫn được cài, chỉ chờ bạn tự khởi động lại.
- Bật **OpenSSH Server**, shell mặc định là Git Bash, để các lệnh trong RESCUE gõ được y nguyên.
- `git config core.longpaths true`, vì đường dẫn trong `node_modules` hay vượt 260 ký tự.

Để mọi thứ tự chạy lại sau khi mất điện:
1. BIOS/UEFI: **Restore on AC Power Loss = Power On**.
2. Windows tự đăng nhập: `winget install Microsoft.Sysinternals.Autologon`, chạy Autologon (mật khẩu được lưu mã hoá trong LSA).
3. `.\vibe.ps1 remote autostart claude` nếu bạn dùng Claude.

**Tuỳ chọn WSL2:** muốn môi trường Linux ngay trên máy Windows thì cài Ubuntu trong WSL2, bật systemd (`/etc/wsl.conf` → `[boot]` `systemd=true`, rồi `wsl --shutdown`), và làm theo phần Linux bên trong WSL. Lưu ý: WSL tự tắt khi không có gì chạy, và SSH vào WSL phải đi qua Windows. Cách đơn giản hơn là dùng `bootstrap.ps1` chạy thẳng trên Windows.

## 4. Danh sách kiểm tra cho máy ở nhà (máy trạm, mini PC, laptop, Mac, Pi)
- [ ] **Tự bật lại khi có điện:** BIOS `Restore on AC Power Loss = Power On` / Mac đã có `pmset autorestart 1` / Pi tự bật khi có nguồn.
- [ ] **Tự đăng nhập** (Windows, macOS) để agent lên lại sau reboot. Đổi lại: ai cầm được máy là dùng được máy. Nên để máy ở nơi an toàn và bật mã hoá cho từng repo nhạy cảm nếu cần.
- [ ] **UPS** nhỏ (500–1000 VA) cho máy và router: tránh mất việc khi chập điện.
- [ ] **Cắm dây mạng** thay Wi-Fi nếu được.
- [ ] **Tailscale** (`TOOLS+=(tailscale)`) để SSH từ điện thoại vào máy sau router, **không mở cổng** trên modem. Remote control của cả 3 agent chỉ dùng kết nối ra ngoài, nên không cần mở cổng nào.
- [ ] **Không để máy tự ngủ:** bootstrap đã chỉnh. Kiểm tra lại sau khi cập nhật hệ điều hành lớn.
- [ ] **Máy dùng chung** với người nhà, đồng nghiệp: đặt `HOST_SHARED=1`, agent sẽ không đụng app hay file của người khác. Nên tạo tài khoản người dùng riêng cho agent.
- [ ] **Thử một lần trước khi đi:** rút điện → cắm lại → đợi 3 phút → điện thoại vẫn thấy máy? Nếu không, xem RESCUE §1.

## 5. Khuyến nghị nhanh
- **Đi xa, cần chắc chắn:** VPS Ubuntu + Antigravity (agent chính) + Claude (dự phòng).
- **Có Mac mini ở nhà:** dùng Mac mini làm host. Codex chạy chính thức qua app ChatGPT, Antigravity và Claude chạy song song.
- **Có PC Windows mạnh ở nhà:** dùng `bootstrap.ps1` + Tailscale + Autologon. Cẩn thận Windows Update.
- **Ngân sách thấp nhất:** Raspberry Pi 5 8 GB + SSD, `PROFILE="small"`, build nặng để CI chạy.

---
<sub>[vibecode-anywhere](https://github.com/tsennguyen/vibecode-anywhere) — © 2026 Nguyễn Việt Thành, MIT.</sub>
