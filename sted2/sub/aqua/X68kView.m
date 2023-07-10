/* X68kView.m */
/* An X680x0 emulating window for sted2_aqua. */
/* Jun.01.2003 Toshi Nagata */
/* Copyright 2003 Toshi Nagata. All rights reserved. */

#import "X68kView.h"
#import "CoreMIDIRCPPlayer.h"

#include "sted.h"

NSString *STed2ScreenRedrawNotification = @"STed2 screen redraw";

//
//  Basic design of X68kView
//
//    The X680x0 program runs in a single thread, and the user interface
//  (keyboard/mouse input and screen output) are accessed upon request
//  from the thread. This is in contrast with the event-driven model
//  in most modern GUI operating systems.
//    One simple implementation is to run the X680x0 program in a
//  background thread, and the user interface is handled in the main
//  thread. The main thread and the background thread communicate
//  each other via a shared memory mechanism.
//    Another complication with the X680x0 architecture is the use of
//  two separate graphic screens, namely 'text' and 'graphic'. If the
//  above execution model is used, the contents of these graphic screens
//  can be retained as offscreen memory buffers, and the real window is
//  updated in the main thread as requested from the background thread.

static NSLock *sLock;     //  The lock to access shared memory

//  Offscreen buffers
static uint8_t *sTextVram;         //  The 'text' VRAM data as in X680x0 screen (bit 0-3 = plane 0-3)
static uint8_t *sGraphVram;     //  The 'graphic' screen buffer (4-bit color)
static uint32_t *sCompositeBitmap; //  The composite screen buffer 
static NSRect sTextInvalRect;      //  The rectangle to be redrawn in the main thread
static NSRect sGraphInvalRect;     //  ibid

//  Key inputs
#define kKeyBufferMax 128
static uint16_t sKeyBuffer[kKeyBufferMax];
static int sKeyBufferBase, sKeyBufferCount;

//  The screen coordinate of the upper-left point of the real graphic screen.
static NSPoint sGraphOrigin;

static int sCursorX, sCursorY;
static BOOL sCursorOn;
static int sTextColor = 3;
static int sGraphColor = 15;

static unsigned int sModifierFlags;
//static unsigned int sModifierChange;
static unsigned short sLastKeyDown;  //  The last getKeyWithOptions: return value

static int sRequestAppKitCall;
static void **sRequestAppKitArgs;

//  End of shared memory variables

static NSView *sMainView;
static NSTimer *sTimer;

//  The palette values are to be stored in big-endian format
static char sPaletteEndianIsFixed = 0;  //  Endian conversion should be done only once
static uint32_t sTextPalette[4] = {
	0, 0xffff00ff, 0x00ffffff, 0xffffffff
};
static uint32_t sGraphPalette[16] = {
	0, 0x0000ffff, 0xff0000ff, 0xff00ffff, 0x00ff00ff, 0x00ffffff, 0xffff00ff, 0xffffffff,
	0, 0x0000ffff, 0xff0000ff, 0xff00ffff, 0x00ff00ff, 0x00ffffff, 0xffff00ff, 0xffffffff
};

//  8x16 bitmap font data for characters 0x20-0x7f (alpha-numeric)
//  and 0xa0-0xdf (hankaku kana).
//  One character is represented by 16-byte bitmap.

static unsigned char *sFontData;  /* 16*160 */
static unsigned char *sKanjiData; /* 32*47*188 */

#if 1
#define _NSLog NSLog
#else
inline void  _NSLog() {}
#endif

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
	x68k_kana = 0x5a,
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
	(x68k_f1 << 24) + (1 << 17) + '1',  /*  ctrl-1  */
	(x68k_f2 << 24) + (1 << 17) + '2',
	(x68k_f3 << 24) + (1 << 17) + '3',
	(x68k_f4 << 24) + (1 << 17) + '4',
	(x68k_f5 << 24) + (1 << 17) + '5',
	(x68k_f6 << 24) + (1 << 17) + '6',
	(x68k_f7 << 24) + (1 << 17) + '7',
	(x68k_f8 << 24) + (1 << 17) + '8',
	(x68k_f9 << 24) + (1 << 17) + '9',
	(x68k_f10 << 24) + (1 << 17) + '0',
	(x68k_xf1 << 24) + (1 << 18) + NSF1FunctionKey,  /*  Option + F1  */
	(x68k_xf2 << 24) + (1 << 18) + NSF2FunctionKey,
	(x68k_xf3 << 24) + (1 << 18) + NSF3FunctionKey,
	(x68k_xf4 << 24) + (1 << 18) + NSF4FunctionKey,
	(x68k_xf5 << 24) + (1 << 18) + NSF5FunctionKey,
	(x68k_xf1 << 24) + (1 << 17) + (1 << 18) + '1',  /*  ctrl-option-1  */
	(x68k_xf2 << 24) + (1 << 17) + (1 << 18) + '2',
	(x68k_xf3 << 24) + (1 << 17) + (1 << 18) + '3',
	(x68k_xf4 << 24) + (1 << 17) + (1 << 18) + '4',
	(x68k_xf5 << 24) + (1 << 17) + (1 << 18) + '5',
	(x68k_touroku << 24) + NSF11FunctionKey,
	(x68k_kigou << 24) + NSF12FunctionKey,
	(x68k_del << 24) + NSDeleteFunctionKey,
	(x68k_home << 24) + NSHomeFunctionKey,
	(x68k_rollup << 24) + NSPageUpFunctionKey,
	(x68k_rolldown << 24) + NSPageDownFunctionKey,
	(x68k_clr << 24) + NSClearLineFunctionKey
};

@implementation X68kView

- (void)awakeFromNib
{
	int i;
	FILE *fp;

	sLock = [[NSLock alloc] init];
	
	sCompositeBitmap = (uint32_t *)calloc(sizeof(uint32_t), sTextWidth * sTextHeight);
	sGraphVram = (uint8_t *)calloc(sizeof(uint8_t), sGraphWidth * sGraphHeight);
	sTextVram = (uint8_t *)calloc(sizeof(uint8_t), sTextWidth * sTextHeight);
	
	if (sPaletteEndianIsFixed == 0) {
		sPaletteEndianIsFixed = 1;
		for (i = 0; i < 4; i++)
			sTextPalette[i] = NSSwapHostIntToBig(sTextPalette[i]);
		for (i = 0; i < 16; i++)
			sGraphPalette[i] = NSSwapHostIntToBig(sGraphPalette[i]);
	}
}

