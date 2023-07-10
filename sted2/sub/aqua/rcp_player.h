/*
 *  rcp_player.h
 *  STed2_aqua
 *
 *  Created by Toshi Nagata on Tue Jun 10 2003.
 *  Copyright (c) 2003 Toshi Nagata. All rights reserved.
 *
 */

#ifndef __rcp_player_h__
#define __rcp_player_h__

#define kMaxMIDIMessageLength 256

extern double rcpplayer_step_to_microseconds(long step);
extern int rcpplayer_next_midi_event(long *step, unsigned char **ptr, int *length, int *port);
extern int rcpplayer_init(unsigned char *data_ptr, long data_length);

#endif
