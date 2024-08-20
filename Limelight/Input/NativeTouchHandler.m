//
//  NativeTouchHandler.m
//  Moonlight
//
//  Created by ZWM on 2024/6/16.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NativeTouchHandler.h"
#import "NativeTouchPointer.h"
#import "OnScreenControls.h"
#import "StreamView.h"
#import "DataManager.h"

#include <Limelight.h>




@implementation NativeTouchHandler {
    StreamView* streamView;
    TemporarySettings* currentSettings;
    bool activateCoordSelector;
    bool notPureNativeTouchMode;
    
    // Use a Dictionary to store UITouch object's memory address as key, and pointerId as value,字典存放UITouch对象地址和pointerId映射关系
    // pointerId will be generated from a pre-defined pool
    // Use a NSSet store active pointerId,
    NSMutableDictionary *pointerIdDict; //pointerId Dict for active touches.
    NSMutableSet<NSNumber *> *activePointerIds; //pointerId Set for active touches.
    NSMutableSet<NSNumber *> *pointerIdPool; //pre-defined pool of pointerIds.
    NSMutableSet<NSNumber *> *unassignedPointerIds;
    NSMutableSet<NSNumber *> *excludedPointerIds; // a NSSet of pointerIds of touches that will not be sent to the remote PC for better swipe gesture handling
    CGFloat slideGestureVerticalThreshold;
    CGFloat screenWidthWithThreshold;
    CGFloat EDGE_TOLERANCE;
}

- (id)initWithView:(StreamView*)view andSettings:(TemporarySettings*)settings{
    self = [super init];
    self->streamView = view;
    self->currentSettings = settings;
    self->activateCoordSelector = currentSettings.pointerVelocityModeDivider.floatValue != 1.0;
    self->notPureNativeTouchMode = !(currentSettings.touchMode.intValue == PURE_NATIVE_TOUCH);
    
    self->pointerIdDict = [NSMutableDictionary dictionary];
    self->pointerIdPool = [NSMutableSet set];
    for (uint8_t i = 0; i <= 10; i++) { //ipadOS supports upto 11 finger touches
        [self->pointerIdPool addObject:@(i)];
    }
    self->activePointerIds = [NSMutableSet set];
    self->excludedPointerIds = [[NSMutableSet alloc] init];
    
    EDGE_TOLERANCE = 5.0;
    slideGestureVerticalThreshold = CGRectGetHeight([[UIScreen mainScreen] bounds]) * 0.4;
    screenWidthWithThreshold = CGRectGetWidth([[UIScreen mainScreen] bounds]) - EDGE_TOLERANCE;

    [NativeTouchPointer setPointerVelocityDivider:settings.pointerVelocityModeDivider.floatValue];
    [NativeTouchPointer setPointerVelocityFactor:settings.touchPointerVelocityFactor.floatValue];
    [NativeTouchPointer initContextWithView:self->streamView];
    //_touchesCapturedByOnScreenButtons = [[NSMutableSet alloc] init];
    return self;
}



// generate & populate pointerId into NSDict & NSSet, called in touchesBegan
- (void)populatePointerId:(UITouch*)touch{
    //populate pointerId
    uintptr_t memAddrValue = (uintptr_t)touch;
    unassignedPointerIds = [pointerIdPool mutableCopy]; //reset unassignedPointerIds
    [unassignedPointerIds minusSet:activePointerIds];
    uint8_t pointerId = [[unassignedPointerIds anyObject] unsignedIntValue];
    [pointerIdDict setObject:@(pointerId) forKey:@(memAddrValue)];
    [activePointerIds addObject:@(pointerId)];
    
    //check if touch point is spawned on the left or right upper half screen edges, if so we'll populate the excluded pointer id NSSet and not send the touch event to remote PC. this is for better handling in-stream slide gesture
    CGPoint initialPoint = [touch locationInView:self->streamView];
    if(initialPoint.y < slideGestureVerticalThreshold && (initialPoint.x < EDGE_TOLERANCE || initialPoint.x > screenWidthWithThreshold)) [excludedPointerIds addObject:@(pointerId)];
}

