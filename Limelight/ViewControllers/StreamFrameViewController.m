//
//  StreamFrameViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "StreamFrameViewController.h"
#import "MainFrameViewController.h"
#import "VideoDecoderRenderer.h"
#import "StreamManager.h"
#import "ControllerSupport.h"
#import "DataManager.h"
#import "CustomEdgeSlideGestureRecognizer.h"
#import "CustomTapGestureRecognizer.h"
#import "LocalizationHelper.h"
#import "Moonlight-Swift.h"
#import "OSCProfilesManager.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <Limelight.h>

#if TARGET_OS_TV
#import <AVFoundation/AVDisplayCriteria.h>
#import <AVKit/AVDisplayManager.h>
#import <AVKit/UIWindow.h>
#endif

@interface AVDisplayCriteria()
@property(readonly) int videoDynamicRange;
@property(readonly, nonatomic) float refreshRate;
- (id)initWithRefreshRate:(float)arg1 videoDynamicRange:(int)arg2;
@end



@implementation StreamFrameViewController {
    ControllerSupport *_controllerSupport;
    StreamManager *_streamMan;
    TemporarySettings *_settings;
    NSTimer *_inactivityTimer;
    NSTimer *_statsUpdateTimer;
    UITapGestureRecognizer *_menuTapGestureRecognizer;
    UITapGestureRecognizer *_menuDoubleTapGestureRecognizer;
    UITapGestureRecognizer *_playPauseTapGestureRecognizer;
    UITextView *_overlayView;
    UILabel *_stageLabel;
    UILabel *_tipLabel;
    UIActivityIndicatorView *_spinner;
    StreamView *_streamView;
    UIScrollView *_scrollView;
    BOOL _userIsInteracting;
    CGSize _keyboardSize;
    UIWindow *_extWindow;
    UIView *_renderView;
    UIWindow *_deviceWindow;
    dispatch_block_t _delayedRemoveExtScreen;
#if !TARGET_OS_TV
    CustomEdgeSlideGestureRecognizer *_slideToSettingsRecognizer;
    CustomEdgeSlideGestureRecognizer *_slideToCmdToolRecognizer;
    CustomTapGestureRecognizer *_oscLayoutTapRecoginizer;
    LayoutOnScreenControlsViewController *_layoutOnScreenControlsVC;
#endif
}

- (bool)isOscLayoutToolEnabled{
    return (_settings.touchMode.intValue == RELATIVE_TOUCH || _settings.touchMode.intValue == REGULAR_NATIVE_TOUCH || _settings.touchMode.intValue == ABSOLUTE_TOUCH) && _settings.onscreenControls.intValue == OnScreenControlsLevelCustom;
}

- (void)configOscLayoutTool{
    if([self isOscLayoutToolEnabled]){
        _oscLayoutTapRecoginizer = [[CustomTapGestureRecognizer alloc] initWithTarget:self action:@selector(layoutOSC)];
        _oscLayoutTapRecoginizer.numberOfTouchesRequired = _settings.oscLayoutToolFingers.intValue; //tap a predefined number of fingers to open osc layout tool
        _oscLayoutTapRecoginizer.tapDownTimeThreshold = 0.2;
        _oscLayoutTapRecoginizer.delaysTouchesBegan = NO;
        _oscLayoutTapRecoginizer.delaysTouchesEnded = NO;
        if(_settings.touchMode.intValue == ABSOLUTE_TOUCH) _oscLayoutTapRecoginizer.immediateTriggering = true; // make immediate triggering on for absolute touch mode
        
        [self.view addGestureRecognizer:_oscLayoutTapRecoginizer]; //
        /* sets a reference to the correct 'LayoutOnScreenControlsViewController' depending on whether the user is on an iPhone or iPad */
        _layoutOnScreenControlsVC = [[LayoutOnScreenControlsViewController alloc] init];
        BOOL isIPhone = ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone);
        if (isIPhone) {
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"iPhone" bundle:nil];
            _layoutOnScreenControlsVC = [storyboard instantiateViewControllerWithIdentifier:@"LayoutOnScreenControlsViewController"];
        }
        else {
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"iPad" bundle:nil];
            _layoutOnScreenControlsVC = [storyboard instantiateViewControllerWithIdentifier:@"LayoutOnScreenControlsViewController"];
            _layoutOnScreenControlsVC.modalPresentationStyle = UIModalPresentationFullScreen;
        }
        _layoutOnScreenControlsVC.view.backgroundColor = UIColor.clearColor;
        _layoutOnScreenControlsVC.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    }
}

