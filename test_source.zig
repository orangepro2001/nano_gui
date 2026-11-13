//! 测试用：内嵌 tests/all.zig 源文本，供 AC-TEST-016 静态扫描。
pub const source = @embedFile("tests/all.zig");