+ (void)initializeX68k
{
	sTextInvalRect = NSZeroRect;
	sGraphInvalRect = NSZeroRect;

	sKeyBufferBase = 0;
	sKeyBufferCount = 0;
	
	//  The following code snippet was used in generating the bitmap data
#if 0
	{
		static uint32_t *sBitmapBuffer;
		NSDictionary *attr;
		NSGraphicsContext *sTextContext;
		NSBitmapImageRep *rep;
		char ch[10];
		int i, j, xx, yy;
		uint16_t b;
		FILE *fp1, *fp2;
		NSString *s;
	
		sBitmapBuffer = (uint32_t *)calloc(sizeof(uint32_t), 1024);
		
		rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:(uint8_t **)&sBitmapBuffer pixelsWide:32 pixelsHigh:32 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
		sTextContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
		[sTextContext setShouldAntialias:NO];
		[NSGraphicsContext saveGraphicsState];
		[NSGraphicsContext setCurrentContext:sTextContext];
		attr = [NSDictionary dictionaryWithObjectsAndKeys:[NSFont fontWithName:@"Sazanami-Gothic-Regular" size:16], NSFontAttributeName, [NSColor whiteColor], NSForegroundColorAttributeName, nil];
//	attr = [NSDictionary dictionaryWithObjectsAndKeys:[NSFont userFixedPitchFontOfSize:14], NSFontAttributeName, [NSColor whiteColor], NSForegroundColorAttributeName, nil];
		fp1 = fopen("fontdata.bin", "wb");
		fp2 = fopen("fontdata.ascii", "w");
		for (i = 0; i < 160; i++) {
			/*	if (i == 96)
			 attr = [NSDictionary dictionaryWithObjectsAndKeys:[NSFont userFixedPitchFontOfSize:16], NSFontAttributeName, [NSColor whiteColor], NSForegroundColorAttributeName, nil]; */
			if (i == 95 || i == 96) {
				ch[0] = 32;
				ch[1] = 0;
			} else if (i < 96) {
				ch[0] = i + 32;
				ch[1] = 0;
			} else if (i < 128) {
				ch[0] = 0xef;
				ch[1] = 0xbd;
				ch[2] = 0xa0 + (i - 96);
				ch[3] = 0;
			} else {
				ch[0] = 0xef;
				ch[1] = 0xbe;
				ch[2] = 0x80 + (i - 128);
				ch[3] = 0;
			}
			s = [[NSString alloc] initWithUTF8String:ch];
			memset(sBitmapBuffer, 0, sizeof(sBitmapBuffer[0]) * 1024);
			[s drawWithRect:NSMakeRect(0, 0, 16, 32) options:NSStringDrawingUsesLineFragmentOrigin	attributes:attr];
			[s release];
			fprintf(fp2, "%02x:\n", (i < 96 ? i + 32 : i + 0xa0));
			for (yy = 0; yy < 16; yy++) {
				b = 0;
				for (xx = 0; xx < 8; xx++) {
					if (sBitmapBuffer[(yy + 6) * 32 + xx] != 0)
						b |= (1 << xx);
					fprintf(fp2, "%c", (b & (1 << xx)) ? '#' : '.');
				}
				fprintf(fp2, "\n");
				fputc(b, fp1);
			}
		//	if (i < 95)
		//		fprintf(fp1, "/* %c */\n", i + 32);
		//	else fprintf(fp1, "/* \\uFF%02X */\n", i - 96 + 0x60);
		}
		
		for (i = 0; i < 47; i++) {  /* 0x81-0x9f/0xe0-0xef */
			for (j = 0; j < 188; j++) {  /* 0x40-0x7e/0x80-0xfc */
				int c1, c2;
				c1 = (i < 31 ? i + 0x81 : i + (0xe0 - 31));
				c2 = (j < 63 ? j + 0x40 : j + (0x80 - 63));
				ch[0] = c1;
				ch[1] = c2;
				ch[2] = 0;
				s = [[NSString alloc] initWithCString:ch encoding:NSShiftJISStringEncoding];
				memset(sBitmapBuffer, 0, sizeof(sBitmapBuffer[0]) * 1024);
				[s drawWithRect:NSMakeRect(0, 0, 32, 32) options:NSStringDrawingUsesLineFragmentOrigin	attributes:attr];
				[s release];
				fprintf(fp2, "%02x%2x:\n", c1, c2);
				for (yy = 0; yy < 16; yy++) {
					const char *p;
					b = 0;
					for (xx = 0; xx < 16; xx++) {
						if (sBitmapBuffer[(yy + 6) * 32 + xx] != 0)
							b |= (1 << xx);
						fprintf(fp2, "%c", (b & (1 << xx)) ? '#' : '.');
					}
					fprintf(fp2, "\n");
					if (yy == 7)
						p = ",\n    ";
					else if (yy == 15 && i == 62 && j == 187)
						p = "";
					else p = ",";
					fputc(b & 0xff, fp1);
					fputc((b >> 8) & 0xff, fp1);
				}
			}
		}		

		[NSGraphicsContext restoreGraphicsState];
		fclose(fp1);
		fclose(fp2);
	}
#endif

}

- (void)timerHandler:(NSTimer *)aTimer
{
	int x1, y1, x2, y2, x, y, xx, yy;
	NSRect rect;

	//  Handle AppKit request
	if (sRequestAppKitCall != 0) {
		void (*func_handler)(void **) = (void (*)(void **))sRequestAppKitArgs[0];
		(*func_handler)(sRequestAppKitArgs + 1);
	}
	
	rect = NSUnionRect(sTextInvalRect, sGraphInvalRect);

	if (rect.size.width != 0.0 && rect.size.height != 0.0) {
		//  Composite the text screen and the graph screen
		uint8_t *tp, *gp;
		uint32_t c;
		
		[sLock lock];
		
		x1 = rect.origin.x;
		y1 = rect.origin.y;
		x2 = rect.origin.x + rect.size.width;
		y2 = rect.origin.y + rect.size.height;
		if (x1 < 0)
			x1 = 0;
		if (x2 > sTextWidth)
			x2 = sTextWidth;
		if (y1 < 0)
			y1 = 0;
		if (y2 > sTextHeight)
			y2 = sTextHeight;
		rect.origin.x = x1;
		rect.origin.y = y1;
		rect.size.width = x2 - x1;
		rect.size.height = y2 - y1;
		for (y = y1; y < y2; y++) {
			if (y >= 0 && y < sTextHeight)
				tp = &sTextVram[y * sTextWidth];
			else tp = NULL;
			yy = y + sGraphOrigin.y;
			if (yy >= 0 && yy < sGraphHeight)
				gp = &sGraphVram[yy * sGraphWidth];
			else gp = NULL;
			for (x = x1; x < x2; x++) {
				xx = x + sGraphOrigin.x;
				if (gp != NULL && xx >= 0 && xx < sGraphWidth)
					c = sGraphPalette[gp[xx] % 16];
				else c = 0;
				if (tp != NULL && x >= 0 && x < sTextWidth)
					c |= sTextPalette[tp[x] % 4];
				sCompositeBitmap[y * sTextWidth + x] = c;
			}
		}

		sTextInvalRect = NSZeroRect;
		sGraphInvalRect = NSZeroRect;
				
		[sLock unlock];

		//  Create a new NSBitmapImageRep
		//  (It is necessary to create a new instance every time when the bitmap is
		//  externally modified.)
		if (bitmapRep != nil)
			[bitmapRep release];
		bitmapRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:(unsigned char **)&sCompositeBitmap pixelsWide:sTextWidth pixelsHigh:sTextHeight bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:32];
		
		//  Request redraw
		rect.origin.y = sTextHeight - (rect.origin.y + rect.size.height);
		[sMainView setNeedsDisplayInRect:rect];

	//	printf("timerHandler - setNeedsDisplayInRect:(%f,%f,%f,%f)\n", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
		
		if (0) {  /*  For debug  */
			[[bitmapRep TIFFRepresentation] writeToFile:@"/Users/toshi_n/STed_composedBitmap.tiff" atomically:YES];
			int i;
			for (i = 0; i < sTextWidth * sTextHeight; i++)
				sTextVram[i] *= 64;
			NSBitmapImageRep *textVram = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:(unsigned char **)&sTextVram pixelsWide:sTextWidth pixelsHigh:sTextHeight bitsPerSample:8 samplesPerPixel:1 hasAlpha:NO isPlanar:NO colorSpaceName:NSCalibratedWhiteColorSpace bytesPerRow:0 bitsPerPixel:8];
			[[textVram TIFFRepresentation] writeToFile:@"/Users/toshi_n/STed_textVram.tiff" atomically:YES];
			for (i = 0; i < sTextWidth * sTextHeight; i++)
				sTextVram[i] /= 64;
			for (i = 0; i < sGraphWidth * sGraphHeight; i++)
				sGraphVram[i] *= 16;
			NSBitmapImageRep *graphBitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:(unsigned char **)&sGraphVram pixelsWide:sGraphWidth pixelsHigh:sGraphHeight bitsPerSample:8 samplesPerPixel:1 hasAlpha:NO isPlanar:NO colorSpaceName:NSCalibratedWhiteColorSpace bytesPerRow:0 bitsPerPixel:8];
			[[graphBitmap TIFFRepresentation] writeToFile:@"/Users/toshi_n/STed_graphBitmap.tiff" atomically:YES];			
			for (i = 0; i < sGraphWidth * sGraphHeight; i++)
				sGraphVram[i] /= 16;
		}
		
	}
}

- (void)drawRect: (NSRect)rect
{
	if (sMainView == nil) {
		sMainView = self;
		sTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(timerHandler:) userInfo:nil repeats:YES];
	}
	if (bitmapRep != nil) {
		[bitmapRep drawAtPoint:NSZeroPoint];
	}
//	printf("drawRect\n");
}

- (BOOL)acceptsFirstResponder
{
	return YES;
}

