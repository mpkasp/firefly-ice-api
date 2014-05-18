//
//  FDBundle.m
//  FireflyDevice
//
//  Created by scripts/plistToDictionary.sh
//

#import "FDBundle.h"
#import <FireflyDevice/FDBundleManager.h>

@implementation FDBundle

+ (void)load
{
    [FDBundleManager addLibraryBundle:[[FDBundle alloc] init]];
}

- (NSDictionary *)infoDictionary
{
    return @{
        @"CFBundleName": @"FireflyDevice",
        @"CFBundleShortVersionString": @"1.0.15",
        @"CFBundleVersion": @"15",
        @"NSHumanReadableCopyright": @"Copyright © 2013-2014 Firefly Design LLC / Denis Bohm. All rights reserved.",
    };
}

@end