// remove pointerId in touchesEnded or touchesCancelled
- (void)removePointerId:(UITouch*)touch{
    uintptr_t memAddrValue = (uintptr_t)touch;
    NSNumber* pointerIdObj = [pointerIdDict objectForKey:@(memAddrValue)];
    if(pointerIdObj != nil){
        [activePointerIds removeObject:pointerIdObj];
        [pointerIdDict removeObjectForKey:@(memAddrValue)];
        if([excludedPointerIds containsObject:pointerIdObj]) [excludedPointerIds removeObject:pointerIdObj]; // remove pointer id from excludedPointerId NSSet
    }
}

// 从字典中获取UITouch事件对应的pointerId
// called in method of sendTouchEvent
- (uint8_t) retrievePointerIdFromDict:(UITouch*)touch{
    return [[pointerIdDict objectForKey:@((uintptr_t)touch)] unsignedIntValue];
}


- (void)sendTouchEvent:(UITouch*)touch withTouchtype:(uint8_t)touchType{
    CGPoint targetCoords;
    uint8_t pointerId = [self retrievePointerIdFromDict:touch];
    NSLog(@"excluded count: %d", (uint32_t)[excludedPointerIds count]);
    if(activateCoordSelector && touch.phase == UITouchPhaseMoved) targetCoords = [NativeTouchPointer selectCoordsFor:touch]; // coordinates of touch pointer replaced to relative ones here.
    
    if([excludedPointerIds containsObject:@(pointerId)]) return; // if the pointerId has been excluded by edge check, we're done here. this touch event will not be sent to the remote PC. and this must be checked after coord selector finishes populating new relative coords, or the app will crash!
    else targetCoords = [touch locationInView:streamView];
    CGPoint location = [streamView adjustCoordinatesForVideoArea:targetCoords];
    CGSize videoSize = [streamView getVideoAreaSize];
    CGFloat normalizedX = location.x / videoSize.width;
    CGFloat normalizedY = location.y / videoSize.height;
    
    if([NativeTouchPointer getPointerObjFromDict:touch].needResetCoords){ // access whether the current pointer has reached the boundary, and need a coord reset.
        LiSendTouchEvent(LI_TOUCH_EVENT_UP, pointerId, normalizedX, normalizedY, 0, 0, 0, 0);  //event must sent from the lowest level directy by LiSendTouchEvent to simulate continous dragging to another point on screen
        LiSendTouchEvent(LI_TOUCH_EVENT_DOWN, pointerId, 0.3, 0.4, 0, 0, 0, 0);
    }else LiSendTouchEvent(touchType, pointerId, normalizedX, normalizedY,(touch.force / touch.maximumPossibleForce) / sin(touch.altitudeAngle),0.0f, 0.0f,[streamView getRotationFromAzimuthAngle:[touch azimuthAngleInView:streamView]]);
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    for (UITouch* touch in touches){
        // continue to the next loop if current touch is already captured by OSC. works only in regular native touch
        if(notPureNativeTouchMode && [OnScreenControls.touchAddrsCapturedByOnScreenControls containsObject:@((uintptr_t)touch)]) continue;
        [self populatePointerId:touch]; //generate & populate pointerId
        if(activateCoordSelector) [NativeTouchPointer populatePointerObjIntoDict:touch];
        [self sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_DOWN];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    // NSLog(@"captured by OSB touches: %d", (uint32_t)[OnScreenControls.touchAddrsCapturedByOnScreenControls count]);
    for (UITouch* touch in touches){
        // continue to the next loop if current touch is already captured by OSC. works only in regular native touch
        if(notPureNativeTouchMode && [OnScreenControls.touchAddrsCapturedByOnScreenControls containsObject:@((uintptr_t)touch)]) continue;
        if(activateCoordSelector) [NativeTouchPointer updatePointerObjInDict:touch];
        [self sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_MOVE];
        [[NativeTouchPointer getPointerObjFromDict:touch] doesNeedResetCoords]; // execute the judging of doesReachBoundary for current pointer instance. (happens after the event is sent to Sunshine service)
    }
    return;
}


- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    for (UITouch* touch in touches){
        // continue to the next loop if current touch is already captured by OSC. works only in regular native touch
        if(notPureNativeTouchMode && [OnScreenControls.touchAddrsCapturedByOnScreenControls containsObject:@((uintptr_t)touch)]) continue;
        [self sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_UP]; //send touch event before remove pointerId
        [self removePointerId:touch]; //then remove pointerId
        if(activateCoordSelector) [NativeTouchPointer removePointerObjFromDict:touch];
    }
    return;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}


@end