//  Bits 0-7: ASCII code
//  Bits 8-15: scan code
//  Bits 16-19: modifier key mask (used internally)
static unsigned long
eventToX68kKeyInfo(NSEvent *theEvent)
{
	unichar theChar;
	unsigned int theMask;
	unsigned long keyCode = 0, keyMask = 0;
	int i;
	theMask = [theEvent modifierFlags];
	keyMask = 0;
	if (theMask & NSShiftKeyMask)
		keyMask |= 1;
	if (theMask & NSControlKeyMask)
		keyMask |= 2;
	if (theMask & NSAlternateKeyMask)
		keyMask |= 4;	/* Opt.1 */
	if (theMask & NSAlphaShiftKeyMask)
		keyMask |= 8;   /* Opt.2 */
	theChar = [[theEvent charactersIgnoringModifiers] characterAtIndex: 0];
	for (i = 0; i < sizeof(s_x68k_special_key) / sizeof(s_x68k_special_key[0]); i++) {
		if (s_x68k_special_key[i] == 0)
			break;
		if ((s_x68k_special_key[i] & 0xffff) == theChar
		&& ((s_x68k_special_key[i] >> 16) & 6) == (keyMask & 6)) {
			keyCode = (s_x68k_special_key[i] >> 16) & 0xff00;
		//	NSLog(@"keyCode = %d", (int)keyCode);
		}
	}
	if (keyCode == 0) {
		theChar = [[theEvent characters] characterAtIndex: 0];
		if (theChar > 0 && theChar < 128) {
			if ((theMask & NSNumericPadKeyMask) && theChar < 64) {
				keyCode = sPadKeyTable[theChar];
			} else {
				keyCode = sKeyTable[theChar];
			}
			keyCode = (keyCode << 8) + theChar;
		}
	}
	return (keyMask << 16) | keyCode;
}

//  Register key down event in the ring buffer.
//  [sLock lock] should have been called.
static void
s_RegisterKeyDown(int ch)
{
	if (ch != 0) {
		if (sKeyBufferCount < kKeyBufferMax) {
			sKeyBuffer[(sKeyBufferBase + sKeyBufferCount) % kKeyBufferMax] = ch;
			sKeyBufferCount++;
		}
	}
//	printf("registerKeyDown %04x\n", ch);
}

- (void)keyDown: (NSEvent *)theEvent
{
	unsigned long keyInfo;
	unsigned int flags, flagsChange;
	[sLock lock];
	flags = [theEvent modifierFlags];
	flagsChange = (sModifierFlags ^ flags);
	if ([theEvent type] == NSKeyDown) {
		keyInfo = eventToX68kKeyInfo(theEvent);
		s_RegisterKeyDown(keyInfo & 0xffff);
	} else {
		if (flagsChange != 0) {
			if (flagsChange & NSControlKeyMask)
				s_RegisterKeyDown((0x71 + (flags & NSControlKeyMask ? 0 : 0x80)) << 8);
			if (flagsChange & NSShiftKeyMask)
				s_RegisterKeyDown((0x70 + (flags & NSShiftKeyMask ? 0 : 0x80)) << 8);
			if (flagsChange & NSAlternateKeyMask)
				s_RegisterKeyDown((0x72 + (flags & NSAlternateKeyMask ? 0 : 0x80)) << 8);
			if (flagsChange & NSAlphaShiftKeyMask)
				s_RegisterKeyDown((0x73 + (flags & NSAlphaShiftKeyMask ? 0 : 0x80)) << 8);
		}
	}
	[sLock unlock];
}

- (void)flagsChanged:(NSEvent *)theEvent
{
	[self keyDown:theEvent];
}

- (void)keyUp:(NSEvent *)theEvent
{
	[self keyDown:theEvent];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
	NSTextField *tf = (NSTextField *)control;
	NSString *str = [tf stringValue];
	char *buf = (char *)sRequestAppKitArgs[1];
	int len = (int)sRequestAppKitArgs[2];
	if (command == @selector(insertNewline:)) {
		if ([str getCString:buf maxLength:len encoding:NSShiftJISStringEncoding]) {
			[tf removeFromSuperview];
			[[sMainView window] makeFirstResponder:sMainView];
			sRequestAppKitCall = 0;
			return YES;
		} else {
			NSString *mes;
			if ([str canBeConvertedToEncoding:NSShiftJISStringEncoding]) {
				mes = @"The string is too long.";
			} else {
				mes = @"The string includes non-Shift-JIS characters.";
			}
			NSAlert *alert = [NSAlert alertWithMessageText:nil defaultButton:nil alternateButton:nil otherButton:nil informativeTextWithFormat:@"%@", mes];
			[alert setAlertStyle:2];
			[alert runModal];
			return YES;
		}
	} else if (command == @selector(cancelOperation:)) {
		//  Esc key is pressed
		//  The original string is not changed, and editing will terminate
		[tf removeFromSuperview];
		[[sMainView window] makeFirstResponder:sMainView];
		sRequestAppKitCall = 0;
		return YES;
	}
	return NO;
}

#define kGetKeyNoWaitOption 1
#define kGetKeyKeepInBufferOption 2
#define kGetKeySenseModifiersOption 4

+ (unsigned short)getKeyWithOptions:(int)optionFlags
{
	uint16_t ch;
	int pt;
	while (1) {
		[sLock lock];
		for (pt = 0; pt < sKeyBufferCount; pt++) {
			ch = sKeyBuffer[(sKeyBufferBase + pt) % kKeyBufferMax];
			if ((optionFlags & kGetKeySenseModifiersOption) != 0 || ch < 0x7000)
				break;
		}
		if (pt < sKeyBufferCount) {
			if ((optionFlags & kGetKeyKeepInBufferOption) == 0) {
				//  Remove from the buffer
				sKeyBufferCount -= pt + 1;
				sKeyBufferBase = (sKeyBufferBase + pt + 1) % kKeyBufferMax;
			}
			[sLock unlock];
			break;
		}
		[sLock unlock];
		if (optionFlags & kGetKeyNoWaitOption) {
			ch = 0;
			break;
		}
		usleep(50000);  //  Wait for the main thread to handle the key event
	}
//	if (ch != 0)
//		printf("getKeyWithOptions %04x\n", ch);
	sLastKeyDown = ch;
	return ch;
}

#pragma mark "=== System setup functions ==="
			
void
XSTed_start_main(int (*mainPtr)(int, char **), int argc, char **argv)
{
//	extern char s_sted_default_path[1024];
	NSArray *args;
	NSString *pathString, *rsrcPathString;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	FILE *fp;

	/*  Set up the config files  */
	pathString = [@"~/Library/Application Support/sted" stringByExpandingTildeInPath];
	if (![fileManager fileExistsAtPath: pathString]) {
		/*  If the directory does not exist, then the "Resource/conf" directory in the main bundle is copied  */
		rsrcPathString = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"conf"];
		[fileManager copyPath: rsrcPathString toPath: pathString handler: nil];
	}
	if (![pathString getFileSystemRepresentation: s_sted_default_path maxLength: 1000])
		s_sted_default_path[0] = 0;
	
	/*  Read font data  */
	sFontData = (uint8_t *)malloc(sizeof(uint8_t) * 16 * 160);
	sKanjiData = (uint8_t *)malloc(sizeof(uint8_t) * 32 * 47 * 188);
	
	fp = fopen([[pathString stringByAppendingPathComponent:@"fontdata.bin"] fileSystemRepresentation], "rb");
	if (fp != NULL) {
		fread(sFontData, sizeof(uint8_t), 16 * 160, fp);
		fread(sKanjiData, sizeof(uint8_t), 32 * 47 * 188, fp);
		fclose(fp);
	} else {
		NSLog(@"Warning: cannot open fontdata.bin\n");
	}

	/*  Initialize CoreMIDI  */
	CoreMIDIInitIfNeeded();
	CoreMIDISelectDeviceForPort(0, 0);
	CoreMIDISelectDeviceForPort(1, 1);

	args = [NSArray arrayWithObjects:
			[NSValue valueWithPointer: mainPtr],
			[NSNumber numberWithInt: argc],
			[NSValue valueWithPointer: argv], nil];
	
	NSThread *thread = [[[NSThread alloc] initWithTarget:[NSApp delegate] selector:@selector(startX68kThread:) object:args] autorelease];
	[thread setStackSize:4*1024*1024];  //  4MB should be sufficient (the default 512K may be too small)
	[thread start];
}


void
XSTed_init_window(void)
{
	iswindowopened = 1;
}

void
XSTed_close_window(void)
{
}

