//
//  FDExecutor.h
//  FireflyDevice
//
//  Created by Denis Bohm on 9/14/13.
//  Copyright (c) 2013-2014 Firefly Design LLC / Denis Bohm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <FireflyDevice/FDObservable.h>

@protocol FDFireflyDeviceLog;
@class FDExecutor;

@protocol FDExecutorTask <NSObject>

@property NSTimeInterval timeout;
@property NSInteger priority;
@property BOOL isSuspended;
@property NSDate *appointment;

- (void)executorTaskStarted:(FDExecutor *)executor;
- (void)executorTaskSuspended:(FDExecutor *)executor;
- (void)executorTaskResumed:(FDExecutor *)executor;
- (void)executorTaskCompleted:(FDExecutor *)executor;
- (void)executorTaskFailed:(FDExecutor *)executor error:(NSError *)error;

@end

#define FDExecutorErrorDomain @"com.fireflydesign.device.FDExecutor"

enum {
    FDExecutorErrorCodeAbort,
    FDExecutorErrorCodeCancel,
    FDExecutorErrorCodeTimeout,
};

@protocol FDExecutorObserver
@optional
- (void)executorChanged:(FDExecutor *)executor;
@end

@interface FDExecutorObservable : FDObservable <FDExecutorObserver>
@end

@interface FDExecutor : NSObject

@property id<FDFireflyDeviceLog> log;
@property FDExecutorObservable *observable;
@property NSTimeInterval timeoutCheckInterval;

@property(nonatomic) BOOL run;

- (void)execute:(id<FDExecutorTask>)task;
- (void)cancel:(id<FDExecutorTask>)task;
- (void)cancelAll;
- (NSArray<id<FDExecutorTask>> *)allTasks;
@property(readonly) BOOL hasTasks;

- (void)feedWatchdog:(id<FDExecutorTask>)task;
- (void)complete:(id<FDExecutorTask>)task;
- (void)fail:(id<FDExecutorTask>)task error:(NSError *)error;

@end
