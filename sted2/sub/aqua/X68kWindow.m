/* X68kWindow.m */
/* An X680x0 emulating window for sted2_aqua. */
/* Jun.01.2003 Toshi Nagata */
/* Copyright 2003 Toshi Nagata. All rights reserved. */

#import "X68kWindow.h"
#import "CoreMIDIRCPPlayer.h"

#include "sted.h"

static X68kWindow *sWindow = nil;

static RGBColor sTextPalette[16] = {
	{0xffff, 0xffff, 0xffff},
	{0xffff, 0xffff, 0},
	{0, 0xffff, 0xffff},
	{0, 0, 0}
};

static RGBColor sGraphPalette[16] = {
	{0xffff, 0xffff, 0xffff},
	{0xffff, 0xffff, 0},
	{0xffff, 0, 0xffff},
	{0xffff, 0, 0},
	{0, 0xffff, 0xffff},
	{0, 0xffff, 0},
	{0, 0, 0xffff},
	{0, 0, 0},
	{0xffff, 0xffff, 0xffff},
	{0xffff, 0xffff, 0},
	{0xffff, 0, 0xffff},
	{0xffff, 0, 0},
	{0, 0xffff, 0xffff},
	{0, 0xffff, 0},
	{0, 0, 0xffff},
	{0, 0, 0}
};

static RGBColor sWhite = {0xffff, 0xffff, 0xffff};
//static RGBColor sBlack = {0, 0, 0};
//static RGBColor sBlue = {0, 0, 0xffff};
//static RGBColor sRed = {0xffff, 0, 0};

//static X68kView *sCurrent = nil;
static long sCurWidth, sCurHeight;
static long sCurAscent, sCurLineHeight, sCurCharWidth;
static long sX68kWidth = 768, sX68kHeight = 512;
static long sX68kTextWidth = 96, sX68kTextHeight = 32;
static short sFont, sSize;
static short sTextColor = 3;
static short sGraphColor = 15;

static unsigned char sKeyTable[128] = {
	/*08    19    2a    3b    4c    5d    6e    7f  */
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x0f, 0x10, 0x00, 0x00, 0x00, 0x1d, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
	0x35, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, /*  !"@#$%' */
	0x09, 0x0a, 0x28, 0x27, 0x31, 0x0c, 0x32, 0x33, /* ()*+,-./ */
	0x0b, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, /* 01234567 */
	0x09, 0x0a, 0x28, 0x27, 0x31, 0x0c, 0x32, 0x33, /* 89:;<=>? */
	0x1b, 0x1e, 0x2e, 0x2c, 0x20, 0x13, 0x21, 0x22, /* @ABCDEFG */
	0x23, 0x18, 0x24, 0x25, 0x26, 0x30, 0x2f, 0x19, /* HIJKLMNO */
	0x1a, 0x11, 0x14, 0x1f, 0x15, 0x17, 0x2d, 0x12, /* PQRSTUVW */
	0x2b, 0x16, 0x2a, 0x1c, 0x0e, 0x29, 0x0d, 0x34, /* XYZ[\]^_ */
	0x1b, 0x1e, 0x2e, 0x2c, 0x20, 0x13, 0x21, 0x22, /* `abcdefg */
	0x23, 0x18, 0x24, 0x25, 0x26, 0x30, 0x2f, 0x19, /* hijklmno */
	0x1a, 0x11, 0x14, 0x1f, 0x15, 0x17, 0x2d, 0x12, /* pqrstuvw */
	0x2b, 0x16, 0x2a, 0x1c, 0x0e, 0x29, 0x0d, 0x00  /* xyz{|}~  */
};

static unsigned char sPadKeyTable[64] = {
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x0f, 0x10, 0x00, 0x00, 0x00, 0x4e, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x41, 0x46, 0x00, 0x42, 0x51, 0x40,
	0x4f, 0x4b, 0x4c, 0x4d, 0x47, 0x48, 0x49, 0x43,
	0x44, 0x45, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};


enum {
	x68k_up = 0x3c,
	x68k_down = 0x3e,
	x68k_left = 0x3b,
	x68k_right = 0x3d,
	x68k_f1 = 0x63,
	x68k_f2 = 0x64,
	x68k_f3 = 0x65,
	x68k_f4 = 0x66,
	x68k_f5 = 0x67,
	x68k_f6 = 0x68,
	x68k_f7 = 0x69,
	x68k_f8 = 0x6a,
	x68k_f9 = 0x6b,
	x68k_f10 = 0x6c,
	x68k_xf1 = 0x55,
	x68k_xf2 = 0x56,
	x68k_xf3 = 0x57,
	x68k_xf4 = 0x58,
	x68k_xf5 = 0x59,
	x68k_touroku = 0x53,
	x68k_kigou = 0x52,
	x68k_kana = 0x51,  /* ??? */
	x68k_del = 0x37,
	x68k_home = 0x36,
	x68k_rollup = 0x39,
	x68k_rolldown = 0x38,
	x68k_clr = 0x35,
	x68k_ins = 0x5e,
	x68k_undo = 0x3a
};

