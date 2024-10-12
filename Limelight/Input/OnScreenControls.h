//
//  OnScreenControls.h
//  Moonlight
//
//  Created by Diego Waxemberg on 12/28/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ControllerSupport.h"
#import "CustomTapGestureRecognizer.h"
#import "OSCProfile.h"

@class ControllerSupport;
@class StreamConfiguration;

static const float D_PAD_DIST = 10;
static const float BUTTON_DIST = 20;

@interface OnScreenControls : NSObject{
    @protected
    CGFloat _leftStickSizeFactor;
    CGFloat _rightStickSizeFactor;
    CGFloat _dPadSizeFactor;
}

typedef NS_ENUM(NSInteger, OnScreenControlsLevel) {
    OnScreenControlsLevelOff,
    OnScreenControlsLevelSimple,
    OnScreenControlsLevelFull,
    OnScreenControlsLevelCustom,
    OnScreenControlsLevelAuto, // move it here instead of delete , to ensure integrity of the codes

    // Internal levels selected by ControllerSupport
    OnScreenControlsLevelAutoGCGamepad,
    OnScreenControlsLevelAutoGCExtendedGamepad,
    OnScreenControlsLevelAutoGCExtendedGamepadWithStickButtons
};


// @property (nonatomic, assign) CustomTapGestureRecognizer* mouseRightClickTapRecognizer; // this object will be passed to onscreencontrols class for areVirtualControllerTaps flag setting
@property (nonatomic, assign) bool isLayingOut;
//@property (nonatomic) NSMutableSet<UITouch* >* touchesCapturedByOnScreenButtons;


@property (nonatomic, assign) CGRect standardRoundButtonBounds;
@property (nonatomic, assign) CGRect standardRectangleButtonBounds;
@property (nonatomic, assign) CGRect standardStickBounds;
@property (nonatomic, assign) CGRect standardStickBackgroundBounds;
@property (nonatomic, assign) CGRect standardUpDownButtonBounds;
@property (nonatomic, assign) CGRect standardLeftRightButtonBounds;

@property (nonatomic, assign) CGPoint leftStickCenter;
@property (nonatomic, assign) CGPoint rightStickCenter;

@property CALayer* _aButton;
@property (nonatomic, assign) CGFloat aButtonSizeFactor;
@property CALayer* _bButton;
@property (nonatomic, assign) CGFloat bButtonSizeFactor;
@property CALayer* _xButton;
@property (nonatomic, assign) CGFloat xButtonSizeFactor;
@property CALayer* _yButton;
@property (nonatomic, assign) CGFloat yButtonSizeFactor;


@property CALayer* _startButton;
@property CALayer* _selectButton;
@property CALayer* _r1Button;
@property CALayer* _r2Button;
@property CALayer* _r3Button;
@property CALayer* _l1Button;
@property CALayer* _l2Button;
@property CALayer* _l3Button;
@property CALayer* _upButton;
@property CALayer* _downButton;
@property CALayer* _leftButton;
@property CALayer* _rightButton;
@property CALayer* _leftStickBackground;
@property CALayer* _leftStick;
@property CALayer* _rightStickBackground;
@property CALayer* _rightStick;
@property CALayer* _dPadBackground;    // parent layer that contains each individual dPad button so user can drag them around the screen together

@property float D_PAD_CENTER_X;
@property float D_PAD_CENTER_Y;

@property OnScreenControlsLevel _level;

@property NSMutableArray *OSCButtonLayers;


+ (NSMutableSet* )touchAddrsCapturedByOnScreenControls;
- (id) initWithView:(UIView*)view controllerSup:(ControllerSupport*)controllerSupport streamConfig:(StreamConfiguration*)streamConfig;
- (BOOL) handleTouchDownEvent:(NSSet*)touches;
- (BOOL) handleTouchUpEvent:(NSSet*)touches;
- (BOOL) handleTouchMovedEvent:(NSSet*)touches;
- (void) setLevel:(OnScreenControlsLevel)level;
- (void) show;
- (void) setupComplexControls;
- (void) drawButtons;
- (void) drawBumpers;
- (void) updateControls;
- (OnScreenControlsLevel) getLevel;
- (void) setDPadCenter;
- (void) setAnalogStickPositions;
- (void) positionAndResizeSingleControllerLayers;
- (void) resizeControllerLayerWith:(CALayer*)layer and:(CGFloat)sizeFactor;
+ (CGFloat) getControllerLayerSizeFactor:(CALayer*)layer;

@end
