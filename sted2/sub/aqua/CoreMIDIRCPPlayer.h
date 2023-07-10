/*
 *  CoreMIDIRCPPlayer.h
 *  STed2_aqua
 *
 *  Created by Toshi Nagata on Sun Jun 08 2003.
 *  Copyright (c) 2003 Toshi Nagata. All rights reserved.
 *
 */

#ifndef __CoreMIDIRCPPlayer_H__
#define __CoreMIDIRCPPlayer_H__

extern void play_coremidi_rcpplayer(char *rcp_data_ptr, int data_length);
extern void stop_coremidi_rcpplayer(void);
extern void exit_coremidi_rcpplayer(void);

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
@interface CoreMIDIRCPPlayer : NSObject
{
	BOOL playing;
}
+ (CoreMIDIRCPPlayer *)currentPlayer;
- (BOOL)isPlaying;
@end

void CoreMIDIInitIfNeeded(void);
NSString *CoreMIDIDeviceNameAtIndex(int index);
void CoreMIDISelectDeviceForPort(int index, int port);
void CoreMIDISelectDeviceByNameForPort(const char *name, int port);
void CoreMIDIAllSoundOff(void);

#endif __OBJC__

#endif
