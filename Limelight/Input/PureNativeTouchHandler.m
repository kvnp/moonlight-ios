//
//  NativeTouchHandler.m
//  Moonlight
//
//  Created by ZWM on 2024/8/29.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PureNativeTouchHandler.h"
#import "NativeTouchPointer.h"
#import "StreamView.h"

#include <Limelight.h>


@implementation PureNativeTouchHandler {
    StreamView* streamView;
    TemporarySettings* currentSettings;
    bool activateCoordSelector;
    bool touchPointSpawnedAtUpperScreenEdge;
    
    // Use a Dictionary to store UITouch object's memory address as key, and pointerId as value,字典存放UITouch对象地址和pointerId映射关系
    // pointerId will be generated from a pre-defined pool
    // Use a NSSet store active pointerId,
    NSMutableDictionary *pointerIdDict; //pointerId Dict for active touches.
    NSMutableSet<NSNumber *> *activePointerIds; //pointerId Set for active touches.
    NSMutableSet<NSNumber *> *pointerIdPool; //pre-defined pool of pointerIds.
    NSMutableSet<NSNumber *> *unassignedPointerIds;
    
    CGFloat slideGestureVerticalThreshold;
    CGFloat screenWidthWithThreshold;
    CGFloat EDGE_TOLERANCE;
}


- (id)initWithView:(StreamView*)view andSettings:(TemporarySettings*)settings{
    self = [super init];
    self->streamView = view;
    self->currentSettings = settings;
    self->activateCoordSelector = currentSettings.pointerVelocityModeDivider.floatValue != 1.0;
    
    pointerIdDict = [NSMutableDictionary dictionary];
    pointerIdPool = [NSMutableSet set];
    for (uint8_t i = 0; i <= 10; i++) { //ipadOS supports upto 11 finger touches
        [pointerIdPool addObject:@(i)];
    }
    activePointerIds = [NSMutableSet set];
    self->touchPointSpawnedAtUpperScreenEdge = false;

    EDGE_TOLERANCE = 15.0;
    slideGestureVerticalThreshold = CGRectGetHeight([[UIScreen mainScreen] bounds]) * 0.4;
    screenWidthWithThreshold = CGRectGetWidth([[UIScreen mainScreen] bounds]) - EDGE_TOLERANCE;

    [NativeTouchPointer setPointerVelocityDivider:settings.pointerVelocityModeDivider.floatValue];
    [NativeTouchPointer setPointerVelocityFactor:settings.touchPointerVelocityFactor.floatValue];
    [NativeTouchPointer initContextWithView:self->streamView];
    return self;
}


// generate & populate pointerId into NSDict & NSSet, called in touchesBegan
- (void)handleTouchDown:(UITouch*)touch{
    uintptr_t memAddrValue = (uintptr_t)touch;
    unassignedPointerIds = [pointerIdPool mutableCopy]; //reset unassignedPointerIds
    [unassignedPointerIds minusSet:activePointerIds];
    uint8_t pointerId = [[unassignedPointerIds anyObject] unsignedIntValue];
    [pointerIdDict setObject:@(pointerId) forKey:@(memAddrValue)];
    [activePointerIds addObject:@(pointerId)];
    
    //check if touch point is spawned on the left or right upper half screen edges,
    CGPoint initialPoint = [touch locationInView:self->streamView];
    if(initialPoint.y < slideGestureVerticalThreshold && (initialPoint.x < EDGE_TOLERANCE || initialPoint.x > screenWidthWithThreshold)) {
        self->touchPointSpawnedAtUpperScreenEdge = true;
    }
}

// remove pointerId in touchesEnded or touchesCancelled
- (void)removePointerId:(UITouch*)touch{
    uintptr_t memAddrValue = (uintptr_t)touch;
    NSNumber* pointerIdObj = [pointerIdDict objectForKey:@(memAddrValue)];
    if(pointerIdObj != nil){
        [activePointerIds removeObject:pointerIdObj];
        [pointerIdDict removeObjectForKey:@(memAddrValue)];
    }
}

// 从字典中获取UITouch事件对应的pointerId
// called in method of sendTouchEvent
- (uint8_t) retrievePointerIdFromDict:(UITouch*)touch{
    return [[pointerIdDict objectForKey:@((uintptr_t)touch)] unsignedIntValue];
}


- (void)sendTouchEvent:(UITouch*)touch withTouchtype:(uint8_t)touchType{
    if(touchPointSpawnedAtUpperScreenEdge) return; // we're done here. this touch event will not be sent to the remote PC. and this must be checked after coord selector finishes populating new relative coords, or the app will crash!

    CGPoint targetCoords;
    if(activateCoordSelector && touch.phase == UITouchPhaseMoved) targetCoords = [NativeTouchPointer selectCoordsFor:touch]; // coordinates of touch pointer replaced to relative ones here.
    else targetCoords = [touch locationInView:streamView];
    
    CGPoint location = [streamView adjustCoordinatesForVideoArea:targetCoords];
    CGSize videoSize = [streamView getVideoAreaSize];
    CGFloat normalizedX = location.x / videoSize.width;
    CGFloat normalizedY = location.y / videoSize.height;
    uint8_t pointerId = [self retrievePointerIdFromDict:touch];
    
    if([NativeTouchPointer getPointerObjFromDict:touch].needResetCoords){ // access whether the current pointer has reached the boundary, and need a coord reset.
        LiSendTouchEvent(LI_TOUCH_EVENT_UP, pointerId, normalizedX, normalizedY, 0, 0, 0, 0);  //event must sent from the lowest level directy by LiSendTouchEvent to simulate continous dragging to another point on screen
        LiSendTouchEvent(LI_TOUCH_EVENT_DOWN, pointerId, 0.3, 0.4, 0, 0, 0, 0);
    }else LiSendTouchEvent(touchType, pointerId, normalizedX, normalizedY,(touch.force / touch.maximumPossibleForce) / sin(touch.altitudeAngle),0.0f, 0.0f,[streamView getRotationFromAzimuthAngle:[touch azimuthAngleInView:streamView]]);
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    for (UITouch* touch in touches){
        [self handleTouchDown:touch]; //generate & populate pointerId
        if(activateCoordSelector) [NativeTouchPointer populatePointerObjIntoDict:touch];
        [self sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_DOWN];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    for (UITouch* touch in touches){
        if(activateCoordSelector) [NativeTouchPointer updatePointerObjInDict:touch];
        [self sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_MOVE];
        [[NativeTouchPointer getPointerObjFromDict:touch] doesNeedResetCoords]; // execute the judging of doesReachBoundary for current pointer instance. (happens after the event is sent to Sunshine service)
    }
    return;
}


- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    for (UITouch* touch in touches){
        [self sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_UP]; //send touch event before remove pointerId
        [self removePointerId:touch]; //then remove pointerId
        if(activateCoordSelector) [NativeTouchPointer removePointerObjFromDict:touch];
    }
    if(touchPointSpawnedAtUpperScreenEdge && [[event allTouches] count] == [touches count]) touchPointSpawnedAtUpperScreenEdge = false;

    return;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}


@end