- (void)presentCommandManagerViewController{
    CommandManagerViewController* cmdManViewController = [[CommandManagerViewController alloc] init];
    [self presentViewController:cmdManViewController animated:YES completion:nil];
}

- (void)configSwipeGestures{
    _slideToSettingsRecognizer = [[CustomEdgeSlideGestureRecognizer alloc] initWithTarget:self action:@selector(edgeSwiped)];
    _slideToSettingsRecognizer.edges = _settings.slideToSettingsScreenEdge.intValue;
    _slideToSettingsRecognizer.normalizedThresholdDistance = _settings.slideToSettingsDistance.floatValue;
    _slideToSettingsRecognizer.delaysTouchesBegan = NO;
    _slideToSettingsRecognizer.delaysTouchesEnded = NO;
    [self.view addGestureRecognizer:_slideToSettingsRecognizer];
    
    
    _slideToCmdToolRecognizer = [[CustomEdgeSlideGestureRecognizer alloc] initWithTarget:self action:@selector(presentCommandManagerViewController)];
    if(_settings.slideToSettingsScreenEdge.intValue == UIRectEdgeLeft) _slideToCmdToolRecognizer.edges = UIRectEdgeRight;
    else _slideToCmdToolRecognizer.edges = UIRectEdgeLeft;  // _commandManager triggered by sliding from another side.
    _slideToCmdToolRecognizer.normalizedThresholdDistance = _settings.slideToSettingsDistance.floatValue;
    _slideToCmdToolRecognizer.delaysTouchesBegan = NO;
    _slideToCmdToolRecognizer.delaysTouchesEnded = NO;
    [self.view addGestureRecognizer:_slideToCmdToolRecognizer];
}

- (void)configZoomGestureAndAddStreamView{
    if (_settings.touchMode.intValue == ABSOLUTE_TOUCH) {
        _scrollView = [[UIScrollView alloc] initWithFrame:self.view.frame];
#if !TARGET_OS_TV
        [_scrollView.panGestureRecognizer setMinimumNumberOfTouches:2];
        [_scrollView.panGestureRecognizer setMaximumNumberOfTouches:2]; // reduce competing with keyboardToggleRecognizer in StreamView.
#endif
        [_scrollView setShowsHorizontalScrollIndicator:NO];
        [_scrollView setShowsVerticalScrollIndicator:NO];
        [_scrollView setDelegate:self];
        [_scrollView setMaximumZoomScale:10.0f];
        
        // Add StreamView inside a UIScrollView for absolute mode
        [_scrollView addSubview:_streamView];
        [self.view addSubview:_scrollView];
    }
    else{
        // Add streamView directly to self.view in other touch modes
        [self.view addSubview:_streamView];
    }
}

// key implementation of reconfiguring streamview after realtime setting menu is closed.
- (void)reConfigStreamViewRealtime{
    //[self.view removeGestureRecognizer:]
    //first, remove all gesture recognizers:
    for (UIGestureRecognizer *recognizer in _streamView.gestureRecognizers) {
        [_streamView removeGestureRecognizer:recognizer];
    }
    for (UIGestureRecognizer *recognizer in self.view.gestureRecognizers) {
        [self.view removeGestureRecognizer:recognizer];
    }
    
    _settings = [[[DataManager alloc] init] getSettings];  //StreamFrameViewController retrieve the settings here.
    [self configOscLayoutTool];
    [self configSwipeGestures];
    [self configZoomGestureAndAddStreamView];
    [self->_streamView disableOnScreenControls]; //don't know why but this must be called outside the streamview class, just put it here. execute in streamview class cause hang
    [self.mainFrameViewcontroller reloadStreamConfig]; // reload streamconfig
    
    _controllerSupport = [[ControllerSupport alloc] initWithConfig:self.streamConfig delegate:self]; // reload controllerSupport obj, this is mandatory for OSC reload,especially when the stream view is launched without OSC
    [_streamView setupStreamView:_controllerSupport interactionDelegate:self config:self.streamConfig streamFrameTopLayerView:self.view]; //reinitiate setupStreamView process.
        // we got self.view passed to streamView class as the topLayerView, will be useful in many cases
    [self->_streamView reloadOnScreenControlsRealtimeWith:(ControllerSupport*)_controllerSupport
                                        andConfig:(StreamConfiguration*)_streamConfig]; //reload OSC here.
    [self->_streamView reloadOnScreenButtonViews]; //reload keyboard buttons here. the keyboard button view will be added to the streamframe view instead streamview, the highest layer, which saves a lot of reengineering
    [self reloadAirPlayConfig];
    [self mousePresenceChanged];
    
    //reconfig statsOverlay
    self->_statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                               target:self
                                                             selector:@selector(updateStatsOverlay)
                                                             userInfo:nil
                                                              repeats:_settings.statsOverlay];
    
    NSLog(@"frameview gestures: %d", (uint32_t)[self.view.gestureRecognizers count]);
    NSLog(@"streamview gestures: %d", (uint32_t)[_streamView.gestureRecognizers count]);
}




- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    _deviceWindow = self.view.window;

    if (UIScreen.screens.count > 1 && [self isAirPlayEnabled]) {
        [self prepExtScreen:UIScreen.screens.lastObject];
    }
    else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.view insertSubview:self->_renderView atIndex:0];
        });
    }

    // check to see if external screen is connected/disconnected

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(extScreenDidConnect:)
                                                 name: UIScreenDidConnectNotification
                                               object: nil];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(extScreenDidDisconnect:)
                                                 name: UIScreenDidDisconnectNotification
                                               object: nil];
   
#if !TARGET_OS_TV
    [[self revealViewController] setPrimaryViewController:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reConfigStreamViewRealtime) // reconfig streamview when settings view is closed in stream view
                                                 name:@"SettingsViewClosedNotification"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sessionDisconnectedBySettingView) //quit session when exit button is press in setting view during streaming
                                                 name:@"SessionDisconnectedBySettingsViewNotification"
                                               object:nil];
#endif
}

#if TARGET_OS_TV
- (void)controllerPauseButtonPressed:(id)sender { }
- (void)controllerPauseButtonDoublePressed:(id)sender {
    Log(LOG_I, @"Menu double-pressed -- backing out of stream");
    [self returnToMainFrame];
}
- (void)controllerPlayPauseButtonPressed:(id)sender {
    Log(LOG_I, @"Play/Pause button pressed -- backing out of stream");
    [self returnToMainFrame];
}
#endif


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    _settings = [[[DataManager alloc] init] getSettings];  //StreamFrameViewController retrieve the settings here.
    
    _stageLabel = [[UILabel alloc] init];
    [_stageLabel setUserInteractionEnabled:NO];
    [_stageLabel setText:[NSString stringWithFormat:@"Starting %@...", self.streamConfig.appName]];
    [_stageLabel sizeToFit];
    _stageLabel.textAlignment = NSTextAlignmentCenter;
    _stageLabel.textColor = [UIColor whiteColor];
    _stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2);
    
    _spinner = [[UIActivityIndicatorView alloc] init];
    [_spinner setUserInteractionEnabled:NO];
#if TARGET_OS_TV
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhiteLarge];
#else
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhite];
#endif
    [_spinner sizeToFit];
    [_spinner startAnimating];
    _spinner.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2 - _stageLabel.frame.size.height - _spinner.frame.size.height);
    
    _controllerSupport = [[ControllerSupport alloc] initWithConfig:self.streamConfig delegate:self];
    _inactivityTimer = nil;
    
    _renderView = (StreamView*)[[UIView alloc] initWithFrame:self.view.frame];
    _streamView = [[StreamView alloc] initWithFrame:self.view.frame];
    _renderView.bounds = _streamView.bounds;
    //[_streamView setupStreamView:_controllerSupport interactionDelegate:self config:self.streamConfig];
    [self reConfigStreamViewRealtime]; // call this method again to make sure all gestures are configured & added to the superview(self.view), including the gestures added from inside the streamview.
    
#if TARGET_OS_TV
    if (!_menuTapGestureRecognizer || !_menuDoubleTapGestureRecognizer || !_playPauseTapGestureRecognizer) {
        _menuTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonPressed:)];
        _menuTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];

        _playPauseTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPlayPauseButtonPressed:)];
        _playPauseTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypePlayPause)];
        
        _menuDoubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonDoublePressed:)];
        _menuDoubleTapGestureRecognizer.numberOfTapsRequired = 2;
        [_menuTapGestureRecognizer requireGestureRecognizerToFail:_menuDoubleTapGestureRecognizer];
        _menuDoubleTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];
    }
    
    [self.view addGestureRecognizer:_menuTapGestureRecognizer];
    [self.view addGestureRecognizer:_menuDoubleTapGestureRecognizer];
    [self.view addGestureRecognizer:_playPauseTapGestureRecognizer];

