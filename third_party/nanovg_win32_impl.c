/* Win32 NanoVG GL3 backend: GL loader + NanoVG context + persistent FBO. */
#include "nanovg_win32_gl.h"
#include <stdio.h>
#include <string.h>
#include "nanovg_win32_api.h"
#define NANOVG_GL3_IMPLEMENTATION
#include "nanovg.h"
#include "nanovg_gl.h"

PFNGLACTIVETEXTUREPROC nvg_p_glActiveTexture = NULL;
PFNGLATTACHSHADERPROC nvg_p_glAttachShader = NULL;
PFNGLBINDATTRIBLOCATIONPROC nvg_p_glBindAttribLocation = NULL;
PFNGLBINDBUFFERPROC nvg_p_glBindBuffer = NULL;
PFNGLBINDBUFFERRANGEPROC nvg_p_glBindBufferRange = NULL;
PFNGLBINDTEXTUREPROC nvg_p_glBindTexture = NULL;
PFNGLBINDVERTEXARRAYPROC nvg_p_glBindVertexArray = NULL;
PFNGLBLENDFUNCSEPARATEPROC nvg_p_glBlendFuncSeparate = NULL;
PFNGLBUFFERDATAPROC nvg_p_glBufferData = NULL;
PFNGLCOLORMASKPROC nvg_p_glColorMask = NULL;
PFNGLCOMPILESHADERPROC nvg_p_glCompileShader = NULL;
PFNGLCREATEPROGRAMPROC nvg_p_glCreateProgram = NULL;
PFNGLCREATESHADERPROC nvg_p_glCreateShader = NULL;
PFNGLCULLFACEPROC nvg_p_glCullFace = NULL;
PFNGLDELETEBUFFERSPROC nvg_p_glDeleteBuffers = NULL;
PFNGLDELETEPROGRAMPROC nvg_p_glDeleteProgram = NULL;
PFNGLDELETESHADERPROC nvg_p_glDeleteShader = NULL;
PFNGLDELETETEXTURESPROC nvg_p_glDeleteTextures = NULL;
PFNGLDELETEVERTEXARRAYSPROC nvg_p_glDeleteVertexArrays = NULL;
PFNGLDISABLEPROC nvg_p_glDisable = NULL;
PFNGLDISABLEVERTEXATTRIBARRAYPROC nvg_p_glDisableVertexAttribArray = NULL;
PFNGLDRAWARRAYSPROC nvg_p_glDrawArrays = NULL;
PFNGLENABLEPROC nvg_p_glEnable = NULL;
PFNGLENABLEVERTEXATTRIBARRAYPROC nvg_p_glEnableVertexAttribArray = NULL;
PFNGLFINISHPROC nvg_p_glFinish = NULL;
PFNGLFRONTFACEPROC nvg_p_glFrontFace = NULL;
PFNGLGENBUFFERSPROC nvg_p_glGenBuffers = NULL;
PFNGLGENTEXTURESPROC nvg_p_glGenTextures = NULL;
PFNGLGENVERTEXARRAYSPROC nvg_p_glGenVertexArrays = NULL;
PFNGLGENERATEMIPMAPPROC nvg_p_glGenerateMipmap = NULL;
PFNGLGETERRORPROC nvg_p_glGetError = NULL;
PFNGLGETINTEGERVPROC nvg_p_glGetIntegerv = NULL;
PFNGLGETPROGRAMINFOLOGPROC nvg_p_glGetProgramInfoLog = NULL;
PFNGLGETPROGRAMIVPROC nvg_p_glGetProgramiv = NULL;
PFNGLGETSHADERINFOLOGPROC nvg_p_glGetShaderInfoLog = NULL;
PFNGLGETSHADERIVPROC nvg_p_glGetShaderiv = NULL;
PFNGLGETUNIFORMBLOCKINDEXPROC nvg_p_glGetUniformBlockIndex = NULL;
PFNGLGETUNIFORMLOCATIONPROC nvg_p_glGetUniformLocation = NULL;
PFNGLLINKPROGRAMPROC nvg_p_glLinkProgram = NULL;
PFNGLPIXELSTOREIPROC nvg_p_glPixelStorei = NULL;
PFNGLSHADERSOURCEPROC nvg_p_glShaderSource = NULL;
PFNGLSTENCILFUNCPROC nvg_p_glStencilFunc = NULL;
PFNGLSTENCILMASKPROC nvg_p_glStencilMask = NULL;
PFNGLSTENCILOPPROC nvg_p_glStencilOp = NULL;
PFNGLSTENCILOPSEPARATEPROC nvg_p_glStencilOpSeparate = NULL;
PFNGLTEXIMAGE2DPROC nvg_p_glTexImage2D = NULL;
PFNGLTEXPARAMETERIPROC nvg_p_glTexParameteri = NULL;
PFNGLTEXSUBIMAGE2DPROC nvg_p_glTexSubImage2D = NULL;
PFNGLUNIFORM1IPROC nvg_p_glUniform1i = NULL;
PFNGLUNIFORM2FVPROC nvg_p_glUniform2fv = NULL;
PFNGLUNIFORM4FVPROC nvg_p_glUniform4fv = NULL;
PFNGLUNIFORMBLOCKBINDINGPROC nvg_p_glUniformBlockBinding = NULL;
PFNGLUSEPROGRAMPROC nvg_p_glUseProgram = NULL;
PFNGLVERTEXATTRIBPOINTERPROC nvg_p_glVertexAttribPointer = NULL;
PFNGLGENFRAMEBUFFERSPROC nvg_p_glGenFramebuffers = NULL;
PFNGLBINDFRAMEBUFFERPROC nvg_p_glBindFramebuffer = NULL;
PFNGLGENRENDERBUFFERSPROC nvg_p_glGenRenderbuffers = NULL;
PFNGLBINDRENDERBUFFERPROC nvg_p_glBindRenderbuffer = NULL;
PFNGLRENDERBUFFERSTORAGEPROC nvg_p_glRenderbufferStorage = NULL;
PFNGLFRAMEBUFFERTEXTURE2DPROC nvg_p_glFramebufferTexture2D = NULL;
PFNGLFRAMEBUFFERRENDERBUFFERPROC nvg_p_glFramebufferRenderbuffer = NULL;
PFNGLCHECKFRAMEBUFFERSTATUSPROC nvg_p_glCheckFramebufferStatus = NULL;
PFNGLDELETEFRAMEBUFFERSPROC nvg_p_glDeleteFramebuffers = NULL;
PFNGLDELETERENDERBUFFERSPROC nvg_p_glDeleteRenderbuffers = NULL;
PFNGLBLITFRAMEBUFFERPROC nvg_p_glBlitFramebuffer = NULL;
PFNGLCLEARPROC nvg_p_glClear = NULL;
PFNGLVIEWPORTPROC nvg_p_glViewport = NULL;
PFNGLCLEARCOLORPROC nvg_p_glClearColor = NULL;
PFNGLREADPIXELSPROC nvg_p_glReadPixels = NULL;

