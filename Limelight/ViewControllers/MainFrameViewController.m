//  MainFrameViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/17/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import ImageIO;

#import "MainFrameViewController.h"
#import "CryptoManager.h"
#import "HttpManager.h"
#import "Connection.h"
#import "StreamManager.h"
#import "Utils.h"
#import "UIComputerView.h"
#import "UIAppView.h"
#import "DataManager.h"
#import "TemporarySettings.h"
#import "WakeOnLanManager.h"
#import "AppListResponse.h"
#import "ServerInfoResponse.h"
#import "StreamFrameViewController.h"
#import "LoadingFrameViewController.h"
#import "ComputerScrollView.h"
#import "TemporaryApp.h"
#import "IdManager.h"
#import "ConnectionHelper.h"
#import "LocalizationHelper.h"
#import "CustomEdgeSlideGestureRecognizer.h"
#import "DataManager.h"
#import "Moonlight-Swift.h" // not used yet.

#if !TARGET_OS_TV
#import "SettingsViewController.h"
#else
#import <sys/utsname.h>
#endif

#import <VideoToolbox/VideoToolbox.h>

#include <Limelight.h>

@implementation MainFrameViewController {
    UILabel* waterMark;
    //CGFloat recordedScreenWidth;
    NSOperationQueue* _opQueue;
    TemporaryHost* _selectedHost;
    BOOL _showHiddenApps;
    NSString* _uniqueId;
    NSData* _clientCert;
    DiscoveryManager* _discMan;
    AppAssetManager* _appManager;
    StreamConfiguration* _streamConfig;
    UIAlertController* _pairAlert;
    LoadingFrameViewController* _loadingFrame;
    UIScrollView* hostScrollView;
    FrontViewPosition currentPosition;
    NSArray* _sortedAppList;
    NSCache* _boxArtCache;
    bool _background;
#if TARGET_OS_TV
    UITapGestureRecognizer* _menuRecognizer;
#endif
}
static NSMutableSet* hostList;

- (void)startPairing:(NSString *)PIN {
    // Needs to be synchronous to ensure the alert is shown before any potential
    // failure callback could be invoked.
    dispatch_sync(dispatch_get_main_queue(), ^{
        self->_pairAlert = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Pairing"]
                                                               message:[LocalizationHelper localizedStringForKey:@"Enter_PIN_Msg", PIN]
                                                        preferredStyle:UIAlertControllerStyleAlert];
        [self->_pairAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Cancel"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action) {
            self->_pairAlert = nil;
            [self->_discMan startDiscovery];
            [self hideLoadingFrame: ^{
                [self showHostSelectionView];
            }];
        }]];
        [[self activeViewController] presentViewController:self->_pairAlert animated:YES completion:nil];
    });
}

- (void)displayPairingFailureDialog:(NSString *)message {
    UIAlertController* failedDialog = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Pairing Failed"]
                                                                          message:message
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [Utils addHelpOptionToDialog:failedDialog];
    [failedDialog addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:nil]];
    
    [_discMan startDiscovery];
    
    [self hideLoadingFrame: ^{
        [self showHostSelectionView];
        [[self activeViewController] presentViewController:failedDialog animated:YES completion:nil];
    }];
}

- (void)pairFailed:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_pairAlert != nil) {
            [self->_pairAlert dismissViewControllerAnimated:YES completion:^{
                [self displayPairingFailureDialog:message];
            }];
            self->_pairAlert = nil;
        }
    });
}

- (void)pairSuccessful:(NSData*)serverCert {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Store the cert from pairing with the host
        self->_selectedHost.serverCert = serverCert;
        
        [self->_pairAlert dismissViewControllerAnimated:YES completion:nil];
        self->_pairAlert = nil;
        
        [self->_discMan startDiscovery];
        [self alreadyPaired];
    });
}

- (void)disableUpButton {
#if !TARGET_OS_TV
    [self->_upButton setTitle:nil];
    self.revealViewController.mainFrameIsInHostView = true;  // to allow orientation change only in app view, tell top view controller the mainframe is not in host view
    [self setNeedsUpdateAllowedOrientation];
#endif
}

- (void)enableUpButton {
#if !TARGET_OS_TV
    [self->_upButton setTitle: [LocalizationHelper localizedStringForKey: @"Select New Host"]];
    self.revealViewController.mainFrameIsInHostView = false; // to allow orientation change only in app view, tell top view controller the mainframe is not in host view
    [self setNeedsUpdateAllowedOrientation];
#endif
}

- (void)updateTitle {
    if (_selectedHost != nil) {
        self.title = _selectedHost.name;
    }
    else if ([hostList count] == 0) {
        self.title = [LocalizationHelper localizedStringForKey: @"Searching for PCs on your network..."] ;
    }
    else {
        self.title = [LocalizationHelper localizedStringForKey: @"Select Host" ];
    }
}

- (void)alreadyPaired {
    BOOL usingCachedAppList = false;
    
    // Capture the host here because it can change once we
    // leave the main thread
    TemporaryHost* host = _selectedHost;
    if (host == nil) {
        [self hideLoadingFrame: nil];
        return;
    }
    
    if ([host.appList count] > 0) {
        usingCachedAppList = true;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (host != self->_selectedHost) {
                [self hideLoadingFrame: nil];
                return;
            }
            
            [self updateAppsForHost:host];
            [self hideLoadingFrame: nil];
        });
    }
    Log(LOG_I, @"Using cached app list: %d", usingCachedAppList);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Exempt this host from discovery while handling the applist query
        [self->_discMan pauseDiscoveryForHost:host];
        
        AppListResponse* appListResp = [ConnectionHelper getAppListForHost:host];
        
        [self->_discMan resumeDiscoveryForHost:host];
        
        if (![appListResp isStatusOk] || [appListResp getAppList] == nil) {
            Log(LOG_W, @"Failed to get applist: %@", appListResp.statusMessage);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (host != self->_selectedHost) {
                    [self hideLoadingFrame: nil];
                    return;
                }
                
                UIAlertController* applistAlert = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Connection Interrupted"]
                                                                                      message:appListResp.statusMessage
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                [Utils addHelpOptionToDialog:applistAlert];
                [applistAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:nil]];
                [self hideLoadingFrame: ^{
                    [self showHostSelectionView];
                    [[self activeViewController] presentViewController:applistAlert animated:YES completion:nil];
                }];
                host.state = StateOffline;
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateApplist:[appListResp getAppList] forHost:host];
                
                if (host != self->_selectedHost) {
                    [self hideLoadingFrame: nil];
                    return;
                }
                
                [self updateAppsForHost:host];
                [self->_appManager stopRetrieving];
                [self->_appManager retrieveAssetsFromHost:host];
                [self hideLoadingFrame: nil];
            });
        }
    });
}

- (void) updateAppEntry:(TemporaryApp*)app forHost:(TemporaryHost*)host {
    DataManager* database = [[DataManager alloc] init];
    NSMutableSet* newHostAppList = [NSMutableSet setWithSet:host.appList];
    
    for (TemporaryApp* savedApp in newHostAppList) {
        if ([app.id isEqualToString:savedApp.id]) {
            savedApp.name = app.name;
            savedApp.hdrSupported = app.hdrSupported;
            savedApp.hidden = app.hidden;
            
            host.appList = newHostAppList;
            
            [database updateAppsForExistingHost:host];
            return;
        }
    }
}

- (void) updateApplist:(NSSet*) newList forHost:(TemporaryHost*)host {
    DataManager* database = [[DataManager alloc] init];
    NSMutableSet* newHostAppList = [NSMutableSet setWithSet:host.appList];
    
    for (TemporaryApp* app in newList) {
        BOOL appAlreadyInList = NO;
        for (TemporaryApp* savedApp in newHostAppList) {
            if ([app.id isEqualToString:savedApp.id]) {
                savedApp.name = app.name;
                savedApp.hdrSupported = app.hdrSupported;
                // Don't propagate hidden, because we want the local data to prevail
                appAlreadyInList = YES;
                break;
            }
        }
        if (!appAlreadyInList) {
            app.host = host;
            [newHostAppList addObject:app];
        }
    }
    
    BOOL appWasRemoved;
    do {
        appWasRemoved = NO;
        
        for (TemporaryApp* app in newHostAppList) {
            appWasRemoved = YES;
            for (TemporaryApp* mergedApp in newList) {
                if ([mergedApp.id isEqualToString:app.id]) {
                    appWasRemoved = NO;
                    break;
                }
            }
            if (appWasRemoved) {
                // Removing the app mutates the list we're iterating (which isn't legal).
                // We need to jump out of this loop and restart enumeration.
                
                [newHostAppList removeObject:app];
                
                // It's important to remove the app record from the database
                // since we'll have a constraint violation now that appList
                // doesn't have this app in it.
                [database removeApp:app];
                
                break;
            }
        }
        
        // Keep looping until the list is no longer being mutated
    } while (appWasRemoved);
    
    host.appList = newHostAppList;
    
    [database updateAppsForExistingHost:host];
    
    // This host may be eligible for a shortcut now that the app list
    // has been populated
    [self updateHostShortcuts];
}