/*  Key combination -> X68k special key conversion table  */
/*  bit 0-15 = Mac key code (unicode)  */
/*  bit 16 = unused, bit 17 = control mask, bit 18 = option mask  */
/*  bit 24-31 = X68k key code  */
static unsigned long s_x68k_special_key[128] = {
	(x68k_up << 24) + NSUpArrowFunctionKey,
	(x68k_down << 24) + NSDownArrowFunctionKey,
	(x68k_left << 24) + NSLeftArrowFunctionKey,
	(x68k_right << 24) + NSRightArrowFunctionKey,
	(x68k_f1 << 24) + NSF1FunctionKey,
	(x68k_f2 << 24) + NSF2FunctionKey,
	(x68k_f3 << 24) + NSF3FunctionKey,
	(x68k_f4 << 24) + NSF4FunctionKey,
	(x68k_f5 << 24) + NSF5FunctionKey,
	(x68k_f6 << 24) + NSF6FunctionKey,
	(x68k_f7 << 24) + NSF7FunctionKey,
	(x68k_f8 << 24) + NSF8FunctionKey,
	(x68k_f9 << 24) + NSF9FunctionKey,
	(x68k_f10 << 24) + NSF10FunctionKey,
//	(x68k_f1 << 24) + (1 << 17) + '1',  /*  ctrl-1  */
//	(x68k_f2 << 24) + (1 << 17) + '2',
//	(x68k_f3 << 24) + (1 << 17) + '3',
//	(x68k_f4 << 24) + (1 << 17) + '4',
//	(x68k_f5 << 24) + (1 << 17) + '5',
//	(x68k_f6 << 24) + (1 << 17) + '6',
//	(x68k_f7 << 24) + (1 << 17) + '7',
//	(x68k_f8 << 24) + (1 << 17) + '8',
//	(x68k_f9 << 24) + (1 << 17) + '9',
//	(x68k_f10 << 24) + (1 << 17) + '0',
//	(x68k_xf1 << 24) + (1 << 18) + NSF1FunctionKey,  /*  Option + F1  */
//	(x68k_xf2 << 24) + (1 << 18) + NSF2FunctionKey,
//	(x68k_xf3 << 24) + (1 << 18) + NSF3FunctionKey,
//	(x68k_xf4 << 24) + (1 << 18) + NSF4FunctionKey,
//	(x68k_xf5 << 24) + (1 << 18) + NSF5FunctionKey,
//	(x68k_xf1 << 24) + (1 << 17) + (1 << 18) + '1',  /*  ctrl-option-1  */
//	(x68k_xf2 << 24) + (1 << 17) + (1 << 18) + '2',
//	(x68k_xf3 << 24) + (1 << 17) + (1 << 18) + '3',
//	(x68k_xf4 << 24) + (1 << 17) + (1 << 18) + '4',
//	(x68k_xf5 << 24) + (1 << 17) + (1 << 18) + '5',
	(x68k_touroku << 24) + NSF11FunctionKey,
	(x68k_kigou << 24) + NSF12FunctionKey,
	(x68k_del << 24) + NSDeleteFunctionKey,
	(x68k_home << 24) + NSHomeFunctionKey,
	(x68k_rollup << 24) + NSPageUpFunctionKey,
	(x68k_rolldown << 24) + NSPageDownFunctionKey,
	(x68k_clr << 24) + NSClearLineFunctionKey
};

@implementation X68kWindow

- (id)initWithContentRect:(NSRect)contentRect styleMask:(unsigned int)styleMask backing:(NSBackingStoreType)backingType defer:(BOOL)flag
{
	self = [super initWithContentRect: contentRect styleMask: styleMask backing: backingType defer: flag];
	sWindow = self;
	return self;
}
- (void)setUpX68kScreen: (NSRect)frameRect
{
	NSRect frame;
	frame = [self frame];
	frame.size = frameRect.size;
//	[self setFrame: frame display: YES];
	[self setContentSize: frame.size];
//	if (sCurrent != nil) {
//		[sCurrent removeFromSuperview];
//		[sCurrent release];
//		sCurrent = nil;
//	}
//	sCurrent = [[X68kView alloc] initWithFrame: frameRect];
//	[[self contentView] addSubview: sCurrent];
}
- (IBAction)refreshDisplay:(id)sender
{
//	if (sCurrent != nil)
//		[sCurrent setNeedsDisplay:YES];
}

@end
