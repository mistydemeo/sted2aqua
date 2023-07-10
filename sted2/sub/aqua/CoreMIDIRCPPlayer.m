//
//  CoreMIDIRCPPlayer.m
//  STed2_aqua
//
//  Created by Toshi Nagata on Sun Jun 08 2003.
//  Copyright (c) 2003 Toshi Nagata. All rights reserved.
//

#import "rcp_player.h"
#import "CoreMIDIRCPPlayer.h"

#include <CoreMIDI/CoreMIDI.h>				/*  for MIDI input/output  */
#include <CoreAudio/CoreAudio.h>			/*  for timing functions  */
#include <AudioToolbox/AUGraph.h>			/*  for AUNode output  */
#include <AudioToolbox/AUMIDIController.h>	/*  for routing MIDI to DLS synth */
#include <AudioUnit/MusicDevice.h>
#include <unistd.h>

#define kMaxNumberOfPorts 2
#define kMaxPrefetchMicroseconds 1000000

#define kMaxMIDIMessageSize  256  /* Should match RCP_MAX_RESULT_SMF_SIZE in rcp.h */

#define GetHostTimeInMDTimeType()	((MDTimeType)(AudioConvertHostTimeToNanos(AudioGetCurrentHostTime()) / 1000))
#define ConvertMDTimeTypeToHostTime(tm)	AudioConvertNanosToHostTime((tm) * 1000)

void rcpplayer_engine(void);

static CoreMIDIRCPPlayer *sCurrentPlayer;
static MIDIClientRef	sMIDIClientRef = NULL;
static MIDIPortRef		sMIDIOutputPortRef = NULL;
static MIDIEndpointRef	sDest[kMaxNumberOfPorts];

static MIDISysexSendRequest sSysexRequest[kMaxNumberOfPorts];
static unsigned char sSysexSendBuffer[kMaxNumberOfPorts][kMaxMIDIMessageSize];

static char sStopPlaying;
static MIDITimeStamp sStartTimeStamp;
static MIDITimeStamp sLastTimeStamp;
static char sNoteOnTable[kMaxNumberOfPorts][16][128];

//  Next earliest timestamp for each port (to avoid too thick MIDI byte sequence)
static MIDITimeStamp sNextEarliestTimeForPort[kMaxNumberOfPorts];

//  Microsecond wait per MIDI byte (it depends on the hardware feature, so it should be 
//  assigned per port)
static int sWaitPerMIDIByte[kMaxNumberOfPorts];

//  Microsecond offset to avoid 'simultaneous event' in the different port
static int sOffsetMIDITime = 1;

#define DEBUG_RCP 0

#if DEBUG_RCP
#define sRCPDebugSize 200000
static long sRCPDebugCount;
static unsigned char *sRCPDebugBuffer;
#endif

@implementation CoreMIDIRCPPlayer

+ (CoreMIDIRCPPlayer *)currentPlayer
{
	if (sCurrentPlayer == nil)
		sCurrentPlayer = [[CoreMIDIRCPPlayer alloc] init];
	return sCurrentPlayer;
}

- (NSString *)deviceNameAtIndex: (int)index
{
	return nil;
}

- (void)setDevice: (NSString *)device forPort: (int)port
{
}

- (void)startPlaying:(id)argument
{
	playing = YES;
	sStopPlaying = 0;
	rcpplayer_engine();
	playing = NO;
	sStopPlaying = 0;
}

- (BOOL)isPlaying
{
	return playing;
}

@end

static AUGraph sGraph = NULL;
static AUNode sSynth, sSynth2;
static AUNode sMixer;
static AUNode sOutput;
static MusicDeviceComponent sMusicDev, sMusicDev2;
static AUMIDIControllerRef sMIDIController, sMIDIController2;

