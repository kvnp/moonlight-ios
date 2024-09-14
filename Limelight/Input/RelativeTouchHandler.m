//
//  RelativeTouchHandler.m
//  Moonlight
//
//  Completely refactored by ZWM on 2024.9.13
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import "RelativeTouchHandler.h"
#import "DataManager.h"

#include <Limelight.h>


static const int REFERENCE_WIDTH = 1280;
static const int REFERENCE_HEIGHT = 720;
static const float QUICK_TAP_TIME_INTERVAL = 0.2;

@implementation RelativeTouchHandler {
    TemporarySettings* currentSettings;
    CGPoint latestMousePointerLocation, initialMousePointerLocation;
    CGPoint twoFingerTouchLocation;
    NSTimeInterval mousePointerTimestamp;
    BOOL mousePointerMoved;
    BOOL quickTapDetected;
    BOOL mouseLeftButtonHeldDown;
    BOOL isInMouseWheelScrollingMode;
    
    // upper screen edge check
    bool touchPointSpawnedAtUpperScreenEdge;
    CGFloat slideGestureVerticalThreshold;
    CGFloat screenWidthWithThreshold;
    CGFloat EDGE_TOLERANCE;

    UITouch* touchLockedForMouseMove;
    
#if TARGET_OS_TV
    UIGestureRecognizer* remotePressRecognizer;
    UIGestureRecognizer* remoteLongPressRecognizer;
#endif
    
    StreamView* streamView;
}

- (id)initWithView:(StreamView*)view andSettings:(TemporarySettings*)settings {
    self = [self init];
    self->streamView = view;
    self->currentSettings = settings;
    // replace righclick recoginizing with my CustomTapGestureRecognizer for better experience, higher recoginizing rate.
    _mouseRightClickTapRecognizer = [[CustomTapGestureRecognizer alloc] initWithTarget:self action:@selector(mouseRightClick)];
    _mouseRightClickTapRecognizer.numberOfTouchesRequired = 2;
    _mouseRightClickTapRecognizer.tapDownTimeThreshold = RIGHTCLICK_TAP_DOWN_TIME_THRESHOLD_S; // tap down time in seconds.
    _mouseRightClickTapRecognizer.delaysTouchesBegan = NO;
    _mouseRightClickTapRecognizer.delaysTouchesEnded = NO;
    [self->streamView.streamFrameTopLayerView addGestureRecognizer:_mouseRightClickTapRecognizer]; // add all additional gestures to the streamFrameTopLayerView instead of the streamview.
    
    isInMouseWheelScrollingMode = false;
    mousePointerMoved = false;
    mouseLeftButtonHeldDown = false;
    mousePointerTimestamp = 0;
    
    // upper screen check
    EDGE_TOLERANCE = 15.0;
    slideGestureVerticalThreshold = CGRectGetHeight([[UIScreen mainScreen] bounds]) * 0.4;
    screenWidthWithThreshold = CGRectGetWidth([[UIScreen mainScreen] bounds]) - EDGE_TOLERANCE;
    self->touchPointSpawnedAtUpperScreenEdge = false;

#if TARGET_OS_TV
    remotePressRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(remoteButtonPressed:)];
    remotePressRecognizer.allowedPressTypes = @[@(UIPressTypeSelect)];
    
    remoteLongPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(remoteButtonLongPressed:)];
    remoteLongPressRecognizer.allowedPressTypes = @[@(UIPressTypeSelect)];
    
    [self->view addGestureRecognizer:remotePressRecognizer];
    [self->view addGestureRecognizer:remoteLongPressRecognizer];
#endif
    
    return self;
}


- (bool)containOnScreenControllerTaps:(NSSet* )touches{
    for(UITouch* touch in touches){
        if([OnScreenControls.touchAddrsCapturedByOnScreenControls containsObject:@((uintptr_t)touch)]) return true;
    }
    return false;
}


- (bool)containOnScreenButtonTaps {
    bool gotOneButtonPressed = false;
    for(UIView* view in self->streamView.superview.subviews){  // iterates all on-screen button views in StreamFrameView
        if ([view isKindOfClass:[OnScreenButtonView class]]) {
            OnScreenButtonView* buttonView = (OnScreenButtonView*) view;
            if(buttonView.pressed){
                gotOneButtonPressed = true; //got one button pressed
            }
        }
    }
    return gotOneButtonPressed;
}

- (void)resetAllPressedFlagsForOnscreenButtonViews {
    for(UIView* view in self->streamView.superview.subviews){  // iterates all on-screen button views in StreamFrameView
        if ([view isKindOfClass:[OnScreenButtonView class]]) {
            OnScreenButtonView* buttonView = (OnScreenButtonView*) view;
            buttonView.pressed = false;
        }
    }
}