static HMODULE glmod = NULL;
static NVGcontext* g_ctx = NULL;
static unsigned g_fbo = 0, g_tex = 0, g_rb = 0;
static int g_w = 0, g_h = 0;
static void* g_hdc = NULL;

static void nvg_load(void) {
    if (glmod) return;
    glmod = LoadLibraryA("opengl32.dll");
    nvg_p_glActiveTexture = (PFNGLACTIVETEXTUREPROC)wglGetProcAddress("glActiveTexture");
    if (!nvg_p_glActiveTexture) nvg_p_glActiveTexture = (PFNGLACTIVETEXTUREPROC)GetProcAddress(glmod, "glActiveTexture");
    nvg_p_glAttachShader = (PFNGLATTACHSHADERPROC)wglGetProcAddress("glAttachShader");
    if (!nvg_p_glAttachShader) nvg_p_glAttachShader = (PFNGLATTACHSHADERPROC)GetProcAddress(glmod, "glAttachShader");
    nvg_p_glBindAttribLocation = (PFNGLBINDATTRIBLOCATIONPROC)wglGetProcAddress("glBindAttribLocation");
    if (!nvg_p_glBindAttribLocation) nvg_p_glBindAttribLocation = (PFNGLBINDATTRIBLOCATIONPROC)GetProcAddress(glmod, "glBindAttribLocation");
    nvg_p_glBindBuffer = (PFNGLBINDBUFFERPROC)wglGetProcAddress("glBindBuffer");
    if (!nvg_p_glBindBuffer) nvg_p_glBindBuffer = (PFNGLBINDBUFFERPROC)GetProcAddress(glmod, "glBindBuffer");
    nvg_p_glBindBufferRange = (PFNGLBINDBUFFERRANGEPROC)wglGetProcAddress("glBindBufferRange");
    if (!nvg_p_glBindBufferRange) nvg_p_glBindBufferRange = (PFNGLBINDBUFFERRANGEPROC)GetProcAddress(glmod, "glBindBufferRange");
    nvg_p_glBindTexture = (PFNGLBINDTEXTUREPROC)wglGetProcAddress("glBindTexture");
    if (!nvg_p_glBindTexture) nvg_p_glBindTexture = (PFNGLBINDTEXTUREPROC)GetProcAddress(glmod, "glBindTexture");
    nvg_p_glBindVertexArray = (PFNGLBINDVERTEXARRAYPROC)wglGetProcAddress("glBindVertexArray");
    if (!nvg_p_glBindVertexArray) nvg_p_glBindVertexArray = (PFNGLBINDVERTEXARRAYPROC)GetProcAddress(glmod, "glBindVertexArray");
    nvg_p_glBlendFuncSeparate = (PFNGLBLENDFUNCSEPARATEPROC)wglGetProcAddress("glBlendFuncSeparate");
    if (!nvg_p_glBlendFuncSeparate) nvg_p_glBlendFuncSeparate = (PFNGLBLENDFUNCSEPARATEPROC)GetProcAddress(glmod, "glBlendFuncSeparate");
    nvg_p_glBufferData = (PFNGLBUFFERDATAPROC)wglGetProcAddress("glBufferData");
    if (!nvg_p_glBufferData) nvg_p_glBufferData = (PFNGLBUFFERDATAPROC)GetProcAddress(glmod, "glBufferData");
    nvg_p_glColorMask = (PFNGLCOLORMASKPROC)wglGetProcAddress("glColorMask");
    if (!nvg_p_glColorMask) nvg_p_glColorMask = (PFNGLCOLORMASKPROC)GetProcAddress(glmod, "glColorMask");
    nvg_p_glCompileShader = (PFNGLCOMPILESHADERPROC)wglGetProcAddress("glCompileShader");
    if (!nvg_p_glCompileShader) nvg_p_glCompileShader = (PFNGLCOMPILESHADERPROC)GetProcAddress(glmod, "glCompileShader");
    nvg_p_glCreateProgram = (PFNGLCREATEPROGRAMPROC)wglGetProcAddress("glCreateProgram");
    if (!nvg_p_glCreateProgram) nvg_p_glCreateProgram = (PFNGLCREATEPROGRAMPROC)GetProcAddress(glmod, "glCreateProgram");
    nvg_p_glCreateShader = (PFNGLCREATESHADERPROC)wglGetProcAddress("glCreateShader");
    if (!nvg_p_glCreateShader) nvg_p_glCreateShader = (PFNGLCREATESHADERPROC)GetProcAddress(glmod, "glCreateShader");
    nvg_p_glCullFace = (PFNGLCULLFACEPROC)wglGetProcAddress("glCullFace");
    if (!nvg_p_glCullFace) nvg_p_glCullFace = (PFNGLCULLFACEPROC)GetProcAddress(glmod, "glCullFace");
    nvg_p_glDeleteBuffers = (PFNGLDELETEBUFFERSPROC)wglGetProcAddress("glDeleteBuffers");
    if (!nvg_p_glDeleteBuffers) nvg_p_glDeleteBuffers = (PFNGLDELETEBUFFERSPROC)GetProcAddress(glmod, "glDeleteBuffers");
    nvg_p_glDeleteProgram = (PFNGLDELETEPROGRAMPROC)wglGetProcAddress("glDeleteProgram");
    if (!nvg_p_glDeleteProgram) nvg_p_glDeleteProgram = (PFNGLDELETEPROGRAMPROC)GetProcAddress(glmod, "glDeleteProgram");
    nvg_p_glDeleteShader = (PFNGLDELETESHADERPROC)wglGetProcAddress("glDeleteShader");
    if (!nvg_p_glDeleteShader) nvg_p_glDeleteShader = (PFNGLDELETESHADERPROC)GetProcAddress(glmod, "glDeleteShader");
    nvg_p_glDeleteTextures = (PFNGLDELETETEXTURESPROC)wglGetProcAddress("glDeleteTextures");
    if (!nvg_p_glDeleteTextures) nvg_p_glDeleteTextures = (PFNGLDELETETEXTURESPROC)GetProcAddress(glmod, "glDeleteTextures");
    nvg_p_glDeleteVertexArrays = (PFNGLDELETEVERTEXARRAYSPROC)wglGetProcAddress("glDeleteVertexArrays");
    if (!nvg_p_glDeleteVertexArrays) nvg_p_glDeleteVertexArrays = (PFNGLDELETEVERTEXARRAYSPROC)GetProcAddress(glmod, "glDeleteVertexArrays");
    nvg_p_glDisable = (PFNGLDISABLEPROC)wglGetProcAddress("glDisable");
    if (!nvg_p_glDisable) nvg_p_glDisable = (PFNGLDISABLEPROC)GetProcAddress(glmod, "glDisable");
    nvg_p_glDisableVertexAttribArray = (PFNGLDISABLEVERTEXATTRIBARRAYPROC)wglGetProcAddress("glDisableVertexAttribArray");
    if (!nvg_p_glDisableVertexAttribArray) nvg_p_glDisableVertexAttribArray = (PFNGLDISABLEVERTEXATTRIBARRAYPROC)GetProcAddress(glmod, "glDisableVertexAttribArray");
    nvg_p_glDrawArrays = (PFNGLDRAWARRAYSPROC)wglGetProcAddress("glDrawArrays");
    if (!nvg_p_glDrawArrays) nvg_p_glDrawArrays = (PFNGLDRAWARRAYSPROC)GetProcAddress(glmod, "glDrawArrays");
    nvg_p_glEnable = (PFNGLENABLEPROC)wglGetProcAddress("glEnable");
    if (!nvg_p_glEnable) nvg_p_glEnable = (PFNGLENABLEPROC)GetProcAddress(glmod, "glEnable");
    nvg_p_glEnableVertexAttribArray = (PFNGLENABLEVERTEXATTRIBARRAYPROC)wglGetProcAddress("glEnableVertexAttribArray");
    if (!nvg_p_glEnableVertexAttribArray) nvg_p_glEnableVertexAttribArray = (PFNGLENABLEVERTEXATTRIBARRAYPROC)GetProcAddress(glmod, "glEnableVertexAttribArray");
    nvg_p_glFinish = (PFNGLFINISHPROC)wglGetProcAddress("glFinish");
    if (!nvg_p_glFinish) nvg_p_glFinish = (PFNGLFINISHPROC)GetProcAddress(glmod, "glFinish");
    nvg_p_glFrontFace = (PFNGLFRONTFACEPROC)wglGetProcAddress("glFrontFace");
    if (!nvg_p_glFrontFace) nvg_p_glFrontFace = (PFNGLFRONTFACEPROC)GetProcAddress(glmod, "glFrontFace");
    nvg_p_glGenBuffers = (PFNGLGENBUFFERSPROC)wglGetProcAddress("glGenBuffers");
    if (!nvg_p_glGenBuffers) nvg_p_glGenBuffers = (PFNGLGENBUFFERSPROC)GetProcAddress(glmod, "glGenBuffers");
    nvg_p_glGenTextures = (PFNGLGENTEXTURESPROC)wglGetProcAddress("glGenTextures");
    if (!nvg_p_glGenTextures) nvg_p_glGenTextures = (PFNGLGENTEXTURESPROC)GetProcAddress(glmod, "glGenTextures");
    nvg_p_glGenVertexArrays = (PFNGLGENVERTEXARRAYSPROC)wglGetProcAddress("glGenVertexArrays");
    if (!nvg_p_glGenVertexArrays) nvg_p_glGenVertexArrays = (PFNGLGENVERTEXARRAYSPROC)GetProcAddress(glmod, "glGenVertexArrays");
    nvg_p_glGenerateMipmap = (PFNGLGENERATEMIPMAPPROC)wglGetProcAddress("glGenerateMipmap");
    if (!nvg_p_glGenerateMipmap) nvg_p_glGenerateMipmap = (PFNGLGENERATEMIPMAPPROC)GetProcAddress(glmod, "glGenerateMipmap");
    nvg_p_glGetError = (PFNGLGETERRORPROC)wglGetProcAddress("glGetError");
    if (!nvg_p_glGetError) nvg_p_glGetError = (PFNGLGETERRORPROC)GetProcAddress(glmod, "glGetError");
    nvg_p_glGetIntegerv = (PFNGLGETINTEGERVPROC)wglGetProcAddress("glGetIntegerv");
    if (!nvg_p_glGetIntegerv) nvg_p_glGetIntegerv = (PFNGLGETINTEGERVPROC)GetProcAddress(glmod, "glGetIntegerv");
    nvg_p_glGetProgramInfoLog = (PFNGLGETPROGRAMINFOLOGPROC)wglGetProcAddress("glGetProgramInfoLog");
    if (!nvg_p_glGetProgramInfoLog) nvg_p_glGetProgramInfoLog = (PFNGLGETPROGRAMINFOLOGPROC)GetProcAddress(glmod, "glGetProgramInfoLog");
    nvg_p_glGetProgramiv = (PFNGLGETPROGRAMIVPROC)wglGetProcAddress("glGetProgramiv");
    if (!nvg_p_glGetProgramiv) nvg_p_glGetProgramiv = (PFNGLGETPROGRAMIVPROC)GetProcAddress(glmod, "glGetProgramiv");
    nvg_p_glGetShaderInfoLog = (PFNGLGETSHADERINFOLOGPROC)wglGetProcAddress("glGetShaderInfoLog");
    if (!nvg_p_glGetShaderInfoLog) nvg_p_glGetShaderInfoLog = (PFNGLGETSHADERINFOLOGPROC)GetProcAddress(glmod, "glGetShaderInfoLog");
    nvg_p_glGetShaderiv = (PFNGLGETSHADERIVPROC)wglGetProcAddress("glGetShaderiv");
    if (!nvg_p_glGetShaderiv) nvg_p_glGetShaderiv = (PFNGLGETSHADERIVPROC)GetProcAddress(glmod, "glGetShaderiv");
    nvg_p_glGetUniformBlockIndex = (PFNGLGETUNIFORMBLOCKINDEXPROC)wglGetProcAddress("glGetUniformBlockIndex");
    if (!nvg_p_glGetUniformBlockIndex) nvg_p_glGetUniformBlockIndex = (PFNGLGETUNIFORMBLOCKINDEXPROC)GetProcAddress(glmod, "glGetUniformBlockIndex");
    nvg_p_glGetUniformLocation = (PFNGLGETUNIFORMLOCATIONPROC)wglGetProcAddress("glGetUniformLocation");
    if (!nvg_p_glGetUniformLocation) nvg_p_glGetUniformLocation = (PFNGLGETUNIFORMLOCATIONPROC)GetProcAddress(glmod, "glGetUniformLocation");
    nvg_p_glLinkProgram = (PFNGLLINKPROGRAMPROC)wglGetProcAddress("glLinkProgram");
    if (!nvg_p_glLinkProgram) nvg_p_glLinkProgram = (PFNGLLINKPROGRAMPROC)GetProcAddress(glmod, "glLinkProgram");
    nvg_p_glPixelStorei = (PFNGLPIXELSTOREIPROC)wglGetProcAddress("glPixelStorei");
    if (!nvg_p_glPixelStorei) nvg_p_glPixelStorei = (PFNGLPIXELSTOREIPROC)GetProcAddress(glmod, "glPixelStorei");
    nvg_p_glShaderSource = (PFNGLSHADERSOURCEPROC)wglGetProcAddress("glShaderSource");
    if (!nvg_p_glShaderSource) nvg_p_glShaderSource = (PFNGLSHADERSOURCEPROC)GetProcAddress(glmod, "glShaderSource");
    nvg_p_glStencilFunc = (PFNGLSTENCILFUNCPROC)wglGetProcAddress("glStencilFunc");
    if (!nvg_p_glStencilFunc) nvg_p_glStencilFunc = (PFNGLSTENCILFUNCPROC)GetProcAddress(glmod, "glStencilFunc");
    nvg_p_glStencilMask = (PFNGLSTENCILMASKPROC)wglGetProcAddress("glStencilMask");
    if (!nvg_p_glStencilMask) nvg_p_glStencilMask = (PFNGLSTENCILMASKPROC)GetProcAddress(glmod, "glStencilMask");
    nvg_p_glStencilOp = (PFNGLSTENCILOPPROC)wglGetProcAddress("glStencilOp");
    if (!nvg_p_glStencilOp) nvg_p_glStencilOp = (PFNGLSTENCILOPPROC)GetProcAddress(glmod, "glStencilOp");
    nvg_p_glStencilOpSeparate = (PFNGLSTENCILOPSEPARATEPROC)wglGetProcAddress("glStencilOpSeparate");
    if (!nvg_p_glStencilOpSeparate) nvg_p_glStencilOpSeparate = (PFNGLSTENCILOPSEPARATEPROC)GetProcAddress(glmod, "glStencilOpSeparate");
    nvg_p_glTexImage2D = (PFNGLTEXIMAGE2DPROC)wglGetProcAddress("glTexImage2D");
    if (!nvg_p_glTexImage2D) nvg_p_glTexImage2D = (PFNGLTEXIMAGE2DPROC)GetProcAddress(glmod, "glTexImage2D");
    nvg_p_glTexParameteri = (PFNGLTEXPARAMETERIPROC)wglGetProcAddress("glTexParameteri");
    if (!nvg_p_glTexParameteri) nvg_p_glTexParameteri = (PFNGLTEXPARAMETERIPROC)GetProcAddress(glmod, "glTexParameteri");
    nvg_p_glTexSubImage2D = (PFNGLTEXSUBIMAGE2DPROC)wglGetProcAddress("glTexSubImage2D");
    if (!nvg_p_glTexSubImage2D) nvg_p_glTexSubImage2D = (PFNGLTEXSUBIMAGE2DPROC)GetProcAddress(glmod, "glTexSubImage2D");
    nvg_p_glUniform1i = (PFNGLUNIFORM1IPROC)wglGetProcAddress("glUniform1i");
    if (!nvg_p_glUniform1i) nvg_p_glUniform1i = (PFNGLUNIFORM1IPROC)GetProcAddress(glmod, "glUniform1i");
    nvg_p_glUniform2fv = (PFNGLUNIFORM2FVPROC)wglGetProcAddress("glUniform2fv");
    if (!nvg_p_glUniform2fv) nvg_p_glUniform2fv = (PFNGLUNIFORM2FVPROC)GetProcAddress(glmod, "glUniform2fv");
    nvg_p_glUniform4fv = (PFNGLUNIFORM4FVPROC)wglGetProcAddress("glUniform4fv");
    if (!nvg_p_glUniform4fv) nvg_p_glUniform4fv = (PFNGLUNIFORM4FVPROC)GetProcAddress(glmod, "glUniform4fv");
    nvg_p_glUniformBlockBinding = (PFNGLUNIFORMBLOCKBINDINGPROC)wglGetProcAddress("glUniformBlockBinding");
    if (!nvg_p_glUniformBlockBinding) nvg_p_glUniformBlockBinding = (PFNGLUNIFORMBLOCKBINDINGPROC)GetProcAddress(glmod, "glUniformBlockBinding");
    nvg_p_glUseProgram = (PFNGLUSEPROGRAMPROC)wglGetProcAddress("glUseProgram");
    if (!nvg_p_glUseProgram) nvg_p_glUseProgram = (PFNGLUSEPROGRAMPROC)GetProcAddress(glmod, "glUseProgram");
    nvg_p_glVertexAttribPointer = (PFNGLVERTEXATTRIBPOINTERPROC)wglGetProcAddress("glVertexAttribPointer");
    if (!nvg_p_glVertexAttribPointer) nvg_p_glVertexAttribPointer = (PFNGLVERTEXATTRIBPOINTERPROC)GetProcAddress(glmod, "glVertexAttribPointer");
    nvg_p_glGenFramebuffers = (PFNGLGENFRAMEBUFFERSPROC)wglGetProcAddress("glGenFramebuffers");
    if (!nvg_p_glGenFramebuffers) nvg_p_glGenFramebuffers = (PFNGLGENFRAMEBUFFERSPROC)GetProcAddress(glmod, "glGenFramebuffers");
    nvg_p_glBindFramebuffer = (PFNGLBINDFRAMEBUFFERPROC)wglGetProcAddress("glBindFramebuffer");
    if (!nvg_p_glBindFramebuffer) nvg_p_glBindFramebuffer = (PFNGLBINDFRAMEBUFFERPROC)GetProcAddress(glmod, "glBindFramebuffer");
    nvg_p_glGenRenderbuffers = (PFNGLGENRENDERBUFFERSPROC)wglGetProcAddress("glGenRenderbuffers");
    if (!nvg_p_glGenRenderbuffers) nvg_p_glGenRenderbuffers = (PFNGLGENRENDERBUFFERSPROC)GetProcAddress(glmod, "glGenRenderbuffers");
    nvg_p_glBindRenderbuffer = (PFNGLBINDRENDERBUFFERPROC)wglGetProcAddress("glBindRenderbuffer");
    if (!nvg_p_glBindRenderbuffer) nvg_p_glBindRenderbuffer = (PFNGLBINDRENDERBUFFERPROC)GetProcAddress(glmod, "glBindRenderbuffer");
    nvg_p_glRenderbufferStorage = (PFNGLRENDERBUFFERSTORAGEPROC)wglGetProcAddress("glRenderbufferStorage");
    if (!nvg_p_glRenderbufferStorage) nvg_p_glRenderbufferStorage = (PFNGLRENDERBUFFERSTORAGEPROC)GetProcAddress(glmod, "glRenderbufferStorage");
    nvg_p_glFramebufferTexture2D = (PFNGLFRAMEBUFFERTEXTURE2DPROC)wglGetProcAddress("glFramebufferTexture2D");
    if (!nvg_p_glFramebufferTexture2D) nvg_p_glFramebufferTexture2D = (PFNGLFRAMEBUFFERTEXTURE2DPROC)GetProcAddress(glmod, "glFramebufferTexture2D");
    nvg_p_glFramebufferRenderbuffer = (PFNGLFRAMEBUFFERRENDERBUFFERPROC)wglGetProcAddress("glFramebufferRenderbuffer");
    if (!nvg_p_glFramebufferRenderbuffer) nvg_p_glFramebufferRenderbuffer = (PFNGLFRAMEBUFFERRENDERBUFFERPROC)GetProcAddress(glmod, "glFramebufferRenderbuffer");
    nvg_p_glCheckFramebufferStatus = (PFNGLCHECKFRAMEBUFFERSTATUSPROC)wglGetProcAddress("glCheckFramebufferStatus");
    if (!nvg_p_glCheckFramebufferStatus) nvg_p_glCheckFramebufferStatus = (PFNGLCHECKFRAMEBUFFERSTATUSPROC)GetProcAddress(glmod, "glCheckFramebufferStatus");
    nvg_p_glDeleteFramebuffers = (PFNGLDELETEFRAMEBUFFERSPROC)wglGetProcAddress("glDeleteFramebuffers");
    if (!nvg_p_glDeleteFramebuffers) nvg_p_glDeleteFramebuffers = (PFNGLDELETEFRAMEBUFFERSPROC)GetProcAddress(glmod, "glDeleteFramebuffers");
    nvg_p_glDeleteRenderbuffers = (PFNGLDELETERENDERBUFFERSPROC)wglGetProcAddress("glDeleteRenderbuffers");
    if (!nvg_p_glDeleteRenderbuffers) nvg_p_glDeleteRenderbuffers = (PFNGLDELETERENDERBUFFERSPROC)GetProcAddress(glmod, "glDeleteRenderbuffers");
    nvg_p_glBlitFramebuffer = (PFNGLBLITFRAMEBUFFERPROC)wglGetProcAddress("glBlitFramebuffer");
    if (!nvg_p_glBlitFramebuffer) nvg_p_glBlitFramebuffer = (PFNGLBLITFRAMEBUFFERPROC)GetProcAddress(glmod, "glBlitFramebuffer");
    nvg_p_glClear = (PFNGLCLEARPROC)wglGetProcAddress("glClear");
    if (!nvg_p_glClear) nvg_p_glClear = (PFNGLCLEARPROC)GetProcAddress(glmod, "glClear");
    nvg_p_glViewport = (PFNGLVIEWPORTPROC)wglGetProcAddress("glViewport");
    if (!nvg_p_glViewport) nvg_p_glViewport = (PFNGLVIEWPORTPROC)GetProcAddress(glmod, "glViewport");
    nvg_p_glClearColor = (PFNGLCLEARCOLORPROC)wglGetProcAddress("glClearColor");
    if (!nvg_p_glClearColor) nvg_p_glClearColor = (PFNGLCLEARCOLORPROC)GetProcAddress(glmod, "glClearColor");
    nvg_p_glReadPixels = (PFNGLREADPIXELSPROC)wglGetProcAddress("glReadPixels");
    if (!nvg_p_glReadPixels) nvg_p_glReadPixels = (PFNGLREADPIXELSPROC)GetProcAddress(glmod, "glReadPixels");
}