static void
InitInternalSynth(void)
{
	OSStatus sts;
	ComponentDescription desc;
	UInt32 unum;
//	int ch;

	sts = NewAUGraph(&sGraph);

	desc.componentType = kAudioUnitType_MusicDevice;
	desc.componentSubType = kAudioUnitSubType_DLSSynth;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;
	desc.componentFlags = desc.componentFlagsMask = 0;
//	sts = AUGraphNewNode(sGraph, &desc, 0, NULL, &sSynth);
//	sts = AUGraphNewNode(sGraph, &desc, 0, NULL, &sSynth2);
	sts = AUGraphAddNode(sGraph, &desc, &sSynth);
	sts = AUGraphAddNode(sGraph, &desc, &sSynth2);

	/*  Mixer  */
	desc.componentType = kAudioUnitType_Mixer;
	desc.componentSubType = kAudioUnitSubType_StereoMixer;
//	desc.componentManufacturer = kAudioUnitID_StereoMixer;
	sts = AUGraphAddNode(sGraph, &desc, &sMixer);

	/*  Default output  */
	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_DefaultOutput;
//	desc.componentManufacturer = kAudioUnitID_DefaultOutput;
	sts = AUGraphAddNode(sGraph, &desc, &sOutput);

	sts = AUGraphConnectNodeInput(sGraph, sSynth, 0, sMixer, 0);
	sts = AUGraphConnectNodeInput(sGraph, sSynth2, 0, sMixer, 1);
	
	sts = AUGraphConnectNodeInput(sGraph, sMixer, 0, sOutput, 0);
	
	sts = AUGraphGetNodeCount(sGraph, &unum);
	
	sts = AUGraphOpen(sGraph);
	
	sts = AUGraphNodeInfo(sGraph, sSynth, NULL, &sMusicDev);
	sts = AUGraphNodeInfo(sGraph, sSynth2, NULL, &sMusicDev2);
	
	/*  Create a virtual MIDI endpoint and route the input to the DLS synth  */
	sts = AUMIDIControllerCreate(CFSTR("Internal Synth"), &sMIDIController);
	sts = AUMIDIControllerCreate(CFSTR("Internal Synth 2"), &sMIDIController2);
	
	sts = AUMIDIControllerMapChannelToAU(sMIDIController, -1, sMusicDev, -1, 0);
	sts = AUMIDIControllerMapChannelToAU(sMIDIController2, -1, sMusicDev2, -1, 0);
	
	sts = AUGraphInitialize(sGraph);
	sts = AUGraphStart(sGraph);
	
#if 0
	for (ch = 0; ch < 16; ch++) {
		/*  Reset all controllers  */
		sts = MusicDeviceMIDIEvent(sMusicDev, 0xb0 + ch, 0x79, 0, 0);
		sts = MusicDeviceMIDIEvent(sMusicDev, 0xb0 + ch, 7, 127, 0);
		sts = MusicDeviceMIDIEvent(sMusicDev, 0xc0 + ch, 0, 0, 0);
	//	sts = MusicDeviceMIDIEvent(gMusicDev, 0x90 + ch, 60 + ch, 127, 0);
	}
//	sts = MusicDeviceMIDIEvent(gMusicDev, 0xC0, 0, 0, 0);
//	sts = MusicDeviceMIDIEvent(gMusicDev, 0xB0, 7, 127, 0);
//	sts = MusicDeviceMIDIEvent(gMusicDev, 0x90, 60, 127, 0);
#endif	
}

void
CoreMIDIInitIfNeeded(void)
{
	int i;
	if (sMIDIClientRef == NULL) {
		MIDIClientCreate(CFSTR("STed2 Mac"), NULL, NULL, &sMIDIClientRef);
		if (sMIDIOutputPortRef == NULL)
			MIDIOutputPortCreate(sMIDIClientRef, CFSTR("STed2 output port"), &sMIDIOutputPortRef);
		if (sGraph == NULL)
			InitInternalSynth();
		for (i = 0; i < sizeof(sDest) / sizeof(sDest[0]); i++)
			sDest[i] = NULL;
	}
	for (i = 0; i < kMaxNumberOfPorts; i++)
		sWaitPerMIDIByte[i] = 300;
	sOffsetMIDITime = 1;
}