- (void)showHostSelectionView {
#if TARGET_OS_TV
    // Remove the menu button intercept to allow the app to exit
    // when at the host selection view.
    [self.navigationController.view removeGestureRecognizer:_menuRecognizer];
#endif
    [_appManager stopRetrieving];
    _showHiddenApps = NO;
    _selectedHost = nil;
    _sortedAppList = nil;
    
    [self updateTitle];
    [self disableUpButton];
    [self.collectionView removeFromSuperview]; // necessary for new scroll host view reloading mechanism
    [self.view setBackgroundColor:[UIColor darkGrayColor]];
    [self reloadScrollHostView]; // host view must be reloaded here
}

- (void) receivedAssetForApp:(TemporaryApp*)app {
    // Update the box art cache now so we don't have to do it
    // on the main thread
    [self updateBoxArtCacheForApp:app];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.collectionView reloadData];
    });
}

- (void)displayDnsFailedDialog {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Network Error"]
                                                                   message:[LocalizationHelper localizedStringForKey:@"Failed to resolve host."]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [Utils addHelpOptionToDialog:alert];
    [alert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:nil]];
    [[self activeViewController] presentViewController:alert animated:YES completion:nil];
}

- (void) hostClicked:(TemporaryHost *)host view:(UIView *)view {
    // Treat clicks on offline hosts to be long clicks
    // This shows the context menu with wake, delete, etc. rather
    // than just hanging for a while and failing as we would in this
    // code path.
    if (host.state != StateOnline && view != nil) {
        [self hostLongClicked:host view:view];
        return;
    }
    
    Log(LOG_D, @"Clicked host: %@", host.name);
    _selectedHost = host;
    [self updateTitle];
    //_appManager = [[AppAssetManager alloc] initWithCallback:self];
    [self.collectionView setCollectionViewLayout:self.collectionViewLayout];
    [self.collectionView reloadData]; //for new scroll host view reloading mechanism
    [self.view addSubview:self.collectionView]; //for new scroll host view reloading mechanism
    [self attachWaterMark];
    [self enableUpButton];
    [self disableNavigation];
    
#if TARGET_OS_TV
    // Intercept the menu key to go back to the host page
    [self.navigationController.view addGestureRecognizer:_menuRecognizer];
#endif
    
    // If we are online, paired, and have a cached app list, skip straight
    // to the app grid without a loading frame. This is the fast path that users
    // should hit most. Check for a valid view because we don't want to hit the fast
    // path after coming back from streaming, since we need to fetch serverinfo too
    // so that our active game data is correct.
    if (host.state == StateOnline && host.pairState == PairStatePaired && host.appList.count > 0 && view != nil) {
        [self alreadyPaired];
        return;
    }
    
    [self showLoadingFrame: ^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            // Wait for the PC's status to be known
            while (host.state == StateUnknown) {
                sleep(1);
            }
            
            // Don't bother polling if the server is already offline
            if (host.state == StateOffline) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self hideLoadingFrame:^{
                        [self showHostSelectionView];
                    }];
                });
                return;
            }
            
            HttpManager* hMan = [[HttpManager alloc] initWithHost:host];
            ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
            
            // Exempt this host from discovery while handling the serverinfo request
            [self->_discMan pauseDiscoveryForHost:host];
            [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                                                fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
            [self->_discMan resumeDiscoveryForHost:host];
            
            if (![serverInfoResp isStatusOk]) {
                Log(LOG_W, @"Failed to get server info: %@", serverInfoResp.statusMessage);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (host != self->_selectedHost) {
                        [self hideLoadingFrame:nil];
                        return;
                    }
                    
                    UIAlertController* applistAlert = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Connection Failed"]
                                                                                          message:serverInfoResp.statusMessage
                                                                                   preferredStyle:UIAlertControllerStyleAlert];
                    [Utils addHelpOptionToDialog:applistAlert];
                    [applistAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:nil]];
                    
                    // Only display an alert if this was the result of a real
                    // user action, not just passively entering the foreground again
                    [self hideLoadingFrame: ^{
                        [self showHostSelectionView];
                        if (view != nil) {
                            [[self activeViewController] presentViewController:applistAlert animated:YES completion:nil];
                        }
                    }];
                    
                    host.state = StateOffline;
                });
            } else {
                // Update the host object with this data
                [serverInfoResp populateHost:host];
                if (host.pairState == PairStatePaired) {
                    Log(LOG_I, @"Already Paired");
                    [self alreadyPaired];
                }
                // Only pair when this was the result of explicit user action
                else if (view != nil) {
                    Log(LOG_I, @"Trying to pair");
                    // Polling the server while pairing causes the server to screw up
                    [self->_discMan stopDiscoveryBlocking];
                    PairManager* pMan = [[PairManager alloc] initWithManager:hMan clientCert:self->_clientCert callback:self];
                    [self->_opQueue addOperation:pMan];
                }
                else {
                    // Not user action, so just return to host screen
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self hideLoadingFrame:^{
                            [self showHostSelectionView];
                        }];
                    });
                }
            }
        });
    }];
}

- (UIViewController*) activeViewController {
    UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;
    
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    
    return topController;
}

- (void)hostLongClicked:(TemporaryHost *)host view:(UIView *)view {
    Log(LOG_D, @"Long clicked host: %@", host.name);
    NSString* message;
    
    switch (host.state) {
        case StateOffline:
            message = [LocalizationHelper localizedStringForKey:@"Offline"];
            break;
            
        case StateOnline:
            if (host.pairState == PairStatePaired) {
                message = [LocalizationHelper localizedStringForKey:@"Online - Paired"];
            }
            else {
                message = [LocalizationHelper localizedStringForKey:@"Online - Not Paired"];
            }
            break;
            
        case StateUnknown:
            message = [LocalizationHelper localizedStringForKey:@"Connecting"];
            break;
            
        default:
            break;
    }
    
    UIAlertController* longClickAlert = [UIAlertController alertControllerWithTitle:host.name message:message preferredStyle:UIAlertControllerStyleActionSheet];
    if (host.state != StateOnline) {
        [longClickAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Wake PC"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            UIAlertController* wolAlert = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Wake-On-LAN"] message:@"" preferredStyle:UIAlertControllerStyleAlert];
            [wolAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:nil]];
            if (host.mac == nil || [host.mac isEqualToString:@"00:00:00:00:00:00"]) {
                wolAlert.message = [LocalizationHelper localizedStringForKey: @"Host MAC unknown, unable to send WOL Packet"];
            } else {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [WakeOnLanManager wakeHost:host];
                });
                wolAlert.message = [LocalizationHelper localizedStringForKey:@"Successfully sent wake-up request. It may take a few moments for the PC to wake. If it never wakes up, ensure it's properly configured for Wake-on-LAN."];
            }
            [[self activeViewController] presentViewController:wolAlert animated:YES completion:nil];
        }]];
    }
    else if (host.pairState == PairStatePaired) {
        [longClickAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"View All Apps"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            self->_showHiddenApps = YES;
            [self hostClicked:host view:view];
        }]];
        
#if !TARGET_OS_TV
        if (host.isNvidiaServerSoftware) {
            [longClickAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"NVIDIA GameStream End-of-Service"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
                [Utils launchUrl:@"https://github.com/moonlight-stream/moonlight-docs/wiki/NVIDIA-GameStream-End-Of-Service-Announcement-FAQ"];
            }]];
        }
