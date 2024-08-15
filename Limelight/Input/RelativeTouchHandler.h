//
//  RelativeTouchHandler.h
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import "StreamView.h"
#import "DataManager.h"
#import "CustomTapGestureRecognizer.h"


NS_ASSUME_NONNULL_BEGIN

@interface RelativeTouchHandler : UIResponder


- (id)initWithView:(StreamView*)view andSettings:(TemporarySettings*)settings;
- (CustomTapGestureRecognizer* )getMouseRightClickTapRecognizer; // rightClickTapRec must be created from relativeTouchHandler,since there's a attr must be accessed directly from recognizer, and it's also a relative touch specific recognizer.

@end

NS_ASSUME_NONNULL_END