#else
    //[self configSwipeGestures]; // swipe & exit gesture configured here
    //[self configOscLayoutTool]; //_oscLayoutTapRecoginizer will be added or removed to the view here
#endif
    
    _tipLabel = [[UILabel alloc] init];
    [_tipLabel setUserInteractionEnabled:NO];
    
#if TARGET_OS_TV
    [_tipLabel setText:@"Tip: Tap the Play/Pause button on the Apple TV Remote to disconnect from your PC"];
#else
    [_tipLabel setText:[LocalizationHelper localizedStringForKey:@"Tip: Swipe from screen edge to a certiain distance (configured by Swipe & Exit settings) to disconnect from your PC"]];
#endif
    
    [_tipLabel sizeToFit];
    _tipLabel.textColor = [UIColor whiteColor];
    _tipLabel.textAlignment = NSTextAlignmentCenter;
    _tipLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height * 0.9);
    
    _streamMan = [[StreamManager alloc] initWithConfig:self.streamConfig
                                            renderView:_renderView
                                   connectionCallbacks:self];
    NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
    [opQueue addOperation:_streamMan];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidBecomeActive:)
                                                 name: UIApplicationDidBecomeActiveNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidEnterBackground:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(oscLayoutClosed)
                                                 name:@"OscLayoutCloseNotification"
                                               object:nil];

#if 0
    // FIXME: This doesn't work reliably on iPad for some reason. Showing and hiding the keyboard
    // several times in a row will not correctly restore the state of the UIScrollView.
    // TrueZhuanJia: Already fixed by my refactored keyboard toggle gesture recognizer, and the keyboardWillShow/Hide method in StreamView.m
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillShow:)
                                                 name: UIKeyboardWillShowNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillHide:)
                                                 name: UIKeyboardWillHideNotification
                                               object: nil];
#endif
    
    [self.view addSubview:_stageLabel];
    [self.view addSubview:_spinner];
    [self.view addSubview:_tipLabel];
}

- (void)layoutOSC{
    [self->_streamView disableOnScreenControls];
    [self->_streamView clearOnScreenKeyboardButtons]; // clear all onScreenKeyboardButtons before entering edit mode
    [self presentViewController:_layoutOnScreenControlsVC animated:YES completion:nil];
}

- (void)oscLayoutClosed{
    // Handle the callback
    [self->_streamView disableOnScreenControls]; // add this to get realtime back menu working.
    [self->_streamView reloadOnScreenControlsWith:(ControllerSupport*)_controllerSupport
                                        andConfig:(StreamConfiguration*)_streamConfig];
    [self->_streamView showOnScreenControls];
    [self->_streamView reloadOnScreenButtonViews]; //update keyboard buttons here
}


- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _streamView;
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    // Only cleanup when we're being destroyed
    if (parent == nil) {
        [_controllerSupport cleanup];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [_streamMan stopStream];
        if (_inactivityTimer != nil) {
            [_inactivityTimer invalidate];
            _inactivityTimer = nil;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

#if 0
- (void)keyboardWillShow:(NSNotification *)notification {
    _keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;

    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self->_scrollView.frame;
        frame.size.height -= self->_keyboardSize.height;
        self->_scrollView.frame = frame;
    }];
}

-(void)keyboardWillHide:(NSNotification *)notification {
    // NOTE: UIKeyboardFrameEndUserInfoKey returns a different keyboard size
    // than UIKeyboardFrameBeginUserInfoKey, so it's unsuitable for use here
    // to undo the changes made by keyboardWillShow.
    
    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self->_scrollView.frame;
        frame.size.height += self->_keyboardSize.height;
        self->_scrollView.frame = frame;
    }];
}
#endif

- (void)updateStatsOverlay {
    if(!_settings.statsOverlay){
        [_overlayView removeFromSuperview];
        return; // add this for realtime streamview reconfig
    }
    else [self.view addSubview:_overlayView]; // don't know why but this is necessary for reactivating overlay.

    NSString* overlayText = [self->_streamMan getStatsOverlayText];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateOverlayText:overlayText];
    });
}