#endif
    }
    [longClickAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Test Network"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
        [self showLoadingFrame:^{
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // Perform the network test on a GCD worker thread. It may take a while.
                unsigned int portTestResult = LiTestClientConnectivity(CONN_TEST_SERVER, 443, ML_PORT_FLAG_ALL);
                dispatch_sync(dispatch_get_main_queue(), ^{
                    [self hideLoadingFrame:^{
                        NSString* message;
                        
                        if (portTestResult == 0) {
                            message = [LocalizationHelper localizedStringForKey:@"NetTestOK"];
                        }
                        else if (portTestResult == ML_TEST_RESULT_INCONCLUSIVE) {
                            message = [LocalizationHelper localizedStringForKey:@"ML_TEST_RESULT_INCONCLUSIVE"];
                        }
                        else {
                            char blockedPorts[512];
                            LiStringifyPortFlags(portTestResult, "\n", blockedPorts, sizeof(blockedPorts));
                            message = [LocalizationHelper localizedStringForKey:@"NetTestFailed", blockedPorts];
                        }
                        
                        UIAlertController* netTestAlert = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Network Test Complete"] message:message preferredStyle:UIAlertControllerStyleAlert];
                        [netTestAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:nil]];
                        [[self activeViewController] presentViewController:netTestAlert animated:YES completion:nil];
                    }];
                });
            });
        }];
    }]];
#if !TARGET_OS_TV
    if (host.state != StateOnline) {
        [longClickAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"NVIDIA GameStream End-of-Service"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [Utils launchUrl:@"https://github.com/moonlight-stream/moonlight-docs/wiki/NVIDIA-GameStream-End-Of-Service-Announcement-FAQ"];
        }]];
        [longClickAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Connection Help"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [Utils launchUrl:@"https://github.com/moonlight-stream/moonlight-docs/wiki/Troubleshooting"];
        }]];
    }
#endif
    [longClickAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Remove Host"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action) {   // host removed here
        [self->_discMan removeHostFromDiscovery:host];
        DataManager* dataMan = [[DataManager alloc] init];
        [dataMan removeHost:host];
        @synchronized(hostList) {
            [hostList removeObject:host];
            [self updateAllHosts:[hostList allObjects]];
        }
        
    }]];
    [longClickAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Cancel"] style:UIAlertActionStyleCancel handler:nil]];
    
    // these two lines are required for iPad support of UIAlertSheet
    longClickAlert.popoverPresentationController.sourceView = view;
    
    longClickAlert.popoverPresentationController.sourceRect = CGRectMake(view.bounds.size.width / 2.0, view.bounds.size.height / 2.0, 1.0, 1.0); // center of the view
    [[self activeViewController] presentViewController:longClickAlert animated:YES completion:nil];
}

- (void) addHostClicked {
    Log(LOG_D, @"Clicked add host");
    UIAlertController* alertController = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Add Host Manually"] message:[LocalizationHelper localizedStringForKey:@"If Moonlight doesn't find your local gaming PC automatically, enter the IP address of your PC"] preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Cancel"] style:UIAlertActionStyleCancel handler:nil]];
    [alertController addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
        NSString* hostAddress = [((UITextField*)[[alertController textFields] objectAtIndex:0]).text trim];
                
        [self showLoadingFrame:^{
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                [self->_discMan discoverHost:hostAddress withCallback:^(TemporaryHost* host, NSString* error){
                    if (host != nil) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self hideLoadingFrame:^{
                                @synchronized(hostList) {
                                    [hostList addObject:host];
                                }
                                [self updateHosts];
                            }];
                        });
                    } else {
                        unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443,
                                                                                ML_PORT_FLAG_TCP_47984 | ML_PORT_FLAG_TCP_47989);
                        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
                            error = [error stringByAppendingString:[LocalizationHelper localizedStringForKey:@"!ML_TEST_RESULT_INCONCLUSIVE"]];
                        }
                        
                        UIAlertController* hostNotFoundAlert = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Add Host Manually"] message:error preferredStyle:UIAlertControllerStyleAlert];
                        [Utils addHelpOptionToDialog:hostNotFoundAlert];
                        [hostNotFoundAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:nil]];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self hideLoadingFrame:^{
                                [[self activeViewController] presentViewController:hostNotFoundAlert animated:YES completion:nil];
                            }];
                        });
                    }
                }];
            });
        }];
    }]];
    [alertController addTextFieldWithConfigurationHandler:nil];
    [[self activeViewController] presentViewController:alertController animated:YES completion:nil];
}

- (void) prepareToStreamApp:(TemporaryApp *)app {
    [self updateResolutionAccordingly];
    self.revealViewController.isStreaming = true; // tell the revealViewController streaming is started.
    _streamConfig = [[StreamConfiguration alloc] init];
    _streamConfig.host = app.host.activeAddress;
    _streamConfig.httpsPort = app.host.httpsPort;
    _streamConfig.appID = app.id;
    _streamConfig.appName = app.name;
    _streamConfig.serverCert = app.host.serverCert;
    _streamConfig.serverCodecModeSupport = app.host.serverCodecModeSupport;
    [self reloadStreamConfig];
}

- (void) reloadStreamConfig {
    DataManager* dataMan = [[DataManager alloc] init];
    TemporarySettings* streamSettings = [dataMan getSettings];
    
    _streamConfig.frameRate = [streamSettings.framerate intValue];
    if (@available(iOS 10.3, *)) {
        UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
        NSInteger maximumFramesPerSecond = window.screen.maximumFramesPerSecond;
        if(UIScreen.screens.count > 1 && streamSettings.externalDisplayMode.intValue == 1){ //AirPlaying
            maximumFramesPerSecond = UIScreen.screens.lastObject.maximumFramesPerSecond;
        }
        // Don't stream more FPS than the display can show
        if (_streamConfig.frameRate > maximumFramesPerSecond) {
            _streamConfig.frameRate = (int)maximumFramesPerSecond;
            Log(LOG_W, @"Clamping FPS to maximum refresh rate: %d", _streamConfig.frameRate);
        }
    }
    
    _streamConfig.height = [streamSettings.height intValue];
    _streamConfig.width = [streamSettings.width intValue];
#if TARGET_OS_TV
    // Don't allow streaming 4K on the Apple TV HD
    struct utsname systemInfo;
    uname(&systemInfo);
    if (strcmp(systemInfo.machine, "AppleTV5,3") == 0 && _streamConfig.height >= 2160) {
        Log(LOG_W, @"4K streaming not supported on Apple TV HD");
        _streamConfig.width = 1920;
        _streamConfig.height = 1080;
    }
#endif
    
    _streamConfig.bitRate = [streamSettings.bitrate intValue];
    _streamConfig.optimizeGameSettings = streamSettings.optimizeGames;
    _streamConfig.playAudioOnPC = streamSettings.playAudioOnPC;
    _streamConfig.useFramePacing = streamSettings.useFramePacing;
    _streamConfig.swapABXYButtons = streamSettings.swapABXYButtons;
    _streamConfig.motionMode = [streamSettings.motionMode intValue];
    _streamConfig.largerStickLR1 = streamSettings.largerStickLR1; // new streamConfig segment
    
    // multiController must be set before calling getConnectedGamepadMask
    _streamConfig.multiController = streamSettings.multiController;
    _streamConfig.gamepadMask = [ControllerSupport getConnectedGamepadMask:_streamConfig];
    _streamConfig.mouseMode = streamSettings.mouseMode.intValue;
    
    // Probe for supported channel configurations
    int physicalOutputChannels = (int)[AVAudioSession sharedInstance].maximumOutputNumberOfChannels;
    Log(LOG_I, @"Audio device supports %d channels", physicalOutputChannels);
    
    int numberOfChannels = MIN([streamSettings.audioConfig intValue], physicalOutputChannels);
    Log(LOG_I, @"Selected number of audio channels %d", numberOfChannels);
    if (numberOfChannels >= 8) {
        _streamConfig.audioConfiguration = AUDIO_CONFIGURATION_71_SURROUND;
    }
    else if (numberOfChannels >= 6) {
        _streamConfig.audioConfiguration = AUDIO_CONFIGURATION_51_SURROUND;
    }
    else {
        _streamConfig.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
    }
    
    
    switch (streamSettings.preferredCodec) {
        case CODEC_PREF_AV1:
#if defined(__IPHONE_16_0) || defined(__TVOS_16_0)
            if (VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)) {
                _streamConfig.supportedVideoFormats |= VIDEO_FORMAT_AV1_MAIN8;
            }
#endif
            // Fall-through
            
        case CODEC_PREF_AUTO:
        case CODEC_PREF_HEVC:
            if (VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
                _streamConfig.supportedVideoFormats |= VIDEO_FORMAT_H265;
            }
            // Fall-through
            
        case CODEC_PREF_H264:
            _streamConfig.supportedVideoFormats |= VIDEO_FORMAT_H264;
            break;
    }
    
    // HEVC is supported if the user wants it (or it's required by the chosen resolution) and the SoC supports it
    if ((_streamConfig.width > 4096 || _streamConfig.height > 4096 || streamSettings.enableHdr) && VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
        _streamConfig.supportedVideoFormats |= VIDEO_FORMAT_H265;
        
        // HEVC Main10 is supported if the user wants it and the display supports it
        if (streamSettings.enableHdr && (AVPlayer.availableHDRModes & AVPlayerHDRModeHDR10) != 0) {
            _streamConfig.supportedVideoFormats |= VIDEO_FORMAT_H265_MAIN10;
        }
    }
    
