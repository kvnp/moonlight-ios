//
//  StreamView.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "ControllerSupport.h"
#import "OnScreenControls.h"
#import "Moonlight-Swift.h"
#import "StreamConfiguration.h"

@protocol UserInteractionDelegate <NSObject>

- (void) userInteractionBegan;
- (void) userInteractionEnded;

@end

#if TARGET_OS_TV
@interface StreamView : UIView <X1KitMouseDelegate, UITextFieldDelegate>
#else
@interface StreamView : UIView <X1KitMouseDelegate, UITextFieldDelegate, UIPointerInteractionDelegate>
#endif

- (void) setupStreamView:(ControllerSupport*)controllerSupport
     interactionDelegate:(id<UserInteractionDelegate>)interactionDelegate
                  config:(StreamConfiguration*)streamConfig;
- (void) showOnScreenControls;
- (void) setOnScreenControls;
- (void) disableOnScreenControls;
- (void) reloadOnScreenControlsRealtimeWith:(ControllerSupport*)controllerSupport
                          andConfig:(StreamConfiguration*)streamConfig;
- (void) reloadOnScreenControlsWith:(ControllerSupport*)controllerSupport
                          andConfig:(StreamConfiguration*)streamConfig;
- (CGSize) getVideoAreaSize;
- (CGPoint) adjustCoordinatesForVideoArea:(CGPoint)point;
- (uint16_t)getRotationFromAzimuthAngle:(float)azimuthAngle;

- (OnScreenControlsLevel) getCurrentOscState;
- (UIResponder* )getTouchHandler;
- (OnScreenControls* )getOnScreenControlsObj;

#if !TARGET_OS_TV
- (void) updateCursorLocation:(CGPoint)location isMouse:(BOOL)isMouse;
#endif

@end