- (void)updateOverlayText:(NSString*)text {
    if (_overlayView == nil) {
        _overlayView = [[UITextView alloc] init];
#if !TARGET_OS_TV
        [_overlayView setEditable:NO];
#endif
        [_overlayView setUserInteractionEnabled:NO];
        [_overlayView setSelectable:NO];
        [_overlayView setScrollEnabled:NO];
        
        // HACK: If not using stats overlay, center the text
        if (_statsUpdateTimer == nil) {
            [_overlayView setTextAlignment:NSTextAlignmentCenter];
        }
        
        [_overlayView setTextColor:[UIColor lightGrayColor]];
        [_overlayView setBackgroundColor:[UIColor blackColor]];
#if TARGET_OS_TV
        [_overlayView setFont:[UIFont systemFontOfSize:24]];
#else
        [_overlayView setFont:[UIFont systemFontOfSize:12]];
#endif
        [_overlayView setAlpha:0.5];
        [self.view addSubview:_overlayView];
    }
    
    if (text != nil) {
        // We set our bounds to the maximum width in order to work around a bug where
        // sizeToFit interacts badly with the UITextView's line breaks, causing the
        // width to get smaller and smaller each time as more line breaks are inserted.
        [_overlayView setBounds:CGRectMake(self.view.frame.origin.x,
                                           _overlayView.frame.origin.y,
                                           self.view.frame.size.width,
                                           _overlayView.frame.size.height)];
        [_overlayView setText:text];
        [_overlayView sizeToFit];
        [_overlayView setCenter:CGPointMake(self.view.frame.size.width / 2, _overlayView.frame.size.height / 2)];
        [_overlayView setHidden:NO];
    }
    else {
        [_overlayView setHidden:YES];
    }
}

- (void) returnToMainFrame {
    // Reset display mode back to default
    [self updatePreferredDisplayMode:NO];
    
    [_statsUpdateTimer invalidate];
    _statsUpdateTimer = nil;
    
    [self.navigationController popToRootViewControllerAnimated:YES];
    
    _extWindow = nil;
}

// External Screen connected
- (void)extScreenDidConnect:(NSNotification *)notification {
    Log(LOG_I, @"External Screen Connected");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self prepExtScreen:notification.object];
    });
}

// External Screen disconnected
- (void)extScreenDidDisconnect:(NSNotification *)notification {
    Log(LOG_I, @"External Screen Disconnected");
    if(UIScreen.screens.count < 2)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
        [self removeExtScreen];
        });
    }
}

- (BOOL) isAirPlaying{
    return _extWindow != nil && _extWindow.hidden == NO;
}

- (BOOL) isAirPlayEnabled{
    return _settings.externalDisplayMode.intValue == 1;
}

- (void) reloadAirPlayConfig{
    if (UIScreen.screens.count == 1){return;}
    if (![self isAirPlaying] && [self isAirPlayEnabled]){
        [self prepExtScreen:UIScreen.screens.lastObject];
    }else if ([self isAirPlaying] && ![self isAirPlayEnabled]){
        [self removeExtScreen];
    }
}

// Prepare Screen
- (void)prepExtScreen:(UIScreen*)extScreen {
    Log(LOG_I, @"Preparing External Screen");
    if(![self isAirPlayEnabled]){
        return;
    }
    CGRect frame = extScreen.bounds;
    extScreen.overscanCompensation = UIScreenOverscanCompensationNone;
    if(_extWindow==nil){
        _extWindow = [[UIWindow alloc] initWithFrame:frame];
    }
    _extWindow.screen = extScreen;
    _renderView.bounds = frame;
    _renderView.frame = frame;
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName:@"ScreenChanged" object:self];
    [_extWindow addSubview:_renderView];
    _extWindow.hidden = NO;
}

- (void)removeExtScreen {
    Log(LOG_I, @"Removing External Screen");
    _extWindow.hidden = YES;
    [self handleViewResize];
    [self.view insertSubview:_renderView atIndex:0];
}

- (void) handleViewResize{
    _streamView.bounds = _deviceWindow.bounds;
    _streamView.frame = _deviceWindow.frame;
    if(![self isAirPlaying]){
        _renderView.bounds = _deviceWindow.bounds;
        _renderView.frame = _deviceWindow.frame;
        NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
        [nc postNotificationName:@"ScreenChanged" object:self];
    }
    [self reConfigStreamViewRealtime];
}


// This will fire if the user opens control center or gets a low battery message
- (void)applicationWillResignActive:(NSNotification *)notification {
    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
    }
    