#if defined(__IPHONE_16_0) || defined(__TVOS_16_0)
    // Add the AV1 Main10 format if AV1 and HDR are both enabled and supported
    if ((_streamConfig.supportedVideoFormats & VIDEO_FORMAT_MASK_AV1) && streamSettings.enableHdr &&
        VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1) && (AVPlayer.availableHDRModes & AVPlayerHDRModeHDR10) != 0) {
        _streamConfig.supportedVideoFormats |= VIDEO_FORMAT_AV1_MAIN10;
    }
#endif
}

- (void)appLongClicked:(TemporaryApp *)app view:(UIView *)view {
    Log(LOG_D, @"Long clicked app: %@", app.name);
    
    [_appManager stopRetrieving];
    
#if !TARGET_OS_TV
    if (currentPosition != FrontViewPositionLeft) {
        // This must not be animated because we need the position
        // to change (and notify our callback to save settings data)
        // before we call prepareToStreamApp.
        [[self revealViewController] revealToggleAnimated:NO];
    }
#endif

    TemporaryApp* currentApp = [self findRunningApp:app.host];
    
    NSString* message;
    
    if (currentApp == nil || [app.id isEqualToString:currentApp.id]) {
        if (app.hidden) {
            message = @"Hidden";
        }
        else {
            message = @"";
        }
    }
    else {
        message = [LocalizationHelper localizedStringForKey:@"%@ is currently running", currentApp.name];
    }
    
    UIAlertController* alertController = [UIAlertController
                                          alertControllerWithTitle: app.name
                                          message:message
                                          preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alertController addAction:[UIAlertAction
                                actionWithTitle:currentApp == nil ? [LocalizationHelper localizedStringForKey:@"Launch App"] : ([app.id isEqualToString:currentApp.id] ? [LocalizationHelper localizedStringForKey: @"Resume App"] : [LocalizationHelper localizedStringForKey: @"Resume Running App"]) style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
        if (currentApp != nil) {
            Log(LOG_I, @"Resuming application: %@", currentApp.name);
            [self prepareToStreamApp:currentApp];
        }
        else {
            Log(LOG_I, @"Launching application: %@", app.name);
            [self prepareToStreamApp:app];
        }

        [self performSegueWithIdentifier:@"createStreamFrame" sender:nil];
    }]];
    
    if (currentApp != nil) {
        [alertController addAction:[UIAlertAction actionWithTitle:
                                    [app.id isEqualToString:currentApp.id] ? [LocalizationHelper localizedStringForKey:@"Quit App"] : [LocalizationHelper localizedStringForKey:@"Quit Running App and Start"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action){
                                        Log(LOG_I, @"Quitting application: %@", currentApp.name);
                                        [self showLoadingFrame: ^{
                                            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                                                HttpManager* hMan = [[HttpManager alloc] initWithHost:app.host];
                                                HttpResponse* quitResponse = [[HttpResponse alloc] init];
                                                HttpRequest* quitRequest = [HttpRequest requestForResponse: quitResponse withUrlRequest:[hMan newQuitAppRequest]];
                                                
                                                // Exempt this host from discovery while handling the quit operation
                                                [self->_discMan pauseDiscoveryForHost:app.host];
                                                [hMan executeRequestSynchronously:quitRequest];
                                                if (quitResponse.statusCode == 200) {
                                                    ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
                                                    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                                                                                        fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
                                                    if (![serverInfoResp isStatusOk] || [[serverInfoResp getStringTag:@"state"] hasSuffix:@"_SERVER_BUSY"]) {
                                                        // On newer GFE versions, the quit request succeeds even though the app doesn't
                                                        // really quit if another client tries to kill your app. We'll patch the response
                                                        // to look like the old error in that case, so the UI behaves.
                                                        quitResponse.statusCode = 599;
                                                    }
                                                    else if ([serverInfoResp isStatusOk]) {
                                                        // Update the host object with this info
                                                        [serverInfoResp populateHost:app.host];
                                                    }
                                                }
                                                [self->_discMan resumeDiscoveryForHost:app.host];

                                                // If it fails, display an error and stop the current operation
                                                if (quitResponse.statusCode != 200) {
                                                    UIAlertController* alert = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Quitting App Failed"]
                                                                                                                   message:[LocalizationHelper localizedStringForKey:@"Failed to quit app. If this app was started by another device, you'll need to quit from that device."]
                                                                                         preferredStyle:UIAlertControllerStyleAlert];
                                                    [alert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:nil]];
                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                        [self updateAppsForHost:app.host];
                                                        [self hideLoadingFrame: ^{
                                                            [[self activeViewController] presentViewController:alert animated:YES completion:nil];
                                                        }];
                                                    });
                                                }
                                                else {
                                                    app.host.currentGame = @"0";
                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                        // If it succeeds and we're to start streaming, segue to the stream
                                                        if (![app.id isEqualToString:currentApp.id]) {
                                                            [self prepareToStreamApp:app];
                                                            [self hideLoadingFrame: ^{
                                                                [self performSegueWithIdentifier:@"createStreamFrame" sender:nil];
                                                            }];
                                                        }
                                                        else {
                                                            // Otherwise, just hide the loading icon
                                                            [self hideLoadingFrame:nil];
                                                        }
                                                    });
                                                }
                                            });
                                        }];
                                        
                                    }]];
    }

    if (currentApp == nil || ![app.id isEqualToString:currentApp.id] || app.hidden) {
        [alertController addAction:[UIAlertAction actionWithTitle:app.hidden ? [LocalizationHelper localizedStringForKey: @"Show App"] : [LocalizationHelper localizedStringForKey: @"Hide App"]
                                                            style:app.hidden ? UIAlertActionStyleDefault : UIAlertActionStyleDestructive
                                                          handler:^(UIAlertAction* action) {
            app.hidden = !app.hidden;
            [self updateAppEntry:app forHost:app.host];
            
            // Don't call updateAppsForHost because that will nuke this
            // app immediately if we're not showing hidden apps.
        }]];
    }
    
    [alertController addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Cancel"] style:UIAlertActionStyleCancel handler:nil]];

    // these two lines are required for iPad support of UIAlertSheet
    alertController.popoverPresentationController.sourceView = view;
    
    alertController.popoverPresentationController.sourceRect = CGRectMake(view.bounds.size.width / 2.0, view.bounds.size.height / 2.0, 1.0, 1.0); // center of the view
    [[self activeViewController] presentViewController:alertController animated:YES completion:nil];
}

- (void) appClicked:(TemporaryApp *)app view:(UIView *)view {
    Log(LOG_D, @"Clicked app: %@", app.name);
    
    [_appManager stopRetrieving];
    
#if !TARGET_OS_TV
    if (currentPosition != FrontViewPositionLeft) {
        // This must not be animated because we need the position
        // to change (and notify our callback to save settings data)
        // before we call prepareToStreamApp.
        [[self revealViewController] revealToggleAnimated:NO];
    }
#endif
    
    if ([self findRunningApp:app.host]) {
        // If there's a running app, display a menu
        [self appLongClicked:app view:view];
    } else {
        [self prepareToStreamApp:app];
        [self performSegueWithIdentifier:@"createStreamFrame" sender:nil];
    }
}