int nvg_win32_init(void* hdc, int w, int h) {
    g_hdc = hdc;
    nvg_load();
    g_ctx = nvgCreateGL3(NVG_ANTIALIAS | NVG_STENCIL_STROKES);
    if (!g_ctx) return 0;
    g_w = w;
    g_h = h;
    glGenFramebuffers(1, &g_fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
    glGenTextures(1, &g_tex);
    glBindTexture(GL_TEXTURE_2D, g_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g_tex, 0);
    glGenRenderbuffers(1, &g_rb);
    glBindRenderbuffer(GL_RENDERBUFFER, g_rb);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, w, h);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, g_rb);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) return 0;
    return 1;
}

void nvg_win32_shutdown(void) {
    if (g_ctx) { nvgDeleteGL3(g_ctx); g_ctx = NULL; }
    if (g_fbo) { glDeleteFramebuffers(1, &g_fbo); g_fbo = 0; }
    if (g_tex) { glDeleteTextures(1, &g_tex); g_tex = 0; }
    if (g_rb) { glDeleteRenderbuffers(1, &g_rb); g_rb = 0; }
}

int nvg_win32_resize(int w, int h) {
    if (w == g_w && h == g_h) return 1;
    nvg_win32_shutdown();
    return nvg_win32_init(g_hdc, w, h);
}