#if !TARGET_OS_TV
    // Terminate the stream if the app is inactive for 60 seconds
    Log(LOG_I, @"Starting inactivity termination timer");
    _inactivityTimer = [NSTimer scheduledTimerWithTimeInterval:60
                                                      target:self
                                                    selector:@selector(inactiveTimerExpired:)
                                                    userInfo:nil
                                                     repeats:NO];
#endif
}

- (void)inactiveTimerExpired:(NSTimer*)timer {
    Log(LOG_I, @"Terminating stream after inactivity");

    [self returnToMainFrame];
    
    _inactivityTimer = nil;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    // Stop the background timer, since we're foregrounded again
    if (_inactivityTimer != nil) {
        Log(LOG_I, @"Stopping inactivity timer after becoming active again");
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
}

// This fires when the home button is pressed
- (void)applicationDidEnterBackground:(UIApplication *)application {
    Log(LOG_I, @"Terminating stream immediately for backgrounding");

    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
    
    [self returnToMainFrame];
}

- (void)expandSettingsView{
    self.mainFrameViewcontroller.settingsExpandedInStreamView = true; //notify mainFrameViewContorller that this is a setting expansion in stream view, some settings shall be disabled.
    [self.mainFrameViewcontroller simulateSettingsButtonPress];
}

- (void)edgeSwiped{
    if([self->_mainFrameViewcontroller isIPhonePortrait]){ // disable backmenu for iphone portrait mode;
        [self returnToMainFrame]; //directly quit the session
        return;
    }
    [self expandSettingsView];  // expand settings view in other cases;
}

- (void)sessionDisconnectedBySettingView {
    Log(LOG_I, @"Settings view disconnect the session in stream view");
    self.mainFrameViewcontroller.settingsExpandedInStreamView = false; // reset this flag to false
    [self returnToMainFrame];
}

- (void) connectionStarted {
    Log(LOG_I, @"Connection started");
    dispatch_async(dispatch_get_main_queue(), ^{
        // Leave the spinner spinning until it's obscured by
        // the first frame of video.
        self->_stageLabel.hidden = YES;
        self->_tipLabel.hidden = YES;
        self->_spinner.hidden = YES;
        
        [self->_streamView showOnScreenControls];
        
        [self->_controllerSupport connectionEstablished];
        
        if (self->_settings.statsOverlay) {
            self->_statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                                       target:self
                                                                     selector:@selector(updateStatsOverlay)
                                                                     userInfo:nil
                                                                      repeats:YES];
        }
    });
}

- (void)connectionTerminated:(int)errorCode {
    Log(LOG_I, @"Connection terminated: %d", errorCode);
    
    unsigned int portFlags = LiGetPortFlagsFromTerminationErrorCode(errorCode);
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portFlags);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* title;
        NSString* message;
        
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            title = [LocalizationHelper localizedStringForKey:@"Connection Error"];
            message = @"Your device's network connection is blocking Moonlight. Streaming may not work while connected to this network.";
        }
        else {
            switch (errorCode) {
                case ML_ERROR_GRACEFUL_TERMINATION:
                    [self returnToMainFrame];
                    return;
                    
                case ML_ERROR_NO_VIDEO_TRAFFIC:
                    title = [LocalizationHelper localizedStringForKey:@"Connection Error"];
                    message = [LocalizationHelper localizedStringForKey:@"No video received from host."];
                    if (portFlags != 0) {
                        char failingPorts[256];
                        LiStringifyPortFlags(portFlags, "\n", failingPorts, sizeof(failingPorts));
                        message = [message stringByAppendingString:[LocalizationHelper localizedStringForKey:@"ConnectionFailedFirewall", failingPorts]];
                    }
                    break;
                    
                case ML_ERROR_NO_VIDEO_FRAME:
                    title = [LocalizationHelper localizedStringForKey:@"Connection Error"];
                    message = [LocalizationHelper localizedStringForKey: @"Your network connection isn't performing well. Reduce your video bitrate setting or try a faster connection."];
                    break;
                    
                case ML_ERROR_UNEXPECTED_EARLY_TERMINATION:
                case ML_ERROR_PROTECTED_CONTENT:
                    title = [LocalizationHelper localizedStringForKey:@"Connection Error"];
                    message = @"Something went wrong on your host PC when starting the stream.\n\nMake sure you don't have any DRM-protected content open on your host PC. You can also try restarting your host PC.\n\nIf the issue persists, try reinstalling your GPU drivers and GeForce Experience.";
                    break;
                    
                case ML_ERROR_FRAME_CONVERSION:
                    title = [LocalizationHelper localizedStringForKey:@"Connection Error"];
                    message = @"The host PC reported a fatal video encoding error.\n\nTry disabling HDR mode, changing the streaming resolution, or changing your host PC's display resolution.";
                    break;
                    
                default:
                {
                    NSString* errorString;
                    if (abs(errorCode) > 1000) {
                        // We'll assume large errors are hex values
                        errorString = [NSString stringWithFormat:@"%08X", (uint32_t)errorCode];
                    }
                    else {
                        // Smaller values will just be printed as decimal (probably errno.h values)
                        errorString = [NSString stringWithFormat:@"%d", errorCode];
                    }
                    
                    title = [LocalizationHelper localizedStringForKey: @"Connection Terminated"];
                    message = [LocalizationHelper localizedStringForKey: @"The connection was terminated, Error code: %@", errorString];
                    break;
                }
            }
        }
        
        UIAlertController* conTermAlert = [UIAlertController alertControllerWithTitle:title
                                                                              message:message
                                                                       preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:conTermAlert];
        [conTermAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:conTermAlert animated:YES completion:nil];
    });

    [_streamMan stopStream];
}

