/* X68kWindow.h */
/* Header file for X68kWindow, an X680x0 emulating window for sted2_aqua. */
/* Jun.01.2003 Toshi Nagata */
/* Copyright 2003 Toshi Nagata. All rights reserved. */

#include <Carbon/Carbon.h>

void XSTed_start_main(int (*mainPtr)(int, char **), int argc, char **argv);
void XSTed_init_window(void);

void XSTed_txbox(short x0, short y0, short x1, short y1, unsigned short p);
void XSTed_txxline(unsigned short p, short x0, short y0, short x1, unsigned short ls);
void XSTed_txyline(unsigned short p, short x0, short y0, short y1, unsigned short ls);
void XSTed_trev(int xch, int ych, int lch, int col);
void XSTed_rev_area(int r_ad, int r_ln, int edit_scr);
void XSTed_tfill(unsigned short p, short x0, short y0, short x1, short y1, unsigned short ls);
void XSTed_trascpy(int src, int dst, int line, int mode);
void XSTed_t_scrw(int x1, int y1, int xs, int ys, int x2, int y2);
void XSTed_gbox(int x1, int y1, int x2, int y2, unsigned int col, unsigned int ls);
void XSTed_gfill(int x1, int y1, int x2, int y2, int col);
int XSTed_gpoint(int x, int y);
void XSTed_gline(int x1, int y1, int x2, int y2, int col, int ls);
void XSTed_tg_copy(int edit_scr);
void XSTed_tg_copy2(int edit_scr);
void XSTed_ghome(int home_flag);
void XSTed_gclr(void);
void XSTed_tclr(void);
void XSTed_cls_al(void);
int XSTed_gpalet(int pal, int col);
int XSTed_tpalet(int pal, int col);
int XSTed_tcolor(int col);
int XSTed_gcolor(int col);
int XSTed_SetTCol(int col);
int XSTed_SetGCol(int col);
void XSTed_curon(void);
void XSTed_curoff(void);
void XSTed_tlocate(int x, int y);
void XSTed_tputs(char *message);
void XSTed_gputs(int x0, int y0, const char *message);
void XSTed_cls_eol(void);
void XSTed_cls_ed(void);
int XSTed_keyin(int code);
void XSTed_key_wait(void);

#ifdef __OBJC__

#import <Cocoa/Cocoa.h>
@interface X68kWindow : NSWindow
{
}
- (void)setUpX68kScreen: (NSRect)frameRect;
- (IBAction)refreshDisplay:(id)sender;
@end

#endif __OBJC__

