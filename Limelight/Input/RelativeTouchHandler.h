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
@property (nonatomic, readonly) CustomTapGestureRecognizer* mouseRightClickTapRecognizer; // this object will be passed to onscreencontrol class for areVirtualControllerTaps flag setting


- (id)initWithView:(StreamView*)view andSettings:(TemporarySettings*)settings;

@end

NS_ASSUME_NONNULL_END