void
XSTed_register_key(const char *str)
{
	char buf[128];
	char *p, *q, *r;
	int code, mask, n;
	unsigned long ul;
	static struct {
		const char *symbol;
		int code;
	} s_x68k_keysym_table[] = {
		{ "TOROKU", x68k_touroku },
		{ "KIGOU", x68k_kigou },
		{ "KANA", x68k_kana },
		{ "DEL", x68k_del },
		{ "HOME", x68k_home },
		{ "RUP", x68k_rollup },
		{ "RDOWN", x68k_rolldown },
		{ "CLR", x68k_clr },
		{ "INS", x68k_ins },
		{ "UNDO", x68k_undo },
		{ NULL, 0 }
	};
		
	strncpy(buf, str, 127);
	buf[127] = 0;
	p = buf + 5;   /*  skip 'KEY_'  */
	code = 0;
	q = strsep(&p, "=");
	while ((r = strrchr(q, ' ')) != NULL)
		*r = 0;
	if (strncasecmp(q, "XF", 2) == 0 && (n = atoi(q + 2)) >= 1 && n <= 5) {
		code = x68k_xf1 + n - 1;
	} else if (strncasecmp(q, "F", 1) == 0 && (n = atoi(q + 1)) >= 1 && n <= 10) {
		code = x68k_f1 + n - 1;
	} else if (strcasecmp(q, "TOROKU") == 0) {
		code = x68k_touroku;
	} else if (strcasecmp(q, "KIGOU") == 0) {
		code = x68k_kigou;
	} else if (strcasecmp(q, "KANA") == 0) {
		code = x68k_kana;
	} else {
		for (n = 0; s_x68k_keysym_table[n].symbol != NULL; n++) {
			if (strcasecmp(q, s_x68k_keysym_table[n].symbol) == 0) {
				code = s_x68k_keysym_table[n].code;
				break;
			}
		}
	}
	
	if (code == 0)
		return;

	while ((q = strsep(&p, " ")) != NULL) {
		if (*q == 0)
			continue;
		mask = 0;
		while (q != NULL && strchr(q, '-') != NULL) {
			r = strsep(&q, "-");
			if (strcasecmp(r, "c") == 0 || strcasecmp(r, "ctrl") == 0 || strcasecmp(r, "control") == 0)
				mask |= 2;
			else if (strcasecmp(r, "o") == 0 || strcasecmp(r, "opt") == 0 || strcasecmp(r, "option") == 0)
				mask |= 4;
		}
		if (q == NULL || *q == 0)
			continue;
		if (strcasecmp(q, "space") == 0)
			n = ' ';
		else if (strcasecmp(q, "up") == 0)
			n = NSUpArrowFunctionKey;
		else if (strcasecmp(q, "down") == 0)
			n = NSDownArrowFunctionKey;
		else if (strcasecmp(q, "left") == 0)
			n = NSLeftArrowFunctionKey;
		else if (strcasecmp(q, "right") == 0)
			n = NSRightArrowFunctionKey;
		else if (tolower(*q) == 'f' && (n = atoi(q + 1)) >= 1 && n <= 12)
			n = NSF1FunctionKey - 1 + n;
		else if (strcasecmp(q, "delete") == 0)
			n = NSDeleteFunctionKey;
		else if (strcasecmp(q, "home") == 0)
			n = NSHomeFunctionKey;
		else if (strcasecmp(q, "page_up") == 0)
			n = NSPageUpFunctionKey;
		else if (strcasecmp(q, "page_down") == 0)
			n = NSPageDownFunctionKey;
		else if (strcasecmp(q, "clear") == 0)
			n = NSClearLineFunctionKey;
		else if (strlen(q) == 1)
			n = tolower(*q) & 127;
		else n = 0;
		/*  Look up the table, and replace the entry if present  */
		ul = n | ((unsigned long)mask << 16);
		for (n = 0; n < 127; n++) {
			if (s_x68k_special_key[n] == 0
			|| (s_x68k_special_key[n] & 0x00ffffff) == ul) {
				s_x68k_special_key[n] = (ul | ((unsigned long)code << 24));
				break;
			}
		}
	}		
}

void
XSTed_register_midi_device(const char *str)
{
	char buf[128];
	char *p, *q, *r;
	int n;
	unsigned char input_flag;

	NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
	
	strncpy(buf, str, 127);
	buf[127] = 0;
	p = buf + 13;  /*  skip "#midi_device_"  */
	q = strsep(&p, "=");
	while ((r = strrchr(q, ' ')) != NULL)
		*r = 0;	
	if (strcasecmp(q, "input") == 0) {
		input_flag = 1;
	} else if (strcasecmp(q, "output") == 0) {
		input_flag = 0;
	} else return;
	
	n = 0;
	while ((q = strsep(&p, ",")) != NULL) {
		while (*q == ' ')
			q++;
		if (*q == 0)
			continue;
		if (input_flag == 0) {
			CoreMIDISelectDeviceByNameForPort(q, n);
			[def setValue:[NSString stringWithUTF8String:q] forKey:[NSString stringWithFormat:@"midiout%d", n + 1]];
		}
		n++;
	}
}

void
XSTed_configure_mac_settings(const char *line)
{
	if (strncasecmp(line, "#KEY_", 5) == 0)
		XSTed_register_key(line);
	if (strncasecmp(line, "#MIDI_DEVICE_", 13) == 0)
		XSTed_register_midi_device(line);
}

#pragma mark "=== Graphic functions ==="
			
static int
tpage(int plane)
{
	if (plane == 0)
		return 1;
	else if (plane == 1)
		return 2;
	else return 3;
}

static void
MakeRect(Rect *rect, short x0, short y0, short x1, short y1)
{
	if (x0 < x1) {
		rect->left = x0;
		rect->right = x1;
	} else {
		rect->left = x1;
		rect->right = x0;
	}
	if (y0 < y1) {
		rect->top = y0;
		rect->bottom = y1;
	} else {
		rect->top = y1;
		rect->bottom = y0;
	}
}

static void
InvalTextInRect(short x0, short y0, short x1, short y1)
{
	NSRect rect = NSMakeRect(x0, y0, x1 - x0, y1 - y0);
	if (sTextInvalRect.size.width == 0.0 || sTextInvalRect.size.height == 0.0)
		sTextInvalRect = rect;
	else {
		sTextInvalRect = NSUnionRect(sTextInvalRect, rect);
	}
}

static void
InvalGraphInRect(short x0, short y0, short x1, short y1)
{
	//  The rect must be in the screen coordinate
	NSRect rect = NSMakeRect(x0 - sGraphOrigin.x, y0 - sGraphOrigin.y, x1 - x0, y1 - y0);
	if (sGraphInvalRect.size.width == 0.0 || sGraphInvalRect.size.height == 0.0)
		sGraphInvalRect = rect;
	else {
		sGraphInvalRect = NSUnionRect(sGraphInvalRect, rect);
	}
}

void
XSTed_txxline(unsigned short p, short x0, short y0, short x1, unsigned short ls)
{
	short i;
	uint8_t col;
	if (y0 < 0 || y0 >= sTextHeight)
		return;
	if (x0 > x1) {
		i = x0;
		x0 = x1;
		x1 = i;
	}
	if (x0 < 0)
		x0 = 0;
	if (x1 >= sTextWidth)
		x1 = sTextWidth - 1;
	col = (ls == 0 ? 0 : tpage(p));
	[sLock lock];
	for (i = x0; i <= x1; i++) {
		sTextVram[y0 * sTextWidth + i] = col;
	}
	InvalTextInRect(x0, y0, x1 + 1, y0 + 1);
	[sLock unlock];
}

void
XSTed_txyline(unsigned short p, short x0, short y0, short y1, unsigned short ls)
{
	short i;
	uint8_t col;
	if (x0 < 0 || x0 >= sTextWidth)
		return;
	if (y0 > y1) {
		i = y0;
		y0 = y1;
		y1 = i;
	}
	if (y0 < 0)
		y0 = 0;
	if (y1 >= sTextHeight)
		y1 = sTextHeight - 1;
	col = (ls == 0 ? 0 : tpage(p));
	[sLock lock];
	for (i = y0; i <= y1; i++) {
		sTextVram[i * sTextWidth + x0] = col;
	}
	InvalTextInRect(x0, y0, x0 + 1, y1 + 1);
	[sLock unlock];
}

void
XSTed_txbox(short x0, short y0, short x1, short y1, unsigned short p)
{
	XSTed_txxline(p, x0, y0, x1, 1);
	XSTed_txyline(p, x1, y0, y1, 1);
	XSTed_txxline(p, x1, y1, x0, 1);
	XSTed_txyline(p, x0, y1, y0, 1);
}

void
XSTed_trev(int xch, int ych, int lch, int col)
{
	short x0, x1, y0, i, j;
	uint32_t *ip;
	x0 = xch * 8;
	y0 = ych * 16;
	if (y0 < 0 || y0 >= sTextHeight)
		return;
	x1 = (xch + lch) * 8;
	if (x0 < 0)
		x0 = 0;
	if (x1 >= sTextWidth)
		x1 = sTextWidth - 1;
	[sLock lock];
	for (i = x0; i < x1; i++) {
		for (j = 0; j < 16; j++) {
			sTextVram[(j + y0) * sTextWidth + i] ^= 3;
		}
	}
	InvalTextInRect(x0, y0, x1 + 1, y0 + 16);
	[sLock unlock];
}

