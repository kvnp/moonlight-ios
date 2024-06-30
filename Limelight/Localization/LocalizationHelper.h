//
//  LocalizationHelper.h
//  Moonlight
//
//  Created by ZWM on 2024/6/30.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

#ifndef LocalizationHelper_h
#define LocalizationHelper_h

#import <Foundation/Foundation.h>

@interface LocalizationHelper : NSObject

// Method to get localized string with format arguments
+ (NSString *)localizedStringForKey:(NSString *)key, ... NS_FORMAT_FUNCTION(1,2);

@end

#endif /* LocalizationHelper_h */