void nvg_win32_begin(int w, int h) {
    glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
    glViewport(0, 0, w, h);
    glClearColor(0.925f, 0.933f, 0.945f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    nvgBeginFrame(g_ctx, (float)w, (float)h, 1.0f);
}
void nvg_win32_end(void) { nvgEndFrame(g_ctx); }
void nvg_win32_present(int w, int h) {
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    glBlitFramebuffer(0,0,w,h,0,0,w,h,GL_COLOR_BUFFER_BIT,GL_NEAREST);
    SwapBuffers((HDC)g_hdc);
}
void nvg_win32_fill(float x,float y,float w,float h,unsigned char r,unsigned char g,unsigned char b,unsigned char a) {
    nvgBeginPath(g_ctx); nvgRect(g_ctx,x,y,w,h); nvgFillColor(g_ctx,nvgRGBA(r,g,b,a)); nvgFill(g_ctx);
}
void nvg_win32_fill_v(float x,float y,float w,float h,unsigned char rt,unsigned char gt,unsigned char bt,unsigned char at,unsigned char rb,unsigned char gb,unsigned char bb,unsigned char ab) {
    nvgBeginPath(g_ctx); nvgRect(g_ctx,x,y,w,h);
    nvgFillPaint(g_ctx,nvgLinearGradient(g_ctx,x,y,x,y+h,nvgRGBA(rt,gt,bt,at),nvgRGBA(rb,gb,bb,ab)));
    nvgFill(g_ctx);
}
void nvg_win32_fill_round(float x,float y,float w,float h,float rad,unsigned char r,unsigned char g,unsigned char b,unsigned char a) {
    nvgBeginPath(g_ctx); nvgRoundedRect(g_ctx,x,y,w,h,rad); nvgFillColor(g_ctx,nvgRGBA(r,g,b,a)); nvgFill(g_ctx);
}
void nvg_win32_fill_round_v(float x,float y,float w,float h,float rad,unsigned char rt,unsigned char gt,unsigned char bt,unsigned char at,unsigned char rb,unsigned char gb,unsigned char bb,unsigned char ab) {
    nvgBeginPath(g_ctx); nvgRoundedRect(g_ctx,x,y,w,h,rad);
    nvgFillPaint(g_ctx,nvgLinearGradient(g_ctx,x,y,x,y+h,nvgRGBA(rt,gt,bt,at),nvgRGBA(rb,gb,bb,ab)));
    nvgFill(g_ctx);
}
void nvg_win32_stroke_rect(float x,float y,float w,float h,unsigned char r,unsigned char g,unsigned char b,unsigned char a,int width) {
    nvgBeginPath(g_ctx); nvgRect(g_ctx,x,y,w,h); nvgStrokeColor(g_ctx,nvgRGBA(r,g,b,a)); nvgStrokeWidth(g_ctx,(float)(width<1?1:width)); nvgStroke(g_ctx);
}
void nvg_win32_stroke_round(float x,float y,float w,float h,float rad,unsigned char r,unsigned char g,unsigned char b,unsigned char a,int width) {
    nvgBeginPath(g_ctx); nvgRoundedRect(g_ctx,x,y,w,h,rad); nvgStrokeColor(g_ctx,nvgRGBA(r,g,b,a)); nvgStrokeWidth(g_ctx,(float)(width<1?1:width)); nvgStroke(g_ctx);
}
void nvg_win32_stroke_line(float ax,float ay,float bx,float by,unsigned char r,unsigned char g,unsigned char b,unsigned char a,int width) {
    nvgBeginPath(g_ctx); nvgMoveTo(g_ctx,ax,ay); nvgLineTo(g_ctx,bx,by); nvgStrokeColor(g_ctx,nvgRGBA(r,g,b,a)); nvgStrokeWidth(g_ctx,(float)(width<1?1:width)); nvgStroke(g_ctx);
}
void nvg_win32_push_clip(float x,float y,float w,float h) { nvgSave(g_ctx); nvgScissor(g_ctx,x,y,w,h); }
void nvg_win32_pop(void) { nvgRestore(g_ctx); }
void nvg_win32_translate(float x,float y) { nvgSave(g_ctx); nvgTranslate(g_ctx,x,y); }
