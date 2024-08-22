//
//  NativeTouchPointer.m
//  Moonlight
//
//  Created by ZWM on 2024/5/14.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NativeTouchPointer.h"
#include <Limelight.h>

// native touch pointer ojbect that stores & manipulates touch coordinates

static NSMutableDictionary *pointerObjDict;

static CGFloat pointerVelocityFactor;
static CGFloat pointerVelocityDivider;
static CGFloat pointerVelocityDividerLocationByPoints;
static CGFloat streamViewHeight;
static CGFloat streamViewWidth;
static CGFloat fixedResetCoordX;
static CGFloat fixedResetCoordY;
static StreamView* _streamView;

@implementation NativeTouchPointer{
    CGPoint initialPoint;
    CGPoint latestPoint;
    CGPoint previousPoint;
    CGPoint latestRelativePoint;
    CGPoint previousRelativePoint;
    bool useRelativeCoords;
}

- (instancetype)initWithTouch:(UITouch *)touch{
    self = [super init];
    self->initialPoint = [touch locationInView:_streamView];
    self->latestPoint = self->initialPoint;
    self->latestRelativePoint = self->initialPoint;
    return self;
}

- (bool)doesNeedResetCoords{
    bool boundaryReached = (latestRelativePoint.x > streamViewWidth || latestRelativePoint.x < 0.0f ||  latestRelativePoint.y > streamViewHeight || latestRelativePoint.y < 0.0f);
    bool withinExcludedArea =  (initialPoint.x > streamViewWidth * (0.75) && initialPoint.x < streamViewWidth) && (initialPoint.y > streamViewHeight * (0.8) && initialPoint.y < streamViewHeight);
    _needResetCoords = (pointerVelocityFactor > 1.0f) && self->useRelativeCoords && boundaryReached && !withinExcludedArea; 
    // boundary detection & coordinates reset to the specific point for HK:StarTrail(needs a very high pointer velocity)
    // must exclude touch pointer that uses native coords instead of relative ones.
    // also exclude touch pointer created within  the bottom right corner
    
    return _needResetCoords;
}

- (void)updatePointerCoords:(UITouch *)touch{
    previousPoint = latestPoint;
    latestPoint = [touch locationInView:_streamView];
    previousRelativePoint = latestRelativePoint;
    if(_needResetCoords){// boundary detection & coordinates reset to the central screen point for HK:StarTrail(needs a very high pointer velocity); // boundary detection & coordinates reset to specific point for HK:StarTrail(needs a very high pointer velocity)
        previousRelativePoint.x = fixedResetCoordX;
        previousRelativePoint.y = fixedResetCoordY;
    }
    latestRelativePoint.x = previousRelativePoint.x + pointerVelocityFactor * (latestPoint.x - previousPoint.x);
    latestRelativePoint.y = previousRelativePoint.y + pointerVelocityFactor * (latestPoint.y - previousPoint.y);
}

+ (void)initContextWithView:(StreamView *)view {
    _streamView = view;
    streamViewWidth = _streamView.frame.size.width;
    fixedResetCoordX = streamViewWidth * 0.3;
    streamViewHeight = _streamView.frame.size.height;
    fixedResetCoordY = streamViewHeight * 0.4;
    NSLog(@"stream wdith %f, stream height %f", streamViewWidth, streamViewHeight);
    pointerObjDict = [NSMutableDictionary dictionary];
    pointerVelocityDividerLocationByPoints = CGRectGetWidth([[UIScreen mainScreen] bounds]) * pointerVelocityDivider;
    NSLog(@"pointerVelocityDivider:  %.2f", pointerVelocityDivider);
    NSLog(@"pointerVelocityFactor:  %.2f", pointerVelocityFactor);
    NSLog(@"pointerVelocityDividerLocationByPoints:  %.2f", pointerVelocityDividerLocationByPoints);
}

+ (void)setPointerVelocityDivider:(CGFloat)dividerLocation{
    pointerVelocityDivider = dividerLocation;
}

+ (void)setPointerVelocityFactor:(CGFloat)velocityFactor{
    pointerVelocityFactor = velocityFactor;
}


+ (void)populatePointerObjIntoDict:(UITouch*)touch{
    [pointerObjDict setObject:[[NativeTouchPointer alloc] initWithTouch:touch] forKey:@((uintptr_t)touch)];
}

+ (void)removePointerObjFromDict:(UITouch*)touch{
    uintptr_t memAddrValue = (uintptr_t)touch;
    NativeTouchPointer* pointer = [pointerObjDict objectForKey:@(memAddrValue)];
    if(pointer != nil){
        [pointerObjDict removeObjectForKey:@(memAddrValue)];
    }
}

+ (NativeTouchPointer* )getPointerObjFromDict:(UITouch*)touch{
    return [pointerObjDict objectForKey:@((uintptr_t)touch)];
}


+ (void)updatePointerObjInDict:(UITouch *)touch{
    [[pointerObjDict objectForKey:@((uintptr_t)touch)] updatePointerCoords:touch];
}


+ (CGPoint)selectCoordsFor:(UITouch *)touch{
    NativeTouchPointer *pointer = [pointerObjDict objectForKey:@((uintptr_t)touch)];
    if(pointer == nil) return CGPointMake(0, 0); // THIS will PREVENT CRASH caused by slide gesture!
    if((pointer -> initialPoint).x > pointerVelocityDividerLocationByPoints){  //if first contact coords locates on the right side of divider.
        pointer -> useRelativeCoords = true;
        return pointer->latestRelativePoint;
    }
    else{
        pointer -> useRelativeCoords = false;
        return[touch locationInView:_streamView];
    }
}


@end
