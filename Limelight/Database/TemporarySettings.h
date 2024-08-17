//
//  TemporarySettings.h
//  Moonlight
//
//  Created by Cameron Gutman on 12/1/15.
//  Copyright © 2015 Moonlight Stream. All rights reserved.
//

#import "Settings+CoreDataClass.h"
#define RELATIVE_TOUCH 0
#define REGULAR_NATIVE_TOUCH 1
#define PURE_NATIVE_TOUCH 2
#define ABSOLUTE_TOUCH 3
#define OSC_TOOL_FINGERS 4


@interface TemporarySettings : NSObject

@property (nonatomic, retain) Settings * parent;

@property (nonatomic, retain) NSNumber * bitrate;
@property (nonatomic, retain) NSNumber * framerate;
@property (nonatomic, retain) NSNumber * height;
@property (nonatomic, retain) NSNumber * width;
@property (nonatomic, retain) NSNumber * audioConfig;
@property (nonatomic, retain) NSNumber * onscreenControls;
@property (nonatomic, retain) NSNumber * keyboardToggleFingers;
@property (nonatomic, retain) NSNumber * oscLayoutToolFingers;
@property (nonatomic, retain) NSNumber * slideToSettingsScreenEdge;
@property (nonatomic, retain) NSNumber * slideToSettingsDistance;
@property (nonatomic, retain) NSNumber * touchPointerVelocityFactor;
@property (nonatomic, retain) NSNumber * mousePointerVelocityFactor;
@property (nonatomic, retain) NSNumber * pointerVelocityModeDivider;
@property (nonatomic, retain) NSString * uniqueId;
@property (nonatomic) enum {
    CODEC_PREF_AUTO,
    CODEC_PREF_H264,
    CODEC_PREF_HEVC,
    CODEC_PREF_AV1,
} preferredCodec;
@property (nonatomic) BOOL oscVisualFeedback;
@property (nonatomic) BOOL useFramePacing;
@property (nonatomic) BOOL multiController;
@property (nonatomic) BOOL swapABXYButtons;
@property (nonatomic) BOOL playAudioOnPC;
@property (nonatomic) BOOL optimizeGames;
@property (nonatomic) BOOL enableHdr;
@property (nonatomic) BOOL btMouseSupport;
// @property (nonatomic) BOOL absoluteTouchMode;
@property (nonatomic, retain) NSNumber * touchMode;
@property (nonatomic) BOOL statsOverlay;
@property (nonatomic) BOOL liftStreamViewForKeyboard;
@property (nonatomic) BOOL showKeyboardToolbar;
@property (nonatomic) BOOL allowPortrait;

- (id) initFromSettings:(Settings*)settings;

@end
