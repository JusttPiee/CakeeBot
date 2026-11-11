# Web UI của CakeeBot (React)

Thư mục này là **frontend**: phần chạy trong trình duyệt. **Backend** (phần đọc/ghi file của bot) nằm ở `../web_api/`, viết bằng Ruby.

Trang giải thích React từ số 0, có sơ đồ: https://claude.ai/artifact/RG23fwCACkFhzubfe9UA5Y

## Chạy thế nào

| Việc | Lệnh (chạy trong thư mục `web/`) | Ghi chú |
|---|---|---|
| Cài thư viện (lần đầu) | `npm install` | Giống `bundle install`. Tạo thư mục `node_modules/` |
| Vừa code vừa xem | `npm run dev` | Mở `http://localhost:5173/?token=...`. Bot phải đang chạy. Sửa file là trang tự cập nhật |
| Đóng gói để dùng thật | `npm run build` | Tạo `dist/`. Bot phát thư mục này ở `http://localhost:4567` |
| Chạy test | `npm test` | |

Token lấy từ dòng `First time in this browser? Open: ...` trong terminal của bot.

## Đường đi của một cú bấm

Ví dụ bạn bấm **Save** ở note của một người:

1. `pages/memory/UserNoteForm.tsx`: nút Save gọi hàm `save()`.
2. `api/memory.ts`: `saveUser(...)` chuẩn bị đường dẫn `/api/servers/<id>/users/<id>`.
3. `api/client.ts`: `apiRequest(...)` gửi request kèm token.
4. `../web_api/routes/user_note_routes.rb`: bot nhận, gọi `write_user_note` (hàm có sẵn của bot), trả JSON.
5. Quay lại `UserNoteForm.tsx`: cập nhật state, React tự vẽ lại, hiện toast "Saved".

## Thư mục `src/`

```
main.tsx            điểm bắt đầu: gắn <App /> vào trang
App.tsx             các provider + bảng "địa chỉ nào → trang nào"
api/                nói chuyện với bot. client.ts là chỗ duy nhất gọi fetch
  types.ts          hình dạng dữ liệu bot trả về (TypeScript kiểm tra giúp)
hooks/              logic dùng lại được, không có giao diện
  useApi.ts         tải dữ liệu: { data, error, loading, reload }
  useGuardedSelection.ts   chọn một mục trong danh sách, hỏi lại nếu còn thay đổi chưa lưu
context/            dữ liệu dùng chung cho cả app
  StatusContext.tsx bot còn sống không, đang restart không
  ServerContext.tsx đang xem server nào
i18n/               chữ trên giao diện, tiếng Anh và tiếng Việt
components/         mảnh giao diện dùng ở nhiều trang (Toggle, ConfirmButton, ListDetail...)
pages/              mỗi trang một thư mục
styles/             tokens.css (màu, cỡ chữ, thời gian animation) và global.css
motion/presets.ts   các kiểu animation dùng chung
test/               cài đặt chung cho test
```

File `X.module.css` nằm cạnh `X.tsx` là CSS riêng của component đó. File `X.test.tsx` là test của nó.

## Các khái niệm React, và file dễ đọc nhất cho từng cái

| Khái niệm | Nghĩa ngắn gọn | Xem ở |
|---|---|---|
| Component | Hàm trả ra một mảnh giao diện | `components/EmptyState.tsx` (4 dòng) |
| Props | Dữ liệu cha truyền cho con, con chỉ đọc | `components/Toggle.tsx` |
| State (`useState`) | Dữ liệu component tự giữ; đổi là vẽ lại | `components/ConfirmButton.tsx` |
| Controlled input | Ô nhập hiển thị state, gõ thì cập nhật state | `components/SearchBox.tsx` |
| `useEffect` | Chạy việc phụ sau khi vẽ (hẹn giờ, tải dữ liệu), có bước dọn dẹp | `components/ConfirmButton.tsx` |
| Hook tự viết | Hàm `use...` gom logic để dùng lại | `hooks/useApi.ts` |
| Context | Dữ liệu mọi component đọc được, không phải truyền qua từng tầng | `i18n/LanguageContext.tsx` |
| Danh sách + `key` | Vẽ nhiều phần tử từ một mảng | `components/ListDetail.tsx` |
| Nâng state lên | Hai component cần chung dữ liệu thì cha giữ | `pages/memory/PeopleTab.tsx` |
| Optimistic update | Hiện kết quả ngay, hoàn tác nếu bot từ chối | `pages/ChannelsPage.tsx` |
| Polling | Hỏi lại bot theo chu kỳ | `pages/logs/useLogLines.ts` |
| Hàm thuần | Không đụng gì bên ngoài, nên dễ test | `pages/logs/filterLogLines.ts` |
| Router | Địa chỉ quyết định trang nào hiện | `App.tsx`, `pages/memory/MemoryPage.tsx` |

Gợi ý thứ tự đọc: `main.tsx` → `App.tsx` → `components/Sidebar.tsx` → `pages/ChannelsPage.tsx` (trang đơn giản nhất) → `pages/memory/`.

## Thêm một chuỗi chữ

1. Thêm key vào `i18n/en.ts`, ví dụ `"logs.clear": "Clear"`.
2. Thêm đúng key đó vào `i18n/vi.ts`. Quên bước này thì `npm run build` báo lỗi ngay.
3. Trong component: `const t = useT();` rồi `t("logs.clear")`.

## Thêm một trang mới

1. Backend: thêm file route trong `../web_api/routes/`, đăng ký nó trong `../web_api/web_app.rb`, viết test trong `../test/`.
2. Thêm hàm gọi API trong `api/`, và kiểu dữ liệu trong `api/types.ts`.
3. Tạo `pages/<tên>/<Tên>Page.tsx`.
4. Thêm một dòng `<Route>` trong `App.tsx` và một mục trong `PAGES` của `components/Sidebar.tsx`.

## Bảo mật

- Bot chỉ nghe ở `127.0.0.1`, nên máy khác không vào được.
- Mọi request `/api` phải có token. Token nằm trong `.env` của bot (`WEB_UI_TOKEN`) và trong bộ nhớ trình duyệt.
- Web không bao giờ hiện hay sửa `.env`.