- (TemporaryApp*) findRunningApp:(TemporaryHost*)host {
    for (TemporaryApp* app in host.appList) {
        if ([app.id isEqualToString:host.currentGame]) {
            return app;
        }
    }
    return nil;
}

#if !TARGET_OS_TV
// this method is deprecated
- (void)simulateSettingsButtonPressClose { //force expand settings view to update resolution table, and all setting includes current fullscreen resolution will be updated.
    if (currentPosition == FrontViewPositionRight && _settingsButton.target && [_settingsButton.target respondsToSelector:_settingsButton.action]) {
        [_settingsButton.target performSelector:_settingsButton.action withObject:_settingsButton];
    }
}

- (void)simulateSettingsButtonPress { //simulate pressing the setting button, called from setting view controller.
    //if([self isIPhonePortrait]) return; // disable settings view expanding in iphone portrait mode since it's buggy.
    if (_settingsButton.target && [_settingsButton.target respondsToSelector:_settingsButton.action]) {
        [_settingsButton.target performSelector:_settingsButton.action withObject:_settingsButton];
    }
}

- (void)handleOrientationChange {
    UIDeviceOrientation targetOrientation = [[UIDevice currentDevice] orientation];
    if([self isIphone] && UIDeviceOrientationIsPortrait(targetOrientation)) [self simulateSettingsButtonPressClose]; // on iphone, force close settings views if target orietation is portrait.
    double delayInSeconds = 0.7;
    // Convert the delay into a dispatch_time_t value
    dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    // Perform some task after the delay
    dispatch_after(delayTime, dispatch_get_main_queue(), ^{// Code to execute after the delay
        // [self updateResolutionAccordingly];
        [self.settingsButton setEnabled:![self isIPhonePortrait]]; //make sure settings button is disabled in iphone portrait mode.
        if([self->_upButton title] == nil) [self reloadScrollHostView]; // title of the _upButton is a good flag for judging if we're on the Host selection view
        //self->recordedScreenWidth = screenWidthInPoints; // kind of obselete, but i keep this in the code.
    });
}

// currently obselete:
- (void) setNeedsUpdateAllowedOrientation{
    if (@available(iOS 16.0, *)) {
        [self setNeedsUpdateOfSupportedInterfaceOrientations];
    } else {
        // Fallback on earlier versions
    }
}


- (void)revealController:(SWRevealViewController *)revealController didMoveToPosition:(FrontViewPosition)position {
        // If we moved back to the center position, we should save the settings
    SettingsViewController* settingsViewController = (SettingsViewController*)[revealController rearViewController];
    settingsViewController.mainFrameViewController = self;
    // enable / disable widgets acoordingly: in streamview, disable, outside of streamview, enable.
    [settingsViewController.resolutionSelector setEnabled:!self.settingsExpandedInStreamView];
    [settingsViewController.framerateSelector setEnabled:!self.settingsExpandedInStreamView];
    [settingsViewController widget:settingsViewController.bitrateSlider setEnabled:!self.settingsExpandedInStreamView];
    [settingsViewController.optimizeSettingsSelector setEnabled:!self.settingsExpandedInStreamView];
    [settingsViewController.audioOnPCSelector setEnabled:!self.settingsExpandedInStreamView];
    [settingsViewController.codecSelector setEnabled:!self.settingsExpandedInStreamView];
    [settingsViewController.hdrSelector setEnabled:!self.settingsExpandedInStreamView];
    [settingsViewController.framePacingSelector setEnabled:!self.settingsExpandedInStreamView];
    [settingsViewController.btMouseSelector setEnabled:!self.settingsExpandedInStreamView];
    [settingsViewController.goBackToStreamViewButton setEnabled:self.settingsExpandedInStreamView];
    [settingsViewController.allowPortraitSelector setEnabled:!self.settingsExpandedInStreamView && [self isFullScreenRequired]];//need "requires fullscreen" enabled in the app bunddle to make runtime orientation limitation woring

    if (position == FrontViewPositionLeft) {
        [settingsViewController saveSettings];
        [self setNeedsUpdateAllowedOrientation]; // handle allow portratit on & off
        _settingsButton.enabled = YES; // make sure these 2 buttons are enabled after closing setting view.
        _upButton.enabled = YES; // here is the select new host button
    }
    
    currentPosition = position;
}
#endif

#if TARGET_OS_TV
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [self appClicked:_sortedAppList[indexPath.row] view:nil];
}
#endif

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.destinationViewController isKindOfClass:[StreamFrameViewController class]]) {
        StreamFrameViewController* streamFrame = segue.destinationViewController;
        streamFrame.mainFrameViewcontroller = self;
        streamFrame.streamConfig = _streamConfig;
    }
}

- (void) showLoadingFrame:(void (^)(void))completion {
    [_loadingFrame showLoadingFrame:completion];
}

- (void) hideLoadingFrame:(void (^)(void))completion {
    [self enableNavigation];
    [_loadingFrame dismissLoadingFrame:completion];
}

- (void)adjustScrollViewForSafeArea:(UIScrollView*)view {
    if (@available(iOS 11.0, *)) {
        if (self.view.safeAreaInsets.left >= 20 || self.view.safeAreaInsets.right >= 20) {
            view.contentInset = UIEdgeInsetsMake(0, 20, 0, 20);
        }
    }
}

// Adjust the subviews for the safe area on the iPhone X.
- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    
    [self adjustScrollViewForSafeArea:self.collectionView];
    [self adjustScrollViewForSafeArea:self->hostScrollView];
}

- (void)waterMarkTapped {
    // Handle the tap action here, e.g., open a URL
    NSURL *url = [NSURL URLWithString:@"https://www.wolai.com/k8RVqMrgYgC9NB4tXdz46H"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (BOOL)isFullScreenRequired {
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSNumber *requiresFullScreen = infoDictionary[@"UIRequiresFullScreen"];
    
    if (requiresFullScreen != nil) {
        return [requiresFullScreen boolValue];
    }
    // Default behavior if the key is not set
    return YES;
}


- (void)attachWaterMark {
    // Create and configure the label
    if(true){
        [self->waterMark removeFromSuperview];
        self->waterMark = [[UILabel alloc] init];
        self->waterMark.translatesAutoresizingMaskIntoConstraints = NO;
        self->waterMark.numberOfLines = 1;
        self->waterMark.font = [UIFont systemFontOfSize:22];
        self->waterMark.text = [LocalizationHelper localizedStringForKey:@"waterMarkText"];
        CGFloat labelHeight = 60;
        NSLog(@"fullscr: %d", [self isFullScreenRequired]);
        // the app is unable to automatically lock screen orientation in app window resiable mode(aka. not require fullscreen)
        if(![self isFullScreenRequired]){
            NSString* screenRotationTip = [LocalizationHelper localizedStringForKey:@"screenRotationTIp"];
            self->waterMark.text = [NSString stringWithFormat:@"%@\n%@", self->waterMark.text, screenRotationTip];
            self->waterMark.numberOfLines = 0; // Allow multiline text
            self->waterMark.font = [UIFont systemFontOfSize:19];
            labelHeight = 80;
        }
        self->waterMark.textColor = UIColor.blackColor;
        self->waterMark.alpha = 0.35;
        self->waterMark.textAlignment = NSTextAlignmentCenter;
        self->waterMark.backgroundColor = [UIColor clearColor];
        self->waterMark.userInteractionEnabled = YES; // Enable user interaction for tap gesture
        // Add tap gesture recognizer to handle hyperlink action
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(waterMarkTapped)];
        [self->waterMark addGestureRecognizer:tapGesture];
        // Add the label to the view hierarchy
        [self.view addSubview:self->waterMark];
        // Set up constraints
        [NSLayoutConstraint activateConstraints:@[
            [self->waterMark.centerXAnchor constraintEqualToAnchor:self.view.rightAnchor constant:-210], // Aligns the horizontal center of label to the horizontal center of view
            [self->waterMark.centerYAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-(labelHeight+10)], // Aligns the vertical center of label to the vertical center of view
            [self->waterMark.widthAnchor constraintEqualToConstant:500],                     // Sets the width of label to 200 points
            [self->waterMark.heightAnchor constraintEqualToConstant:labelHeight]                      // Sets the height of label to 50 points
        ]];
    }
}

- (bool)isIphone{
    return ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone);
}