NSString *
CoreMIDIDeviceNameAtIndex(int index)
{
	MIDIEndpointRef eref;
	CFStringRef name, name2;
	NSString *string;
	SInt32 i;
	MIDIObjectType objType;
	MIDIObjectRef oref;
	MIDIEntityRef enref;
	MIDIDeviceRef dref;
	CoreMIDIInitIfNeeded();
	eref = MIDIGetDestination(index);
	if (eref == NULL)
		return nil;
	name = name2 = NULL;
	if (MIDIObjectGetIntegerProperty(eref, kMIDIPropertyConnectionUniqueID, &i) == noErr
	&& i != 0
	&& MIDIObjectFindByUniqueID(i, &oref, &objType) == noErr) {
		MIDIObjectGetStringProperty(oref, kMIDIPropertyName, &name);
	} else {
		MIDIObjectGetStringProperty(eref, kMIDIPropertyName, &name);
		if (MIDIEndpointGetEntity(eref, &enref) == noErr
			&& enref != NULL
			&& MIDIEntityGetDevice(enref, &dref) == noErr
			&& dref != NULL) {
			if (MIDIObjectGetStringProperty(dref, kMIDIPropertyName, &name2) != noErr)
				name2 = NULL;
		}
	}
	if (name2 != NULL && [(NSString *)name2 isEqualToString:(NSString *)name]) {
		//  Some MIDI device has the same name for entity and port (like NSX-39)
		CFRelease(name2);
		name2 = NULL;
	}
	string = [NSString stringWithString:(NSString *)name];
	CFRelease(name);
	if (name2 != NULL) {
		string = [NSString stringWithFormat:@"%@-%@", (NSString *)name2, string];
		CFRelease(name2);
	}
	return string;
}

void
CoreMIDISelectDeviceForPort(int index, int port)
{
	CoreMIDIInitIfNeeded();
	sDest[port % kMaxNumberOfPorts] = MIDIGetDestination(index);
}

void
CoreMIDISelectDeviceByNameForPort(const char *name, int port)
{
	int n;
	NSString *str;
	CoreMIDIInitIfNeeded();
	n = 0;
	while ((str = CoreMIDIDeviceNameAtIndex(n)) != nil) {
		if (strcasecmp(name, [str UTF8String]) == 0) {
			CoreMIDISelectDeviceForPort(n, port);
			return;
		}
		n++;
	}
}

OSStatus
CoreMIDISend(unsigned char *ptr, int length, int port, MIDITimeStamp atTime)
{
	MIDIPacketList	packetList;
	MIDIPacket *	packetPtr;
	OSStatus sts;
	port = port % kMaxNumberOfPorts;
	if (length <= 0 || sDest[port] == NULL)
		return 0;
	if (ptr[0] == 0xf0) {
		/*  Sysex  */
		MIDISysexSendRequest *rp = &sSysexRequest[port];
		while (rp->bytesToSend > 0)
			usleep(10000);  /*  Wait until the last sysex sent to the same port has completed */
		if (length > kMaxMIDIMessageSize)
			length = kMaxMIDIMessageSize;
		memmove(sSysexSendBuffer[port], ptr, length);
		rp->destination = sDest[port];
		rp->data = sSysexSendBuffer[port];
		rp->bytesToSend = length;
		rp->complete = 0;
		rp->completionProc = NULL;
		rp->completionRefCon = NULL;
		sts = MIDISendSysex(rp);
	} else {
		unsigned char b;
		packetPtr = MIDIPacketListInit(&packetList);
		packetPtr = MIDIPacketListAdd(&packetList, sizeof(packetList), packetPtr, atTime, length, ptr);
		sts = MIDISend(sMIDIOutputPortRef, sDest[port], &packetList);
		b = ptr[0] & 0xf0;
		if (b == 0x80 || b == 0x90) {
			char *pp = &sNoteOnTable[port][ptr[0] & 0x0f][ptr[1]];
			if (b == 0x80 || ptr[2] == 0) {
				/*  Note off  */
				(*pp)--;
			} else {
				/*  Note on  */
				(*pp)++;
			}
		}
	}
	return sts;
}

