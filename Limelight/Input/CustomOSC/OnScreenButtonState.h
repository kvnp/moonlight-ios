//
//  OnScreenButtonState.h
//  Moonlight
//
//  Created by Long Le on 10/20/22.
//  Copyright © 2022 Moonlight Game Streaming Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 This object is used to save positional and visibility information for any particular on screen virtual controller button.
 We are able to associate this 'OnScreenButtonState' object and its corresponding CALayer onscreen controller button by setting their 'name' properties equal; in our particular case we give them descriptive names such as 'aButton', 'upButton', 'leftStick', etc. By keeping references to the 19 on screen controller buttons (CALayers) in an array, and creating 19 'OnScreenButtonState' objects with names corresponding to these 19 CALayers and keeping them in an array, we can iterate through both arrays to find OSC buttons (CALayers) with the same name as one of the 'OnScreenButtonStateObjects' and then set the CALayer on screen control button's 'position' and 'hidden' property according to the value of the 'OnScreenButtonState' objects 'position' and 'isHidden' properties.
 Naturally we would like the user to be able to save their controller layout configurations so that they can load them between app launches, so we adopt encoding/decoding related protocols so we encode these 'OnScreenButtonState' objects and save them to NSUserDefaults
 */

// OS Button state info obj to be modified
@interface OnScreenButtonState : NSObject  <NSCoding, NSSecureCoding>

@property NSString *name;
@property NSString *alias;
@property CGPoint position;
@property (nonatomic, assign) BOOL isHidden;
@property (nonatomic, assign) uint8_t buttonType;
@property (nonatomic, assign) NSTimeInterval timestamp;
@property (nonatomic, assign) CGFloat widthFactor; // for OnScreenButtonView
@property (nonatomic, assign) CGFloat heightFactor; // for OnScreenButtonView
@property (nonatomic, assign) CGFloat oscLayerSizeFactor; // for OnScreenController CALayer
@property (nonatomic, assign) CGFloat backgroundAlpha; // for OnScreenController CALayer

// @property (nonatomic, assign) BOOL hasValidPosition;

typedef NS_ENUM(NSInteger, OnScreenButtonType) {
    GameControllerButton,
    KeyboardOrMouseButton
};

- (id) initWithButtonName:(NSString*)name buttonType:(uint8_t)buttonType andPosition:(CGPoint)position;

+ (BOOL) supportsSecureCoding;
- (void) encodeWithCoder:(NSCoder*)encoder;
- (id) initWithCoder:(NSCoder*)decoder;

@end

NS_ASSUME_NONNULL_END
