//
//  MyDialogController.h
//  STed2_aqua2
//
//  Created by Toshi Nagata on 15/03/27.
//  Copyright 2015 Toshi Nagata. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface MyDialogController : NSWindowController {
}
+ (BOOL)runDialogWithNibName:(NSString *)nibName;
- (IBAction)okPressed:(id)sender;
- (IBAction)cancelPressed:(id)sender;
@end
