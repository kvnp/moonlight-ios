//
//  StreamFrameViewController.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "Connection.h"
#import "StreamConfiguration.h"
#import "StreamView.h"
#import "LayoutOnScreenControlsViewController.h"
#import "MainFrameViewController.h"

#import <UIKit/UIKit.h>

#if TARGET_OS_TV
@import GameController;

@interface StreamFrameViewController : GCEventViewController <ConnectionCallbacks, ControllerSupportDelegate, UserInteractionDelegate, UIScrollViewDelegate>
#else
@interface StreamFrameViewController : UIViewController <ConnectionCallbacks, ControllerSupportDelegate, UserInteractionDelegate, UIScrollViewDelegate>

#endif
@property (nonatomic) StreamConfiguration* streamConfig;
@property (nonatomic, assign) MainFrameViewController *mainFrameViewcontroller;


-(void)updatePreferredDisplayMode:(BOOL)streamActive;

@end
