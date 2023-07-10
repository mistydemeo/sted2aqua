/* AppController.m */
/* The application controller object for sted2_aqua. */
/* Jun.01.2003 Toshi Nagata */
/* Copyright 2003 Toshi Nagata. All rights reserved. */

#import "AppController.h"
#import "X68kView.h"
// #import "X68kWindow.h"
#import "CoreMIDIRCPPlayer.h"
#import "MyDialogController.h"

#include <stdlib.h>

@implementation AppController

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	extern int sted2_main(int, char**);
	static char *sArgv[] = {"sted2", NULL};
	X68kView *xview = (X68kView *)[myWindow contentView];

	[X68kView initializeX68k];

	[xview setNeedsDisplay:YES];
	XSTed_init_window();
	XSTed_start_main(sted2_main, 1, sArgv);
}

- (void)startX68kThread: (id)argument
{
	int (*mainPtr)(int, char**);
	int argc;
	char **argv;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	mainPtr = (int (*)(int, char **))[[argument objectAtIndex: 0] pointerValue];
	argc = [[argument objectAtIndex: 1] intValue];
	argv = (char **)[[argument objectAtIndex: 2] pointerValue];
	(*mainPtr)(argc, argv);
	[pool release];
}

- (IBAction)midiSettingsDialog:(id)sender
{
	NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
	NSMutableArray *devices = [NSMutableArray array];
	int i;
	NSString *devName, *outdevice1, *outdevice2;

	for (i = 0; (devName = CoreMIDIDeviceNameAtIndex(i)) != nil; i++) {
		[devices addObject:devName];
	}
	[def setValue:devices forKey:@"devicelist"];
	outdevice1 = [def valueForKey:@"midiout1"];
	outdevice2 = [def valueForKey:@"midiout2"];
	
	if ([MyDialogController runDialogWithNibName:@"MIDISettings"]) {
		CoreMIDISelectDeviceByNameForPort([[def valueForKey:@"midiout1"] UTF8String], 0);
		CoreMIDISelectDeviceByNameForPort([[def valueForKey:@"midiout2"] UTF8String], 1);
	} else {
		[def setValue:outdevice1 forKey:@"midiout1"];
		[def setValue:outdevice2 forKey:@"midiout2"];
	}
}

- (IBAction)allSoundOff:(id)sender
{
	CoreMIDIAllSoundOff();
}

@end