void
XSTed_rev_area(int r_ad, int r_ln, int edit_scr)
{
//	printf("XSTed_rev_area %d %d %d\n", r_ad, r_ln, edit_scr);
	/*  Not implemented yet  */
}

void
XSTed_tfill(unsigned short p, short x0, short y0, short x1, short y1, unsigned short ls)
{
	uint8_t col;
	short i, j;
	if (x0 < 0)
		x0 = 0;
	if (x1 >= sTextWidth)
		x1 = sTextWidth - 1;
	if (y0 < 0)
		y0 = 0;
	if (y1 >= sTextHeight)
		y1 = sTextHeight - 1;
	col = (ls == 0 ? 0 : tpage(p));
	[sLock lock];
	for (i = x0; i <= x1; i++) {
		for (j = y0; j <= y1; j++) {
			sTextVram[j * sTextWidth + i] = col;
		}
	}
	InvalTextInRect(x0, y0, x1 + 1, y1 + 1);
	[sLock unlock];
//	printf("XSTed_tfill %d %d %d %d %d %d\n", p, x0, y0, x1, y1, ls);
}

void
XSTed_trascpy(int dst, int src, int line, int mode)
{
	int i;
	line /= 4;
	if (mode >= 0x8000) {
		/*  Move downward, dst > src  */
		src = (src - 3) / 4 - line + 1;
		dst = (dst - 3) / 4 - line + 1;
		if (dst + line >= sTextHeight / 16)
			line = sTextHeight / 16 - dst;
		if (line <= 0)
			return;
		[sLock lock];
		memmove(sTextVram + dst * 16 * sTextWidth, sTextVram + src * 16 * sTextWidth, line * 16 * sTextWidth);
		memset(sTextVram + src * 16 * sTextWidth, 0, (dst - src) * 16 * sTextWidth);
		InvalTextInRect(0, src * 16, sTextWidth, (dst + line) * 16);
		[sLock unlock];
	} else {
		/*  Move upward, dst < src  */
		src = src / 4;
		dst = dst / 4;
		if (src == 63) {
			/*  Clear  */
			if (dst + line >= sTextHeight / 16)
				line = sTextHeight / 16 - dst;
			if (line <= 0)
				return;
			[sLock lock];
		//	memset(sTextVram + dst * 16 * sTextWidth, 0, line * 16 * sTextWidth);
			InvalTextInRect(0, dst * 16, sTextWidth, (dst + line) * 16);
			[sLock unlock];
		} else {
			if (src + line >= sTextHeight / 16)
				line = sTextHeight / 16 - src;
			if (line <= 0)
				return;
			[sLock lock];
			memmove(sTextVram + dst * 16 * sTextWidth, sTextVram + src * 16 * sTextWidth, line * 16 * sTextWidth);
		//	memset(sTextVram + (dst + line) * 16 * sTextWidth, 0, (src - dst) * 16 * sTextWidth);
			InvalTextInRect(0, dst * 16, sTextWidth, (src + line) * 16);
			[sLock unlock];
		}
	}
}

void
XSTed_t_scrw(int x1, int y1, int xs, int ys, int x2, int y2)
{
	int xxs, yys, xc, xcs, y;
	x1 *= 8;
	y1 *= 8;
	x2 *= 8;
	y2 *= 8;
	if (x1 < 0) {
		xs += x1;
		x1 = 0;
	}
	if (y1 < 0) {
		ys += y1;
		y1 = 0;
	}
	if (xs <= 0 || ys <= 0)
		return;
	if (x2 + xs < sTextWidth)
		xxs = xs;
	else xxs = sTextWidth - x2;
	if (y2 + ys < sTextHeight)
		yys = ys;
	else yys = sTextHeight - y2;
	if (y1 != y2) {
		xc = x1;
		xcs = xs;
	} else {
		if (x1 < x2) {
			xc = x1;
			xcs = x2 - x1;
		} else {
			xc = x2 + xs;
			xcs = x1 - x2;
		}
	}
	[sLock lock];
	if (y1 < y2) {
		for (y = yys - 1; y >= 0; y--) {
			memmove(sTextVram + (y1 + y) * sTextWidth + x1, sTextVram + (y2 + y) * sTextWidth + x2, xxs);
			memset(sTextVram + (y1 + y) * sTextWidth + xc, 0, xcs);
		}
	} else {
		for (y = 0; y < yys; y++) {
			memmove(sTextVram + (y1 + y) * sTextWidth + x1, sTextVram + (y2 + y) * sTextWidth + x2, xxs);
			memset(sTextVram + (y1 + y) * sTextWidth + xc, 0, xcs);
		}
	}
	InvalTextInRect(x1, y1, x1 + xs, y1 + ys);
	InvalTextInRect(x2, y2, x2 + xxs, y2 + ys);
	[sLock unlock];
}

void
XSTed_gbox(int x1, int y1, int x2, int y2, unsigned int col, unsigned int ls)
{
	int x, y;
	col = col % 16;
	[sLock lock];
	if (y1 >= 0 && y1 < sGraphHeight) {
		for (x = x1; x <= x2; x++) {
			if (x >= 0 && x < sGraphWidth)
				sGraphVram[y1 * sGraphWidth + x] = col;
		}
	}
	if (y2 >= 0 && y2 < sGraphHeight) {
		for (x = x1; x <= x2; x++) {
			if (x >= 0 && x < sGraphWidth)
				sGraphVram[y2 * sGraphWidth + x] = col;
		}
	}
	if (x1 >= 0 && x1 < sGraphWidth) {
		for (y = y1; y <= y2; y++) {
			if (y >= 0 && y < sGraphHeight)
				sGraphVram[y * sGraphWidth + x1] = col;
		}
	}
	if (x2 >= 0 && x2 < sGraphWidth) {
		for (y = y1; y <= y2; y++) {
			if (y >= 0 && y < sGraphHeight)
				sGraphVram[y * sGraphWidth + x2] = col;
		}
	}
	InvalGraphInRect(x1, y1, x2 + 1, y2 + 1);
	[sLock unlock];
//	printf("XSTed_gbox %d %d %d %d %d %d\n", x1, y1, x2, y2, col, ls);
}

void
XSTed_gfill(int x1, int y1, int x2, int y2, int col)
{
	int x, y;
	col = col % 16;
	if (x1 < 0)
		x1 = 0;
	if (y1 < 0)
		y1 = 0;
	if (x2 >= sGraphWidth)
		x2 = sGraphWidth - 1;
	if (y2 >= sGraphHeight)
		y2 = sGraphHeight - 1;
	[sLock lock];
	for (y = y1; y < y2; y++) {
		for (x = x1; x < x2; x++) {
			sGraphVram[y * sGraphWidth + x] = col;
		}
	}
	InvalGraphInRect(x1, y1, x2 + 1, y2 + 1);
	[sLock unlock];
//	printf("XSTed_gfill %d %d %d %d %d\n", x1, y1, x2, y2, col);
}

int
XSTed_gpoint(int x, int y)
{
//	printf("XSTed_gpoint %d %d\n", x, y);
	return 0;
}

void
XSTed_gline(int x1, int y1, int x2, int y2, int col, int ls)
{
	int dx, wx, dy, wy, x, y, i;
	float fx, fy, d;
	col = col % 16;
	wx = x2 - x1;
	if (wx < 0) {
		wx = -wx;
		dx = -1;
	} else dx = 1;
	wy = y2 - y1;
	if (wy < 0) {
		wy = -wy;
		dy = -1;
	} else dy = 1;
	[sLock lock];
	if (wx == wy) {
		if (x1 >= 0 && x1 < sGraphWidth && y1 >= 0 && y1 < sGraphHeight)
			sGraphVram[y1 * sGraphWidth + x1] = col;
	} else if (wx > wy) {
		//  Proceed along the x axis
		d = dy * (float)wy / wx;
		for (x = x1, fy = y1, i = 0; i <= wx; x += dx, fy += d, i++) {
			y = floor(fy + 0.5);
			if (x >= 0 && x < sGraphWidth && y >= 0 && y < sGraphHeight)
				sGraphVram[y * sGraphWidth + x] = col;
		}
	} else {
		//  Proceed along the y axis
		d = dx * (float)wx / wy;
		for (fx = x1, y = y1, i = 0; i <= wy; fx += d, y += dy, i++) {
			x = floor(fx + 0.5);
			if (x >= 0 && x < sGraphWidth && y >= 0 && y < sGraphHeight)
				sGraphVram[y * sGraphWidth + x] = col;
		}
	}
	x = (dx > 0 ? x1 : x2);
	y = (dy > 0 ? y1 : y2);
	InvalGraphInRect(x, y, x + wx + 1, y + wy + 1);
	[sLock unlock];
//	printf("XSTed_gline %d %d %d %d %d %d\n", x1, y1, x2, y2, col, ls);
}

