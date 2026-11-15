# music/ — Node speaker

Thư mục này chứa một chương trình Node.js nhỏ chỉ làm một việc: phát nhạc trong voice channel
(dùng `@discordjs/voice`, hỗ trợ mã hoá DAVE mà discordrb chưa có). Bot Ruby khởi động nó,
gửi lệnh JSON qua stdin và đọc sự kiện JSON từ stdout. Bạn không cần chạy nó bằng tay.

Cài đặt (một lần): `cd music && npm install`

Cần có `yt-dlp` và `ffmpeg` trong PATH. Chạy test: `node --test`.