- (void)mouseRightClick {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        Log(LOG_D, @"Sending right mouse button press");
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT);
        // Wait 100 ms to simulate a real button press
        usleep(100 * 1000);
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
    });
}

- (BOOL)isConfirmedMove:(CGPoint)currentPoint from:(CGPoint)originalPoint {
    // Movements of greater than 5 pixels are considered confirmed
    return hypotf(originalPoint.x - currentPoint.x, originalPoint.y - currentPoint.y) >= 5;
}

- (BOOL)isAdjacentTouches:(CGPoint)currentPoint from:(CGPoint)originalPoint {
    // Movements of greater than 5 pixels are considered confirmed
    return hypotf(originalPoint.x - currentPoint.x, originalPoint.y - currentPoint.y) <= 100;
}


- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    
    //check if touch point is spawned on the left or right upper half screen edges, this is the highest priority
    CGPoint initialPoint = [[touches anyObject] locationInView:streamView];
    if(initialPoint.y < slideGestureVerticalThreshold && (initialPoint.x < EDGE_TOLERANCE || initialPoint.x > screenWidthWithThreshold)) {
        self->touchPointSpawnedAtUpperScreenEdge = true;
        return;
    }
    
    touchPointSpawnedAtUpperScreenEdge = false; // reset this flag immediately if we get a touch event passing the check above, this fixes irresponsive touch after closing the command tool menu.
    
    if([[event allTouches] count] == 2 && ![self containOnScreenButtonTaps] && ![self containOnScreenControllerTaps:[event allTouches]]){
        NSLog(@"get in scrolling mode");
        isInMouseWheelScrollingMode = true;
        return; // if we got 2 touches on the blank area, it's gonna be a mouse scroll touch, and must prevent UITtouch object for mouse pointer being captured & locked
    }
    
    // NSLog(@"touches count in began stage: %llu", (uint64_t)[touches count]);
    
    UITouch* candidateTouch = nil;
    
    // the onscreen controllers are implmented by CALayer, which can not intercept UITouch event, touch will penetrate to the streamView level and captured in the touches callback of this touchHandler class.
    // the onscreen button are UIViews, they intercept UITouch events, so we don't need to worry about them.
    for(UITouch* touch in touches){
        // NSLog(@"candidate touch test: %llu", (uint64_t)touch);
        if([OnScreenControls.touchAddrsCapturedByOnScreenControls containsObject:@((uintptr_t)touch)]){
            // NSLog(@"%f controller tap detected", CACurrentMediaTime());
            continue;
        }
        else candidateTouch = touch;
    }

    // quick double tap detection for dragging. simulates a real notebook computer touchpad
    CGPoint currentTouchLocation = [candidateTouch locationInView:streamView];
    NSTimeInterval tapInterval = CACurrentMediaTime() - mousePointerTimestamp;
    if(tapInterval < QUICK_TAP_TIME_INTERVAL && [self isAdjacentTouches:currentTouchLocation from:initialMousePointerLocation] ) {
        // NSLog(@"quick click detected");
        quickTapDetected = true;
        NSLog(@"quick Tap Detected");
        // LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT); // do not press down mouse button here, or it wiil easily turn to double click on remote PC
    }

    // we must use [event allTouches] to check if touchLockedForMouseMove is captured, because the UITouch object could be captured by upper layer of UIView(in cases like tap gestures), not passed to the touches callbacks in this class, but still available in [event allTouches]
    if(candidateTouch != nil && ![[event allTouches] containsObject:touchLockedForMouseMove]){
        touchLockedForMouseMove = candidateTouch;
        NSLog(@"%f candidate touch for mouse movement locked, addr: %llu", CACurrentMediaTime(), (uintptr_t)touchLockedForMouseMove);
        mousePointerTimestamp = CACurrentMediaTime();
        initialMousePointerLocation = latestMousePointerLocation = [touchLockedForMouseMove locationInView:streamView];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    
    //NSLog(@"%f, touchesMoved callback, is scrolling: %d, touches count: %d", CACurrentMediaTime(), isInMouseWheelScrollingMode, (uint32_t)[touches count]);
    
    if(isInMouseWheelScrollingMode){
        NSSet* twoTouches = [event allTouches];
        CGPoint firstLocation = [[[twoTouches allObjects] objectAtIndex:0] locationInView:streamView];
        CGPoint secondLocation = [[[twoTouches allObjects] objectAtIndex:1] locationInView:streamView];
        
        CGPoint avgLocation = CGPointMake((firstLocation.x + secondLocation.x) / 2, (firstLocation.y + secondLocation.y) / 2);
        if ((CACurrentMediaTime() - _mouseRightClickTapRecognizer.gestureCapturedTime > RIGHTCLICK_TAP_DOWN_TIME_THRESHOLD_S) && twoFingerTouchLocation.y != avgLocation.y && ![self containOnScreenButtonTaps] && ![self containOnScreenControllerTaps:twoTouches]) { //prevent sending scrollevent while right click gesture is being recognized. The time threshold is only 150ms, resulting in a barely noticeable delay before the scroll event is activated.
            // and we must exclude onscreen button taps & on-screen controller taps
            LiSendHighResScrollEvent((avgLocation.y - twoFingerTouchLocation.y) * 10);
        }
        twoFingerTouchLocation = avgLocation;
        return;
    }

    // NSLog(@"%f touchesMoved callback, locked touch: %llu", CACurrentMediaTime(), (uintptr_t)touchLockedForMouseMove);
    
    if([touches containsObject:touchLockedForMouseMove]){
        mousePointerMoved = true;
        if(self->quickTapDetected && !mouseLeftButtonHeldDown) {
            NSLog(@"Sending mouse left button down event in touchesMoved callback ...");
            mouseLeftButtonHeldDown = true;
            LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT); // start Dragging...
        }
        [self sendMouseMoveEvent:touchLockedForMouseMove];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if(isInMouseWheelScrollingMode){
        isInMouseWheelScrollingMode = false;
        return;
    }
    
    if([touches containsObject:touchLockedForMouseMove]){
        if(!mousePointerMoved && !self->quickTapDetected) [self sendLongMouseLeftButtonClickEvent];
        if(self->quickTapDetected){
            // we're in at least the second tap release of the very short time interval after the first tap.
            LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT); // must release the button first, because the button is likely being held down since the long click turned into a dragging event.
            if(!mousePointerMoved) [self sendShortMouseLeftButtonClickEvent]; // if it is a quick tap and the pointer was not moved, we must send another click to simulate double click.
            self->quickTapDetected = false; // reset flag
            self->mouseLeftButtonHeldDown = false; // reset flag
        }
        touchLockedForMouseMove = nil;
        mousePointerMoved = false;
    }
    
    if([[event allTouches] count] == [touches count]){
        isInMouseWheelScrollingMode = false;
        touchLockedForMouseMove = nil;
        mousePointerMoved = false; // need to reset this anyway
        [self resetAllPressedFlagsForOnscreenButtonViews]; // reset all pressed flag for on-screen button views after all fingers lifted from screen.
        touchPointSpawnedAtUpperScreenEdge = false;
    }
}