- (bool)isIPhonePortrait{
    bool isIPhone = ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone);
    CGFloat screenHeightInPoints = CGRectGetHeight([[UIScreen mainScreen] bounds]);
    CGFloat screenWidthInPoints = CGRectGetWidth([[UIScreen mainScreen] bounds]);
    bool isPortrait = screenHeightInPoints > screenWidthInPoints;
    return isIPhone && isPortrait;
   // return isPortrait;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    //[OrientationHelper updateOrientationToLandscape];
#if !TARGET_OS_TV
    self.settingsExpandedInStreamView = false; // init this flag
    self.revealViewController.isStreaming = false; //init this flag for rvlVC
    self.revealViewController.mainFrameIsInHostView = true;
    
    // Set the side bar button action. When it's tapped, it'll show the sidebar.
    [_settingsButton setTarget:self.revealViewController];
    [_settingsButton setAction:@selector(revealToggle:)];
    
    // Set the host name button action. When it's tapped, it'll show the host selection view.
    [_upButton setTarget:self];
    [_upButton setAction:@selector(showHostSelectionView)];
    [self disableUpButton];
    
    // Set the gesture
    if(![self isIPhonePortrait]) [self.view addGestureRecognizer:self.revealViewController.panGestureRecognizer]; // to prevent buggy settings view in iphone portrait mode;
    
    // Get callbacks associated with the viewController
    [self.revealViewController setDelegate:self];
    
    // Disable bounce-back on reveal VC otherwise the settings will snap closed
    // if the user drags all the way off the screen opposite the settings pane.
    self.revealViewController.bounceBackOnOverdraw = NO;
#else
    // The settings button will direct the user into the Settings app on tvOS
    [_settingsButton setTarget:self];
    [_settingsButton setAction:@selector(openTvSettings:)];
    
    // Restore focus on the selected app on view controller pop navigation
    self.restoresFocusAfterTransition = NO;
    self.collectionView.remembersLastFocusedIndexPath = YES;
    
    _menuRecognizer = [[UITapGestureRecognizer alloc] init];
    [_menuRecognizer addTarget:self action: @selector(showHostSelectionView)];
    _menuRecognizer.allowedPressTypes = [[NSArray alloc] initWithObjects:[NSNumber numberWithLong:UIPressTypeMenu], nil];
    
    self.navigationController.navigationBar.titleTextAttributes = [NSDictionary dictionaryWithObject:[UIColor whiteColor] forKey:NSForegroundColorAttributeName];
#endif
    
    _loadingFrame = [self.storyboard instantiateViewControllerWithIdentifier:@"loadingFrame"];
    
    // Set the current position to the center
    currentPosition = FrontViewPositionLeft;
    
    // Set up crypto
    [CryptoManager generateKeyPairUsingSSL];
    _uniqueId = [IdManager getUniqueId];
    _clientCert = [CryptoManager readCertFromFile];

    _appManager = [[AppAssetManager alloc] initWithCallback:self];
    _opQueue = [[NSOperationQueue alloc] init];
    
    // Only initialize the host picker list once
    if (hostList == nil) {
        hostList = [[NSMutableSet alloc] init];
    }
    
    _boxArtCache = [[NSCache alloc] init];
    
    //recordedScreenWidth = CGRectGetWidth([[UIScreen mainScreen] bounds]);
    hostScrollView = [[ComputerScrollView alloc] init];
    CGFloat screenWidthInPoints = CGRectGetWidth([[UIScreen mainScreen] bounds]);
    CGFloat screenHeightInPoints = CGRectGetHeight([[UIScreen mainScreen] bounds]);

    // deal with scroll host view reload after device orientation change here:
    bool isLandscape = screenWidthInPoints > screenHeightInPoints;
    CGFloat realViewFrameWidth = self.view.frame.size.width > self.view.frame.size.height ? self.view.frame.size.width : self.view.frame.size.height;
    CGFloat realViewFrameHeight = self.view.frame.size.width < self.view.frame.size.height ? self.view.frame.size.width : self.view.frame.size.height;
    if(!isLandscape) {
        CGFloat tmpLength = realViewFrameWidth;
        realViewFrameWidth = realViewFrameHeight;
        realViewFrameHeight = tmpLength;
    }

    // implementations for initializing hostScrollView from original moonlight-iOS
    hostScrollView.frame = CGRectMake(0, self.navigationController.navigationBar.frame.origin.y + self.navigationController.navigationBar.frame.size.height, realViewFrameWidth, realViewFrameHeight / 2);
    [hostScrollView setShowsHorizontalScrollIndicator:NO];
    hostScrollView.delaysContentTouches = NO;

    self.collectionView.delaysContentTouches = NO;
    self.collectionView.allowsMultipleSelection = NO;
    #if !TARGET_OS_TV
    self.collectionView.multipleTouchEnabled = NO;
    #else
    // This is the only way to get long press events on a UICollectionViewCell :(
    UILongPressGestureRecognizer* cellLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleCollectionViewLongPress:)];
    cellLongPress.delaysTouchesBegan = YES;
    [self.collectionView addGestureRecognizer:cellLongPress];
    #endif

    [self retrieveSavedHosts];
    _discMan = [[DiscoveryManager alloc] initWithHosts:[hostList allObjects] andCallback:self];
    [self updateTitle];
    [self.view addSubview:hostScrollView];
    
    if ([hostList count] == 1) [self hostClicked:[hostList anyObject] view:nil]; // auto click for single host
    //if([SettingsViewController isLandscapeNow] != _streamConfig.width > _streamConfig.height)
    //[self simulateSettingsButtonPress]; //force expand setting view if orientation changed since last quit from app.
    //[self simulateSettingsButtonPress]; //force expand setting view if orientation changed since last quit from app.
    //[self updateResolutionAccordingly];
    
    // SettingsViewController* settingsViewController = (SettingsViewController*)[self.revealViewController rearViewController];
    // [settingsViewController updateResolutionTable];
}

-(void)handleRealOrientationChange{
    
}

-(void)reloadScrollHostView{
    [hostScrollView removeFromSuperview]; // mandatory for scroll view refresh after orientation change and clicking "select new host"
    CGFloat screenWidthInPoints = CGRectGetWidth([[UIScreen mainScreen] bounds]);
    CGFloat screenHeightInPoints = CGRectGetHeight([[UIScreen mainScreen] bounds]);

    // deal with scroll host view reload after device orientation change here:
    bool isLandscape = screenWidthInPoints > screenHeightInPoints;
    CGFloat realViewFrameWidth = self.view.frame.size.width > self.view.frame.size.height ? self.view.frame.size.width : self.view.frame.size.height;
    CGFloat realViewFrameHeight = self.view.frame.size.width < self.view.frame.size.height ? self.view.frame.size.width : self.view.frame.size.height;
    if(!isLandscape) {
        CGFloat tmpLength = realViewFrameWidth;
        realViewFrameWidth = realViewFrameHeight;
        realViewFrameHeight = tmpLength;
    }

    hostScrollView.frame = CGRectMake(0, self.navigationController.navigationBar.frame.origin.y + self.navigationController.navigationBar.frame.size.height, realViewFrameWidth, realViewFrameHeight / 2);
    [hostScrollView setShowsHorizontalScrollIndicator:NO];
    hostScrollView.delaysContentTouches = NO;

    self.collectionView.delaysContentTouches = NO;
    self.collectionView.allowsMultipleSelection = NO;
    #if !TARGET_OS_TV
    self.collectionView.multipleTouchEnabled = NO;
    #else
    // This is the only way to get long press events on a UICollectionViewCell :(
    UILongPressGestureRecognizer* cellLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleCollectionViewLongPress:)];
    cellLongPress.delaysTouchesBegan = YES;
    [self.collectionView addGestureRecognizer:cellLongPress];
    #endif

    // the reloadScrollHostView method cannnot copy what all viewDidLoad does for initializing the host scroll view, the following 2 lines of codes must be annotated, or there'll be issues with deleting hosts.
    //[self retrieveSavedHosts];
    //_discMan = [[DiscoveryManager alloc] initWithHosts:[hostList allObjects] andCallback:self];
    [self updateTitle];
    [self.view addSubview:hostScrollView];
}

// this will also be called back when device orientation changes
//- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
//    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
//    
//    double delayInSeconds = 0.7;
//    // Convert the delay into a dispatch_time_t value
//    dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
//    // Perform some task after the delay
//    dispatch_after(delayTime, dispatch_get_main_queue(), ^{// Code to execute after the delay
//        [self updateResolutionAccordingly];
//    });
//}

