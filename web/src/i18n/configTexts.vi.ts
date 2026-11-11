// Các chữ của trang Cấu hình, bản tiếng Việt. Phải có đúng các key như configTexts.en.ts.
import type { configEn } from "./configTexts.en";

export const configVi: Record<keyof typeof configEn, string> = {
  "config.title": "Cấu hình",
  "config.intro": "Các giới hạn của Cake. Thay đổi được lưu vào settings.json và có hiệu lực sau khi restart.",
  "config.default": "Mặc định: {value}",
  "config.running": "đang chạy: {value}",
  "config.resetLabel": "Đặt lại {name}",
  "config.outOfRange": "Phải là số nguyên từ {min} đến {max}.",
  "config.restartBanner": "Đã lưu. Restart Cake để áp dụng thay đổi.",
  "config.restartNow": "Restart ngay",
  "config.envTitle": "Đặt trong .env",
  "config.envHelp": "Các giá trị này đọc từ file .env trong thư mục bot, không sửa được ở đây.",
  "config.notSet": "chưa đặt",

  "config.group.chat": "Câu trả lời của AI",
  "config.group.history": "Bộ nhớ chat và compaction",
  "config.group.tools": "Công cụ",
  "config.group.search": "Tìm trong bộ nhớ và tin nhắn cũ",
  "config.group.buildmemory": "!buildmemory",
  "config.group.clear": "!clear",

  // --- Câu trả lời của AI ---
  "config.OPENAI_REASONING_EFFORT.label": "Mức suy nghĩ",
  "config.OPENAI_REASONING_EFFORT.help": "Model suy nghĩ nhiều hay ít trước khi trả lời. Nghĩ nhiều thì chậm và tốn hơn.",
  "config.OPENAI_FALLBACK_REASONING_EFFORT.label": "Mức suy nghĩ khi thử lại",
  "config.OPENAI_FALLBACK_REASONING_EFFORT.help":
    "Nếu suy nghĩ dùng hết số token và câu trả lời bị trống, Cake thử lại một lần với mức này.",
  "config.OPENAI_MAX_OUTPUT_TOKENS.label": "Số token tối đa mỗi câu trả lời",
  "config.OPENAI_MAX_OUTPUT_TOKENS.help": "Gồm cả suy nghĩ lẫn câu trả lời. Chỉ tính tiền phần dùng thật.",
  "config.MAX_TOOL_ROUNDS.label": "Số vòng dùng tool mỗi câu trả lời",
  "config.MAX_TOOL_ROUNDS.help":
    "Một vòng = AI xin dùng tool, Cake chạy rồi gửi kết quả lại. Hết số vòng này thì AI phải trả lời.",

  // --- Bộ nhớ chat và compaction ---
  "config.MAX_HISTORY_MESSAGES.label": "Số tin nhớ mỗi kênh",
  "config.MAX_HISTORY_MESSAGES.help": "Mức cao. Khi bộ nhớ chat của một kênh vượt mức này, phần cũ nhất được tóm tắt rồi bỏ đi.",
  "config.MAX_HISTORY_TOKENS.label": "Số token nhớ mỗi kênh",
  "config.MAX_HISTORY_TOKENS.help": "Cũng là mức cao, nhưng tính bằng token. Giới hạn nào chạm trước thì áp dụng.",
  "config.COMPACT_TARGET_MESSAGES.label": "Số tin còn lại sau compaction",
  "config.COMPACT_TARGET_MESSAGES.help": "Mức thấp mà bộ nhớ chat được cắt xuống. Phải thấp hơn mức cao.",
  "config.COMPACT_TARGET_TOKENS.label": "Số token còn lại sau compaction",
  "config.COMPACT_TARGET_TOKENS.help": "Cũng là mức thấp, nhưng tính bằng token.",
  "config.HARD_MAX_HISTORY_MESSAGES.label": "Giới hạn cứng số tin",
  "config.HARD_MAX_HISTORY_MESSAGES.help":
    "Lưới an toàn: nếu compaction lỗi liên tục, tin cũ nhất bị cắt ở đây mà không có tóm tắt. Phải cao hơn mức cao.",
  "config.HARD_MAX_HISTORY_TOKENS.label": "Giới hạn cứng số token",
  "config.HARD_MAX_HISTORY_TOKENS.help": "Cũng là lưới an toàn đó, nhưng tính bằng token.",
  "config.COMPACTION_REASONING_EFFORT.label": "Mức suy nghĩ khi compaction",
  "config.COMPACTION_REASONING_EFFORT.help": "Model suy nghĩ nhiều hay ít khi viết bản tóm tắt.",

  // --- Công cụ ---
  "config.SEARCH_MAX_RESULTS.label": "Số kết quả mỗi lần tìm web",
  "config.SEARCH_MAX_RESULTS.help": "Mỗi lần tìm web trả cho AI bao nhiêu kết quả.",
  "config.WEBPAGE_MAX_CHARS.label": "Số ký tự đọc từ một trang web",
  "config.WEBPAGE_MAX_CHARS.help": "AI nhận tối đa chừng này chữ của một trang (8.000 ký tự khoảng 2.000 token).",
  "config.IMAGE_MAX_PER_REPLY.label": "Số ảnh mỗi câu trả lời",
  "config.IMAGE_MAX_PER_REPLY.help": "AI được xem tối đa bao nhiêu ảnh cho một câu trả lời. Mỗi ảnh khoảng 1.200 token.",
  "config.TEXT_FILE_MAX_PER_REPLY.label": "Số file text mỗi câu trả lời",
  "config.TEXT_FILE_MAX_PER_REPLY.help": "AI được đọc tối đa bao nhiêu file text đính kèm cho một câu trả lời.",

  // --- Tìm kiếm ---
  "config.MEMORY_SEARCH_RESULTS.label": "Số kết quả mỗi lần tìm bộ nhớ",
  "config.MEMORY_SEARCH_RESULTS.help": "AI nhận lại bao nhiêu memory khớp.",
  "config.CHANNEL_SEARCH_MAX_MESSAGES.label": "Số tin đọc mỗi lần tìm trong kênh",
  "config.CHANNEL_SEARCH_MAX_MESSAGES.help": "Một lần tìm tin nhắn cũ của kênh đọc ngược về bao xa.",
  "config.CHANNEL_SEARCH_RESULTS.label": "Số kết quả mỗi lần tìm trong kênh",
  "config.CHANNEL_SEARCH_RESULTS.help": "AI nhận lại bao nhiêu tin nhắn cũ.",
  "config.CHANNEL_SEARCHES_PER_REPLY.label": "Số lần tìm trong kênh mỗi câu trả lời",
  "config.CHANNEL_SEARCHES_PER_REPLY.help": "Đủ để thử ngày khác một hai lần, mà câu trả lời vẫn nhanh.",

  // --- !buildmemory ---
  "config.BUILD_MEMORY_MESSAGES_PER_CHANNEL.label": "Số tin đọc mỗi kênh",
  "config.BUILD_MEMORY_MESSAGES_PER_CHANNEL.help": "!buildmemory đọc ngược về bao xa trong mỗi kênh.",
  "config.BUILD_MEMORY_MIN_MESSAGES.label": "Số tin tối thiểu mỗi người",
  "config.BUILD_MEMORY_MIN_MESSAGES.help": "Người có ít tin hơn bị bỏ qua vì không đủ dữ liệu.",
  "config.BUILD_MEMORY_MAX_PEOPLE.label": "Số người mỗi lần chạy",
  "config.BUILD_MEMORY_MAX_PEOPLE.help": "Người hoạt động nhiều nhất được làm trước. Mỗi người là một request tới OpenAI.",
  "config.BUILD_MEMORY_MAX_CHARS_PER_PERSON.label": "Số ký tự đọc mỗi người",
  "config.BUILD_MEMORY_MAX_CHARS_PER_PERSON.help": "Các tin mới nhất của họ, tối đa chừng này chữ (12.000 ký tự khoảng 3.000 token).",
  "config.BUILD_MEMORY_REASONING_EFFORT.label": "Mức suy nghĩ cho !buildmemory",
  "config.BUILD_MEMORY_REASONING_EFFORT.help": "Model suy nghĩ nhiều hay ít khi viết note tính cách.",

  // --- !clear ---
  "config.CLEAR_MAX_MESSAGES.label": "Số tin xoá tối đa",
  "config.CLEAR_MAX_MESSAGES.help": "Một lần !clear xoá nhiều nhất bao nhiêu tin. Discord chỉ cho tối đa 100.",
  "config.CLEAR_SCAN_MESSAGES.label": "Số tin tìm cho một người",
  "config.CLEAR_SCAN_MESSAGES.help": "Với !clear @user: tìm tin của người đó ngược về bao xa.",
  "config.CLEAR_REPORT_SECONDS.label": "Số giây hiện báo cáo",
  "config.CLEAR_REPORT_SECONDS.help": "Dòng \"Deleted N messages\" tự biến mất sau chừng này giây.",
};