void
XSTed_tg_copy(int edit_scr)
{
	//  Copy text screen to the 'sub' graphic screen (i.e. y >= 512)
	//  edit_scr 0: (2,4)-(19,31), 1: (58,4)-(75,31)?
	//              (2,6)-(37,29)     (58,6)-(93,29)?
	int x1, x2, y1, y2, x, y;
	if (edit_scr == 0) {
		x1 = 2;
		x2 = 37;
		y1 = 6;
		y2 = 29;
	} else {
		x1 = 58;
		x2 = 93;
		y1 = 6;
		y2 = 29;
	}
	[sLock lock];
	for (y = y1 * 16; y < (y2 + 1) * 16; y++) {
		for (x = x1 * 8; x < (x2 + 1) * 8; x++) {
			sGraphVram[(y + 512) * sGraphWidth + x] = sTextVram[y * sTextWidth + x];
		}
	}
	InvalGraphInRect(x1 * 8, y1 * 16, (x2 + 1) * 16, (y2 + 1) * 16);
	[sLock unlock];
//	printf("XSTed_tg_copy %d\n", edit_scr);
}

void
XSTed_tg_copy2(int edit_scr)
{
	//  Copy text screen to the 'sub' graphic screen (i.e. y >= 512)
	/* (0,6)-(27,29)         (38,6)-(65,29) */
	//  edit_scr 0: (0,6)-(55,29), 1: (38,6)-(93,29)?
	//              (0,6)-(27,29)     (38,6)-(65,29)?
	int x1, x2, y1, y2, x, y;
	if (edit_scr == 0) {
		x1 = 0;
		x2 = 27;
		y1 = 6;
		y2 = 29;
	} else {
		x1 = 38;
		x2 = 93;
		y1 = 6;
		y2 = 29;
	}
	[sLock lock];
	for (y = y1 * 16; y < (y2 + 1) * 16; y++) {
		for (x = x1 * 8; x < (x2 + 1) * 8; x++) {
			sGraphVram[(y + 512) * sGraphWidth + x] = sTextVram[y * sTextWidth + x];
		}
	}
	InvalGraphInRect(x1 * 8, y1 * 16, (x2 + 1) * 16, (y2 + 1) * 16);
	[sLock unlock];
//	 printf("XSTed_tg_copy2 %d\n", edit_scr);
}

void
XSTed_ghome(int home_flag)
{
	if (home_flag)
		sGraphOrigin.y = 512;
	else
		sGraphOrigin.y = 0;
	InvalGraphInRect(0, 0, sGraphWidth, sGraphHeight);
//	printf("XSTed_ghome %d\n", home_flag);
}

void
XSTed_gclr(void)
{
	[sLock lock];
	memset(sGraphVram, 0, sizeof(sGraphVram[0]) * sGraphWidth * sGraphHeight);
	InvalGraphInRect(0, 0, sGraphWidth, sGraphHeight);
	[sLock unlock];
//	printf("XSTed_gclr\n");
}

/*
void
XSTed_tclr(void)
{
	[sLock lock];
	memset(sTextVram, 0, sizeof(sTextVram[0]) * sTextWidth * sTextHeight);
	InvalTextInRect(0, 0, sTextWidth, sTextHeight);
	[sLock unlock];
	printf("XSTed_tclr\n");
}
*/

//  B_CLR_AL: clear all text screen
//  (Equivalent to IOCS call B_CLR_ST(mode) with mode = 2)
void
XSTed_cls_al(void)
{
	[sLock lock];
	memset(sTextVram, 0, sizeof(sTextVram[0]) * sTextWidth * sTextHeight);
	InvalTextInRect(0, 0, sTextWidth, sTextHeight);
	[sLock unlock];
//	printf("XSTed_cls_al\n");
}

void
XSTed_overlap(void)
{
//	printf("XSTed_overlap\n");
}

#pragma mark "=== Color/palette functions ==="

static int
s_XSTed_setpalet(uint32_t *pp, int col)
{
	uint32_t c = col, c2;
	int32_t rgb[3];
	int i;
	rgb[0] = ((c >> 6) & 0x1f);
	rgb[1] = ((c >> 11) & 0x1f);
	rgb[2] = ((c >> 1) & 0x1f);
	for (i = 0; i < 3; i++)
		rgb[i] = (rgb[i] ? (rgb[i] + 1) * 8 - 1 : 0);
	c = (rgb[0] << 24) + (rgb[1] << 16) + (rgb[2] << 8) + 0x00ff;
	c2 = *pp;
	*pp = NSSwapHostIntToBig(c);
	c2 = NSSwapBigIntToHost(c2);
	rgb[0] = ((c2 >> 24) & 0xff) >> 3;
	rgb[1] = ((c2 >> 16) & 0xff) >> 3;
	rgb[2] = ((c2 >> 8) & 0xff) >> 3;
	return (rgb[0] << 6) + (rgb[1] << 11) + (rgb[2] << 1);
}

int
XSTed_gpalet( int pal, int col )
{
	int c = s_XSTed_setpalet(&sGraphPalette[pal % 16], col);
//	printf("XSTed_gpalet %d %04x %08x\n", pal, col, sGraphPalette[pal % 16]);
	InvalGraphInRect(0, 0, sGraphWidth, sGraphHeight);
	return c;
}

int
XSTed_tpalet( int pal, int col )
{
	int c = s_XSTed_setpalet(&sTextPalette[pal % 4], col);
//	printf("XSTed_tpalet %d %04x %08x\n", pal, col, sGraphPalette[pal % 16]);
	InvalTextInRect(0, 0, sTextWidth, sTextHeight);
	return c;
}

int
XSTed_tcolor( int col )
{
	int c = sTextColor;
	sTextColor = col;
	return c;
}

int
XSTed_gcolor( int col )
{
	int c = sGraphColor;
	sGraphColor = col;
	return c;
}

int
XSTed_SetTCol( int col )
{
//	printf("XSTed_SetTCol %d\n", col);
	return 0;
}

int
XSTed_SetGCol( int col )
{
//	printf("XSTed_SetGCol %d\n", col);
	return 0;
}

#pragma mark "=== Text functions ==="

void
XSTed_curon(void)
{
//	printf("XSTed_curon\n");
}

void
XSTed_curoff(void)
{
//	printf("XSTed_curoff\n");
}

void
XSTed_tlocate(int x, int y)
{
	sCursorX = x;
	sCursorY = y;
}

