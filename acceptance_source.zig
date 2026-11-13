//! 测试用：内嵌里程碑验收清单，供 AC-TEST-022 检查人工项记录结构。
pub const pages = [_][]const u8{
    @embedFile("docs/acceptance/M0.md"),
    @embedFile("docs/acceptance/M1.md"),
    @embedFile("docs/acceptance/M2.md"),
    @embedFile("docs/acceptance/M3.md"),
    @embedFile("docs/acceptance/M4.md"),
    @embedFile("docs/acceptance/M5.md"),
};
