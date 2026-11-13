//! 测试用：内嵌 CI 配置，供 AC-TEST-025 检查。
pub const source = @embedFile(".github/workflows/ci.yml");