- (void) stageStarting:(const char*)stageName {
    Log(LOG_I, @"Starting %s", stageName);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* lowerCase = [NSString stringWithFormat:@"%s ...", stageName];
        NSString* titleCase = [[[lowerCase substringToIndex:1] uppercaseString] stringByAppendingString:[lowerCase substringFromIndex:1]];
        [self->_stageLabel setText:titleCase];
        [self->_stageLabel sizeToFit];
        self->_stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self->_stageLabel.center.y);
    });
}

- (void) stageComplete:(const char*)stageName {
}

- (void) stageFailed:(const char*)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags {
    Log(LOG_I, @"Stage %s failed: %d", stageName, errorCode);
    
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portTestFlags);

    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* message = [NSString stringWithFormat:@"%s failed with error %d", stageName, errorCode];
        if (portTestFlags != 0) {
            char failingPorts[256];
            LiStringifyPortFlags(portTestFlags, "\n", failingPorts, sizeof(failingPorts));
            message = [message stringByAppendingString:[LocalizationHelper localizedStringForKey:@"ConnectionFailedFirewall", failingPorts]];
        }
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            message = [message stringByAppendingString:[LocalizationHelper localizedStringForKey:@"!ML_TEST_RESULT_INCONCLUSIVE"]];
        }
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Connection Failed"]
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
    
    [_streamMan stopStream];
}

- (void) launchFailed:(NSString*)message {
    Log(LOG_I, @"Launch failed: %@", message);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Connection Error"]
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
    Log(LOG_I, @"Rumble on gamepad %d: %04x %04x", controllerNumber, lowFreqMotor, highFreqMotor);
    
    [_controllerSupport rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

- (void) rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger {
    Log(LOG_I, @"Trigger rumble on gamepad %d: %04x %04x", controllerNumber, leftTrigger, rightTrigger);
    
    [_controllerSupport rumbleTriggers:controllerNumber leftTrigger:leftTrigger rightTrigger:rightTrigger];
}

- (void) setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
    Log(LOG_I, @"Set motion state on gamepad %d: %02x %u Hz", controllerNumber, motionType, reportRateHz);
    
    [_controllerSupport setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}

- (void) setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    Log(LOG_I, @"Set controller LED on gamepad %d: l%02x%02x%02x", controllerNumber, r, g, b);
    
    [_controllerSupport setControllerLed:controllerNumber r:r g:g b:b];
}

- (void)connectionStatusUpdate:(int)status {
    Log(LOG_W, @"Connection status update: %d", status);

    // The stats overlay takes precedence over these warnings
    if (_statsUpdateTimer != nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (status) {
            case CONN_STATUS_OKAY:
                [self updateOverlayText:nil];
                break;
                
            case CONN_STATUS_POOR:
                if (self->_streamConfig.bitRate > 5000) {
                    [self updateOverlayText:[LocalizationHelper localizedStringForKey:@"Slow connection to PC, Reduce your bitrate"]];
                }
                else {
                    [self updateOverlayText:[LocalizationHelper localizedStringForKey:@"Poor connection to PC"]];
                }
                break;
        }
    });
}