static void
s_XSTed_tputs(const char *message, int *xbase, int *ybase, int col, int isText)
{
	uint8_t ch, ch2, *p, dp;
	uint8_t b, rev;
	int i, x, y, xmin, ymin, xmax, ymax, dx, em;
	xmin = xmax = *xbase;
	ymin = ymax = *ybase;
	[sLock lock];
	rev = 0;
	em = 0;
	if (isText) {
		if (col & 4)
			em = 1;
		if (col & 8)
			rev = 1;
		col = col % 4;
	}
	for (i = 0; (ch = message[i]) != 0; i++) {
		ch2 = 0xff;
		if (ch >= 0x20 && ch < 0x7f)
			ch -= 0x20;
		else if (ch >= 0xa0 && ch <= 0xdf)
			ch -= (0xa0 - 96);
		else {
			/*  Shift jis  */
			if (ch >= 0x81 && ch <= 0x9f)
				ch -= 0x81;
			else if (ch >= 0xe0 && ch <= 0xef)
				ch -= (0xe0 - 31);
			else ch = 32;  /*  No corresponding character  */
			i++;
			ch2 = message[i];
			if (ch2 == 0) {
				ch = 0;  /*  hankaku space  */
				ch2 = 0xff;
				i--;
			} else {
				if (ch2 >= 0x40 && ch2 <= 0x7e)
					ch2 -= 0x40;
				else if (ch2 >= 0x80 && ch2 <= 0xfc)
					ch2 -= (0x80 - 63);
				else {
					ch = ch2 = 0; /*  zenkaku space  */
				}
			}
		}
		if (ch2 == 0xff) {
			p = sFontData + ch * 16;
			dp = 1;
			dx = 8;
		} else {
			p = sKanjiData + (ch * 188 + ch2) * 32;
			dp = 2;
			if ((isText ? sTextWidth : sGraphWidth) - *xbase >= 16)
				dx = 16;
			else dx = 8;
		}
		for (y = 0; y < 16; y++, p += dp) {
			int ofs = (*ybase + y) * (isText ? sTextWidth : sGraphWidth) + *xbase;
			uint8_t bb;
			b = *p;
			for (x = 0; x < 8; x++) {
				if (isText) {
					bb = col * ((b & 1) ^ rev);
					sTextVram[ofs + x] = bb;
					if (em && (dx == 16 || x < 8))
						sTextVram[ofs + x + 1] = bb;
				} else {
					if (b & 1)
						sGraphVram[ofs + x] = col;
				}
				b >>= 1;
			}
			if (dx == 16) {
				b = p[1];
				for (x = 0; x < 8; x++) {
					if (isText) {
						bb = col * ((b & 1) ^ rev);
						sTextVram[ofs + 8 + x] = bb;
						if (em && x < 8)
							sTextVram[ofs + 9 + x] = bb;
					} else {
						if (b & 1)
							sGraphVram[ofs + 8 + x] = col;
					}
					b >>= 1;
				}
			}
		}
		*xbase += dx;
		if (*xbase > xmax)
			xmax = *xbase;
		if (isText) {
			if (*xbase > sTextWidth - 8) {
				*xbase = 0;
				*ybase += 16;
				if (*ybase > sTextHeight - 16)
					*ybase -= 16;
			}
		} else {
			if (*xbase > sGraphWidth - 8) {
				*xbase = 0;
				*ybase += 16;
				if (*ybase > sGraphHeight - 16)
					*ybase -= 16;
			}
		}
		if (*xbase < xmin)
			xmin = *xbase;
		if (*ybase > ymax)
			ymax = *ybase;
	}
	if (isText)
		InvalTextInRect(xmin, ymin, xmax, ymax + 16);
	else
		InvalGraphInRect(xmin, ymin, xmax, ymax + 16);

	[sLock unlock];
}

void
XSTed_tputs(const char *message)
{
	int x, y;
	x = sCursorX * 8;
	y = sCursorY * 16;
	s_XSTed_tputs(message, &x, &y, sTextColor, 1);
	sCursorX = x / 8;
	sCursorY = y / 16;
}

void
XSTed_gputs(int x0, int y0, const char *message)
{
	s_XSTed_tputs(message, &x0, &y0, sGraphColor % 16, 0);
//	printf("XSTed_gputs %d %d %d %s\n", x0, y0, sGraphColor % 16, message);
}

void
XSTed_cls_eol(void)
{
	//  Clear to the end of line
	XSTed_tfill(3, sCursorX * 8, sCursorY * 16, sTextWidth - 1, sCursorY * 16 + 15, 0);
//	printf("XSTed_cls_eol\n");
}

void
XSTed_cls_ed(void)
{
	//  Clear to the end of screen
	XSTed_tfill(3, sCursorX * 8, sCursorY * 16, sTextWidth - 1, sCursorY * 16 + 15, 0);
	if (sCursorY * 16 + 16 < sTextHeight)
		XSTed_tfill(3, 0, sCursorY * 16 + 16, sTextWidth - 1, sTextHeight - 1, 0);
//	printf("XSTed_cls_ed\n");
}

#pragma mark "=== Keyboard functions ==="

#if 0
/* keysym names */
char KEY_XF1[128];
char KEY_XF2[128];
char KEY_XF3[128];
char KEY_XF4[128];
char KEY_XF5[128];
char KEY_KANA[128];
char KEY_KIGO[128];
char KEY_TOROKU[128];
char KEY_INS[128];
char KEY_DEL[128];
char KEY_HOME[128];
char KEY_UNDO[128];
char KEY_RUP[128];
char KEY_RDOWN[128];
char KEY_OPT1[128];
char KEY_OPT2[128];
#endif

char font_name[1024];

int
XSTed_key_init(void)
{
	return 0;
}

/*  X680x0 INPOUT(ch)  */
/*  ch == 0xfe: check for key input and return immediately (if no key input, returns 0).  */
/*  ch == 0xff: key input */
/*  other ch: output one character (not used in STed2)  */
int
XSTed_keyin(int code)
{
	unsigned short ch = 0, ret;
	extern char fnc_key[12][6];
	int options;
	if (code == 0xfe)
		options = kGetKeyNoWaitOption | kGetKeyKeepInBufferOption;
	else if (code == 0xff)
		options = 0;
	else return 0;
	ch = [X68kView getKeyWithOptions:options];
	if (ch == 0)
		return 0;
	/*  One of the function keys is pressed  */
	switch ((ch >> 8) & 0xff) {
		case x68k_up:       ret = fnc_key[4][0]; break;
		case x68k_left:     ret = fnc_key[5][0]; break;
		case x68k_right:    ret = fnc_key[6][0]; break;
		case x68k_down:     ret = fnc_key[7][0]; break;
		case x68k_home:     ret = fnc_key[10][0]; break;
		case x68k_undo:     ret = fnc_key[11][0]; break;
		case x68k_del:      ret = fnc_key[3][0]; break;
		case x68k_ins:      ret = fnc_key[2][0]; break;
		case x68k_rolldown: ret = fnc_key[0][0]; break;
		case x68k_rollup:   ret = fnc_key[1][0]; break;
		case x68k_f1:       ret = fnc_func[0][0]; break;
		case x68k_f2:       ret = fnc_func[1][0]; break;
		case x68k_f3:       ret = fnc_func[2][0]; break;
		case x68k_f4:       ret = fnc_func[3][0]; break;
		case x68k_f5:       ret = fnc_func[4][0]; break;
		case x68k_f6:       ret = fnc_func[5][0]; break;
		case x68k_f7:       ret = fnc_func[6][0]; break;
		case x68k_f8:       ret = fnc_func[7][0]; break;
		case x68k_f9:       ret = fnc_func[8][0]; break;
		case x68k_f10:      ret = fnc_func[9][0]; break;
		default: ret = (ch & 0xff); break;
	}
	if (ch != 0 && ret == 0) {
		//  Key was pressed but no charater input
		//  If it is still in the buffer, it is removed
		if (options & kGetKeyKeepInBufferOption)
			ch = [X68kView getKeyWithOptions:0];
	}
	return ret;
}

/*  X680x0 B_KEYINP()  */
/*  Wait for key input.  */
/*  Return value: high byte = scan code, low byte = ASCII code  */
/*  For SHIFT, CTRL, OPT.1 and OPT.2 keys, key-up is also detected, with the
    scan code +0x80.  */
int
XSTed_keyinp(void)
{
	unsigned short ch;
	ch = [X68kView getKeyWithOptions:kGetKeySenseModifiersOption];
	//	printf("XSTed_keyinp\n");
	return ch;
}

/*  X680x0 B_SFTSNS()  */
/*  Examine the present state of modifier keys.  */
/*  bit 0-7: shift, control, opt1, opt2, kana, romaji, code-input, caps  */
int
XSTed_sftsns(void)
{
	unsigned int modifiers;
	unsigned short ch;
	[sLock lock];
	modifiers = sModifierFlags;
	[sLock unlock];
	ch = 0;
	if (modifiers & NSShiftKeyMask)
		ch |= 1;
	if (modifiers & NSControlKeyMask)
		ch |= 2;
	if (modifiers & NSAlternateKeyMask)
		ch |= 4;
	if (modifiers & NSAlphaShiftKeyMask)
		ch |= 8;
//	printf("XSTed_sftsns\n");
	return ch;
}

/*  X680x0 BITSNS(group)  */
/*  Examine which keys in the specified key group are pressed  */
/*  Complete implementation is very difficult, so it is partially implemented
    as follows; for shift, control, opt1 (option) and opt2 (caps lock) are
    implemented by use of the modifier flags, and other keys are recognized
    as 'pressed' when the last return value of getKeyWithOptions matches that key.  */
int
XSTed_bitsns(int group)
{
	int ret = 0;
	if (group == 14) {
		/*  shift, ctrl, opt1, opt2  */
		unsigned int mflags = sModifierFlags;
		if (mflags & NSShiftKeyMask)
			ret |= 1;
		if (mflags & NSControlKeyMask)
			ret |= 2;
		if (mflags & NSAlternateKeyMask)
			ret |= 4;
		if (mflags & NSAlphaShiftKeyMask)
			ret |= 16;
		return ret;
	}
	ret = (sLastKeyDown >> 8) & 0xff;  //  Scan code
	if (ret / 8 == group)
		ret = (1 << (ret % 8));
	else ret = 0;
//	printf("XSTed_bitsns %d\n", group);
	return ret;
}

