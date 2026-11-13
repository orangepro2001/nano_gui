#ifndef NVG_WIN32_API_H
#define NVG_WIN32_API_H
#ifdef __cplusplus
extern "C" {
#endif
int nvg_win32_init(void* hdc, int w, int h);
void nvg_win32_shutdown(void);
int nvg_win32_resize(int w, int h);
void nvg_win32_begin(int w, int h);
void nvg_win32_end(void);
void nvg_win32_present(int w, int h);
void nvg_win32_fill(float,float,float,float,unsigned char,unsigned char,unsigned char,unsigned char);
void nvg_win32_fill_v(float,float,float,float,unsigned char,unsigned char,unsigned char,unsigned char,unsigned char,unsigned char,unsigned char,unsigned char);
void nvg_win32_fill_round(float,float,float,float,float,unsigned char,unsigned char,unsigned char,unsigned char);
void nvg_win32_fill_round_v(float,float,float,float,float,unsigned char,unsigned char,unsigned char,unsigned char,unsigned char,unsigned char,unsigned char,unsigned char);
void nvg_win32_stroke_rect(float,float,float,float,unsigned char,unsigned char,unsigned char,unsigned char,int);
void nvg_win32_stroke_round(float,float,float,float,float,unsigned char,unsigned char,unsigned char,unsigned char,int);
void nvg_win32_stroke_line(float,float,float,float,unsigned char,unsigned char,unsigned char,unsigned char,int);
void nvg_win32_push_clip(float,float,float,float);
void nvg_win32_pop(void);
void nvg_win32_translate(float,float);
#ifdef __cplusplus
}
#endif
#endif
