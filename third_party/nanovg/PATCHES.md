# NanoVG vendoring

- Upstream: memnonen/nanovg, commit fetched 2026-11-12 from `master`.
- Source files: `nanovg.c`, `nanovg.h`, `nanovg_gl.h`, `stb_truetype.h`, `stb_image.h`.
- Local addition: `nanovg_gl3.c` only defines `NANOVG_GL3_IMPLEMENTATION` and includes
  `nanovg_gl.h`; no upstream file content is modified.
- License: zlib (see `LICENSE.txt`), allowed by ADR 0010.