void
CoreMIDIAllSoundOff(void)
{
	int port, ch;
	
	/*  Flush all output that are scheduled for future delivery  */
	MIDIFlushOutput(NULL);
	/*  All sound off  */
	for (port = 0; port < 2; port++) {
		for (ch = 0; ch < 16; ch++) {
			unsigned char buf[4];
			/*  All sound off  */
			buf[0] = 0xb0 + ch;
			buf[1] = 0x78;
			buf[2] = 0;
			CoreMIDISend(buf, 3, port, 0);
		}
	}
}

#if DEBUG_RCP
static void
dump_debug_rcp(void)
{
	FILE *fp = fopen("sted2_debug_rcp.log", "w");
	int n = 0;
	int m;
	unsigned char *p;
	static unsigned char tbl[16][128];
	unsigned char *pp;
	memset(tbl, 0, sizeof(tbl));
	while (n < sRCPDebugCount) {
		UInt32 t1, t2;
		unsigned char c;
		p = sRCPDebugBuffer + n;
		t1 = p[0] + ((UInt32)p[1] << 8) + ((UInt32)p[2] << 16) + ((UInt32)p[3] << 24);
		t2 = p[4] + ((UInt32)p[5] << 8) + ((UInt32)p[6] << 16) + ((UInt32)p[7] << 24);
		fprintf(fp, "%-10d %-10d", (int)t1, (int)t2);
		m = p[8];
		c = p[9];
		if ((c & 0xf0) == 0x80 || ((c & 0xf0) == 0x90 && p[11] == 0)) {
			pp = &tbl[c & 0x0f][p[10] & 0x7f];
			(*pp)--;
			fprintf(fp, "%2d OFF %3d   0 [%d]\n", c & 0x0f, p[10], *pp);
		} else if ((c & 0xf0) == 0x90) {
			pp = &tbl[c & 0x0f][p[10] & 0x7f];
			(*pp)++;
			fprintf(fp, "%2d ON  %3d %3d [%d]\n", c & 0x0f, p[10], p[11], *pp);
		} else {
			int i;
			for (i = 0; i < m && i < 8; i++) {
				fprintf(fp, "%02x ", p[9 + i]);
			}
			fprintf(fp, "\n");
		}
		n += 9 + m;
	}
	for (n = 0; n < 16; n++) {
		for (m = 0; m < 128; m++) {
			if (tbl[n][m] != 0) {
				fprintf(fp, "%d:%d(%d) ", n, m, tbl[n][m]);
			}
		}
	}
	fprintf(fp, "\n");
	fclose(fp);
}

#endif

#define ConvertMicrosToHostTime(t) (AudioConvertNanosToHostTime((t) * 1000))