- (void)sendMouseMoveEvent:(UITouch* )touch{
    if(touchPointSpawnedAtUpperScreenEdge) return; // we're done here. this touch event will not be sent to the remote PC.

    CGPoint currentLocation = [touch locationInView:streamView];
    
    if (latestMousePointerLocation.x != currentLocation.x ||
        latestMousePointerLocation.y != currentLocation.y)
    {
        int deltaX = (currentLocation.x - latestMousePointerLocation.x) * (REFERENCE_WIDTH / streamView.bounds.size.width) * currentSettings.mousePointerVelocityFactor.floatValue;
        int deltaY = (currentLocation.y - latestMousePointerLocation.y) * (REFERENCE_HEIGHT / streamView.bounds.size.height) * currentSettings.mousePointerVelocityFactor.floatValue;
        
        if (deltaX != 0 || deltaY != 0) {
            LiSendMouseMoveEvent(deltaX, deltaY);
            latestMousePointerLocation = currentLocation;
            
            // If we've moved far enough to confirm this wasn't just human/machine error,
            // mark it as such.
            if ([self isConfirmedMove:latestMousePointerLocation from:initialMousePointerLocation]) {
                mousePointerMoved = true;
            }
        }
    }
}


// this will turn into a dragging anytime...
- (void)sendLongMouseLeftButtonClickEvent{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        // if (!self->isDragging){
        Log(LOG_D, @"Sending left mouse button press");
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
        // Wait 100 ms to simulate a real button press
        usleep(QUICK_TAP_TIME_INTERVAL * 1000000);
        if(!self->quickTapDetected){
            NSLog(@"Left mouse button release cancelled, keep pressing down, turning into dragging...");
            LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
        }
        // do not release the button if we're still dragging, this will prevent the dragging from being interrupted.
    });
}

- (void)sendShortMouseLeftButtonClickEvent{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
        usleep(50 * 1000);
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    });
}



#if TARGET_OS_TV
- (void)remoteButtonPressed:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        Log(LOG_D, @"Sending left mouse button press");
        
        // Mark this as touchMoved to avoid a duplicate press on touch up
        self->touchMoved = true;
        
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
        
        // Wait 100 ms to simulate a real button press
        usleep(100 * 1000);
            
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    });
}
- (void)remoteButtonLongPressed:(id)sender {
    Log(LOG_D, @"Holding left mouse button");
    
    isDragging = true;
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
}
#endif

@end
