//
//  FDHelloTask.h
//  FireflyDevice
//
//  Created by Denis Bohm on 10/6/13.
//  Copyright (c) 2013-2014 Firefly Design LLC / Denis Bohm. All rights reserved.
//

#import "FDFireflyIceTaskSteps.h"

#import <Foundation/Foundation.h>

#define FDHelloTaskErrorDomain @"com.fireflydesign.device.FDHelloTask"

enum {
    FDHelloTaskErrorCodeIncomplete
};

@class FDHelloTask;

@protocol FDHelloTaskDelegate <NSObject>

- (void)helloTaskSuccess:(FDHelloTask *)helloTask;
- (void)helloTask:(FDHelloTask *)helloTask error:(NSError *)error;

@end

@interface FDHelloTask : FDFireflyIceTaskSteps

+ (FDHelloTask *)helloTask:(FDFireflyIce *)fireflyIce channel:(id<FDFireflyIceChannel>)channel delegate:(id<FDHelloTaskDelegate>)delegate;

@property id<FDHelloTaskDelegate> delegate;

@end
