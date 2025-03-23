//
//  CustomEdgeSlideGestureRecognizer.m
//  Moonlight-ZWM
//
//  Created by ZWM on 2024/4/30.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

// #import <Foundation/Foundation.h>

#import "CustomEdgeSlideGestureRecognizer.h"
#import <UIKit/UIGestureRecognizerSubclass.h>

@implementation CustomEdgeSlideGestureRecognizer
UITouch* capturedUITouch;
CGFloat startPointX;
static CGFloat screenWidthInPoints;

- (instancetype)initWithTarget:(nullable id)target action:(nullable SEL)action {
    self = [super initWithTarget:target action:action];
    screenWidthInPoints = CGRectGetWidth([UIApplication.sharedApplication.windows.firstObject.screen bounds]); // Get the screen's bounds (in points)
    _immediateTriggering = false;
    _EDGE_TOLERANCE = 15.0f;
    return self;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // [super touchesBegan:touches withEvent:event];
    UITouch *touch = [touches anyObject];
    capturedUITouch = touch;
    startPointX = [capturedUITouch locationInView:self.view].x;
    if(_immediateTriggering){
        
        if(self.edges & UIRectEdgeLeft){
            if(startPointX < _EDGE_TOLERANCE){
                self.state = UIGestureRecognizerStateEnded;
            }
            // NSLog(@"startPointX  %f , normalizedGestureDeltaX %f", startPointX,  normalizedGestureDistance);
        }
        if(self.edges & UIRectEdgeRight){
            if(startPointX > screenWidthInPoints - _EDGE_TOLERANCE){
                self.state = UIGestureRecognizerStateEnded;
            }
           // NSLog(@"startPointX  %f , normalizedGestureDeltaX %f", startPointX,  normalizedGestureDistance);
        }

    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // [super touchesEnded:touches withEvent:event];
    
    if([touches containsObject:capturedUITouch]){
        CGFloat _endPointX = [capturedUITouch locationInView:self.view].x;
        CGFloat normalizedGestureDistance = fabs(_endPointX - startPointX)/screenWidthInPoints;
        
        if(self.edges & UIRectEdgeLeft){
            if(startPointX < _EDGE_TOLERANCE && normalizedGestureDistance > _normalizedThresholdDistance){
                self.state = UIGestureRecognizerStateEnded;
            }
            // NSLog(@"startPointX  %f , normalizedGestureDeltaX %f", startPointX,  normalizedGestureDistance);
        }
        if(self.edges & UIRectEdgeRight){
            if((startPointX > (screenWidthInPoints - _EDGE_TOLERANCE)) && normalizedGestureDistance > _normalizedThresholdDistance){
                self.state = UIGestureRecognizerStateEnded;
            }
           // NSLog(@"startPointX  %f , normalizedGestureDeltaX %f", startPointX,  normalizedGestureDistance);
        }
    }
}

@end





