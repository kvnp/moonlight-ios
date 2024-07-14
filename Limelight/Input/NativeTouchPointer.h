//
//  NativeTouchPointer.h
//  Moonlight
//
//  Created by ZWM on 2024/5/14.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

#import "StreamView.h"
#import "NativeTouchHandler.h"

NS_ASSUME_NONNULL_BEGIN

@interface NativeTouchPointer : NSObject
@property (nonatomic, assign) bool boundaryReached;

+ (void)initContextWithView:(StreamView *)view;
+ (void)setPointerVelocityDivider:(CGFloat)dividerLocation;
+ (void)setPointerVelocityFactor:(CGFloat)velocityFactor;

+ (NativeTouchPointer* )getPointerObjFromDict:(UITouch*)touch;
- (bool)doesReachBoundary;

+ (void)populatePointerObjIntoDict:(UITouch*)touch;
+ (void)removePointerObjFromDict:(UITouch*)touch;
+ (void)updatePointerObjInDict:(UITouch *)touch;
+ (CGPoint)selectCoordsFor:(UITouch *)touch;


- (instancetype)initWithTouch:(UITouch *)touch;
@end




NS_ASSUME_NONNULL_END