/*  Player engine; to be called after rcpplayer_init() in a separate thread  */
void
rcpplayer_engine(void)
{
	MIDITimeStamp currentTime, nextTime, nextEventTime, offsetTime, prefetchTime;
	long step;
	unsigned char *ptr;
	int length, port;
	OSStatus sts;
	MIDITimeStamp waitPerMIDIByte[kMaxNumberOfPorts];
	
	sStartTimeStamp = AudioGetCurrentHostTime();
	currentTime = sStartTimeStamp;

	for (port = 0; port < kMaxNumberOfPorts; port++) {
		waitPerMIDIByte[port] = ConvertMicrosToHostTime(sWaitPerMIDIByte[port]);
		sNextEarliestTimeForPort[port] = sStartTimeStamp;
	}
	
	prefetchTime = ConvertMicrosToHostTime(kMaxPrefetchMicroseconds);
	offsetTime = ConvertMicrosToHostTime(sOffsetMIDITime);

	while (rcpplayer_next_midi_event(&step, &ptr, &length, &port)) {
		if (length == 0 || ptr[0] == 0xff)
			continue;
		nextEventTime = sStartTimeStamp + ConvertMicrosToHostTime(rcpplayer_step_to_microseconds(step));
		if (nextEventTime > currentTime + prefetchTime) {
			usleep(AudioConvertHostTimeToNanos(nextEventTime - currentTime - prefetchTime) / 1000);
			currentTime = AudioGetCurrentHostTime();
		}
	//	printf("step %ld, nextTime %qd, port %d, length %d, %02x %02x %02x\n",
	//		step, nextTime, port, length, (int)ptr[0], (int)ptr[1], (int)ptr[2]);
		
		nextTime = nextEventTime;
		if (nextTime < sNextEarliestTimeForPort[port])
			nextTime = sNextEarliestTimeForPort[port];
		if (nextTime < sLastTimeStamp + offsetTime)
			nextTime = sLastTimeStamp + offsetTime;
		sLastTimeStamp = nextTime;
		sts = CoreMIDISend(ptr, length, port, nextTime);
		sNextEarliestTimeForPort[port] = nextTime + waitPerMIDIByte[port] * length;

#if DEBUG_RCP
		{
			UInt32 lastMicro = AudioConvertHostTimeToNanos(sLastTimeStamp - sStartTimeStamp) / 1000;
			UInt32 nextMicro = AudioConvertHostTimeToNanos(nextEventTime - sStartTimeStamp) / 1000;
			nextMicro = sts;
			int n = (length >= 256 ? 255 : length);
			if (sRCPDebugCount + 9 + n < sRCPDebugSize) {
				unsigned char *pp = sRCPDebugBuffer + sRCPDebugCount;
				*pp++ = lastMicro & 0xff;
				*pp++ = (lastMicro >> 8) & 0xff;
				*pp++ = (lastMicro >> 16) & 0xff;
				*pp++ = (lastMicro >> 24) & 0xff;
				*pp++ = nextMicro & 0xff;
				*pp++ = (nextMicro >> 8) & 0xff;
				*pp++ = (nextMicro >> 16) & 0xff;
				*pp++ = (nextMicro >> 24) & 0xff;
				*pp++ = n;
				memmove(pp, ptr, n);
				sRCPDebugCount += 9 + n;
			}
		}
#endif
		if (sStopPlaying)
			break;
	}
}

void
stop_coremidi_rcpplayer(void)
{
	int port, ch, i, j;
	UInt64 nextTime;
	CoreMIDIRCPPlayer *player = [CoreMIDIRCPPlayer currentPlayer];
	if ([player isPlaying]) {
		sStopPlaying = 1;
		while ([player isPlaying])
			usleep(100000);
	}
	/*  Send Note-off  */
	nextTime = sLastTimeStamp;
	for (port = 0; port < 2; port++) {
		for (ch = 0; ch < 16; ch++) {
			for (i = 0; i < 128; i++) {
				for (j = sNoteOnTable[port][ch][i]; j > 0; j--) {
					unsigned char buf[4];
					buf[0] = 0x80 + ch;
					buf[1] = i;
					buf[2] = 0;
					CoreMIDISend(buf, 3, port, AudioConvertNanosToHostTime(nextTime));
					nextTime += 1000000;  /*  Wait 1 millisecond (= 1000000 nanoseconds) */
				}
				sNoteOnTable[port][ch][i] = 0;
			}
		}
	}
	
#if DEBUG_RCP
	dump_debug_rcp();
#endif
	
}

void
play_coremidi_rcpplayer(char *rcp_data_ptr, int data_length)
{
	CoreMIDIRCPPlayer *player;
	rcpplayer_init((unsigned char *)rcp_data_ptr, data_length);
#if DEBUG_RCP
	sRCPDebugBuffer = (unsigned char *)realloc(sRCPDebugBuffer, sRCPDebugSize);
	sRCPDebugCount = 0;
#endif
	player = [CoreMIDIRCPPlayer currentPlayer];
	if ([player isPlaying]) {
		stop_coremidi_rcpplayer();
	}
	sLastTimeStamp = 0;
	[NSThread detachNewThreadSelector:@selector(startPlaying:) toTarget:player withObject:nil];
}

int
is_coremidi_playing(void)
{
	if ([[CoreMIDIRCPPlayer currentPlayer] isPlaying])
		return 1;
	else return 0;
}

void
exit_coremidi_rcpplayer(void)
{
	/* Do nothing */
}
