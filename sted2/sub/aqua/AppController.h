/* AppController.h */
/* Header file for AppController, the application controller object for sted2_aqua. */
/* Jun.01.2003 Toshi Nagata */
/* Copyright 2003 Toshi Nagata. All rights reserved. */

#import <Cocoa/Cocoa.h>

@class X68kWindow;
@class X68kView;

@interface AppController : NSObject
{
    IBOutlet NSWindow *myWindow;
}
- (void)startX68kThread:(id)argument;
- (IBAction)midiSettingsDialog:(id)sender;
- (IBAction)allSoundOff:(id)sender;
@end
