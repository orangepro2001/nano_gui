//! 测试用：内嵌 build.zig 源文本，供 AC-TEST-002 检查步骤名。
pub const source = @embedFile("build.zig");