- (void) updatePreferredDisplayMode:(BOOL)streamActive {
#if TARGET_OS_TV
    if (@available(tvOS 11.2, *)) {
        UIWindow* window = [[[UIApplication sharedApplication] delegate] window];
        AVDisplayManager* displayManager = [window avDisplayManager];
        
        // This logic comes from Kodi and MrMC
        if (streamActive) {
            int dynamicRange;
            
            if (LiGetCurrentHostDisplayHdrMode()) {
                dynamicRange = 2; // HDR10
            }
            else {
                dynamicRange = 0; // SDR
            }
            
            AVDisplayCriteria* displayCriteria = [[AVDisplayCriteria alloc] initWithRefreshRate:[_settings.framerate floatValue]
                                                                              videoDynamicRange:dynamicRange];
            displayManager.preferredDisplayCriteria = displayCriteria;
        }
        else {
            // Switch back to the default display mode
            displayManager.preferredDisplayCriteria = nil;
        }
    }
#endif
}

- (void) setHdrMode:(bool)enabled {
    Log(LOG_I, @"HDR is now: %s", enabled ? "active" : "inactive");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updatePreferredDisplayMode:YES];
    });
}

- (void) videoContentShown {
    [_spinner stopAnimating];
    [self.view setBackgroundColor:[UIColor blackColor]];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)gamepadPresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)mousePresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 14.0, *)) {
        [self setNeedsUpdateOfPrefersPointerLocked];
    }
#endif
}

- (void) streamExitRequested {
    Log(LOG_I, @"Gamepad combo requested stream exit");
    
    [self returnToMainFrame];
}

- (void)userInteractionBegan {
    // Disable hiding home bar when user is interacting.
    // iOS will force it to be shown anyway, but it will
    // also discard our edges deferring system gestures unless
    // we willingly give up home bar hiding preference.
    _userIsInteracting = YES;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)userInteractionEnded {
    // Enable home bar hiding again if conditions allow
    _userIsInteracting = NO;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)toggleStatsOverlay{
    DataManager* dataMan = [[DataManager alloc] init];
    Settings *currentSettings = [dataMan retrieveSettings];
    
    currentSettings.statsOverlay = !currentSettings.statsOverlay;
    
    [dataMan saveData];
    [self reConfigStreamViewRealtime];
}

- (void)toggleMouseCapture{
    DataManager* dataMan = [[DataManager alloc] init];
    Settings *currentSettings = [dataMan retrieveSettings];
    
    if(currentSettings.mouseMode.intValue == 0){
        currentSettings.mouseMode = @1;
    }else{
        currentSettings.mouseMode = @0;
    }
    
    [dataMan saveData];
    [self reConfigStreamViewRealtime];
}

- (void)toggleMouseVisible{
    DataManager* dataMan = [[DataManager alloc] init];
    Settings *currentSettings = [dataMan retrieveSettings];
    
    if(currentSettings.mouseMode.intValue == 2){
        currentSettings.mouseMode = @1;
    }else{
        currentSettings.mouseMode = @2;
    }
    
    [dataMan saveData];
    [self reConfigStreamViewRealtime];
}

#if !TARGET_OS_TV
// Require a confirmation when streaming to activate a system gesture
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    if ([_controllerSupport getConnectedGamepadCount] > 0 &&
        [_streamView getCurrentOscState] == OnScreenControlsLevelOff &&
        _userIsInteracting == NO) {
        // Autohide the home bar when a gamepad is connected
        // and the on-screen controls are disabled. We can't
        // do this all the time because any touch on the display
        // will cause the home indicator to reappear, and our
        // preferredScreenEdgesDeferringSystemGestures will also
        // be suppressed (leading to possible errant exits of the
        // stream).
        return YES;
    }
    
    return NO;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (BOOL)prefersPointerLocked {
    // Pointer lock breaks the UIKit mouse APIs, which is a problem because
    // GCMouse is horribly broken on iOS 14.0 for certain mice. Only lock
    // the cursor if there is a GCMouse present.
    return ([GCMouse mice].count > 0) && [_settings mouseMode].intValue == 0;
}
#endif

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    Log(LOG_I, @"View size changed, terminating stream");
    
    double delayInSeconds = 0.2;
    if (_delayedRemoveExtScreen) {
        dispatch_block_cancel(_delayedRemoveExtScreen);
    }
    dispatch_block_t block = dispatch_block_create(0, ^{
        [self handleViewResize];
    });
    _delayedRemoveExtScreen = block;
    dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(delayTime, dispatch_get_main_queue(), block);
}

@end
