//
//  MyDialogController.m
//  STed2_aqua2
//
//  Created by Toshi Nagata on 15/03/27.
//  Copyright 2015 Toshi Nagata. All rights reserved.
//

#import "MyDialogController.h"

@implementation MyDialogController

+ (BOOL)runDialogWithNibName:(NSString *)nibName
{
	MyDialogController *cont = [[MyDialogController alloc] initWithWindowNibName:nibName];
	int result = [NSApp runModalForWindow:[cont window]];
	[cont close];
	[cont release];
	return (result == NSRunStoppedResponse);
}

- (IBAction)okPressed:(id)sender
{
	[NSApp stopModal];
}

- (IBAction)cancelPressed:(id)sender
{
	[NSApp abortModal];
}

@end
