/* X68kView.h */
/* Header file for X68kView, the application controller object for sted2_aqua. */
/* Mar.19, 2015, Toshi Nagata */
/* Copyright 2015 Toshi Nagata. All rights reserved. */

#import <Cocoa/Cocoa.h>

#define sTextWidth 768
#define sTextHeight 512
#define sGraphWidth 1024
#define sGraphHeight 1024

@interface X68kView : NSView
{
	//  These bitmaps must be recreated every time the bitmap content is updated
	NSBitmapImageRep *bitmapRep;
}
+ (void)initializeX68k;
+ (unsigned int)getKey: (BOOL)senseOnly;
@end