/*  X680x0 B_KEYSNS  */
/*  Examine whether the input buffer has a character or not. Does not change the
    input buffer. (Same as INPOUT(0xfe)?)  */
int
XSTed_keysns(void)
{
	return XSTed_keyin(0xfe);
}

void
XSTed_key_wait(void)
{
	while (XSTed_keyin(0xfe) == 0) {
		usleep(50000);
	}
}

void
XSTed_midi_wait(void)
{
	while (1) {
		if (XSTed_keysns())
			return;
		usleep(10000);
	}
}

void
XSTed_ledmod(int code, int onoff)
{
//  Not implemented
//	printf("XSTed_ledmod %d %d\n", code, onoff);
}

#pragma mark "=== Mouse functions ==="

void
XSTed_ms_curof(void)
{
	// Not implemented yet
//	printf("XSTed_ms_curof\n");
}

void
XSTed_ms_curon(void)
{
	// Not implemented yet
//	printf("XSTed_ms_curon\n");
}

int
XSTed_ms_getdt(void)
{
//	printf("XSTed_ms_getdt\n");
	return 0;
}

void
XSTed_ms_init(void)
{
//	printf("XSTed_ms_init\n");
}

int
XSTed_ms_limit( int xs, int ys, int xe, int ye )
{
//	printf("XSTed_ms_limit\n");
	return 0;
}

int
XSTed_ms_pos(int *x, int *y)
{
//	printf("XSTed_ms_pos\n");
	return 0;
}

static int
jis_to_sjis(int code)
{
	uint8_t c1, c2;
	c1 = (code >> 8) & 0xff;
	c2 = code & 0xff;
	if (c1 % 2) {
		c1 = ((c1 + 1) / 2) + 0x70;
		c2 = c2 + 0x1f;
	} else {
		c1 = (c1 / 2) + 0x70;
		c2 = c2 + 0x7d;
	}
	if (c1 >= 0xa0)
		c1 = c1 + 0x40;
	if (c2 >= 0x7f)
		c2 = c2 + 1;
	return ((int)c1 << 8) + c2;
	
}

int
XSTed_defchr(int type, int code, const void *buff)
{
	uint8_t c1, c2, n1, n2;
	int scode = code;
	if ((code >= 0x7621 && code <= 0x767e) || (code >= 0x7721 && code <= 0x777e)) {
		/*  Shift-jis 0xeb9f-0xebfc, 0xec40-0xec7e  */
		scode = jis_to_sjis(code);
	}
	c1 = (scode >> 8) & 0xff;
	c2 = scode & 0xff;
	if ((scode >= 0xeb9f && scode <= 0xebfc) || (scode >= 0xec40 && scode <= 0xec9e)) {
		/*  test  */
		int i, j, b, bb;
		uint8_t *p = (uint8_t *)buff;
		n1 = c1 - (0xe0 - 31);
		if (c2 >= 0x40 && c2 <= 0x7e)
			n2 = c2 - 0x40;
		else n2 = c2 - (0x80 - 63);
	//	printf("defchr %04x\n", scode);
		for (i = 0; i < 32; i++) {
		//	if (i % 2 == 0)
		//		printf("%02d:", i);
			b = p[i];
			bb = 0;
			for (j = 0; j < 8; j++) {
				if (b & (0x80 >> j))
					bb |= (1 << j);
		//		printf("%c", (bb & (1 << j) ? '#' : '.'));
			}
		//	if (i % 2 == 1)
		//		printf("\n");
			sKanjiData[(n1 * 188 + n2) * 32 + i] = bb;
		}
	} else {
		printf("Non-definable character code %04X [%04X]\n", scode, code);
		return -1;
	}
	return 0;
}

/*  The following functions are called from the X68000 thread, which cannot
    access directly to the Application Kit. So it 'throws' message to the main
    thread, which is handled in -[X68kView timerHandler:].  */

static void
s_MacSelectFile(void **args)
{
	char *fna, *path;
	int is_save;
	const char *mes, *ext;
	id panel;
	int i;
	char *p, *pp;
	NSMutableArray *filetypes;
	NSString *title;
	
	fna = (char *)args[0];
	path = (char *)args[1];
	is_save = (int)args[2];
	mes = (const char *)args[3];
	ext = (const char *)args[4];
	
	if (is_save)
		panel = [NSSavePanel savePanel];
	else
		panel = [NSOpenPanel openPanel];
	if (ext != NULL) {
		pp = p = strdup(ext);
		filetypes = [NSMutableArray array];
		for (i = 0; p[i] != 0; i++)
			p[i] = tolower(p[i]);
		while (p != NULL && *p != 0) {
			char *tok = strsep(&p, ":");
			if (*tok != 0)
				[filetypes addObject:[NSString stringWithUTF8String:tok]];
		}
		free(pp);
	} else filetypes = nil;
	[panel setAllowedFileTypes:filetypes];
	if (mes != NULL) {
		title = [NSString stringWithFormat:@"%s %s File", (is_save ? "Save" : "Load"), mes];
		[panel setTitle:title];
	}
	if ([panel runModal] == NSFileHandlingPanelOKButton) {
		NSString *pathstr = [[panel URL] path];
		NSString *lastComp = [pathstr lastPathComponent];
		NSString *dirPath = [pathstr stringByDeletingLastPathComponent];
		strncpy(fna, [lastComp fileSystemRepresentation], PATHLEN - 1);
		fna[PATHLEN - 1] = 0;
		strncpy(path, [dirPath fileSystemRepresentation], PATHLEN - 2);
		path[PATHLEN - 2] = 0;
		strcat(path, "/");
	} else {
		fna[0] = 0;
	}
	sRequestAppKitCall = 0;
}

static void
s_MacErrorBox(void **args)
{
	const char *mes = (const char *)args[0];
	int icon = (int)args[1];
	NSAlert *alert = [NSAlert alertWithMessageText:nil defaultButton:nil alternateButton:nil otherButton:nil informativeTextWithFormat:@"%s", mes];
	[alert setAlertStyle:icon]; /* 0: warning, 1: information, 2: critical */
	[alert runModal];
	sRequestAppKitCall = 0;
}

static void
s_line_input(void **args)
{
	char *buf = (char *)args[0];
	int len = (int)args[1];
	int flag = (int)args[2];  /*  1 on first call, 0 otherwise  */
	int x, y, width;
	NSRect frame;
	NSTextField *tf;
	if (flag == 0)
		return;
	x = sCursorX * 8 - 2;
	y = sTextHeight - 18 - sCursorY * 16;
	width = (len & 0xff) * 8 + 4;
	frame = NSMakeRect(x, y, width, 24);
	tf = [[NSTextField alloc] initWithFrame:frame];
	[tf setBackgroundColor:[NSColor colorWithCalibratedRed:0.8 green:0.8 blue:0.8 alpha:1.0]];
	[tf setDrawsBackground:YES];
	[tf setDelegate:sMainView];
	[tf setFont:[NSFont userFixedPitchFontOfSize:16]];
	[tf setStringValue:[NSString stringWithCString:buf encoding:NSShiftJISStringEncoding]];
	[sMainView addSubview:tf];
	[[sMainView window] makeFirstResponder:tf];
	[tf selectText:nil];
	args[2] = (void *)0;  /*  Avoid duplicate call  */
}

void
MacSelectFile(char *fna, char *path, int is_save, const char *mes, const char *ext)
{
	void *args[] = {(void *)s_MacSelectFile, (void *)fna, (void *)path, (void *)is_save, (void *)mes, (void *)ext};
	sRequestAppKitArgs = args;
	sRequestAppKitCall = 1;
	while (sRequestAppKitCall == 1) {
		usleep(100000);
	}
}

void
MacErrorBox(const char *mes, int icon)
{
	void *args[] = {(void *)s_MacErrorBox, (void *)mes, (void *)icon};
	sRequestAppKitArgs = args;
	sRequestAppKitCall = 2;
	while (sRequestAppKitCall == 2) {
		usleep(100000);
	}
}

void
line_input(char *buf, int len)
{
	void *args[] = {(void *)s_line_input, (void *)buf, (void *)len, (void *)1};
	sRequestAppKitArgs = args;
	sRequestAppKitCall = 3;
	while (sRequestAppKitCall == 3) {
		usleep(100000);
	}
}

@end