-(void) updateResolutionAccordingly {
    DataManager* dataMan = [[DataManager alloc] init];
    Settings *currentSettings = [dataMan retrieveSettings];
    UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
    CGFloat screenScale = window.screen.scale;
    CGFloat appWindowWidth = CGRectGetWidth(window.frame) * screenScale;
    CGFloat appWindowHeight = CGRectGetHeight(window.frame) * screenScale;
    CGFloat screenWidthInPoints = CGRectGetWidth([[UIScreen mainScreen] bounds]);
    CGFloat screenHeightInPoints = CGRectGetHeight([[UIScreen mainScreen] bounds]);
    
    if(currentSettings.externalDisplayMode.intValue == 1 && UIScreen.screens.count > 1){
        CGRect bounds = [UIScreen.screens.lastObject bounds];
        screenScale = [UIScreen.screens.lastObject scale];
        appWindowWidth = bounds.size.width * screenScale;
        appWindowHeight = bounds.size.height * screenScale;
    }

    bool needSwap = false;
    
    if([self isFullScreenRequired]){ // if force fullscreen is enabled in app bundle, we use screen bounds to tell if a swap between width & height is needed
        needSwap = (currentSettings.width.floatValue - currentSettings.height.floatValue) * (screenWidthInPoints - screenHeightInPoints) < 0; //update the current resolution accordingly
        NSLog(@"need to swap width & height (non-app window mode): %d", needSwap);
        if(needSwap){
            CGFloat tmpLength = currentSettings.width.floatValue;
            currentSettings.width = @(currentSettings.height.floatValue);
            currentSettings.height = @(tmpLength);
        }
    }
    else{// if force fullscreen is disabled in app bundle, we use appWindowSize to directly update or to get if we need a swap
        if(currentSettings.resolutionSelected.intValue == 5){ // app window res, previous fullscreen, update resolution directly
            currentSettings.width = @(appWindowWidth);
            currentSettings.height = @(appWindowHeight);
            NSLog(@"Directly Update app window resolution: %f, %f", appWindowWidth, appWindowHeight);
        }
        else if(currentSettings.resolutionSelected.intValue){
            needSwap = (currentSettings.width.floatValue - currentSettings.height.floatValue) * (appWindowWidth - appWindowHeight) < 0;
            if(needSwap){
                CGFloat tmpLength = currentSettings.width.floatValue;
                currentSettings.width = @(currentSettings.height.floatValue);
                currentSettings.height = @(tmpLength);
                NSLog(@"Swap resolution width & height");
            }
        }
    }
    
    
    
    [dataMan saveData];
}

#if TARGET_OS_TV
-(void)handleCollectionViewLongPress:(UILongPressGestureRecognizer *)gestureRecognizer
{
    // FIXME: Something is delaying touches so we only get to the Begin state
    // before we actually want to signal the long press.
    if (gestureRecognizer.state != UIGestureRecognizerStateBegan) {
        return;
    }
    
    CGPoint point = [gestureRecognizer locationInView:self.collectionView];
    NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:point];
    if (indexPath != nil) {
        [self appLongClicked:_sortedAppList[indexPath.row] view:nil];
    }
}

- (void)openTvSettings:(id)sender
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
}
#endif

-(void)beginForegroundRefresh
{
    if (!_background) {
        // This will kick off box art caching
        [self updateHosts];
        
        // Reset state first so we can rediscover hosts that were deleted before
        [_discMan resetDiscoveryState];
        [_discMan startDiscovery];
        
        // This will refresh the applist when a paired host is selected
        if (_selectedHost != nil && _selectedHost.pairState == PairStatePaired) {
            [self hostClicked:_selectedHost view:nil];
        }
    }
}

-(void)handlePendingShortcutAction
{
    // Check if we have a pending shortcut action
    AppDelegate* delegate = (AppDelegate*)[UIApplication sharedApplication].delegate;
    if (delegate.pcUuidToLoad != nil) {
        // Find the host it corresponds to
        TemporaryHost* matchingHost = nil;
        for (TemporaryHost* host in hostList) {
            if ([host.uuid isEqualToString:delegate.pcUuidToLoad]) {
                matchingHost = host;
                break;
            }
        }
        
        // Clear the pending shortcut action
        delegate.pcUuidToLoad = nil;
        
        // Complete the request
        if (delegate.shortcutCompletionHandler != nil) {
            delegate.shortcutCompletionHandler(matchingHost != nil);
            delegate.shortcutCompletionHandler = nil;
        }
        
        if (matchingHost != nil && _selectedHost != matchingHost) {
            // Navigate to the host page
            [self hostClicked:matchingHost view:nil];
        }
    }
}

-(void)handleReturnToForeground
{
    _background = NO;
    
    [self beginForegroundRefresh];
    
    // Check for a pending shortcut action when returning to foreground
    [self handlePendingShortcutAction];
}

-(void)handleEnterBackground
{
    _background = YES;
    
    [_discMan stopDiscovery];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:NO];
    [self attachWaterMark];
    
#if !TARGET_OS_TV
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleOrientationChange) // //force expand settings view to update resolution table, and all setting includes current fullscreen resolution will be updated.
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
    
    [[self revealViewController] setPrimaryViewController:self];
    self.revealViewController.isStreaming = false; // tell the revealViewController streaming is finished
    [self.settingsButton setEnabled:![self isIPhonePortrait]]; //make sure settings button is disabled in iphone portrait mode.
    //recordedScreenWidth = CGRectGetWidth([[UIScreen mainScreen] bounds]); // Get the screen's bounds (in points), update recorded screen width
#endif
    
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    
    // Hide 1px border line
    UIImage* fakeImage = [[UIImage alloc] init];
    [self.navigationController.navigationBar setShadowImage:fakeImage];
    [self.navigationController.navigationBar setBackgroundImage:fakeImage forBarPosition:UIBarPositionAny barMetrics:UIBarMetricsDefault];
    
    // Check for a pending shortcut action when appearing
    [self handlePendingShortcutAction];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(handleReturnToForeground)
                                                 name: UIApplicationDidBecomeActiveNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(handleEnterBackground)
                                                 name: UIApplicationWillResignActiveNotification
                                               object: nil];
    //[self simulateSettingsButtonPress]; //force reload resolution table in the setting
    //[self simulateSettingsButtonPress];
    //[self updateResolutionAccordingly];
}




- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    // We can get here on home press while streaming
    // since the stream view segues to us just before
    // entering the background. We can't check the app
    // state here (since it's in transition), so we have
    // to use this function that will use our internal
    // state here to determine whether we're foreground.
    //
    // Note that this is neccessary here as we may enter
    // this view via an error dialog from the stream
    // view, so we won't get a return to active notification
    // for that which would normally fire beginForegroundRefresh.
    [self beginForegroundRefresh];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    // when discovery stops, we must create a new instance because
    // you cannot restart an NSOperation when it is finished
    [_discMan stopDiscovery];
    
    // Purge the box art cache
    [_boxArtCache removeAllObjects];
    
    // Remove our lifetime observers to avoid triggering them
    // while streaming
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void) retrieveSavedHosts {
    DataManager* dataMan = [[DataManager alloc] init];
    NSArray* hosts = [dataMan getHosts];
    @synchronized(hostList) {
        [hostList addObjectsFromArray:hosts];
        
        // Initialize the non-persistent host state
        for (TemporaryHost* host in hostList) {
            if (host.activeAddress == nil) {
                host.activeAddress = host.localAddress;
            }
            if (host.activeAddress == nil) {
                host.activeAddress = host.externalAddress;
            }
            if (host.activeAddress == nil) {
                host.activeAddress = host.address;
            }
            if (host.activeAddress == nil) {
                host.activeAddress = host.ipv6Address;
            }
        }
    }
}

