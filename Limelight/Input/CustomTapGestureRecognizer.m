//
//  CustomTapGestureRecognizer.m
//  Moonlight
//
//  Created by ZWM on 2024/5/15.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "CustomTapGestureRecognizer.h"
#import "Moonlight-Swift.h"

// The most accurate & reliable tap gesture recognizer of iOS:
// - Almost 100% recoginition rate. UITapGestureRecognizer of Apple API fails frequently, just a piece of crap.
// - When immediateTriggering is set to false (for native multi-touch):
//   Gesture signal will be triggered on touchesEnded stage, multi finger touch operations will not be interrupted by the arising keyboard.
//   Instances of different [numberOfTouchesRequired] barely compete with each other, for example, the chance of 3-finger gesture get triggered by 4 or 5 finger tap is very small.
// - Set property immediateTriggering to true, to ensure the priority of keyboard toggle in non-native touch mode, in compete with 2-finger gestures.
// - This recognizer also provides properties like gestureCapturedTime, to be accessed outside the class for useful purpose.

@implementation CustomTapGestureRecognizer

static CGFloat screenHeightInPoints;
static CGFloat screenWidthInPoints;

- (instancetype)initWithTarget:(nullable id)target action:(nullable SEL)action {
    self = [super initWithTarget:target action:action];
    screenHeightInPoints = CGRectGetHeight([[UIScreen mainScreen] bounds]);
    screenWidthInPoints = CGRectGetWidth([[UIScreen mainScreen] bounds]);
    lowestTouchPointYCoord = 0.0;
    _numberOfTouchesRequired = 3;
    _immediateTriggering = false;
    _tapDownTimeThreshold = 0.3;
    _gestureCaptured = false;
    _containOnScreenControllerTaps = false;
    return self;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // Check if the number of touches and taps meets the required criteria
    if ([[event allTouches] count] == _numberOfTouchesRequired) {
        _gestureCapturedTime = CACurrentMediaTime();
        _gestureCaptured = true;
        for(UITouch *touch in [event allTouches]){
            if(lowestTouchPointYCoord < [touch locationInView:self.view].y) lowestTouchPointYCoord = [touch locationInView:self.view].y;
        }
        
        // this mechanism is deprecated.
        /* if(_numberOfTouchesRequired == 2){
            NSArray *twoTouches = [[event allTouches] allObjects];
            _areVirtualControllerTaps = fabs([twoTouches[1] locationInView:self.view].x - [twoTouches[0] locationInView:self.view].x) > screenWidthInPoints/3;
        } */
        
        _lowestTouchPointHeight = screenHeightInPoints - lowestTouchPointYCoord;
        if(_immediateTriggering){
            lowestTouchPointYCoord = 0.0; //reset for next recoginition
            self.state = UIGestureRecognizerStateRecognized;
            return;
        }
        self.state = UIGestureRecognizerStatePossible;
    }
    if ([[event allTouches] count] > _numberOfTouchesRequired) {
        _gestureCaptured = false;
        self.state = UIGestureRecognizerStateFailed;
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // [super touchesEnded:touches withEvent:event];
    if(_immediateTriggering) return;
    uint8_t allTouchesCount = [[event allTouches] count];
    if(allTouchesCount > _numberOfTouchesRequired) {
        _gestureCaptured = false;
        self.state = UIGestureRecognizerStateFailed;
    }
    else if(_gestureCaptured && allTouchesCount == [touches count] && !_containOnScreenControllerTaps && ![self containOnScreenButtonTaps]){  //must exclude virtual controller & onscreen button taps here to prevent stucked button, _areVirtualControllerTaps flag is set by onscreencontrols, containOnScreenButtonsTaps will be returned by iterating all button views in streamframeview
        _gestureCaptured = false; //reset for next recognition
        if((CACurrentMediaTime() - _gestureCapturedTime) < _tapDownTimeThreshold){
            lowestTouchPointYCoord = 0.0; //reset for next recognition
            self.state = UIGestureRecognizerStateRecognized;
        }
    }
    if (allTouchesCount == [touches count]) _containOnScreenControllerTaps = false; // need to reset this flag anyway, when all fingers are lefting
}


// it was a not a perfect choice to code OnScreenButtonView in Swift...
// we're unable to import this class to swift codebase by the bridging header,and have to exlucde the onscreen button taps here
// by iterating every button view instances. but it's basically ok since the number of buttonViews are always limited.
// and this method will only be called when the recognizer is active & and the taps passes all the checks and is about to ge triggered.
- (bool)containOnScreenButtonTaps {
    NSTimeInterval allFingersTapDownTime = CACurrentMediaTime() - _gestureCapturedTime; //RIGHTCLICK_TAP_DOWN_TIME_THRESHOLD_S has been passed to this recognizer as _tapDownTimeShreshold, we'll decide how to deal with pressed flag of on-screen button views based on tapDownTime
    bool gotOneButtonPressed = false;
    // the tap gestures are all added to the streamFrameTopLayerView, where all the onScreenButtonViews are added. so we can iterate them in this way:
    for(UIView* view in self.view.subviews){
        if ([view isKindOfClass:[OnScreenButtonView class]]) {
            OnScreenButtonView* buttonView = (OnScreenButtonView*) view;
            if(gotOneButtonPressed && allFingersTapDownTime <= _tapDownTimeThreshold){ // once we have just 1 button pressed already,& the tapDownTime has not exceeded the threshold, we'll reset pressed flag for the all the buttonViews.
                buttonView.pressed = false; //reset the flag for buttonView
                continue;
            }
            if(buttonView.pressed){
                gotOneButtonPressed = true; //got one button pressed
                if(allFingersTapDownTime <= _tapDownTimeThreshold) buttonView.pressed = false; // reset the flag for current buttonView if tapDowntime is still within the threshold, if not, leave the flag for mouse scroller gesture in relative touch mode.
            }
        }
    }
    return gotOneButtonPressed;
}

@end