- (void) updateAllHosts:(NSArray *)hosts {
    // We must copy the array here because it could be modified
    // before our main thread dispatch happens.
    NSArray* hostsCopy = [NSArray arrayWithArray:hosts];
    dispatch_async(dispatch_get_main_queue(), ^{
        Log(LOG_D, @"New host list:");
        for (TemporaryHost* host in hostsCopy) {
            Log(LOG_D, @"Host: \n{\n\t name:%@ \n\t address:%@ \n\t localAddress:%@ \n\t externalAddress:%@ \n\t ipv6Address:%@ \n\t uuid:%@ \n\t mac:%@ \n\t pairState:%d \n\t online:%d \n\t activeAddress:%@ \n}", host.name, host.address, host.localAddress, host.externalAddress, host.ipv6Address, host.uuid, host.mac, host.pairState, host.state, host.activeAddress);
        }
        @synchronized(hostList) {
            [hostList removeAllObjects];
            [hostList addObjectsFromArray:hostsCopy];
        }
        [self updateHosts];
    });
}

- (void)updateHostShortcuts {
#if !TARGET_OS_TV
    NSMutableArray* quickActions = [[NSMutableArray alloc] init];
    
    @synchronized (hostList) {
        for (TemporaryHost* host in hostList) {
            // Pair state may be unknown if we haven't polled it yet, but the app list
            // count will persist from paired PCs
            if ([host.appList count] > 0) {
                UIApplicationShortcutItem* shortcut = [[UIApplicationShortcutItem alloc]
                                                       initWithType:@"PC"
                                                       localizedTitle:host.name
                                                       localizedSubtitle:nil
                                                       icon:[UIApplicationShortcutIcon iconWithType:UIApplicationShortcutIconTypePlay]
                                                       userInfo:[NSDictionary dictionaryWithObject:host.uuid forKey:@"UUID"]];
                [quickActions addObject: shortcut];
            }
        }
    }
    
    [UIApplication sharedApplication].shortcutItems = quickActions;
#endif
}

- (void)updateHosts {
    Log(LOG_I, @"Updating hosts...");
    [[hostScrollView subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
    UIComputerView* addComp = [[UIComputerView alloc] initForAddWithCallback:self];
    UIComputerView* compView;
    float prevEdge = -1;
    @synchronized (hostList) {
        // Sort the host list in alphabetical order
        NSArray* sortedHostList = [[hostList allObjects] sortedArrayUsingSelector:@selector(compareName:)];
        for (TemporaryHost* comp in sortedHostList) {
            compView = [[UIComputerView alloc] initWithComputer:comp andCallback:self];
            compView.center = CGPointMake([self getCompViewX:compView addComp:addComp prevEdge:prevEdge], hostScrollView.frame.size.height / 2);
            prevEdge = compView.frame.origin.x + compView.frame.size.width;
            [hostScrollView addSubview:compView];
            
            // Start jobs to decode the box art in advance
            for (TemporaryApp* app in comp.appList) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                    [self updateBoxArtCacheForApp:app];
                });
            }
        }
    }
    
    // Create or delete host shortcuts as needed
    [self updateHostShortcuts];
    
    // Update the title in case we now have a PC
    [self updateTitle];
    
    prevEdge = [self getCompViewX:addComp addComp:addComp prevEdge:prevEdge];
    addComp.center = CGPointMake(prevEdge, hostScrollView.frame.size.height / 2);
    
    [hostScrollView addSubview:addComp];
    [hostScrollView setContentSize:CGSizeMake(prevEdge + addComp.frame.size.width, hostScrollView.frame.size.height)];
}

- (float) getCompViewX:(UIComputerView*)comp addComp:(UIComputerView*)addComp prevEdge:(float)prevEdge {
    float padding;
    
#if TARGET_OS_TV
    padding = 100;
#else
    padding = addComp.frame.size.width / 2;
#endif
    
    if (prevEdge == -1) {
        return hostScrollView.frame.origin.x + comp.frame.size.width / 2 + padding;
    } else {
        return prevEdge + comp.frame.size.width / 2 + padding;
    }
}

// This function forces immediate decoding of the UIImage, rather
// than the default lazy decoding that results in janky scrolling.
+ (UIImage*) loadBoxArtForCaching:(TemporaryApp*)app {
    UIImage* boxArt;
    
    NSData* imageData = [NSData dataWithContentsOfFile:[AppAssetManager boxArtPathForApp:app]];
    if (imageData == nil) {
        // No box art on disk
        return nil;
    }
    
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil);
    
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef imageContext =  CGBitmapContextCreate(NULL, width, height, 8, width * 4, colorSpace,
                                                       kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(colorSpace);

    CGContextDrawImage(imageContext, CGRectMake(0, 0, width, height), cgImage);
    
    CGImageRef outputImage = CGBitmapContextCreateImage(imageContext);

    boxArt = [UIImage imageWithCGImage:outputImage];
    
    CGImageRelease(outputImage);
    CGContextRelease(imageContext);
    
    CGImageRelease(cgImage);
    CFRelease(source);
    
    return boxArt;
}

- (void) updateBoxArtCacheForApp:(TemporaryApp*)app {
    if ([_boxArtCache objectForKey:app] == nil) {
        UIImage* image = [MainFrameViewController loadBoxArtForCaching:app];
        if (image != nil) {
            // Add the image to our cache if it was present
            [_boxArtCache setObject:image forKey:app];
        }
    }
}

- (void) updateAppsForHost:(TemporaryHost*)host {
    if (host != _selectedHost) {
        Log(LOG_W, @"Mismatched host during app update");
        return;
    }
    
    _sortedAppList = [host.appList allObjects];
    _sortedAppList = [_sortedAppList sortedArrayUsingSelector:@selector(compareName:)];
    
    if (!_showHiddenApps) {
        NSMutableArray* visibleAppList = [NSMutableArray array];
        for (TemporaryApp* app in _sortedAppList) {
            if (!app.hidden) {
                [visibleAppList addObject:app];
            }
        }
        _sortedAppList = visibleAppList;
    }
    
    [hostScrollView removeFromSuperview];
    [self.collectionView reloadData];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell* cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"AppCell" forIndexPath:indexPath];
    
    TemporaryApp* app = _sortedAppList[indexPath.row];
    UIAppView* appView = [[UIAppView alloc] initWithApp:app cache:_boxArtCache andCallback:self];
    
    if (appView.bounds.size.width > 10.0) {
        CGFloat scale = cell.bounds.size.width / appView.bounds.size.width;
        [appView setCenter:CGPointMake(appView.bounds.size.width / 2 * scale, appView.bounds.size.height / 2 * scale)];
        appView.transform = CGAffineTransformMakeScale(scale, scale);
    }
    
    [cell.subviews.firstObject removeFromSuperview]; // Remove a view that was previously added
    [cell addSubview:appView];
    [self.settingsButton setEnabled:![self isIPhonePortrait]]; // update settings button after host is clicked & appview loaded
    // Shadow opacity is controlled inside UIAppView based on whether the app
    // is hidden or not during the update cycle.
    UIBezierPath *shadowPath = [UIBezierPath bezierPathWithRect:cell.bounds];
    cell.layer.masksToBounds = NO;
    cell.layer.shadowColor = [UIColor blackColor].CGColor;
    cell.layer.shadowOffset = CGSizeMake(1.0f, 5.0f);
    cell.layer.shadowPath = shadowPath.CGPath;
    
#if !TARGET_OS_TV
    cell.layer.borderWidth = 1;
    cell.layer.borderColor = [[UIColor colorWithRed:0 green:0 blue:0 alpha:0.3f] CGColor];
    cell.exclusiveTouch = YES;
#endif

    return cell;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1; // App collection only
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (_selectedHost != nil && _sortedAppList != nil) {
        return _sortedAppList.count;
    }
    else {
        return 0;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    // Purge the box art cache on low memory
    [_boxArtCache removeAllObjects];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#if !TARGET_OS_TV
- (BOOL)shouldAutorotate {
    return YES;
}
#endif

- (void) disableNavigation {
    self.navigationController.navigationBar.topItem.rightBarButtonItem.enabled = NO;
    self.navigationController.navigationBar.topItem.leftBarButtonItem.enabled = NO;
}

- (void) enableNavigation {
    self.navigationController.navigationBar.topItem.rightBarButtonItem.enabled = YES;
    self.navigationController.navigationBar.topItem.leftBarButtonItem.enabled = YES;
}

#if TARGET_OS_TV
- (BOOL)canBecomeFocused {
    return YES;
}
#endif

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    
#if !TARGET_OS_TV
    if (context.nextFocusedView != nil) {
        [context.nextFocusedView setAlpha:0.8];
    }
    [context.previouslyFocusedView setAlpha:1.0];
#endif
}

@end
